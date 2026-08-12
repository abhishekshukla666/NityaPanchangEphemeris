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

    public static let planetNames: [(name: String, symbol: String)] = [
        ("Sun",   "☉"), ("Moon", "☾"), ("Mars", "♂"), ("Mercury",  "☿"),
        ("Jupiter",    "♃"), ("Venus",  "♀"), ("Saturn",   "♄"), ("Rahu",   "☊"), ("Ketu", "☋"),
    ]

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
                                  longitude: lon, rashiNumber: rashi, degrees: deg)
        }
        .sorted { $0.id < $1.id }
    }

    // MARK: - Ekadashi Names

    public static func getEkadashiName(lunarMonth: Int, paksha: Paksha, isAdhik: Bool = false) -> String {
        if isAdhik { return "Padmini Ekadashi" }
        let shukla  = ["Kamada", "Mohini", "Nirjala", "Devshayani", "Putrada", "Parsva",
                       "Pasankusha", "Devutthana", "Mokshada", "Putrada", "Jaya", "Amalaki"]
        let krishna = ["Papamochani", "Varuthini", "Apara", "Yogini", "Kamika", "Aja",
                       "Indira", "Rama", "Utpanna", "Saphala", "Shattila", "Vijaya"]
        let idx = (lunarMonth - 1) % 12
        return (paksha == .shukla ? shukla[idx] : krishna[idx]) + " Ekadashi"
    }

    // MARK: - Panchang Alerts

    /// Ganda Moola nakshatras — inauspicious for new activities and births.
    public static func isGandaMoola(nakshatraName: String) -> Bool {
        ["Ashwini", "Ashlesha", "Magha", "Jyeshtha", "Mula", "Revati"].contains(nakshatraName)
    }

    /// Panchak — Moon in the last five nakshatras; avoid south travel, construction, cremation.
    public static func isPanchak(nakshatraName: String) -> Bool {
        ["Dhanishta", "Shatabhisha", "Purva Bhadrapada", "Uttara Bhadrapada", "Revati"]
            .contains(nakshatraName)
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
