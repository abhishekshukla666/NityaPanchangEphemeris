//
//  PanchangDay.swift
//  NityaPanchangEphemeris
//

import Foundation

// MARK: - Core Limbs

public struct Tithi: Sendable {
    public let name: String
    public let endTime: Date
    public let paksha: Paksha

    public init(name: String, endTime: Date, paksha: Paksha) {
        self.name = name
        self.endTime = endTime
        self.paksha = paksha
    }
}

public struct Nakshatra: Sendable {
    public let name: String
    public let endTime: Date

    public init(name: String, endTime: Date) {
        self.name = name
        self.endTime = endTime
    }
}

public struct MinorLimb: Sendable {
    public let name: String
    public let endTime: Date?

    public init(name: String, endTime: Date?) {
        self.name = name
        self.endTime = endTime
    }
}

public enum Paksha: String, Sendable {
    case shukla  = "Shukla"
    case krishna = "Krishna"
}

// MARK: - Timings

public struct Muhurat: Identifiable, Hashable, Sendable {
    public let id: String = UUID().uuidString
    public let name: String
    public let startTime: Date
    public let endTime: Date
    public let type: MuhuratType

    public init(name: String, startTime: Date, endTime: Date, type: MuhuratType) {
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.type = type
    }
}

public enum MuhuratType: Sendable {
    case auspicious
    case inauspicious
    case neutral
}

// MARK: - Navagraha Position

public struct PlanetPosition: Identifiable, Sendable {
    public let id: Int           // 0=Surya … 8=Ketu
    public let name: String      // "Surya"
    public let symbol: String    // "☉"
    public let longitude: Double // 0–360 sidereal
    public let rashiNumber: Int  // 1–12
    public let degrees: Double   // 0–30 within the sign

    public init(id: Int, name: String, symbol: String, longitude: Double, rashiNumber: Int, degrees: Double) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.longitude = longitude
        self.rashiNumber = rashiNumber
        self.degrees = degrees
    }
}

// MARK: - Hora (Planetary Hour)

public struct HoraInfo: Identifiable, Sendable {
    public let id: Int            // 0–23 (0–11 day, 12–23 night)
    public let planet: String     // "Sun", "Moon", "Mars", "Mercury", "Jupiter", "Venus", "Saturn"
    public let symbol: String     // "☉", "☽", "♂", "☿", "♃", "♀", "♄"
    public let startTime: Date
    public let endTime: Date
    public let isDay: Bool
    public let type: MuhuratType
    public var isActive: Bool { Date() >= startTime && Date() < endTime }

    public init(id: Int, planet: String, symbol: String, startTime: Date, endTime: Date, isDay: Bool, type: MuhuratType) {
        self.id = id
        self.planet = planet
        self.symbol = symbol
        self.startTime = startTime
        self.endTime = endTime
        self.isDay = isDay
        self.type = type
    }
}

// MARK: - Lagna (Rising Sign Period)

public struct LagnaPeriod: Identifiable, Sendable {
    public let id: Int
    public let rashiNumber: Int    // 1–12
    public let rashiName: String   // "Aries", "Taurus", etc.
    public let rashiSymbol: String // "♈", "♉", etc.
    public let isDay: Bool
    public let startTime: Date
    public let endTime: Date
    public var isActive: Bool { Date() >= startTime && Date() < endTime }

    public init(id: Int, rashiNumber: Int, rashiName: String, rashiSymbol: String, isDay: Bool, startTime: Date, endTime: Date) {
        self.id = id
        self.rashiNumber = rashiNumber
        self.rashiName = rashiName
        self.rashiSymbol = rashiSymbol
        self.isDay = isDay
        self.startTime = startTime
        self.endTime = endTime
    }
}

// MARK: - Master Object

public struct PanchangDay: Sendable {
    public let date: Date
    public let lunarMonth: String           // "Chaitra", "Adhik Vaishakha", etc.
    public let lunarMonthNumber: Int        // 1–12, used for Ekadashi name lookup
    public let isAdhikMaas: Bool            // true during a leap/extra lunar month
    public let sunrise: Date
    public let sunset: Date
    public let moonrise: Date?              // nil if Moon doesn't rise that day
    public let moonset: Date?               // nil if Moon doesn't set that day

    public let tithi: Tithi
    public let tithiNumber: Int             // 1–30 for moon phase visual
    public let nakshatra: Nakshatra
    public let yoga: MinorLimb
    public let karana: MinorLimb
    public let vara: String
    public let moonRashi: String            // e.g. "♉ Taurus"

    public let muhurats: [Muhurat]
    public let chaughariya: [Muhurat]       // 8 equal daytime Choghadiya periods (sunrise→sunset)
    public let nightChaughariya: [Muhurat]  // 8 equal nighttime Choghadiya periods (sunset→next sunrise)
    public let planetPositions: [PlanetPosition]

    public let vedaAyana: String            // "Uttarayana" or "Dakshinayana"
    public let raviYoga: Bool               // Moon in weekday's ruling nakshatra

    public let horas: [HoraInfo]            // 24 Vedic planetary hours (12 day + 12 night, Chaldean order)
    public let lagnas: [LagnaPeriod]        // Rising sign (Ascendant) periods sunrise → next sunrise

    /// The Vishti (Bhadra) karana window for the day, if one falls within it —
    /// nil most days (Bhadra occurs on roughly 8 of every 30 tithis). Defaults
    /// to nil so existing callers (previews, tests) don't need updating.
    public let bhadraKaal: Muhurat?

    /// The Amanta (South Indian) name for this same day — a display-only
    /// parallel to `lunarMonth`. All internal matching (festivals, Ekadashi,
    /// Samvat) stays Purnimanta-only regardless of which is shown to the
    /// user. Defaults to "" so existing callers (previews, tests) don't need
    /// updating.
    public let amantaMonth: String

    /// Whether Pradosh Vrat is kept on this day.
    ///
    /// Decided by how much Trayodashi falls inside each day's Pradosh Kaal
    /// window rather than by a tithi read at one instant, because the vrat
    /// is dated by the tithi *prevailing during* dusk. A Trayodashi usually
    /// touches two consecutive windows and belongs to whichever holds more
    /// of it. Defaults to false so existing callers (previews, tests) don't
    /// need updating.
    public let isPradoshVrat: Bool

    public init(date: Date, lunarMonth: String, lunarMonthNumber: Int, isAdhikMaas: Bool,
                sunrise: Date, sunset: Date, moonrise: Date?, moonset: Date?,
                tithi: Tithi, tithiNumber: Int, nakshatra: Nakshatra, yoga: MinorLimb, karana: MinorLimb,
                vara: String, moonRashi: String, muhurats: [Muhurat], chaughariya: [Muhurat],
                nightChaughariya: [Muhurat], planetPositions: [PlanetPosition],
                vedaAyana: String, raviYoga: Bool, horas: [HoraInfo], lagnas: [LagnaPeriod],
                bhadraKaal: Muhurat? = nil, amantaMonth: String = "", isPradoshVrat: Bool = false) {
        self.date = date
        self.lunarMonth = lunarMonth
        self.lunarMonthNumber = lunarMonthNumber
        self.isAdhikMaas = isAdhikMaas
        self.sunrise = sunrise
        self.sunset = sunset
        self.moonrise = moonrise
        self.moonset = moonset
        self.tithi = tithi
        self.tithiNumber = tithiNumber
        self.nakshatra = nakshatra
        self.yoga = yoga
        self.karana = karana
        self.vara = vara
        self.moonRashi = moonRashi
        self.muhurats = muhurats
        self.chaughariya = chaughariya
        self.nightChaughariya = nightChaughariya
        self.planetPositions = planetPositions
        self.vedaAyana = vedaAyana
        self.raviYoga = raviYoga
        self.horas = horas
        self.lagnas = lagnas
        self.bhadraKaal = bhadraKaal
        self.amantaMonth = amantaMonth
        self.isPradoshVrat = isPradoshVrat
    }
}

/// What a calendar cell needs for one day.
///
/// Most markers are Udaya Tithi observances and read `sunriseTithi`;
/// Pradosh Vrat is dated by dusk and reads `isPradoshVrat`. Carrying both
/// avoids a second scan of the month, and avoids the calendar and the Quick
/// Lookup section disagreeing about the same day.
public struct MonthDayTithis: Sendable {
    public let sunriseTithi: Int
    /// Whether Pradosh Vrat is kept on this day.
    ///
    /// Decided by how much Trayodashi falls inside each day's Pradosh Kaal
    /// window rather than by a tithi read at one instant, because the vrat
    /// is dated by the tithi *prevailing during* dusk. A Trayodashi usually
    /// touches two consecutive windows and belongs to whichever holds more
    /// of it.
    public let isPradoshVrat: Bool

    public init(sunriseTithi: Int, isPradoshVrat: Bool) {
        self.sunriseTithi = sunriseTithi
        self.isPradoshVrat = isPradoshVrat
    }
}
