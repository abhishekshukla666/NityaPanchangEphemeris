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
    /// Vakri — apparent backward motion against the zodiac.
    ///
    /// Defaulted in the initialiser so existing callers keep compiling; the
    /// ephemeris fills it from the body's computed daily motion. The Sun and
    /// Moon are never retrograde; Rahu and Ketu always are.
    public let isRetrograde: Bool

    public init(id: Int, name: String, symbol: String, longitude: Double, rashiNumber: Int,
                degrees: Double, isRetrograde: Bool = false) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.longitude = longitude
        self.rashiNumber = rashiNumber
        self.degrees = degrees
        self.isRetrograde = isRetrograde
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

/// One stretch of the day during which a limb holds a single value.
///
/// `nakshatra`, `yoga` and `karana` on PanchangDay are the *Udaya* readings —
/// taken at sunrise, which is what names the day and what every festival and
/// vrat in this library is dated by. They are correct and they must not change.
/// But they are also a snapshot, and a limb moves on during the day: a karana
/// lasts about eleven hours, so by mid-morning the sunrise reading is describing
/// something that has already finished.
///
/// These arrays carry the whole day so a caller can show both — the reading that
/// names the day, and the one running at this moment. Deliberately periods
/// rather than a "current" field: a PanchangDay is fetched once and held, while
/// now keeps moving, so anything baked in as current would go stale in the hand.
/// Hora, Lagna and Chaughariya are already shaped this way.
public struct LimbPeriod: Identifiable, Sendable {
    public let id: Int
    /// The limb's name, unlocalised — the same string the Udaya reading carries,
    /// so both go through the caller's catalogue the same way.
    public let name: String
    public let startTime: Date
    public let endTime: Date

    public init(id: Int, name: String, startTime: Date, endTime: Date) {
        self.id = id
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
    }

    public func contains(_ date: Date) -> Bool { date >= startTime && date < endTime }
    /// Convenience for views, matching LagnaPeriod. Prefer `contains(_:)` where
    /// the instant matters — a test, or a screen that pins a date.
    public var isActive: Bool { contains(Date()) }
}

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
    /// Every nakshatra, yoga and karana touching this panchang day, sunrise to
    /// next sunrise — see LimbPeriod. Two or three entries each; a karana is
    /// about half a tithi, so three of them usually reach into one day.
    ///
    /// Bounded by sunrise the way the hora and lagna lists are, so nothing is
    /// active between midnight and sunrise. That is the same convention those
    /// already follow: before sunrise the panchang day has not begun.
    ///
    /// Defaulted to empty so existing callers, previews and tests are unaffected.
    public let nakshatras: [LimbPeriod]
    public let yogas: [LimbPeriod]
    public let karanas: [LimbPeriod]
    /// The Moon's sign, as periods on the same footing as the three above.
    ///
    /// Usually one entry, and its end usually falls a day or two out: a rashi
    /// is 30 degrees and the Moon covers about 13.2 a day, so it stays in one
    /// sign for roughly two and a quarter days. So unlike the other limbs this
    /// often does not change during the day at all, and the useful fact is when
    /// the Moon next moves on rather than when today's reading stops.
    ///
    /// Names carry the sign's symbol, matching `moonRashi` — the same shape, so
    /// the same localisation path handles both.
    public let rashis: [LimbPeriod]

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
                bhadraKaal: Muhurat? = nil, amantaMonth: String = "", isPradoshVrat: Bool = false,
                nakshatras: [LimbPeriod] = [], yogas: [LimbPeriod] = [],
                karanas: [LimbPeriod] = [], rashis: [LimbPeriod] = []) {
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
        self.nakshatras = nakshatras
        self.yogas = yogas
        self.karanas = karanas
        self.rashis = rashis
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
    /// A tithi that began after this day's sunrise and ended before the next,
    /// so it reaches no sunrise anywhere and `sunriseTithi` cannot show it —
    /// 0 when there is none.
    ///
    /// The calendar's Purnima and Amavasya badges need this or they silently
    /// skip a fortnight: Purnima is lost this way on 23 Dec 2026, where the
    /// 23rd reads 29 and the 24th already reads 1. The full or new moon still
    /// happens on the day that held it, which is this day.
    public let lostTithi: Int
    /// Whether Pradosh Vrat is kept on this day.
    ///
    /// Decided by how much Trayodashi falls inside each day's Pradosh Kaal
    /// window rather than by a tithi read at one instant, because the vrat
    /// is dated by the tithi *prevailing during* dusk. A Trayodashi usually
    /// touches two consecutive windows and belongs to whichever holds more
    /// of it.
    public let isPradoshVrat: Bool
    /// Dated by the tithi at moonrise rather than at sunrise — see
    /// EphemerisPanchaangRepository.isSankashtiDay.
    public let isSankashtiChaturthi: Bool

    public init(sunriseTithi: Int, lostTithi: Int = 0, isPradoshVrat: Bool,
                isSankashtiChaturthi: Bool = false) {
        self.sunriseTithi = sunriseTithi
        self.lostTithi = lostTithi
        self.isPradoshVrat = isPradoshVrat
        self.isSankashtiChaturthi = isSankashtiChaturthi
    }
}
