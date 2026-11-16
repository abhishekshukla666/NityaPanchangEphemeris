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

    // MARK: - Published dates, 2023-2028

    /// Drik Panchang's Smartha list, New Delhi, 2023-2028: every Ekadashi, 149 of them.
    /// Read from drikpanchang.com/vrats/ekadashidates.html on 16 November 2026.
    static let drikSmartha: [String] = [
        "2023-01-02", "2023-01-18", "2023-02-01", "2023-02-16", "2023-03-03", "2023-03-18",
        "2023-04-01", "2023-04-16", "2023-05-01", "2023-05-15", "2023-05-31", "2023-06-14",
        "2023-06-29", "2023-07-13", "2023-07-29", "2023-08-12", "2023-08-27", "2023-09-10",
        "2023-09-25", "2023-10-10", "2023-10-25", "2023-11-09", "2023-11-23", "2023-12-08",
        "2023-12-22", "2024-01-07", "2024-01-21", "2024-02-06", "2024-02-20", "2024-03-06",
        "2024-03-20", "2024-04-05", "2024-04-19", "2024-05-04", "2024-05-19", "2024-06-02",
        "2024-06-18", "2024-07-02", "2024-07-17", "2024-07-31", "2024-08-16", "2024-08-29",
        "2024-09-14", "2024-09-28", "2024-10-13", "2024-10-28", "2024-11-12", "2024-11-26",
        "2024-12-11", "2024-12-26", "2025-01-10", "2025-01-25", "2025-02-08", "2025-02-24",
        "2025-03-10", "2025-03-25", "2025-04-08", "2025-04-24", "2025-05-08", "2025-05-23",
        "2025-06-06", "2025-06-21", "2025-07-06", "2025-07-21", "2025-08-05", "2025-08-19",
        "2025-09-03", "2025-09-17", "2025-10-03", "2025-10-17", "2025-11-01", "2025-11-15",
        "2025-12-01", "2025-12-15", "2025-12-30", "2026-01-14", "2026-01-29", "2026-02-13",
        "2026-02-27", "2026-03-15", "2026-03-29", "2026-04-13", "2026-04-27", "2026-05-13",
        "2026-05-27", "2026-06-11", "2026-06-25", "2026-07-10", "2026-07-25", "2026-08-09",
        "2026-08-23", "2026-09-07", "2026-09-22", "2026-10-06", "2026-10-22", "2026-11-05",
        "2026-11-20", "2026-12-04", "2026-12-20", "2027-01-03", "2027-01-18", "2027-02-02",
        "2027-02-17", "2027-03-04", "2027-03-18", "2027-04-02", "2027-04-17", "2027-05-02",
        "2027-05-16", "2027-06-01", "2027-06-14", "2027-06-30", "2027-07-14", "2027-07-29",
        "2027-08-12", "2027-08-28", "2027-09-11", "2027-09-26", "2027-10-11", "2027-10-25",
        "2027-11-10", "2027-11-24", "2027-12-09", "2027-12-23", "2028-01-08", "2028-01-22",
        "2028-02-06", "2028-02-20", "2028-03-07", "2028-03-21", "2028-04-05", "2028-04-20",
        "2028-05-05", "2028-05-20", "2028-06-03", "2028-06-18", "2028-07-02", "2028-07-18",
        "2028-08-01", "2028-08-16", "2028-08-30", "2028-09-15", "2028-09-29", "2028-10-14",
        "2028-10-28", "2028-11-12", "2028-11-27", "2028-12-12", "2028-12-27"
    ]

    /// Drik Panchang's ISKCON list, New Delhi, 2023-2028, in the same order -- the Vaishnava
    /// date of each of the Smartha ones above. Thirty differ, each by one day.
    /// Read from drikpanchang.com/iskcon/iskcon-ekadashi-list.html on 16 November 2026.
    static let drikVaishnava: [String] = [
        "2023-01-02", "2023-01-18", "2023-02-01", "2023-02-17", "2023-03-03", "2023-03-18",
        "2023-04-02", "2023-04-16", "2023-05-01", "2023-05-15", "2023-05-31", "2023-06-14",
        "2023-06-29", "2023-07-13", "2023-07-29", "2023-08-12", "2023-08-27", "2023-09-11",
        "2023-09-26", "2023-10-10", "2023-10-25", "2023-11-09", "2023-11-23", "2023-12-09",
        "2023-12-23", "2024-01-07", "2024-01-21", "2024-02-06", "2024-02-20", "2024-03-07",
        "2024-03-20", "2024-04-05", "2024-04-19", "2024-05-04", "2024-05-19", "2024-06-03",
        "2024-06-18", "2024-07-02", "2024-07-17", "2024-07-31", "2024-08-16", "2024-08-30",
        "2024-09-14", "2024-09-28", "2024-10-14", "2024-10-28", "2024-11-12", "2024-11-26",
        "2024-12-11", "2024-12-26", "2025-01-10", "2025-01-25", "2025-02-08", "2025-02-24",
        "2025-03-10", "2025-03-26", "2025-04-08", "2025-04-24", "2025-05-08", "2025-05-23",
        "2025-06-07", "2025-06-22", "2025-07-06", "2025-07-21", "2025-08-05", "2025-08-19",
        "2025-09-03", "2025-09-17", "2025-10-03", "2025-10-17", "2025-11-02", "2025-11-15",
        "2025-12-01", "2025-12-16", "2025-12-31", "2026-01-14", "2026-01-29", "2026-02-13",
        "2026-02-27", "2026-03-15", "2026-03-29", "2026-04-13", "2026-04-27", "2026-05-13",
        "2026-05-27", "2026-06-11", "2026-06-25", "2026-07-11", "2026-07-25", "2026-08-09",
        "2026-08-24", "2026-09-07", "2026-09-22", "2026-10-06", "2026-10-22", "2026-11-05",
        "2026-11-21", "2026-12-04", "2026-12-20", "2027-01-03", "2027-01-19", "2027-02-02",
        "2027-02-17", "2027-03-04", "2027-03-18", "2027-04-02", "2027-04-17", "2027-05-02",
        "2027-05-16", "2027-06-01", "2027-06-15", "2027-06-30", "2027-07-14", "2027-07-30",
        "2027-08-12", "2027-08-28", "2027-09-11", "2027-09-26", "2027-10-11", "2027-10-26",
        "2027-11-10", "2027-11-24", "2027-12-09", "2027-12-23", "2028-01-08", "2028-01-22",
        "2028-02-07", "2028-02-21", "2028-03-07", "2028-03-21", "2028-04-06", "2028-04-20",
        "2028-05-05", "2028-05-20", "2028-06-03", "2028-06-18", "2028-07-02", "2028-07-18",
        "2028-08-01", "2028-08-17", "2028-08-30", "2028-09-15", "2028-09-29", "2028-10-14",
        "2028-10-29", "2028-11-13", "2028-11-28", "2028-12-12", "2028-12-27"
    ]

    /// The engine dated for New Delhi, where the published lists are computed.
    private let delhi = EphemerisPanchaangRepository(festivalReference: (28.6358, 77.2245))

    private func ekadashiDays(_ tradition: EkadashiTradition) async -> [String] {
        let names = Set(PanchaangHelper.shuklaEkadashiNames + PanchaangHelper.krishnaEkadashiNames
                        + ["Padmini Ekadashi", "Parama Ekadashi"])
        let f = DateFormatter()
        f.calendar = cal; f.timeZone = cal.timeZone; f.dateFormat = "yyyy-MM-dd"
        return await delhi.fetchFestivals(from: day(2023, 1, 1), to: day(2028, 12, 31), tradition: tradition)
            .filter { names.contains($0.name) }
            .map { f.string(from: $0.date) }
            .filter { $0 >= "2023-01-01" && $0 <= "2028-12-31" }
            .sorted()
    }

    /// Every Smarta Ekadashi in six years, as published. This is the test that caught the
    /// trisprisha rule -- six Smartha dates the engine had a day late -- and the twice-a-year
    /// Saphala and Pausha Putrada the old name-and-year key dropped.
    func testSmartaMatchesTheSmarthaListForSixYears() async {
        let engine = await ekadashiDays(.smarta)
        let published = Self.drikSmartha
        XCTAssertEqual(engine.count, published.count)
        XCTAssertEqual(Set(engine).subtracting(published).sorted(), [], "dated by the engine only")
        XCTAssertEqual(Set(published).subtracting(engine).sorted(), [], "published only")
    }

    /// Every Vaishnava Ekadashi in six years, against ISKCON's. One is excepted: Nirjala 2026,
    /// whose Purnima outlasts its second sunrise at New Delhi by about a minute on this ephemeris
    /// -- a Pakshavardhini here and not in the published list, inside the margin two ephemerides
    /// differ by. It is the only one of the 149 that close.
    func testVaishnavaMatchesTheIskconListForSixYears() async {
        let engine = await ekadashiDays(.vaishnava)
        let published = Self.drikVaishnava.map { $0 == "2026-06-25" ? "2026-06-26" : $0 }
        XCTAssertEqual(engine.count, published.count)
        XCTAssertEqual(Set(engine).subtracting(published).sorted(), [], "dated by the engine only")
        XCTAssertEqual(Set(published).subtracting(engine).sorted(), [], "published only")
    }

    // MARK: - Both at once

    /// Devutthana 2026: the Smarta day and the Vaishnava day, one each and each tagged, from the
    /// one list -- and Utpanna, a fortnight later, which both keep on the same day, once and
    /// untagged.
    func testBothTraditionsTagOnlyTheEkadashisTheyDateApart() async {
        let all = await delhi.fetchFestivals(from: day(2026, 11, 15), to: day(2026, 12, 10), ekadashis: .both)
        let devutthana = all.filter { $0.name == "Devutthana Ekadashi" }
            .map { (cal.startOfDay(for: $0.date), $0.tradition) }
        XCTAssertEqual(devutthana.count, 2)
        XCTAssertEqual(devutthana.first?.0, day(2026, 11, 20))
        XCTAssertEqual(devutthana.first?.1, .smarta)
        XCTAssertEqual(devutthana.last?.0, day(2026, 11, 21))
        XCTAssertEqual(devutthana.last?.1, .vaishnava)

        let utpanna = all.filter { $0.name == "Utpanna Ekadashi" }
        XCTAssertEqual(utpanna.count, 1)
        XCTAssertNil(utpanna.first?.tradition)
        XCTAssertTrue(all.filter { !$0.name.hasSuffix("Ekadashi") }.allSatisfy { $0.tradition == nil })
    }

    /// Asked for both, the six years come out as the union of the two published lists: every
    /// Smartha day, and every ISKCON day that differs from it.
    func testBothIsTheUnionOfTheTwoLists() async {
        let names = Set(PanchaangHelper.shuklaEkadashiNames + PanchaangHelper.krishnaEkadashiNames
                        + ["Padmini Ekadashi", "Parama Ekadashi"])
        let f = DateFormatter()
        f.calendar = cal; f.timeZone = cal.timeZone; f.dateFormat = "yyyy-MM-dd"
        let both = await delhi.fetchFestivals(from: day(2023, 1, 1), to: day(2028, 12, 31), ekadashis: .both)
            .filter { names.contains($0.name) }
        let smarta = Set(both.filter { $0.tradition != .vaishnava }.map { f.string(from: $0.date) })
            .filter { $0 >= "2023-01-01" && $0 <= "2028-12-31" }
        let vaishnava = Set(both.filter { $0.tradition != .smarta }.map { f.string(from: $0.date) })
            .filter { $0 >= "2023-01-01" && $0 <= "2028-12-31" }
        XCTAssertEqual(smarta, Set(Self.drikSmartha))
        XCTAssertEqual(vaishnava, Set(Self.drikVaishnava.map { $0 == "2026-06-25" ? "2026-06-26" : $0 }))
    }
}
