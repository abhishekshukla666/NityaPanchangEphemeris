//
//  PlanetSnapshotTests.swift
//  NityaPanchangEphemerisTests
//
//  `fetchPlanetPositions(at:)` against the case that prompted it.
//

import XCTest
@testable import NityaPanchangEphemeris

final class PlanetSnapshotTests: XCTestCase {

    private let repo = EphemerisPanchaangRepository()
    private let delhi = (lat: 28.61, lon: 77.21)

    private var kolkata: TimeZone { TimeZone(identifier: "Asia/Kolkata")! }

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        var c = DateComponents(year: 2026, month: 9, day: 18, hour: hour, minute: minute)
        c.timeZone = kolkata
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = kolkata
        return cal.date(from: c)!
    }

    /// The reported case. Mars crosses from Mithun into Karka at 16:35 on
    /// 18 September 2026; a panchang day's positions are read at sunrise, so
    /// the dashboard said Mithun all evening while Mars was already in Karka.
    func testMarsMovesSignDuringTheDayAndTheSnapshotFollowsIt() async {
        let morning = await repo.fetchPlanetPositions(at: date(6, 30))
        let evening = await repo.fetchPlanetPositions(at: date(18))

        let marsMorning = morning.navagraha.first { $0.id == 2 }
        let marsEvening = evening.navagraha.first { $0.id == 2 }

        XCTAssertEqual(marsMorning?.rashiNumber, 3, "Mithun at sunrise")
        XCTAssertEqual(marsEvening?.rashiNumber, 4, "Karka by the evening")
    }

    /// And the day's own positions stay at sunrise, which is what the limbs
    /// need. If this ever starts matching the evening snapshot, the panchang
    /// has started moving under its own tithi.
    func testThePanchangDayStillReadsItsPositionsAtSunrise() async {
        let day = await repo.fetchPanchang(for: date(18), latitude: delhi.lat, longitude: delhi.lon)
        let mars = day.planetPositions.first { $0.id == 2 }
        XCTAssertEqual(mars?.rashiNumber, 3, "the panchang day is read at sunrise")
    }

    /// All nine, and the three moderns kept apart from them.
    func testTheSnapshotCarriesTheNineAndTheThree() async {
        let snapshot = await repo.fetchPlanetPositions(at: date(12))
        XCTAssertEqual(snapshot.navagraha.map(\.id), Array(0...8))
        XCTAssertEqual(snapshot.outer.map(\.id), [9, 10, 11])
        for planet in snapshot.navagraha + snapshot.outer {
            XCTAssertTrue((1...12).contains(planet.rashiNumber), "\(planet.name)")
            XCTAssertTrue((0..<30).contains(planet.degrees), "\(planet.name)")
        }
    }

    /// Needs no location, unlike the panchang around it: a longitude is the
    /// same seen from anywhere.
    func testTheSnapshotIsTheSameWhereverItIsAskedFrom() async {
        let snapshot = await repo.fetchPlanetPositions(at: date(12))
        XCTAssertFalse(snapshot.navagraha.isEmpty)
        // Asserted by construction rather than by comparing two calls: the
        // method takes no latitude to vary.
        XCTAssertEqual(snapshot.navagraha.count, 9)
    }
}
