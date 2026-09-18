import XCTest
@testable import NityaPanchangEphemeris

/// Ganda Moola, as a window rather than a sunrise flag.
final class GandaMoolaTests: XCTestCase {

    private let repo = EphemerisPanchaangRepository()
    private let lat = 23.1765, lon = 75.7885     // Ujjain

    private var ist: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) async -> PanchangDay {
        await repo.fetchPanchang(for: ist.date(from: DateComponents(year: y, month: m, day: d))!,
                                 latitude: lat, longitude: lon)
    }

    private func parts(_ date: Date) -> (day: Int, hour: Int, minute: Int) {
        let c = ist.dateComponents([.day, .hour, .minute], from: date)
        return (c.day!, c.hour!, c.minute!)
    }

    /// The days the advisory used to stay silent on.
    ///
    /// Jyeshtha begins at 19:53 on 17 September 2026, so the nakshatra AT
    /// SUNRISE that morning is Anuradha and the old flag answered no — while
    /// the whole evening was already Ganda Moola. The same shape as Panchak's
    /// 23rd, on a different row.
    func testADayWhereGandaMoolaBeginsInTheEveningReportsIt() async throws {
        let seventeenth = await day(2026, 9, 17)
        XCTAssertFalse(PanchaangHelper.isGandaMoola(nakshatraName: seventeenth.nakshatra.name),
                       "Anuradha at sunrise — the old rule's answer")
        let window = try XCTUnwrap(seventeenth.gandaMoolaKaal)
        let start = parts(window.startTime)
        XCTAssertEqual([start.day, start.hour, start.minute], [17, 19, 53])
    }

    /// Adjacent Ganda Moola nakshatras are one caution, not two that touch.
    /// Jyeshtha runs into Mula, so the window covers both and ends when Mula
    /// does rather than at the seam between them.
    func testAdjacentNakshatrasMergeIntoOneWindow() async throws {
        let eighteenth = await day(2026, 9, 18)
        let window = try XCTUnwrap(eighteenth.gandaMoolaKaal)
        let end = parts(window.endTime)
        XCTAssertEqual([end.day, end.hour, end.minute], [20, 1, 43],
                       "the end of Mula, not the end of Jyeshtha")
    }

    /// And across the wrap, where Revati is followed by Ashwini.
    func testTheMergeWorksAcrossTheEndOfTheCycle() async throws {
        let twentyEighth = await day(2026, 9, 28)
        let window = try XCTUnwrap(twentyEighth.gandaMoolaKaal)
        XCTAssertEqual(parts(window.startTime).day, 27, "Revati, which began on the 27th")
        XCTAssertEqual(parts(window.endTime).day, 29, "through Ashwini, which ends on the 29th")
    }

    /// Every day it touches reports the same window, so no two screens describe
    /// one Ganda Moola differently.
    func testEveryDayOfOneWindowAgrees() async throws {
        let seventeenth = await day(2026, 9, 17)
        let first = try XCTUnwrap(seventeenth.gandaMoolaKaal)
        for d in 18...19 {
            let onDay = await day(2026, 9, d)
            let window = try XCTUnwrap(onDay.gandaMoolaKaal, "September \(d)")
            XCTAssertEqual(window.startTime.timeIntervalSince(first.startTime), 0, accuracy: 1)
            XCTAssertEqual(window.endTime.timeIntervalSince(first.endTime), 0, accuracy: 1)
        }
    }

    /// The day after it ends reports nothing. Mula ends at 01:43 on the 20th,
    /// before that day's sunrise, so the 20th is clear.
    func testADayThatOnlyContainsTheTailBeforeSunriseIsClear() async {
        let twentieth = await day(2026, 9, 20)
        XCTAssertNil(twentieth.gandaMoolaKaal)
    }

    /// A window never runs longer than two nakshatras, because no third Ganda
    /// Moola nakshatra follows any adjacent pair.
    func testAWindowIsNeverMoreThanTwoNakshatras() async {
        for d in 1...30 {
            let onDay = await day(2026, 9, d)
            guard let window = onDay.gandaMoolaKaal else { continue }
            let hours = window.endTime.timeIntervalSince(window.startTime) / 3600
            XCTAssertLessThan(hours, 56, "September \(d): longer than two nakshatras")
        }
    }
}
