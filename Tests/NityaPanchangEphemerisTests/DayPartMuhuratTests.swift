import XCTest
@testable import NityaPanchangEphemeris

/// Gulika, Yamaganda and Amrit — the parts of the day the wrapper tabulates.
final class DayPartMuhuratTests: XCTestCase {

    private let repo = EphemerisPanchaangRepository()
    private let lat = 23.1765, lon = 75.7885     // Ujjain

    private var ist: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal
    }

    /// A week beginning on a Sunday, so every weekday is covered once.
    private var week: [Date] {
        let cal = ist
        let sunday = cal.date(from: DateComponents(year: 2026, month: 9, day: 6))!
        return (0..<7).map { cal.date(byAdding: .day, value: $0, to: sunday)! }
    }

    private func day(_ date: Date) async -> PanchangDay {
        await repo.fetchPanchang(for: date, latitude: lat, longitude: lon)
    }

    /// Which eighth of the day a muhurat starts in, 0-based.
    private func eighth(_ start: Date, in p: PanchangDay) -> Int {
        let length = p.sunset.timeIntervalSince(p.sunrise) / 8
        return Int((start.timeIntervalSince(p.sunrise) / length).rounded())
    }

    private func muhurat(_ name: String, in p: PanchangDay) -> Muhurat? {
        p.muhurats.first { $0.name == name }
    }

    /// Seven of the day's eight parts carry a lord, running in weekday order
    /// from the weekday's own lord. Gulika is Saturn's part and Yamaganda is
    /// Jupiter's, and this derives both rather than restating the table, so a
    /// table edited back to its old values fails here.
    func testGulikaAndYamagandaSitInTheirLordsPart() async throws {
        let lords = ["Sun", "Moon", "Mars", "Mercury", "Jupiter", "Venus", "Saturn"]
        for date in week {
            let p = await day(date)
            let weekdayIndex = ist.component(.weekday, from: date) - 1
            let parts = (0..<7).map { lords[(weekdayIndex + $0) % 7] }

            let gulika = try XCTUnwrap(muhurat("Gulik Kaal", in: p) ?? muhurat("Gulika", in: p),
                                       "no Gulika on \(p.vara)")
            XCTAssertEqual(eighth(gulika.startTime, in: p), parts.firstIndex(of: "Saturn"),
                           "Gulika on \(p.vara)")

            let yama = try XCTUnwrap(muhurat("Yamaganda", in: p), "no Yamaganda on \(p.vara)")
            XCTAssertEqual(eighth(yama.startTime, in: p), parts.firstIndex(of: "Jupiter"),
                           "Yamaganda on \(p.vara)")
        }
    }

    /// Saturday is the case the old Gulika table got most wrong: Gulika is the
    /// first part of the day, right after sunrise, and it pointed at the
    /// seventh — most of a day away.
    func testSaturdayGulikaBeginsAtSunrise() async throws {
        let saturday = try XCTUnwrap(week.first { ist.component(.weekday, from: $0) == 7 })
        let p = await day(saturday)
        let gulika = try XCTUnwrap(muhurat("Gulik Kaal", in: p) ?? muhurat("Gulika", in: p))
        XCTAssertEqual(eighth(gulika.startTime, in: p), 0)
    }

    /// The muhurat list and the chaughariya list draw the same Amrit period, so
    /// they must place it at the same time. They did not: the muhurat table was
    /// an eighth of the day late on Tuesday, Thursday and Saturday.
    func testAmritAgreesWithTheChaughariyaListEveryDay() async throws {
        for date in week {
            let p = await day(date)
            let fromMuhurats = try XCTUnwrap(muhurat("Amrit Kaal", in: p) ?? muhurat("Amrit", in: p),
                                             "no Amrit muhurat on \(p.vara)")
            let fromChaughariya = try XCTUnwrap(p.chaughariya.first { $0.name == "Amrit" },
                                                "no Amrit chaughariya on \(p.vara)")
            XCTAssertEqual(fromMuhurats.startTime.timeIntervalSince1970,
                           fromChaughariya.startTime.timeIntervalSince1970,
                           accuracy: 1,
                           "\(p.vara): the two lists disagree about Amrit")
        }
    }

    /// Rahu Kaal is not part of the lord scheme and its table is the standard
    /// one. Pinned so the audit that corrected its neighbours is not read as
    /// licence to change it too.
    func testRahuKaalIsUnchanged() async throws {
        let expected = [8, 2, 7, 5, 6, 4, 3]     // Sunday…Saturday, 1-based
        for date in week {
            let p = await day(date)
            let rahu = try XCTUnwrap(muhurat("Rahu Kaal", in: p), "no Rahu Kaal on \(p.vara)")
            let weekdayIndex = ist.component(.weekday, from: date) - 1
            XCTAssertEqual(eighth(rahu.startTime, in: p), expected[weekdayIndex] - 1,
                           "Rahu Kaal on \(p.vara)")
        }
    }
}
