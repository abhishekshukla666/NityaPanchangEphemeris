import XCTest
@testable import NityaPanchangEphemeris

/// Panchak, which is the Moon in Kumbha and Meena — not "the last five
/// nakshatras", which is how it is usually described and half a nakshatra wrong.
final class PanchakTests: XCTestCase {

    private let repo = EphemerisPanchaangRepository()
    private let lat = 23.1765, lon = 75.7885     // Ujjain

    private var ist: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal
    }

    // MARK: - The rule itself

    func testTheTwoSignsThatArePanchak() {
        XCTAssertTrue(PanchaangHelper.isPanchak(moonRashiNumber: 11), "Kumbha")
        XCTAssertTrue(PanchaangHelper.isPanchak(moonRashiNumber: 12), "Meena")
    }

    /// Makara is the sign Dhanishtha's first half sits in, and the one the old
    /// nakshatra-name rule swept in with it.
    func testMakaraIsNotPanchak() {
        XCTAssertFalse(PanchaangHelper.isPanchak(moonRashiNumber: 10))
    }

    func testNoOtherSignIsPanchak() {
        for rashi in 1...9 {
            XCTAssertFalse(PanchaangHelper.isPanchak(moonRashiNumber: rashi), "rashi \(rashi)")
        }
    }

    // MARK: - Against the ephemeris

    private func summaries(_ year: Int) async -> [DailyPanchangSummary] {
        let start = ist.date(from: DateComponents(year: year, month: 1, day: 1))!
        let end   = ist.date(from: DateComponents(year: year, month: 12, day: 31))!
        return await repo.fetchDailyPanchangSummaries(from: start, to: end,
                                                      latitude: lat, longitude: lon)
    }

    private func day(_ y: Int, _ m: Int, _ d: Int, in all: [DailyPanchangSummary]) -> DailyPanchangSummary? {
        let target = ist.date(from: DateComponents(year: y, month: m, day: d))!
        return all.first { ist.isDate($0.date, inSameDayAs: target) }
    }

    /// The seven days of 2026 the old rule got wrong, and why they are the ones.
    ///
    /// Each holds Dhanishtha at sunrise with the Moon still in Makara — the
    /// nakshatra's first half. Naming the dates rather than counting them means
    /// a future change that shifts the boundary by a day fails here rather than
    /// passing a tally.
    func testTheDaysTheNakshatraRuleClaimedAreNotPanchak() async {
        let all = await summaries(2026)
        let wrongly: [(Int, Int)] = [(2, 17), (3, 16), (5, 10), (7, 31), (8, 27), (10, 21), (11, 17)]
        for (month, dayOfMonth) in wrongly {
            guard let d = day(2026, month, dayOfMonth, in: all) else {
                return XCTFail("no summary for 2026-\(month)-\(dayOfMonth)")
            }
            XCTAssertEqual(d.nakshatraName, "Dhanishta", "2026-\(month)-\(dayOfMonth)")
            XCTAssertEqual(d.moonRashiNumber, 10, "still in Makara, so the Moon is in Dhanishtha's first half")
            XCTAssertFalse(PanchaangHelper.isPanchak(moonRashiNumber: d.moonRashiNumber))
        }
    }

    /// The day after each of those is Panchak on both readings — the period is
    /// real, it simply starts later than the old rule said.
    func testPanchakStillBeginsTheFollowingDay() async {
        let all = await summaries(2026)
        for (month, dayOfMonth) in [(2, 18), (3, 17), (5, 11), (8, 1), (8, 28), (10, 22), (11, 18)] {
            guard let d = day(2026, month, dayOfMonth, in: all) else {
                return XCTFail("no summary for 2026-\(month)-\(dayOfMonth)")
            }
            XCTAssertTrue(PanchaangHelper.isPanchak(moonRashiNumber: d.moonRashiNumber),
                          "2026-\(month)-\(dayOfMonth)")
        }
    }

    /// Panchak runs five days, every time, because two signs are 60° and the
    /// Moon covers about 13.2 a day. A rule that opened it early produced runs
    /// of six.
    func testEveryPanchakRunIsFiveOrSixDaysAndNeverSeven() async {
        let all = await summaries(2026).sorted { $0.date < $1.date }
        var runs: [Int] = []
        var current = 0
        for d in all {
            if PanchaangHelper.isPanchak(moonRashiNumber: d.moonRashiNumber) {
                current += 1
            } else if current > 0 {
                runs.append(current)
                current = 0
            }
        }
        if current > 0 { runs.append(current) }

        XCTAssertFalse(runs.isEmpty)
        // 60° of Moon travel is 4.55 days, so a run catches five sunrises,
        // occasionally four when the entry falls just after one.
        for run in runs.dropFirst().dropLast() {
            XCTAssertTrue((4...5).contains(run), "a Panchak of \(run) days: \(runs)")
        }
    }

    /// The boundary itself, to the minute, for the period current when this was
    /// written: the Moon leaves Makara at 21:57 IST on 23 September 2026.
    ///
    /// The DAY that opens Panchak is not the day it first matches — the match is
    /// read at sunrise, and this boundary falls well after it, so 24 September is
    /// the first matching day while the period begins on the 23rd. Both apps
    /// print the boundary beside a date, and printing the 24th next to 9:57 PM
    /// named a moment that does not exist on that date.
    func testTheMomentPanchakOpens() async {
        let day = await repo.fetchPanchang(for: ist.date(from: DateComponents(year: 2026, month: 9, day: 23))!,
                                           latitude: lat, longitude: lon)
        let makaraEnd = try? XCTUnwrap(day.rashis.first?.endTime)
        guard let makaraEnd else { return XCTFail("no Moon sign period on 23 Sep 2026") }

        XCTAssertEqual(day.moonRashiNumber, 10, "Makara at sunrise")
        let parts = ist.dateComponents([.year, .month, .day, .hour, .minute], from: makaraEnd)
        XCTAssertEqual(parts.day, 23)
        XCTAssertEqual(parts.month, 9)
        XCTAssertEqual(parts.hour, 21)
        XCTAssertEqual(parts.minute, 57)
    }

    /// The nakshatras wholly inside the two signs — the four the old rule had
    /// right — must still read as Panchak, or this fix would have traded one
    /// error for a worse one.
    func testTheFourWholeNakshatrasAreStillPanchak() async {
        let all = await summaries(2026)
        let whollyInside = ["Shatabhisha", "Purva Bhadrapada", "Uttara Bhadrapada", "Revati"]
        let missed = all.filter {
            whollyInside.contains($0.nakshatraName)
                && !PanchaangHelper.isPanchak(moonRashiNumber: $0.moonRashiNumber)
        }
        XCTAssertTrue(missed.isEmpty,
                      "these should still be Panchak: \(missed.map { ($0.date, $0.nakshatraName) })")
    }
}
