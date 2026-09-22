//
//  AdhikEkadashiTests.swift
//  NityaPanchangEphemerisTests
//
//  The Ekadashis of an intercalary month.
//

import XCTest
@testable import NityaPanchangEphemeris

/// Both Ekadashis of an Adhik month are Padmini, and no rule in the festival
/// table can name them: every rule matches on a month number the Adhik month
/// shares with the ordinary one, and the scan skips the whole table while an
/// Adhik month runs. So the calendar drew nothing at all for a month, once
/// every thirty-three, while the Quick Lookup tile named them correctly.
final class AdhikEkadashiTests: XCTestCase {

    private let repo = EphemerisPanchaangRepository()
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return c
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func ekadashis(_ from: Date, _ to: Date) async -> [(String, Date)] {
        await repo.fetchFestivals(from: from, to: to)
            .filter { $0.name.hasSuffix("Ekadashi") }
            .map { ($0.name, $0.date) }
            .sorted { $0.1 < $1.1 }
    }

    /// Adhik Jyeshtha 2026 runs 17 May – 15 June and holds three Ekadashis:
    /// a vriddhi pair on 26/27 May, kept on the second, and one on 11 June.
    func testAnAdhikMonthsEkadashisAreDrawn() async {
        let found = await ekadashis(day(2026, 5, 17), day(2026, 6, 15))
        XCTAssertEqual(found.count, 2, "both pakshas, one Ekadashi each")
        XCTAssertTrue(found.allSatisfy { $0.0 == "Padmini Ekadashi" },
                      "an Adhik month's Ekadashis are Padmini: \(found.map(\.0))")

        let days = found.map { cal.component(.day, from: $0.1) }
        XCTAssertEqual(days, [27, 11], "the vriddhi is kept on the second day")
    }

    /// The reason the whole rule table is skipped during an Adhik month: a rule
    /// matching on month 3 would fire in Adhik Jyeshtha and spend the year's
    /// Nirjala a month early, leaving the real one unnamed. This asserts the
    /// Padmini block did not reopen that door.
    func testTheOrdinaryMonthKeepsItsOwnEkadashi() async {
        let found = await ekadashis(day(2026, 6, 16), day(2026, 7, 15))
        XCTAssertTrue(found.contains { $0.0 == "Nirjala Ekadashi" },
                      "real Jyeshtha still gets Nirjala: \(found.map(\.0))")
        XCTAssertFalse(found.contains { $0.0 == "Padmini Ekadashi" },
                       "Padmini belongs to the Adhik month alone")
    }

    /// An ordinary year has no Padmini at all. Guards the failure that would be
    /// least visible: a block that fired every month rather than only inside an
    /// Adhik one.
    func testAnOrdinaryYearHasNoPadmini() async {
        let found = await ekadashis(day(2027, 1, 1), day(2027, 12, 31))
        XCTAssertFalse(found.contains { $0.0 == "Padmini Ekadashi" })
        // Counted in days, not names: Margashirsha Shukla carries two — Mokshada
        // nationwide and Vaikuntha for the south — on the one day.
        let days = Set(found.map { cal.startOfDay(for: $0.1) })
        XCTAssertEqual(days.count, 24, "twenty-four Ekadashi days in a year with no Adhik month")
    }
}
