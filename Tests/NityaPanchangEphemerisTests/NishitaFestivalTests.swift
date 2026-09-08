import XCTest
@testable import NityaPanchangEphemeris

/// Festivals dated by the night rather than by sunrise.
final class NishitaFestivalTests: XCTestCase {

    private let repo = EphemerisPanchaangRepository()

    private var ist: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal
    }

    private func date(of name: String, in year: Int) async -> (month: Int, day: Int)? {
        let cal = ist
        let start = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
        let end   = cal.date(from: DateComponents(year: year, month: 12, day: 31))!
        guard let f = await repo.fetchFestivals(from: start, to: end).first(where: { $0.name == name })
        else { return nil }
        return (cal.component(.month, from: f.date), cal.component(.day, from: f.date))
    }

    /// The observance is the Kojagara moon-viewing, so the night that holds
    /// Purnima is the day — not the morning it happens to reach. A Purnima
    /// beginning in the afternoon and ending the next morning covers one night
    /// while touching two sunrises, which is why the readings differ in most
    /// years. Both dates checkable against published panchangs go to the night.
    func testSharadPurnimaTakesTheNightNotTheFollowingSunrise() async {
        let twentyFour = await date(of: "Sharad Purnima", in: 2024)
        XCTAssertEqual(twentyFour?.month, 10)
        XCTAssertEqual(twentyFour?.day, 16, "published 16 Oct; the sunrise reading gives the 17th")

        let twentyFive = await date(of: "Sharad Purnima", in: 2025)
        XCTAssertEqual(twentyFive?.month, 10)
        XCTAssertEqual(twentyFive?.day, 6, "published 6 Oct; the sunrise reading gives the 7th")
    }

    /// A tithi is sampled once a night and averages under twenty-four hours, so
    /// a short one can begin after one midnight and end before the next and
    /// reach no night at all. Ashwina Purnima does that in 2041 and the festival
    /// vanished from the year; the day holding it at sunrise takes it instead.
    func testAPurnimaThatReachesNoNightIsStillFound() async {
        let found = await date(of: "Sharad Purnima", in: 2041)
        XCTAssertNotNil(found, "2041 lost Sharad Purnima entirely")
    }

    func testEveryYearFromTwentyToFiftyHasASharadPurnima() async {
        for year in 2020...2050 {
            let found = await date(of: "Sharad Purnima", in: year)
            XCTAssertNotNil(found, "no Sharad Purnima in \(year)")
        }
    }

    /// The fallback is shared by every Nishita rule, so it must not have moved
    /// the two that were already right. Both dates are published ones.
    func testTheOtherNishitaFestivalsAreUnchanged() async {
        let shivratri = await date(of: "Maha Shivratri", in: 2025)
        XCTAssertEqual(shivratri?.month, 2)
        XCTAssertEqual(shivratri?.day, 26)

        let janmashtami = await date(of: "Krishna Janmashtami", in: 2025)
        XCTAssertEqual(janmashtami?.month, 8)
        XCTAssertEqual(janmashtami?.day, 16)
    }
}
