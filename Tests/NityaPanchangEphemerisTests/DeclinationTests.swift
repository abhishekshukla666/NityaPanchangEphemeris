//
//  DeclinationTests.swift
//  NityaPanchangEphemerisTests
//
//  Kranti, which Ayana Bala is graded on.
//

import XCTest
@testable import NityaPanchangEphemeris

final class DeclinationTests: XCTestCase {

    private let repo = EphemerisPanchaangRepository()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var c = DateComponents(year: year, month: month, day: day, hour: 12)
        c.timeZone = TimeZone(identifier: "UTC")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }

    /// The solstices pin the Sun's declination to the obliquity of the ecliptic,
    /// about ±23.44°, and nothing else in the sky does that. If the sidereal flag
    /// had been left on by mistake these would be out by the ayanamsa — some 24°
    /// — which is almost the whole range, so this is the test that proves the
    /// frame is right rather than merely plausible.
    func testTheSunHitsTheObliquityAtTheSolstices() async {
        let june = await repo.fetchDeclinations(at: date(2026, 6, 21))
        let december = await repo.fetchDeclinations(at: date(2026, 12, 21))
        XCTAssertEqual(try XCTUnwrap(june[0]), 23.44, accuracy: 0.05, "June solstice")
        XCTAssertEqual(try XCTUnwrap(december[0]), -23.44, accuracy: 0.05, "December solstice")
    }

    /// And crosses zero at the equinoxes.
    func testTheSunCrossesZeroAtTheEquinoxes() async {
        let march = await repo.fetchDeclinations(at: date(2026, 3, 20))
        XCTAssertEqual(try XCTUnwrap(march[0]), 0, accuracy: 0.5, "March equinox")
    }

    /// All seven are present, and inside the range the ecliptic allows. The Moon
    /// reaches furthest because its orbit is inclined about 5° to the ecliptic —
    /// which is also the reason this is read from the ephemeris rather than
    /// derived from longitude, where that 5° does not exist.
    func testEverySevenIsPresentAndInRange() async {
        let d = await repo.fetchDeclinations(at: date(2026, 9, 18))
        XCTAssertEqual(d.count, 7, "the seven classical grahas")
        for (id, value) in d {
            XCTAssertTrue((-30.0 ... 30.0).contains(value),
                          "planet \(id) at \(value)° is outside anything the ecliptic allows")
        }
    }
}
