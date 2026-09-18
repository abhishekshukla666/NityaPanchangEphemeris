import XCTest
@testable import NityaPanchangEphemeris

/// The Vishti (Bhadra) window a day reports.
final class BhadraKaalTests: XCTestCase {

    private let repo = EphemerisPanchaangRepository()
    private let lat = 23.1765, lon = 75.7885     // Ujjain

    private var ist: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal
    }

    private func bhadra(_ y: Int, _ m: Int, _ d: Int) async -> Muhurat? {
        let date = ist.date(from: DateComponents(year: y, month: m, day: d))!
        return await repo.fetchPanchang(for: date, latitude: lat, longitude: lon).bhadraKaal
    }

    private func parts(_ date: Date) -> (day: Int, hour: Int, minute: Int) {
        let c = ist.dateComponents([.day, .hour, .minute], from: date)
        return (c.day!, c.hour!, c.minute!)
    }

    /// A panchang day runs sunrise to sunrise, so a Bhadra falling between
    /// midnight and the next sunrise is reported by TWO days — and both have to
    /// say the same thing about it. They did not: the start was found by
    /// stepping back on a fifteen-minute grid anchored to whichever sunrise the
    /// scan began at, so the 2nd said 04:26 and the 3rd said 04:39 about one
    /// window.
    func testTwoDaysReportingTheSameBhadraAgreeOnIt() async throws {
        let second = await bhadra(2026, 9, 2)
        let third  = await bhadra(2026, 9, 3)
        let onSecond = try XCTUnwrap(second)
        let onThird  = try XCTUnwrap(third)
        // To the second, not the instant. Both days bisect to the same crossing
        // from different starting points, so they land either side of it by
        // under a millisecond — a difference no clock in the app can show, and
        // not the thirteen minutes this is here to catch.
        XCTAssertEqual(onSecond.startTime.timeIntervalSince(onThird.startTime), 0, accuracy: 1)
        XCTAssertEqual(onSecond.endTime.timeIntervalSince(onThird.endTime), 0, accuracy: 1)
    }

    /// And say it to the minute, rather than to the nearest quarter hour.
    func testTheWindowIsStatedToTheMinute() async throws {
        let found = await bhadra(2026, 9, 3)
        let b = try XCTUnwrap(found)
        let start = parts(b.startTime), end = parts(b.endTime)
        XCTAssertEqual([start.day, start.hour, start.minute], [3, 4, 26])
        XCTAssertEqual([end.day, end.hour, end.minute], [3, 15, 27])
    }

    /// The end is the karana's, never the next sunrise.
    ///
    /// It used to be clipped to the panchang day, so the 2nd announced a Bhadra
    /// ending at 06:09 — the 3rd's sunrise — when it ran until 15:27. Telling a
    /// reader that the period they must not begin anything in is over when it
    /// has nine hours left is the one mistake this row cannot make.
    func testTheEndIsNotClippedToTheNextSunrise() async throws {
        let date = ist.date(from: DateComponents(year: 2026, month: 9, day: 2))!
        let day = await repo.fetchPanchang(for: date, latitude: lat, longitude: lon)
        let b = try XCTUnwrap(day.bhadraKaal)

        let nextSunrise = await repo.fetchPanchang(
            for: ist.date(byAdding: DateComponents(day: 1), to: date)!,
            latitude: lat, longitude: lon).sunrise
        XCTAssertGreaterThan(b.endTime, nextSunrise,
                             "this window outlives the panchang day that reports it")
        XCTAssertEqual(parts(b.endTime).hour, 15)
    }

    /// The 2nd has no Bhadra of its own — a karana-by-karana scan of 30 August
    /// to 6 September finds exactly two Vishti windows, 30 Aug 21:17-31 Aug
    /// 08:51 and this one, and nothing between. What the 2nd reports is the
    /// 3rd's, because its panchang day runs to the 3rd's sunrise and so holds
    /// the first hour and three quarters of it.
    ///
    /// That is correct and deliberate. It is also why the row has to say which
    /// day it is talking about: every hour of this window falls on a date the
    /// card is not.
    func testTheSecondReportsTheThirdsBhadra() async throws {
        let found = await bhadra(2026, 9, 2)
        let b = try XCTUnwrap(found)
        XCTAssertEqual(parts(b.startTime).day, 3, "shown on the 2nd, falls on the 3rd")
        XCTAssertEqual(parts(b.endTime).day, 3)
    }

    /// A karana is half a tithi, so a Bhadra is hours rather than a day. A
    /// window that comes back longer than that is a search that ran away.
    func testAWindowIsAKaranaLong() async throws {
        for day in 1...28 {
            guard let b = await bhadra(2026, 9, day) else { continue }
            let hours = b.endTime.timeIntervalSince(b.startTime) / 3600
            XCTAssertGreaterThan(hours, 0, "September \(day)")
            XCTAssertLessThan(hours, 14, "September \(day): \(hours) hours is longer than a karana")
        }
    }
}
