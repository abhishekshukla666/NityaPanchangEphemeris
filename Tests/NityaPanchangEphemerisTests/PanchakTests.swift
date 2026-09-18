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

    // MARK: - The window, not the day flag

    private func panchakWindow(_ y: Int, _ m: Int, _ d: Int) async -> Muhurat? {
        let date = ist.date(from: DateComponents(year: y, month: m, day: d))!
        return await repo.fetchPanchang(for: date, latitude: lat, longitude: lon).panchakKaal
    }

    /// The day the advisory used to stay silent on.
    ///
    /// Panchak opens at 21:57 on 23 September, so the Moon is still in Makara at
    /// that morning's sunrise. A rule that asks which sign the Moon is in AT
    /// SUNRISE answers no, and the dashboard's advisory said nothing through an
    /// evening that was already Panchak — while the Quick Lookup card, which
    /// reasons about the period, had the 23rd right all along.
    func testTheDayPanchakOpensReportsItEvenThoughSunriseDoesNot() async throws {
        let date = ist.date(from: DateComponents(year: 2026, month: 9, day: 23))!
        let day = await repo.fetchPanchang(for: date, latitude: lat, longitude: lon)

        XCTAssertEqual(day.moonRashiNumber, 10, "Makara at sunrise — the old rule's answer")
        let window = try XCTUnwrap(day.panchakKaal, "and yet the day holds Panchak")
        let start = ist.dateComponents([.day, .hour, .minute], from: window.startTime)
        XCTAssertEqual([start.day, start.hour, start.minute], [23, 21, 57])
    }

    /// Every day it touches reports the same window, so no two screens can
    /// describe one Panchak differently.
    func testEveryDayOfOnePanchakReportsTheSameWindow() async throws {
        let found = await panchakWindow(2026, 9, 23)
        let first = try XCTUnwrap(found)
        for day in 24...28 {
            let onDay = await panchakWindow(2026, 9, day)
            let window = try XCTUnwrap(onDay, "September \(day)")
            XCTAssertEqual(window.startTime.timeIntervalSince(first.startTime), 0, accuracy: 1,
                           "September \(day)")
            XCTAssertEqual(window.endTime.timeIntervalSince(first.endTime), 0, accuracy: 1,
                           "September \(day)")
        }
    }

    /// And the days either side report none. The 29th is the one worth naming:
    /// its panchang day begins after Panchak ended at 10:16 on the 28th.
    func testTheDaysEitherSideReportNothing() async {
        let before = await panchakWindow(2026, 9, 22)
        let after = await panchakWindow(2026, 9, 29)
        XCTAssertNil(before)
        XCTAssertNil(after)
    }

    /// The window is the two signs exactly — 60° of Moon travel, four and a half
    /// days — rather than a slice of one day.
    func testTheWindowIsTheWholeOfBothSigns() async throws {
        let found = await panchakWindow(2026, 9, 25)
        let window = try XCTUnwrap(found)
        let days = window.endTime.timeIntervalSince(window.startTime) / 86_400
        XCTAssertEqual(days, 4.5, accuracy: 0.4)
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
