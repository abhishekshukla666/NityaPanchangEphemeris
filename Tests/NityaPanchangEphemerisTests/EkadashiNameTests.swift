//
//  EkadashiNameTests.swift
//  NityaPanchangEphemerisTests
//
//  One name per Ekadashi, wherever the app asks for it.
//

import XCTest
@testable import NityaPanchangEphemeris

final class EkadashiNameTests: XCTestCase {

    /// The calendar draws festival rules; the Quick Lookup tile asks
    /// getEkadashiName. They used to be two hand-written lists and had drifted
    /// on five of the twenty-four, so the same day was named two ways in one
    /// app. This is the test that could not have been written while they were
    /// separate, and the reason they no longer are.
    func testEveryFestivalRuleAgreesWithTheEkadashiTable() {
        // Nationwide rules only. Vaikuntha Ekadashi is Margashirsha Shukla under
        // the name the south keeps it by, and it is meant to differ from
        // Mokshada — a southern reader gets the one their temple opens its
        // Vaikuntha Dwara for. Region-specific rules are second names for a day
        // that already has one, not a second opinion about it.
        let rules = allFestivalRules.filter {
            $0.name.hasSuffix("Ekadashi") && $0.regions == .all
        }
        XCTAssertEqual(rules.count, 24, "twelve months, two Ekadashis each")

        for rule in rules {
            let paksha: Paksha = rule.tithiNumber == 26 ? .shukla : .krishna
            let expected = PanchaangHelper.getEkadashiName(lunarMonth: rule.lunarMonth,
                                                           paksha: paksha)
            XCTAssertEqual(rule.name, expected,
                           "month \(rule.lunarMonth) tithi \(rule.tithiNumber)")
        }
    }

    /// The five that were wrong, pinned by name so a future edit to either side
    /// has to mean it.
    func testTheFourNamesThatHadDrifted() {
        // पापांकुशा, "the goad against sin" — not पाशांकुशा, a noose-goad, which
        // is a different word and was simply an error.
        XCTAssertEqual(name(7, .shukla), "Papankusha Ekadashi")
        // Mokshada nationwide. The south's own name for the day is carried by a
        // separate regional rule rather than by replacing this one, so a reader
        // in Chennai sees Vaikuntha Ekadashi and everyone else sees Mokshada.
        XCTAssertEqual(name(9, .shukla), "Mokshada Ekadashi")
        // Two Putrada Ekadashis a year, so neither can go by the bare name.
        XCTAssertEqual(name(5, .shukla), "Shravana Putrada Ekadashi")
        XCTAssertEqual(name(10, .shukla), "Pausha Putrada Ekadashi")
        XCTAssertEqual(name(1, .krishna), "Papamochani Ekadashi")
    }

    /// Bhadrapada Shukla. Both names are current — Vishnu turns onto his other
    /// side at the midpoint of Chaturmas, and one name says "side" where the
    /// other says "turning" — and this app serves the Hindi belt, where the
    /// panchangs say Parivartini.
    func testBhadrapadaShuklaIsParivartini() {
        XCTAssertEqual(name(6, .shukla), "Parivartini Ekadashi")
    }

    /// An Adhik month repeats a month number, so the table would otherwise hand
    /// back the ordinary month's name. Both of its Ekadashis are Padmini.
    func testAnAdhikMonthsEkadashisAreBothPadmini() {
        XCTAssertEqual(PanchaangHelper.getEkadashiName(lunarMonth: 3, paksha: .shukla, isAdhik: true),
                       "Padmini Ekadashi")
        XCTAssertEqual(PanchaangHelper.getEkadashiName(lunarMonth: 3, paksha: .krishna, isAdhik: true),
                       "Padmini Ekadashi")
    }

    /// No two Ekadashis share a name, which is the property the two qualified
    /// Putradas exist to preserve.
    func testTheTwentyFourNamesAreDistinct() {
        let names = PanchaangHelper.shuklaEkadashiNames + PanchaangHelper.krishnaEkadashiNames
        XCTAssertEqual(Set(names).count, 24, "a repeated name cannot say which day it means")
    }

    private func name(_ month: Int, _ paksha: Paksha) -> String {
        PanchaangHelper.getEkadashiName(lunarMonth: month, paksha: paksha)
    }
}
