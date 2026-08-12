//
//  BirthChart.swift
//  NityaPanchangEphemeris
//
//  Computed chart used for marriage matching (Guna Milan) and Kundli charts.
//

import Foundation

public struct BirthChart: Sendable {
    public let nakshatra:     Int     // 1–27
    public let pada:          Int     // 1–4
    public let rashi:         Int     // 1–12 (Moon sign)
    public let moonLongitude: Double  // 0–360 sidereal
    public let marsRashi:     Int     // 1–12
    public let lagnaRashi:    Int     // 1–12 (Ascendant sign)

    public let lagnaLongitude:  Double           // 0–360 sidereal — precise Ascendant, used for Navamsa
    public let planetPositions: [PlanetPosition]  // all 9 grahas, used to draw Lagna/Navamsa kundli charts

    public init(nakshatra: Int, pada: Int, rashi: Int, moonLongitude: Double, marsRashi: Int,
                lagnaRashi: Int, lagnaLongitude: Double, planetPositions: [PlanetPosition]) {
        self.nakshatra = nakshatra
        self.pada = pada
        self.rashi = rashi
        self.moonLongitude = moonLongitude
        self.marsRashi = marsRashi
        self.lagnaRashi = lagnaRashi
        self.lagnaLongitude = lagnaLongitude
        self.planetPositions = planetPositions
    }
}
