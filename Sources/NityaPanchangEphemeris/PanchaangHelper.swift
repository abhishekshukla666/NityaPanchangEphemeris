//
//  PanchaangHelper.swift
//  NityaPanchangEphemeris
//
//  Cross-cutting utilities: lookup tables for Panchang limb names,
//  planet metadata, and alert predicates.
//  No SwiftUI, no data access — pure Swift.
//

import Foundation

// MARK: - Lookup Tables

public struct PanchaangHelper {

    // Purnimanta: Krishna 1–15 first, then Shukla 16–30.
    public static let tithiNames: [Int: String] = [
         1: "Pratipada",   2: "Dwitiya",     3: "Tritiya",     4: "Chaturthi",   5: "Panchami",
         6: "Shashthi",    7: "Saptami",     8: "Ashtami",     9: "Navami",     10: "Dashami",
        11: "Ekadashi",   12: "Dwadashi",   13: "Trayodashi", 14: "Chaturdashi", 15: "Amavasya",
        16: "Pratipada",  17: "Dwitiya",    18: "Tritiya",    19: "Chaturthi",  20: "Panchami",
        21: "Shashthi",   22: "Saptami",    23: "Ashtami",    24: "Navami",     25: "Dashami",
        26: "Ekadashi",   27: "Dwadashi",   28: "Trayodashi", 29: "Chaturdashi", 30: "Purnima"
    ]

    public static func getLunarMonthName(_ number: Int, isAdhik: Bool = false) -> String {
        let months = ["Chaitra", "Vaishakha", "Jyeshtha", "Ashadha",
                      "Shravana", "Bhadrapada", "Ashwina", "Kartika",
                      "Margashirsha", "Pausha", "Magha", "Phalguna"]
        let name = months[(number - 1) % 12]
        return isAdhik ? "Adhik \(name)" : name
    }

    public static func getTithiName(_ number: Int) -> String {
        let base = ["Pratipada", "Dwitiya", "Tritiya", "Chaturthi", "Panchami",
                    "Shashthi", "Saptami", "Ashtami", "Navami", "Dashami",
                    "Ekadashi", "Dwadashi", "Trayodashi", "Chaturdashi"]
        if number == 15 { return "Amavasya" }
        if number == 30 { return "Purnima" }
        return base[(number - 1) % 15]
    }

    public static func getNakshatraName(_ number: Int) -> String {
        let names = ["Ashwini", "Bharani", "Krittika", "Rohini", "Mrigashira", "Ardra",
                     "Punarvasu", "Pushya", "Ashlesha", "Magha", "Purva Phalguni", "Uttara Phalguni",
                     "Hasta", "Chitra", "Swati", "Vishakha", "Anuradha", "Jyeshtha",
                     "Mula", "Purva Ashadha", "Uttara Ashadha", "Shravana", "Dhanishta",
                     "Shatabhisha", "Purva Bhadrapada", "Uttara Bhadrapada", "Revati"]
        return names[max(0, min(number - 1, 26))]
    }

    public static func getYogaName(_ number: Int) -> String {
        let names = ["Vishkambha", "Priti", "Ayushman", "Saubhagya", "Shobhana", "Atiganda",
                     "Sukarma", "Dhriti", "Shula", "Ganda", "Vriddhi", "Dhruva",
                     "Vyaghata", "Harshana", "Vajra", "Siddhi", "Vyatipata", "Variyana",
                     "Parigha", "Shiva", "Siddha", "Sadhya", "Shubha", "Shukla",
                     "Brahma", "Indra", "Vaidhriti"]
        return names[(number - 1) % 27]
    }

    public static func getKaranaName(_ number: Int) -> String {
        let fixed  = ["Shakuni", "Chatushpada", "Naga", "Kimstughna"]
        let moving = ["Bava", "Balava", "Kaulava", "Taitila", "Gara", "Vanija", "Vishti (Bhadra)"]
        if number == 1   { return fixed[3] }
        if number >= 58  { return fixed[number - 58] }
        return moving[(number - 2) % 7]
    }

    public static func getVaraName(for date: Date) -> String {
        let weekday = Calendar.current.component(.weekday, from: date)
        return ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][weekday - 1]
    }

    // MARK: - Rashi

    public static func getMoonRashiName(_ number: Int) -> String {
        let names = ["Aries", "Taurus", "Gemini", "Cancer",
                     "Leo", "Virgo", "Libra", "Scorpio",
                     "Sagittarius", "Capricorn", "Aquarius", "Pisces"]
        return names[max(0, min(number - 1, 11))]
    }

    public static func getRashiSymbol(_ number: Int) -> String {
        return ["♈", "♉", "♊", "♋", "♌", "♍", "♎", "♏", "♐", "♑", "♒", "♓"][max(0, min(number - 1, 11))]
    }

    // MARK: - Navagraha

    /// The nine grahas, then the three modern planets.
    ///
    /// Ids 0â8 are the Navagraha and are what every classical calculation in
    /// this package uses — a dasha, a lordship, a hora. Ids 9â11 are Uranus,
    /// Neptune and Pluto, which no classical text knows: they are computed and
    /// named here so a caller can *show* them, and they are kept in their own
    /// array on PanchangDay and BirthChart so that nothing which reasons about
    /// the nine can pick them up by accident.
    public static let planetNames: [(name: String, symbol: String)] = [
        ("Sun",   "☉"), ("Moon", "☾"), ("Mars", "♂"), ("Mercury",  "☿"),
        ("Jupiter",    "♃"), ("Venus",  "♀"), ("Saturn",   "♄"), ("Rahu",   "☊"), ("Ketu", "☋"),
        ("Uranus", "♅"), ("Neptune", "♆"), ("Pluto", "♇"),
    ]

    /// The Navagraha — the ids a classical rule may look at.
    public static let navagrahaIDs = 0...8

    /// Uranus, Neptune and Pluto.
    public static let outerPlanetIDs = 9...11

    public static func buildPlanetPositions(from raw: [[String: Any]]) -> [PlanetPosition] {
        raw.compactMap { dict in
            guard let idx   = dict["planetIndex"] as? Int,
                  let lon   = dict["longitude"]   as? Double,
                  let rashi = dict["rashiNumber"] as? Int,
                  let deg   = dict["degrees"]     as? Double,
                  idx < planetNames.count
            else { return nil }
            let info = planetNames[idx]
            return PlanetPosition(id: idx, name: info.name, symbol: info.symbol,
                                  longitude: lon, rashiNumber: rashi, degrees: deg,
                                  isRetrograde: dict["isRetrograde"] as? Bool ?? false)
        }
        .sorted { $0.id < $1.id }
    }

    // MARK: - Ekadashi Names

    /// The twenty-four Ekadashis, by Purnimanta month.
    ///
    /// Whole names rather than a stem plus " Ekadashi". Two of them need a month
    /// in front — there is a Putrada Ekadashi in Shravana and another in Pausha,
    /// and a bare "Putrada Ekadashi" cannot tell a reader which one is in front
    /// of them — so the composition never held anyway.
    ///
    /// These are also the only source of the twenty-four Ekadashi festival
    /// rules; `ekadashiFestivalRules` builds them from here. The two used to be
    /// written out separately and had drifted apart on five of the twenty-four,
    /// so the calendar and the Quick Lookup tile named the same day differently:
    /// Pasankusha against Papankusha, Vaikuntha against Mokshada, a bare Putrada
    /// against a qualified one twice, and Papmochani against Papamochani.
    ///
    /// Index is `lunarMonth - 1`, Chaitra first.
    public static let shuklaEkadashiNames = [
        "Kamada Ekadashi", "Mohini Ekadashi", "Nirjala Ekadashi", "Devshayani Ekadashi",
        "Shravana Putrada Ekadashi", "Parivartini Ekadashi", "Papankusha Ekadashi",
        "Devutthana Ekadashi", "Mokshada Ekadashi", "Pausha Putrada Ekadashi",
        "Jaya Ekadashi", "Amalaki Ekadashi",
    ]

    public static let krishnaEkadashiNames = [
        "Papamochani Ekadashi", "Varuthini Ekadashi", "Apara Ekadashi", "Yogini Ekadashi",
        "Kamika Ekadashi", "Aja Ekadashi", "Indira Ekadashi", "Rama Ekadashi",
        "Utpanna Ekadashi", "Saphala Ekadashi", "Shattila Ekadashi", "Vijaya Ekadashi",
    ]

    public static func getEkadashiName(lunarMonth: Int, paksha: Paksha, isAdhik: Bool = false) -> String {
        // An Adhik month repeats a month number, so the table above would name
        // the Ekadashi of the ordinary month of the same number. Both of an
        // Adhik month's Ekadashis are Padmini.
        if isAdhik { return "Padmini Ekadashi" }
        let idx = (lunarMonth - 1) % 12
        return paksha == .shukla ? shuklaEkadashiNames[idx] : krishnaEkadashiNames[idx]
    }

    // MARK: - Panchang Alerts

    /// Ganda Moola nakshatras — inauspicious for new activities and births.
    public static func isGandaMoola(nakshatraName: String) -> Bool {
        ["Ashwini", "Ashlesha", "Magha", "Jyeshtha", "Mula", "Revati"].contains(nakshatraName)
    }

    /// Whether a karana number is Vishti, the one Bhadra is named for.
    ///
    /// Vishti sits at index 6 of the seven movable karanas, which run 2-57. The
    /// four fixed ones — 1, and 58 through 60 — can never be it, which the range
    /// check enforces.
    public static func isVishti(karanaNumber: Int) -> Bool {
        karanaNumber >= 2 && karanaNumber <= 57 && (karanaNumber - 2) % 7 == 6
    }

    /// Whether any karana between two readings is Vishti — that is, whether
    /// Bhadra touches the span they bound.
    ///
    /// Exact rather than sampled, and it costs two ephemeris readings instead of
    /// a scan. The Moon-Sun elongation a karana is cut from only ever increases,
    /// so the karanas covering a span are precisely those from the one at its
    /// start to the one at its end, and every number in between belongs to a
    /// karana lying wholly inside it.
    ///
    /// A day cannot be decided by its sunrise karana alone: a karana runs ten to
    /// thirteen hours against a twenty-four hour day, so about half of all
    /// Bhadras begin after one sunrise and end before the next, covering neither.
    public static func isVishti(between first: Int, and last: Int) -> Bool {
        var karana = first
        // The whole cycle. In use the two readings are consecutive sunrises and
        // so at most three karanas apart, but a bound tighter than the cycle
        // would be an invisible limit rather than a saving: this is integer
        // arithmetic, and the ephemeris was already read before it was called.
        for _ in 0..<60 {
            if isVishti(karanaNumber: karana) { return true }
            if karana == last { return false }
            karana = karana % 60 + 1
        }
        return false
    }

    /// Panchak — the Moon in Kumbha or Meena; avoid south travel, construction, cremation.
    ///
    /// Read from the Moon's SIGN, not its nakshatra, and that distinction is the
    /// whole of this function. "The last five nakshatras" is how Panchak is
    /// usually described and it is half a nakshatra wrong: the period is the
    /// Moon's passage through Kumbha and Meena, 300° to 360°, which begins at
    /// Dhanishtha's THIRD pada. Dhanishtha spans 293°20'–306°40', so its first
    /// half lies in Makara and is not Panchak at all.
    ///
    /// Testing the nakshatra name instead opened the period 6°40' early — about
    /// twelve and a half hours of Moon travel, which crosses a sunrise often
    /// enough that seven days of 2026 were flagged Panchak a day before it
    /// began. It can only ever over-report, never miss: the other four
    /// nakshatras lie wholly inside the two signs.
    public static func isPanchak(moonRashiNumber: Int) -> Bool {
        moonRashiNumber == 11 || moonRashiNumber == 12
    }

    /// Dishashool — inauspicious travel direction per weekday.
    public static func dishashool(for vara: String) -> (skt: String, eng: String, arrow: String) {
        switch vara {
        case "Sunday":    return ("पश्चिम", "West",  "←")
        case "Monday":    return ("पूर्व",  "East",  "→")
        case "Tuesday":   return ("उत्तर",  "North", "↑")
        case "Wednesday": return ("उत्तर",  "North", "↑")
        case "Thursday":  return ("दक्षिण", "South", "↓")
        case "Friday":    return ("पश्चिम", "West",  "←")
        case "Saturday":  return ("पूर्व",  "East",  "→")
        default:          return ("",       "",      "")
        }
    }
}
