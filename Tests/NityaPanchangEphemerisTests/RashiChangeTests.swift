import XCTest
import SwissEphWrapper
@testable import NityaPanchangEphemeris

/// Rashi Parivartan — when each graha next changes sign.
///
/// The search strides by "degrees to the nearest sign boundary divided by this
/// graha's top speed", which is what makes a three-year Saturn search cost a few
/// milliseconds instead of thousands of ephemeris calls. The stride is only safe
/// because a graha cannot leave its sign sooner than that, so these tests are
/// mostly about that claim: every answer must be a real crossing, and the first
/// one.
final class RashiChangeTests: XCTestCase {

    private let wrapper = SwissEphWrapper()
    private let repo = EphemerisPanchaangRepository()
    private let minute = 1.0 / 1440.0

    private var ist: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal
    }

    private func jd(_ y: Int, _ m: Int, _ d: Int) -> Double {
        wrapper.getJulianDayUTC(from: ist.date(from: DateComponents(year: y, month: m, day: d, hour: 6))!)
    }

    private func rashi(_ planet: Int, at jd: Double) -> Int {
        Int(wrapper.calculatePlanetLongitude(forPlanet: Int32(planet), julianDay: jd) / 30.0) + 1
    }

    /// The instant returned has to be one the sign actually changes at: the old
    /// sign a minute before, a different one a minute after. An off-by-a-window
    /// answer — the search reporting its own limit — passes a "returns a date"
    /// check and fails this one.
    func testEveryGrahaLandsOnARealCrossing() {
        let start = jd(2026, 9, 11)
        for planet in 0...8 {
            let change = wrapper.calculateRashiChangeJD(forPlanet: Int32(planet), fromJulianDay: start)
            XCTAssertGreaterThan(change, 0, "planet \(planet): no crossing found")
            XCTAssertEqual(rashi(planet, at: change - minute), rashi(planet, at: start),
                           "planet \(planet): still in the old sign a minute before")
            XCTAssertNotEqual(rashi(planet, at: change + minute), rashi(planet, at: start),
                              "planet \(planet): sign unchanged a minute after")
        }
    }

    /// And the *first* crossing. A stride that overshot would return a later,
    /// perfectly real crossing and look correct — so the fast planets are swept
    /// at six-hour steps over the whole interval and must not change sign
    /// anywhere inside it.
    func testNothingIsSkippedOnTheWayThere() {
        let start = jd(2026, 9, 11)
        // The Moon, Sun, Mars and Mercury: fast enough that a fine sweep of the
        // whole interval is affordable, and the ones a stride could overshoot.
        for planet in [0, 1, 2, 3] {
            let change = wrapper.calculateRashiChangeJD(forPlanet: Int32(planet), fromJulianDay: start)
            let startingRashi = rashi(planet, at: start)
            var probe = start
            while probe < change - minute {
                XCTAssertEqual(rashi(planet, at: probe), startingRashi,
                               "planet \(planet): an earlier crossing was stepped over")
                probe += 0.25
            }
        }
    }

    /// The case the stride bound exists for, and the only one that can actually
    /// break it: a graha that leaves a sign and comes straight back.
    ///
    /// Mercury entered Makara on 28 Dec 2022 and retrograded back into Dhanu
    /// three days later — the tightest such excursion in fifteen years of the
    /// ephemeris. Searching from 15 December must find the 28th. It is worth
    /// saying what this test cost to find: a stride of three times the safe
    /// bound passes every other test in this file and a thousand-case sweep of
    /// five grahas, and fails only here — it steps over the 28th, over the
    /// return on the 31st, and reports 7 February 2023 instead, forty-one days
    /// late and perfectly plausible-looking.
    func testAGrahaThatLeavesASignAndComesBackIsNotSteppedOver() {
        let start = jd(2022, 12, 15)
        let change = wrapper.calculateRashiChangeJD(forPlanet: 3, fromJulianDay: start)
        let parts = ist.dateComponents([.year, .month, .day],
                                       from: Date(timeIntervalSince1970: (change - 2440587.5) * 86400))
        XCTAssertEqual(parts.year, 2022)
        XCTAssertEqual(parts.month, 12)
        XCTAssertEqual(parts.day, 28, "stepped over the excursion into Makara")
    }

    /// Retrograde motion leaves through the boundary behind, so the sign it
    /// lands in is one *less*. Rahu and Ketu are the reliable case — the mean
    /// node only ever moves backward.
    func testARetrogradeGrahaMovesIntoTheSignBehindIt() async {
        let changes = await repo.fetchRashiChanges(
            from: ist.date(from: DateComponents(year: 2026, month: 9, day: 11))!)
        let start = jd(2026, 9, 11)
        for node in [7, 8] {
            guard let change = changes.first(where: { $0.planetID == node }) else {
                return XCTFail("no crossing for planet \(node)")
            }
            let from = rashi(node, at: start)
            let expected = from == 1 ? 12 : from - 1
            XCTAssertEqual(change.toRashi, expected,
                           "planet \(node) went forward: \(from) -> \(change.toRashi)")
        }
    }

    /// Ketu is Rahu's opposite point, so the two change sign at the same instant
    /// and six signs apart. Anything else means the Ketu longitude is being
    /// derived wrongly.
    func testKetuTurnsWithRahuSixSignsAway() async {
        let changes = await repo.fetchRashiChanges(
            from: ist.date(from: DateComponents(year: 2026, month: 9, day: 11))!)
        guard let rahu = changes.first(where: { $0.planetID == 7 }),
              let ketu = changes.first(where: { $0.planetID == 8 }) else {
            return XCTFail("a node is missing")
        }
        XCTAssertEqual(rahu.date.timeIntervalSince1970, ketu.date.timeIntervalSince1970, accuracy: 60)
        XCTAssertEqual((rahu.toRashi + 5) % 12 + 1, ketu.toRashi)
    }

    /// The Sun's ingresses are the Sankrantis, which are printed in every
    /// almanac — so this one is checked against the world rather than against
    /// the code that produced it. Kanya Sankranti 2026 falls on 17 September.
    func testTheSunsCrossingIsTheSankranti() async {
        let changes = await repo.fetchRashiChanges(
            from: ist.date(from: DateComponents(year: 2026, month: 9, day: 11))!)
        guard let sun = changes.first(where: { $0.planetID == 0 }) else { return XCTFail("no Sun") }
        let parts = ist.dateComponents([.year, .month, .day], from: sun.date)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 9)
        XCTAssertEqual(parts.day, 17)
        XCTAssertEqual(sun.toRashi, 6, "Kanya")
    }

    /// All twelve, and in planet order — the card that reads them shows them in
    /// that order and does no sorting of its own. Nine grahas, then Uranus,
    /// Neptune and Pluto, which the same search reaches on a longer window.
    func testEveryBodyComesBackInPlanetOrder() async {
        let changes = await repo.fetchRashiChanges(
            from: ist.date(from: DateComponents(year: 2026, month: 9, day: 11))!)
        XCTAssertEqual(changes.map(\.planetID), Array(0...11))
    }

    /// Saturn is the reason the window is 1200 days rather than a year: a
    /// retrograde loop across the boundary can hold it in one sign for three.
    func testTheSlowestGrahaIsStillFoundInsideTheWindow() {
        let change = wrapper.calculateRashiChangeJD(forPlanet: 6, fromJulianDay: jd(2026, 9, 11))
        XCTAssertGreaterThan(change, 0, "Saturn fell off the end of the window")
        XCTAssertLessThan(change - jd(2026, 9, 11), 1200.0)
    }
}
