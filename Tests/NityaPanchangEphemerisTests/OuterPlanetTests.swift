import XCTest
import SwissEphWrapper
@testable import NityaPanchangEphemeris

/// Uranus, Neptune and Pluto — computed and named, and kept out of everything
/// that reasons about the nine.
final class OuterPlanetTests: XCTestCase {

    private let wrapper = SwissEphWrapper()
    private let repo = EphemerisPanchaangRepository()
    private let lat = 23.1765, lon = 75.7885     // Ujjain

    private var ist: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) async -> PanchangDay {
        await repo.fetchPanchang(for: ist.date(from: DateComponents(year: y, month: m, day: d))!,
                                 latitude: lat, longitude: lon)
    }

    /// Where they actually are. Checked against the sky rather than against the
    /// code that produced it: in September 2026 sidereal Uranus is in Taurus,
    /// Neptune in Pisces and Pluto in Capricorn — each about twenty-four
    /// degrees behind its tropical position, which is the Lahiri ayanamsha.
    func testTheThreeStandWhereTheSkyPutsThem() async {
        let p = await day(2026, 9, 11)
        XCTAssertEqual(p.outerPlanets.count, 3)
        XCTAssertEqual(p.outerPlanets.map(\.id), [9, 10, 11])
        XCTAssertEqual(p.outerPlanets.map(\.name), ["Uranus", "Neptune", "Pluto"])
        XCTAssertEqual(p.outerPlanets[0].rashiNumber, 2, "Uranus in Taurus")
        XCTAssertEqual(p.outerPlanets[1].rashiNumber, 12, "Neptune in Pisces")
        XCTAssertEqual(p.outerPlanets[2].rashiNumber, 10, "Pluto in Capricorn")
    }

    /// The whole point of the separate array. Anything that reasons about the
    /// Navagraha reads `planetPositions`, and finding a tenth body there would
    /// put Pluto in a dasha or hand it a sign to rule.
    func testTheNineAreStillNine() async {
        let p = await day(2026, 9, 11)
        XCTAssertEqual(p.planetPositions.count, 9)
        XCTAssertEqual(p.planetPositions.map(\.id), Array(0...8))
        XCTAssertTrue(p.planetPositions.allSatisfy { PanchaangHelper.navagrahaIDs.contains($0.id) })
    }

    /// A birth chart does not carry them at all. They belong to the day's sky,
    /// which is where the app shows them; a kundli is read by rules that have
    /// no place for them, so the chart is left as the nine it has always been.
    func testABirthChartIsStillOnlyTheNine() async {
        let chart = await repo.fetchBirthChart(
            for: ist.date(from: DateComponents(year: 1990, month: 6, day: 15, hour: 10, minute: 30))!,
            latitude: lat, longitude: lon)
        XCTAssertEqual(chart.planetPositions.count, 9)
        XCTAssertEqual(chart.planetPositions.map(\.id), Array(0...8))
    }

    /// All three spend about five months of every year retrograde, so a run of
    /// consecutive days must contain both states — a body stuck reading direct
    /// forever would mean the speed is not being read at all.
    func testTheirMotionIsReadNotAssumed() async {
        var directions: Set<Bool> = []
        for month in [2, 5, 8, 11] {
            let p = await day(2026, month, 15)
            directions.formUnion(p.outerPlanets.map(\.isRetrograde))
        }
        XCTAssertEqual(directions, [true, false], "expected both retrograde and direct across the year")
    }

    /// Rashi Parivartan reaches them, which needs a window an order of
    /// magnitude longer than the nine's: Neptune sits in a sign for fourteen
    /// years and Pluto for up to thirty, where Saturn's worst case is three.
    func testTheirSignChangesAreFoundAtAll() async {
        let changes = await repo.fetchRashiChanges(
            from: ist.date(from: DateComponents(year: 2026, month: 9, day: 11))!)
        XCTAssertEqual(changes.map(\.planetID), Array(0...11))
        for outer in changes.filter({ $0.planetID >= 9 }) {
            XCTAssertGreaterThan(outer.date.timeIntervalSinceNow, 0)
        }
    }

    /// And they are real crossings, not the end of the search window reported
    /// as an answer — the failure a longer window invites.
    func testTheirCrossingsAreRealCrossings() {
        let jd = wrapper.getJulianDayUTC(
            from: ist.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 6))!)
        let minute = 1.0 / 1440.0
        for planet in 9...11 {
            let change = wrapper.calculateRashiChangeJD(forPlanet: Int32(planet), fromJulianDay: jd)
            XCTAssertGreaterThan(change, 0, "planet \(planet): nothing found in the window")
            func rashi(_ at: Double) -> Int {
                Int(wrapper.calculatePlanetLongitude(forPlanet: Int32(planet), julianDay: at) / 30.0) + 1
            }
            XCTAssertEqual(rashi(change - minute), rashi(jd), "planet \(planet)")
            XCTAssertNotEqual(rashi(change + minute), rashi(jd), "planet \(planet)")
        }
    }

    /// Pluto is the one the window was sized for. It entered sidereal Capricorn
    /// in 2008 and does not leave until the 2040s, so a search from 2026 has to
    /// look nearly twenty years ahead to find anything at all.
    func testPlutoIsFoundDespiteSittingInOneSignForDecades() {
        let jd = wrapper.getJulianDayUTC(
            from: ist.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 6))!)
        let change = wrapper.calculateRashiChangeJD(forPlanet: 11, fromJulianDay: jd)
        XCTAssertGreaterThan(change - jd, 3650, "expected Pluto's crossing to be more than a decade out")
        XCTAssertLessThan(change - jd, 12000)
    }
}
