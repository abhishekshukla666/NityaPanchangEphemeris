import XCTest
@testable import NityaPanchangEphemeris

/// Sankashti Chaturthi, which is dated by the tithi at moonrise.
final class SankashtiTests: XCTestCase {

    private let repo = EphemerisPanchaangRepository()
    private let lat = 23.1765, lon = 75.7885     // Ujjain

    private var ist: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal
    }

    private func days(year: Int, month: Int) async -> [Int: MonthDayTithis] {
        await repo.fetchMonthTithis(year: year, month: month, latitude: lat, longitude: lon)
    }

    private func sankashtiDays(year: Int, month: Int) async -> [Int] {
        await days(year: year, month: month)
            .filter(\.value.isSankashtiChaturthi).keys.sorted()
    }

    /// The defect a sunrise reading has: January 2026's Chaturthi begins after
    /// sunrise on the 6th and ends before sunrise on the 7th, so it reaches no
    /// sunrise at all and a sunrise rule shows no Sankashti that month. The
    /// moon still rises inside it on the 6th.
    func testAChaturthiThatReachesNoSunriseIsStillFound() async {
        let found = await sankashtiDays(year: 2026, month: 1)
        XCTAssertEqual(found, [6])
    }

    /// The other failure direction, and the one the first version of this rule
    /// missed. A Chaturthi can reach no moonrise at all: moonrise runs about an
    /// hour later each night while a tithi averages under twenty-four hours, so
    /// one beginning just after an evening's moonrise can end before the next.
    /// Six months over 2026-2031 came back empty for that reason.
    ///
    /// 24 Feb 2027 at Ujjain is the case — Chaturthi had not begun at the 23rd's
    /// moonrise and was over by the 24th's, though the 24th held it at sunrise.
    func testAChaturthiThatReachesNoMoonriseIsStillFound() async {
        let found = await sankashtiDays(year: 2027, month: 2)
        XCTAssertEqual(found, [24])
    }

    /// All six that were empty, so a regression cannot quietly drop one again.
    func testNoMonthIsEverEmpty() async {
        for (year, month) in [(2027, 2), (2028, 1), (2028, 5),
                              (2030, 4), (2031, 5), (2031, 8)] {
            let found = await sankashtiDays(year: year, month: month)
            XCTAssertFalse(found.isEmpty, "\(year)-\(month) has no Sankashti")
        }
    }

    /// A lunar year carries twelve or thirteen. Fewer means a month was lost;
    /// more means the fallback took a day the moonrise rule had already given
    /// to another, which it must never do.
    func testEachYearCarriesTwelveOrThirteen() async {
        for year in 2026...2031 {
            var count = 0
            for month in 1...12 {
                count += await sankashtiDays(year: year, month: month).count
            }
            XCTAssertTrue((12...13).contains(count), "\(year) has \(count)")
        }
    }

    /// Exactly one per lunar month, never none and never a pair.
    func testEveryMonthOfTwentyTwentySixHasOne() async {
        for month in 1...12 {
            let found = await sankashtiDays(year: 2026, month: month)
            XCTAssertFalse(found.isEmpty, "no Sankashti in month \(month)")
            XCTAssertLessThanOrEqual(found.count, 2, "month \(month) got \(found)")
        }
    }

    /// A long Chaturthi catching two consecutive moonrises resolves to the day
    /// that also holds it at sunrise. June 2026 is such a month: the moon rises
    /// inside Chaturthi on both the 3rd and the 4th, and only the 4th holds it
    /// from sunrise.
    func testTwoMoonrisesInOneChaturthiResolveToTheSunriseDay() async {
        let found = await sankashtiDays(year: 2026, month: 6)
        XCTAssertEqual(found, [4])
    }

    /// The day chosen must genuinely be a Chaturthi day — either at sunrise or
    /// reaching it during the day — never a Tritiya or Panchami throughout.
    func testTheChosenDayIsAlwaysAroundChaturthi() async {
        for month in 1...12 {
            let month = await days(year: 2026, month: month)
            for (_, d) in month where d.isSankashtiChaturthi {
                XCTAssertTrue((3...5).contains(d.sunriseTithi),
                              "sunrise tithi \(d.sunriseTithi) is nowhere near Chaturthi")
            }
        }
    }

    /// It is not the same thing as the sunrise reading, which is the whole
    /// point: if these agreed everywhere the flag would be redundant.
    func testMoonriseDatingDiffersFromSunriseDating() async {
        var disagreements = 0
        for month in 1...12 {
            let month = await days(year: 2026, month: month)
            for (_, d) in month where d.isSankashtiChaturthi && d.sunriseTithi != 4 {
                disagreements += 1
            }
        }
        XCTAssertGreaterThan(disagreements, 0,
                             "a sunrise reading would have been enough, which contradicts the rule")
    }
}
