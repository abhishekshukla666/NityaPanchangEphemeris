//
//  EkadashiTraditionTests.swift
//  NityaPanchangEphemerisTests
//
//  Smarta and Vaishnava, and the days they part.
//

import XCTest
@testable import NityaPanchangEphemeris

final class EkadashiTraditionTests: XCTestCase {

    private let repo = EphemerisPanchaangRepository()
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return c
    }
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func date(of name: String, near: Date, _ tradition: EkadashiTradition) async -> Date? {
        let from = cal.date(byAdding: .day, value: -20, to: near)!
        let to   = cal.date(byAdding: .day, value: 20, to: near)!
        return await repo.fetchFestivals(from: from, to: to, tradition: tradition)
            .first { $0.name == name }
            .map { cal.startOfDay(for: $0.date) }
    }

    /// Vijaya Ekadashi 2027. The tithi holds the sunrises of both 3 and 4 March,
    /// and the vrat is the 4th under *both* traditions — a vriddhi is not what
    /// separates them.
    ///
    /// This is the case that corrected the rule. It was first written asserting
    /// the Smarta date as the 3rd, on the reading that a householder keeps the
    /// first day either way. Four published observances already pinned in this
    /// suite say otherwise — Amalaki 2023, Nirjala 2024, Rama 2024 and this one
    /// — and they are evidence where that reading was recollection.
    func testAVriddhiEkadashiMovesUnderBothTraditions() async {
        let smarta = await date(of: "Vijaya Ekadashi", near: day(2027, 3, 3), .smarta)
        let vaishnava = await date(of: "Vijaya Ekadashi", near: day(2027, 3, 3), .vaishnava)
        XCTAssertEqual(smarta, day(2027, 3, 4))
        XCTAssertEqual(vaishnava, day(2027, 3, 4))
    }

    /// 16 August 2028. No vriddhi here — the tithi reaches one sunrise only —
    /// but it began at 05:12 against a 06:03 sunrise, inside the four ghatis
    /// before it, so Dashami was still running at arunodaya. This is the case
    /// the vriddhi test alone cannot see, and the reason the window exists.
    func testDashamiAtArunodayaAlsoPartsThem() async {
        let smarta = await date(of: "Aja Ekadashi", near: day(2028, 8, 16), .smarta)
        let vaishnava = await date(of: "Aja Ekadashi", near: day(2028, 8, 16), .vaishnava)
        XCTAssertEqual(smarta, day(2028, 8, 16))
        XCTAssertEqual(vaishnava, day(2028, 8, 17), "a Vaishnava's fast moves to the Dwadashi")
    }

    /// Most of them agree, which is the point: this must not move
    /// three-quarters of the year's Ekadashis. Today's own is one of them.
    func testAnUnviddhaEkadashiIsTheSameDayInBoth() async {
        let smarta = await date(of: "Parivartini Ekadashi", near: day(2026, 9, 22), .smarta)
        let vaishnava = await date(of: "Parivartini Ekadashi", near: day(2026, 9, 22), .vaishnava)
        XCTAssertEqual(smarta, day(2026, 9, 22))
        XCTAssertEqual(vaishnava, smarta)
    }

    /// Across a whole year the two differ on a handful of days and agree on the
    /// rest. A change that moved every Ekadashi would still pass the cases
    /// above; this is what catches it.
    func testTheTwoTraditionsAgreeOnMostOfTheYear() async {
        let from = day(2027, 1, 1), to = day(2027, 12, 31)
        let smarta = await repo.fetchFestivals(from: from, to: to, tradition: .smarta)
        let vaishnava = await repo.fetchFestivals(from: from, to: to, tradition: .vaishnava)

        func days(_ list: [HinduFestival]) -> [String: Date] {
            Dictionary(list.filter { $0.name.hasSuffix("Ekadashi") }
                .map { ($0.name, cal.startOfDay(for: $0.date)) },
                uniquingKeysWith: { first, _ in first })
        }
        let a = days(smarta), b = days(vaishnava)
        XCTAssertEqual(a.count, b.count, "the same Ekadashis, whichever tradition")

        let moved = a.filter { b[$0.key] != $0.value }
        XCTAssertLessThanOrEqual(moved.count, 4, "moved: \(moved.keys.sorted())")
        XCTAssertGreaterThan(a.count - moved.count, 18, "most of the year must be untouched")
        // Whatever moved, moved forward by exactly one day.
        for (name, smartaDay) in moved {
            XCTAssertEqual(b[name], cal.date(byAdding: .day, value: 1, to: smartaDay),
                           "\(name) should move one day, not \(String(describing: b[name]))")
        }
    }

    /// The default is what a reader gets who never opens Settings.
    func testTheDefaultIsSmarta() async {
        XCTAssertEqual(EkadashiTradition.default, .smarta)
        // Asserted on a day the two actually differ, or it would pass whichever
        // the default were.
        let implied = await date(of: "Aja Ekadashi", near: day(2028, 8, 16), .default)
        XCTAssertEqual(implied, day(2028, 8, 16))
    }
}
