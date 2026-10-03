//
//  PlanetSpeedTests.swift
//  NityaPanchangEphemerisTests
//
//  Daily motion, which Cheshta Bala is graded on.
//
//  The speed was always computed — SEFLG_SPEED has been set for as long as
//  `isRetrograde` has existed, because that flag is this number's sign. It was
//  just discarded after the comparison. These check it now survives the trip out
//  of the wrapper with its magnitude intact, because a value that silently
//  arrived as zero would still look like a plausible reading: a graha at a
//  station.
//

import XCTest
@testable import NityaPanchangEphemeris

final class PlanetSpeedTests: XCTestCase {

    private let repo = EphemerisPanchaangRepository()

    private func positions() async -> [PlanetPosition] {
        var c = DateComponents(year: 2026, month: 9, day: 18, hour: 12)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return await repo.fetchPlanetPositions(at: cal.date(from: c)!).navagraha
    }

    /// Every graha reports one, and none of them reports it as nil — the shape
    /// that would make Shadbala decline to answer.
    func testEveryGrahaCarriesItsSpeed() async {
        let all = await positions()
        // Counted first: a for-loop over an empty array asserts nothing, and this
        // test would then pass loudest exactly when the plumbing was broken.
        XCTAssertEqual(all.count, 9, "the navagraha should be nine")
        for planet in all {
            XCTAssertNotNil(planet.speed, "\(planet.name) has no speed")
        }
    }

    /// The magnitudes are the ones astronomy fixes, so this catches a value that
    /// arrived scaled, truncated, or as somebody else's number. The Moon is the
    /// discriminating one: at roughly 13°/day it is an order of magnitude above
    /// everything else, so a Moon reading near 1 would mean the array had
    /// shifted under us.
    func testTheSpeedsAreThePlausibleOnes() async {
        let byID = Dictionary(uniqueKeysWithValues: await positions().map { ($0.id, $0) })

        // (id, name, lower, upper) — degrees per day, signed.
        let bounds: [(Int, String, Double, Double)] = [
            (0, "Sun",    0.95,  1.03),   // very nearly constant, never retrograde
            (1, "Moon",  11.0,  15.5),    // the fast one
            (2, "Mars",  -0.5,   0.85),
            (3, "Mercury", -1.5, 2.3),    // the widest swing of the seven
            (4, "Jupiter", -0.2, 0.26),
            (5, "Venus", -0.7,   1.3),
            (6, "Saturn", -0.09, 0.14),
            (7, "Rahu",  -0.09, -0.01),   // the mean node only ever moves backward
        ]
        for (id, name, low, high) in bounds {
            let speed = try? XCTUnwrap(byID[id]?.speed)
            guard let speed else { return XCTFail("\(name) has no speed") }
            XCTAssertTrue((low ... high).contains(speed),
                          "\(name) at \(speed)°/day is outside \(low)...\(high)")
        }
    }

    /// The flag and the number cannot disagree, because the flag IS the number's
    /// sign — they are read from the same `pos[3]` one line apart, and a future
    /// edit that recomputed one of them separately is exactly what this catches.
    func testRetrogradeAgreesWithTheSignOfTheSpeed() async {
        for planet in await positions() {
            guard let speed = planet.speed else { continue }
            XCTAssertEqual(planet.isRetrograde, speed < 0,
                           "\(planet.name): flag says \(planet.isRetrograde) at \(speed)°/day")
        }
    }

    /// Ketu travels with Rahu rather than against it. It is the opposite POINT,
    /// not the opposite motion, so negating the speed here would have been an
    /// easy and invisible mistake — both nodes regress together.
    func testKetuMovesWithRahuNotAgainstIt() async {
        let byID = Dictionary(uniqueKeysWithValues: await positions().map { ($0.id, $0) })
        let rahu = try? XCTUnwrap(byID[7]?.speed)
        let ketu = try? XCTUnwrap(byID[8]?.speed)
        guard let rahu, let ketu else { return XCTFail("a node is missing its speed") }
        XCTAssertEqual(ketu, rahu, accuracy: 1e-9, "the nodes must share a speed")
        XCTAssertLessThan(ketu, 0, "both nodes regress")
    }
}
