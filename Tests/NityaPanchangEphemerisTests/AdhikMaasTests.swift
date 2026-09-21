//
//  AdhikMaasTests.swift
//  NityaPanchangEphemerisTests
//
//  `MonthDayTithis.isAdhikMaas`, against the window the calendar draws.
//

import XCTest
@testable import NityaPanchangEphemeris

final class AdhikMaasTests: XCTestCase {

    private let repo = EphemerisPanchaangRepository()
    private let delhi = (lat: 28.61, lon: 77.21)

    private func tithis(_ year: Int, _ month: Int) async -> [Int: MonthDayTithis] {
        await repo.fetchMonthTithis(year: year, month: month,
                                    latitude: delhi.lat, longitude: delhi.lon)
    }

    /// Adhik Jyeshtha 2026, the most recent window, pinned at both ends.
    ///
    /// The boundary days are the point: a test that only asserted somewhere in
    /// the middle would pass against a flag that was off by a week.
    func testTheAdhikJyeshtha2026WindowStartsAndEndsWhereItShould() async {
        let may  = await tithis(2026, 5)
        let june = await tithis(2026, 6)

        XCTAssertEqual(may[16]?.isAdhikMaas, false, "16 May is the last ordinary day")
        XCTAssertEqual(may[17]?.isAdhikMaas, true,  "Adhik Jyeshtha opens on 17 May")
        XCTAssertEqual(may[31]?.isAdhikMaas, true,  "still inside it at the month's end")

        XCTAssertEqual(june[1]?.isAdhikMaas,  true,  "and still inside it on 1 June")
        XCTAssertEqual(june[15]?.isAdhikMaas, true,  "15 June is its last day")
        XCTAssertEqual(june[16]?.isAdhikMaas, false, "ordinary Jyeshtha resumes on 16 June")
    }

    /// Adhik Chaitra 2029 — the next one, and the first this feature will show
    /// a reader who has not gone looking for it.
    func testTheAdhikChaitra2029WindowStartsAndEndsWhereItShould() async {
        let march = await tithis(2029, 3)
        let april = await tithis(2029, 4)

        XCTAssertEqual(march[15]?.isAdhikMaas, false)
        XCTAssertEqual(march[16]?.isAdhikMaas, true, "Adhik Chaitra opens on 16 March")
        XCTAssertEqual(april[13]?.isAdhikMaas, true, "13 April is its last day")
        XCTAssertEqual(april[14]?.isAdhikMaas, false)
    }

    /// An ordinary month carries the flag nowhere. Guards the failure that
    /// would be least visible on the calendar: a run that never ends, which
    /// reads as a tint the reader assumes is decoration.
    func testAnOrdinaryMonthIsNeverAdhik() async {
        let september = await tithis(2026, 9)
        XCTAssertFalse(september.values.contains { $0.isAdhikMaas },
                       "September 2026 sits three months past Adhik Jyeshtha")
    }

    /// The window the calendar draws and the window a tapped day reports are
    /// the same window. These come from different code paths —
    /// `computeMonthTithis` reads its own sunrise, `fetchPanchang` computes the
    /// month name — and the calendar tint would contradict the day detail
    /// sheet if they ever parted.
    func testTheMonthGridAgreesWithTheDayItself() async {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let grid = await tithis(2026, 5)

        for day in [16, 17, 20, 31] {
            var c = DateComponents(year: 2026, month: 5, day: day, hour: 12)
            c.timeZone = cal.timeZone
            let date = cal.date(from: c)!
            let panchang = await repo.fetchPanchang(for: date,
                                                    latitude: delhi.lat, longitude: delhi.lon)
            XCTAssertEqual(grid[day]?.isAdhikMaas, panchang.isAdhikMaas,
                           "grid and day disagree about \(day) May 2026")
        }
    }
}
