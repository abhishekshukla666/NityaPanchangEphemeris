import XCTest
import Foundation
@testable import NityaPanchangEphemeris

final class RegionalFestivalTests: XCTestCase {
    private func festivals(_ year: Int) async -> [HinduFestival] {
        let repo = EphemerisPanchaangRepository()
        var c = DateComponents(); c.year = year; c.month = 1; c.day = 1
        let cal = Calendar.current
        let start = cal.date(from: c)!
        let end = cal.date(byAdding: .year, value: 1, to: start)!
        return await repo.fetchFestivals(from: start, to: end)
    }

    func testRegionalDaysAppearAndCarryTheirRegion() async {
        let all = await festivals(2026)
        let byName = Dictionary(grouping: all, by: \.name)
        for name in ["Bestu Varas", "Labh Pancham", "Gowri Habba", "Bathukamma",
                     "Atla Tadde", "Varalakshmi Vratam", "Vaikuntha Ekadashi"] {
            XCTAssertNotNil(byName[name]?.first, "\(name) was never produced")
        }
        XCTAssertEqual(byName["Bestu Varas"]?.first?.regions, .gujarat)
        XCTAssertEqual(byName["Gowri Habba"]?.first?.regions, .karnataka)
        XCTAssertEqual(byName["Bathukamma"]?.first?.regions, .telugu)
    }

    /// The whole point of the weekday constraint: this one is dated by the day
    /// of the week, not by a tithi, so a wrong weekday means the rule is not
    /// doing what it says.
    func testVaralakshmiFallsOnAFriday() async {
        let all = await festivals(2026)
        guard let v = all.first(where: { $0.name == "Varalakshmi Vratam" }) else {
            return XCTFail("Varalakshmi Vratam missing")
        }
        XCTAssertEqual(Calendar.current.component(.weekday, from: v.date), 6,
                       "expected a Friday, got \(v.date)")
    }

    /// Bestu Varas shares its date with Govardhan Puja — one Kartika Shukla
    /// Pratipada, two names. If they ever diverge, one of the two is wrong.
    func testBestuVarasSharesItsDateWithGovardhanPuja() async {
        let all = await festivals(2026)
        let bestu = all.first { $0.name == "Bestu Varas" }?.date
        let govardhan = all.first { $0.name == "Govardhan Puja" }?.date
        XCTAssertNotNil(bestu); XCTAssertNotNil(govardhan)
        XCTAssertEqual(bestu, govardhan)
    }

    func testPanIndianDaysStillCarryEveryRegion() async {
        let all = await festivals(2026)
        let diwali = all.first { $0.name == "Diwali" }
        XCTAssertEqual(diwali?.regions, .all, "existing rules must not be narrowed")
    }

    /// Each of these regional days shares its date with a day the pan-Indian
    /// table already computes. They are different observances under different
    /// names, but they are the same tithi — so if one ever moves without the
    /// other, one of the two rules is wrong.
    func testRegionalDaysAgreeWithTheirPanIndianTwin() async {
        let all = await festivals(2026)
        func date(_ name: String) -> Date? { all.first { $0.name == name }?.date }

        // Kartika Shukla Pratipada, three names.
        XCTAssertEqual(date("Bestu Varas"), date("Govardhan Puja"))
        XCTAssertEqual(date("Balipadyami"), date("Govardhan Puja"))
        // Bhadrapada Shukla Tritiya.
        XCTAssertEqual(date("Gowri Habba"), date("Hartalika Teej"))
        // Mahalaya Amavasya opens the nine nights of Bathukamma.
        XCTAssertEqual(date("Bathukamma"), date("Pitra Amavasya"))
        // Margashirsha Shukla Ekadashi under its southern name.
        XCTAssertEqual(date("Vaikuntha Ekadashi"), date("Mokshada Ekadashi"))
    }

    /// Boddemma runs the nine days before Bathukamma. Getting the Purnimanta
    /// month wrong put it a month early and behind the festival it precedes.
    func testBoddemmaPrecedesBathukamma() async {
        let all = await festivals(2026)
        guard let boddemma = all.first(where: { $0.name == "Boddemma" })?.date,
              let bathukamma = all.first(where: { $0.name == "Bathukamma" })?.date else {
            return XCTFail("one of the two is missing")
        }
        XCTAssertLessThan(boddemma, bathukamma)
    }
}
