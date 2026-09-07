import XCTest
@testable import NityaPanchangEphemeris

/// Lohri, which follows the Sankranti rather than the Gregorian calendar.
final class LohriTests: XCTestCase {

    private let repo = EphemerisPanchaangRepository()

    private var ist: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal
    }

    private func januaryFestivals(_ year: Int) async -> [HinduFestival] {
        let cal = ist
        let start = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
        let end   = cal.date(from: DateComponents(year: year, month: 1, day: 31))!
        return await repo.fetchFestivals(from: start, to: end)
    }

    private func day(of name: String, in year: Int) async -> Int? {
        let cal = ist
        guard let f = await januaryFestivals(year).first(where: { $0.name == name }) else { return nil }
        return cal.component(.day, from: f.date)
    }

    /// The defect: a fixed 13 January is wrong in the two-in-five years where
    /// the Sankranti lands on the 15th. Both recent years published as
    /// 14 January — 2023 and 2024 — are in this set.
    func testLohriFallsOnTheFourteenthWhenTheSankrantiIsOnTheFifteenth() async {
        for year in [2023, 2024, 2027, 2028, 2031, 2032, 2035] {
            let lohri = await day(of: "Lohri", in: year)
            XCTAssertEqual(lohri, 14, "Lohri \(year)")
        }
    }

    func testLohriStaysOnTheThirteenthWhenTheSankrantiIsOnTheFourteenth() async {
        for year in [2025, 2026, 2029, 2030, 2033, 2034] {
            let lohri = await day(of: "Lohri", in: year)
            XCTAssertEqual(lohri, 13, "Lohri \(year)")
        }
    }

    /// The relationship itself, which is what makes the dates above follow
    /// rather than being a second table to keep in step.
    func testLohriIsAlwaysTheDayBeforeMakarSankranti() async {
        for year in 2023...2035 {
            let lohri = await day(of: "Lohri", in: year)
            let maghi = await day(of: "Makar Sankranti", in: year)
            XCTAssertNotNil(lohri, "Lohri missing in \(year)")
            XCTAssertNotNil(maghi, "Makar Sankranti missing in \(year)")
            XCTAssertEqual(lohri.map { $0 + 1 }, maghi, "\(year)")
        }
    }

    /// Nothing may still be emitting the old fixed date alongside the computed
    /// one, which would put two Lohris in the same January.
    func testOnlyOneLohriAYear() async {
        for year in [2023, 2026] {
            let all = await januaryFestivals(year).filter { $0.name == "Lohri" }
            XCTAssertEqual(all.count, 1, "\(year)")
        }
    }

    func testLohriIsNoLongerAStaticRule() {
        XCTAssertFalse(allStaticFestivalRules.contains { $0.name == "Lohri" })
    }
}
