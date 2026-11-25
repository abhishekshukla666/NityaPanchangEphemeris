import XCTest
@testable import NityaPanchangEphemeris

/// The day's muhurats against Drik Panchang's published times for New Delhi.
///
/// Read from drikpanchang.com's day panchang (geoname 1261481) on 25 November 2026. Times are to
/// the minute there, and the engine's sunrise can sit up to a minute from Drik's, so each is
/// allowed a minute and a half.
final class DrikMuhuratTests: XCTestCase {

    private let repo = EphemerisPanchaangRepository()
    private let lat = 28.6358, lon = 77.2245     // New Delhi
    private let slack: TimeInterval = 90

    private var ist: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal
    }

    private func day(_ d: Int, _ m: Int) async -> PanchangDay {
        let noon = ist.date(from: DateComponents(year: 2026, month: m, day: d, hour: 12))!
        return await repo.fetchPanchang(for: noon, latitude: lat, longitude: lon)
    }

    /// "17:46" on the day given, or the day after when `next` is set.
    private func at(_ d: Int, _ m: Int, _ hm: String, next: Bool = false) -> Date {
        let parts = hm.split(separator: ":").map { Int($0)! }
        let base = ist.date(from: DateComponents(year: 2026, month: m, day: d, hour: parts[0], minute: parts[1]))!
        return next ? ist.date(byAdding: .day, value: 1, to: base)! : base
    }

    private func all(_ name: String, _ p: PanchangDay) -> [Muhurat] { p.muhurats.filter { $0.name == name } }

    private func assertWindow(_ m: Muhurat?, _ start: Date, _ end: Date, _ what: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        guard let m else { return XCTFail("no \(what)", file: file, line: line) }
        XCTAssertEqual(m.startTime.timeIntervalSince(start), 0, accuracy: slack, "\(what) start", file: file, line: line)
        XCTAssertEqual(m.endTime.timeIntervalSince(end), 0, accuracy: slack, "\(what) end", file: file, line: line)
    }

    private func near(_ list: [Muhurat], _ start: Date) -> Muhurat? {
        list.first { abs($0.startTime.timeIntervalSince(start)) <= slack }
    }

    // MARK: - The four dates read in full

    /// A Wednesday: no Abhijit, and the Amrit Kaal that is not Yamaganda.
    func testWednesday25November() async {
        let p = await day(25, 11)
        XCTAssertTrue(all("Abhijit Muhurat", p).isEmpty, "Drik lists no Abhijit on a Wednesday")
        assertWindow(all("Brahma Muhurat", p).first, at(25, 11, "05:04"), at(25, 11, "05:58"), "Brahma")
        assertWindow(all("Vijaya Muhurat", p).first, at(25, 11, "13:53"), at(25, 11, "14:36"), "Vijaya")
        assertWindow(all("Godhuli Muhurat", p).first, at(25, 11, "17:22"), at(25, 11, "17:49"), "Godhuli")
        XCTAssertEqual(all("Amrit Kaal", p).count, 1)
        assertWindow(all("Amrit Kaal", p).first, at(25, 11, "17:46"), at(25, 11, "19:11"), "Amrit Kaal")
        let varjyam = all("Varjyam", p)
        XCTAssertEqual(varjyam.count, 2)
        assertWindow(near(varjyam, at(25, 11, "13:32")), at(25, 11, "13:32"), at(25, 11, "14:57"), "Varjyam")
        assertWindow(near(varjyam, at(25, 11, "01:32", next: true)),
                     at(25, 11, "01:32", next: true), at(25, 11, "02:57", next: true), "night Varjyam")
        // The bug that started this: Amrit Kaal on Yamaganda.
        let yama = all("Yamaganda", p).first
        XCTAssertNotEqual(yama?.startTime, all("Amrit Kaal", p).first?.startTime)
        // These four were already right.
        assertWindow(all("Rahu Kaal", p).first, at(25, 11, "12:08"), at(25, 11, "13:27"), "Rahu Kaal")
        assertWindow(yama, at(25, 11, "08:11"), at(25, 11, "09:30"), "Yamaganda")
        assertWindow(all("Gulik Kaal", p).first, at(25, 11, "10:49"), at(25, 11, "12:08"), "Gulik Kaal")
    }

    /// A Thursday, when the old Amrit Kaal was Rahu Kaal itself.
    func testThursday26November() async {
        let p = await day(26, 11)
        assertWindow(all("Abhijit Muhurat", p).first, at(26, 11, "11:47"), at(26, 11, "12:29"), "Abhijit")
        assertWindow(all("Vijaya Muhurat", p).first, at(26, 11, "13:54"), at(26, 11, "14:36"), "Vijaya")
        // Two: Mrigashira's in the morning, and Ardra's before the next sunrise, which Drik
        // prints as a second line under the first.
        let amrit = all("Amrit Kaal", p)
        XCTAssertEqual(amrit.count, 2)
        assertWindow(near(amrit, at(26, 11, "10:01")), at(26, 11, "10:01"), at(26, 11, "11:26"), "Amrit Kaal")
        assertWindow(near(amrit, at(26, 11, "06:14", next: true)),
                     at(26, 11, "06:14", next: true), at(26, 11, "07:40", next: true), "dawn Amrit Kaal")
        assertWindow(near(all("Varjyam", p), at(26, 11, "01:15", next: true)),
                     at(26, 11, "01:15", next: true), at(26, 11, "02:41", next: true), "Varjyam")
        XCTAssertNotEqual(all("Rahu Kaal", p).first?.startTime, all("Amrit Kaal", p).first?.startTime)
    }

    /// A day with no Amrit Kaal at all, and a Varjyam that runs past midnight.
    func testSunday29November() async {
        let p = await day(29, 11)
        XCTAssertTrue(all("Amrit Kaal", p).isEmpty, "Drik lists no Amrit Kalam on 29 Nov")
        assertWindow(near(all("Varjyam", p), at(29, 11, "23:06")),
                     at(29, 11, "23:06"), at(29, 11, "00:37", next: true), "Varjyam")
    }

    /// A Wednesday whose Amrit Kaal falls in the small hours of the next date.
    func testWednesday2December() async {
        let p = await day(2, 12)
        XCTAssertTrue(all("Abhijit Muhurat", p).isEmpty)
        assertWindow(all("Amrit Kaal", p).first, at(2, 12, "02:03", next: true), at(2, 12, "03:41", next: true), "Amrit Kaal")
        assertWindow(near(all("Varjyam", p), at(2, 12, "16:15")), at(2, 12, "16:15"), at(2, 12, "17:53"), "Varjyam")
    }

    /// Summer: the night's muhurta is 40 minutes, not December's 54, and Godhuli 20.
    func testMidsummer21June() async {
        let p = await day(21, 6)
        assertWindow(all("Brahma Muhurat", p).first, at(21, 6, "04:04"), at(21, 6, "04:44"), "Brahma")
        assertWindow(all("Godhuli Muhurat", p).first, at(21, 6, "19:21"), at(21, 6, "19:41"), "Godhuli")
        assertWindow(all("Amrit Kaal", p).first, at(21, 6, "02:55", next: true), at(21, 6, "04:34", next: true), "Amrit Kaal")
        assertWindow(near(all("Varjyam", p), at(21, 6, "16:58")), at(21, 6, "16:58"), at(21, 6, "18:38"), "Varjyam")
    }

    // MARK: - A month of Amrit Kaal: every nakshatra
    //
    // Drik prints a day's second Amrit Kaal as an unlabelled line under the first; the two
    // read on 26 November and 22 December were re-read for exactly that.

    /// Every Amrit Kaal Drik lists from 1 to 29 December 2026, which between them cover all 27
    /// nakshatras. (day, start, end, whether each time is on the next date.)
    func testAmritKaalThroughDecember() async {
        let drik: [(Int, String, String, Bool, Bool)] = [
            (1, "02:32", "04:08", true, true), (2, "02:03", "03:41", true, true),
            (3, "04:08", "05:48", true, true), (4, "05:01", "06:43", true, true),
            (5, "04:10", "05:53", true, true), (6, "06:12", "07:57", true, true),
            (7, "06:48", "08:34", true, true), (9, "11:12", "12:59", false, false),
            (10, "16:46", "18:34", false, false), (11, "21:39", "23:27", false, false),
            (12, "22:58", "00:46", false, true), (13, "21:30", "23:18", false, false),
            (14, "00:19", "02:06", true, true), (15, "06:11", "07:56", true, true),
            (16, "07:01", "08:43", true, true), (18, "11:14", "12:52", false, false),
            (19, "13:35", "15:10", false, false), (20, "08:02", "09:34", false, false),
            (21, "08:42", "10:11", false, false), (22, "08:35", "10:02", false, false),
            (23, "21:12", "22:36", false, false), (24, "17:04", "18:28", false, false),
            (25, "20:43", "22:07", false, false), (26, "14:30", "15:56", false, false),
            (27, "16:37", "18:04", false, false), (28, "14:18", "15:48", false, false),
            (29, "09:32", "11:05", false, false),
        ]
        for (d, s, e, sNext, eNext) in drik {
            let p = await day(d, 12)
            let amrit = all("Amrit Kaal", p)
            // 22 December has a second, Rohini's, before the next sunrise.
            XCTAssertEqual(amrit.count, d == 22 ? 2 : 1, "\(d) Dec")
            let start = at(d, 12, s, next: sNext)
            assertWindow(near(amrit, start), start, at(d, 12, e, next: eNext), "\(d) Dec Amrit Kaal")
        }
        let p22 = await day(22, 12)
        assertWindow(near(all("Amrit Kaal", p22), at(22, 12, "05:07", next: true)),
                     at(22, 12, "05:07", next: true), at(22, 12, "06:31", next: true), "22 Dec dawn Amrit Kaal")
        // The two days Drik lists none.
        for d in [8, 17] {
            let p = await day(d, 12)
            XCTAssertTrue(all("Amrit Kaal", p).isEmpty, "\(d) Dec")
        }
    }

    /// Varjyam through December, as Drik lists it (the first of the day where it shows two).
    func testVarjyamThroughDecember() async {
        let drik: [(Int, String, String, Bool, Bool)] = [
            (1, "16:58", "18:34", false, false), (2, "16:15", "17:53", false, false),
            (3, "18:08", "19:48", false, false), (4, "18:51", "20:33", false, false),
            (5, "17:50", "19:33", false, false), (6, "19:44", "21:29", false, false),
            (7, "20:12", "21:58", false, false), (8, "00:30", "02:17", true, true),
            (9, "05:59", "07:47", true, true), (10, "22:10", "23:58", false, false),
            (11, "10:48", "12:37", false, false), (12, "12:06", "13:55", false, false),
            (13, "10:42", "12:30", false, false), (14, "13:39", "15:25", false, false),
            (15, "19:43", "21:28", false, false), (16, "20:50", "22:31", false, false),
            (17, "01:22", "03:01", true, true), (18, "04:04", "05:39", true, true),
            (20, "11:06", "12:37", false, false), (21, "23:57", "01:23", false, true),
            (22, "00:52", "02:17", true, true), (23, "12:49", "14:13", false, false),
            (24, "12:12", "13:35", false, false), (25, "12:18", "13:42", false, false),
            (27, "07:52", "09:19", false, false), (28, "00:16", "01:49", true, true),
            (29, "22:53", "00:28", false, true),
        ]
        for (d, s, e, sNext, eNext) in drik {
            let p = await day(d, 12)
            let start = at(d, 12, s, next: sNext)
            assertWindow(near(all("Varjyam", p), start), start, at(d, 12, e, next: eNext), "\(d) Dec Varjyam")
        }
    }

    /// Mula holds two Varjyams, at its 20th and 56th ghatis; Drik lists both on 10 December
    /// (one on the 9th's panchang day, before the 10th's sunrise).
    func testMulaHasTwoVarjyams() {
        XCTAssertEqual(NakshatraWindows.varjyamGhatis[18], [20, 56])
        XCTAssertEqual(NakshatraWindows.amritGhati.count, 27)
        XCTAssertEqual(NakshatraWindows.varjyamGhatis.count, 27)
    }
}
