//
//  HinduFestival.swift
//  NityaPanchangEphemeris
//
//  Domain entity for Hindu festivals and the rules that derive their dates
//  from Panchang (lunar month + tithi) rather than fixed Gregorian dates.
//

import Foundation

public enum ObservationTime: Sendable {
    case sunrise    // Default for most festivals (Udaya Tithi)
    case midnight   // For Shivratri, Janmashtami (Nishita Kaal)
    case pradoshKaal // For Diwali Laxmi Puja, Holika Dahan — the tithi must prevail in
                     // the first fifth of the night after sunset (Pradosh-vyapini)
    case aparahna    // For Dussehra/Vijayadashami — the tithi must prevail in the third
                     // of five equal divisions of daylight (Aparahna-vyapini)
}

// MARK: - Festival Entity

public struct HinduFestival: Identifiable, Sendable {
    public let id = UUID()
    public let name:  String
    public let date:  Date
    public let emoji: String
    public let hasIcon: Bool

    public init(name: String, date: Date, emoji: String, hasIcon: Bool) {
        self.name = name
        self.date = date
        self.emoji = emoji
        self.hasIcon = hasIcon
    }
}

// MARK: - Festival Rule

/// A rule that fires when a specific lunar month AND tithi number align.
/// tithiNumber 1–15 = Krishna Paksha, 16–29 = Shukla Paksha, 15 = Amavasya, 30 = Purnima.
public struct FestivalRule: Sendable {
    public let name:        String
    public let emoji:       String
    public let lunarMonth:  Int   // 1–12
    public let tithiNumber: Int   // 1–30
    public var hasIcon: Bool = false
    public var observationTime: ObservationTime = .sunrise

    public init(name: String, emoji: String, lunarMonth: Int, tithiNumber: Int,
                hasIcon: Bool = false, observationTime: ObservationTime = .sunrise) {
        self.name = name
        self.emoji = emoji
        self.lunarMonth = lunarMonth
        self.tithiNumber = tithiNumber
        self.hasIcon = hasIcon
        self.observationTime = observationTime
    }
}

// MARK: - Festival Rules Database
//
// Lunar month numbers: Chaitra=1, Vaishakha=2, Jyeshtha=3, Ashadha=4,
//   Shravana=5, Bhadrapada=6, Ashwina=7, Kartika=8, Margashirsha=9,
//   Pausha=10, Magha=11, Phalguna=12
//
// Purnimanta convention — month starts at Krishna Paksha (after previous Purnima)
// and closes at the next Purnima. Tithi numbering within each month:
//   Krishna 1–14 + Amavasya  = tithis  1–15  (dark fortnight, opens the month)
//   Shukla  1–14 + Purnima   = tithis 16–30  (bright fortnight, closes the month)

public let allFestivalRules: [FestivalRule] = [

    // ── Chaitra (1) ── [KP after Phalguna Purnima] + [SP → Chaitra Purnima] ──
    FestivalRule(name: "Sheetala Ashtami",     emoji: "🙏", lunarMonth: 1,  tithiNumber: 8),
    FestivalRule(name: "Ugadi",                emoji: "🪷", lunarMonth: 1,  tithiNumber: 16),
    FestivalRule(name: "Gudi Padwa",           emoji: "🌾", lunarMonth: 1,  tithiNumber: 16),
    FestivalRule(name: "Navratri (Chaitra)",   emoji: "🎊", lunarMonth: 1,  tithiNumber: 16),
    FestivalRule(name: "Ram Navami",           emoji: "🏹", lunarMonth: 1,  tithiNumber: 24),
    FestivalRule(
        name: "Hanuman Jayanti",
        emoji: "gada",
        lunarMonth: 1,
        tithiNumber: 30,
        hasIcon: true
    ),

    // ── Vaishakha (2) ─────────────────────────────────────────────────────────
    FestivalRule(
        name: "Akshaya Tritiya",
        emoji: "gold-pot",
        lunarMonth: 2,
        tithiNumber: 18,
        hasIcon: true
    ),
    FestivalRule(
        name: "Parshuram Jayanti",
        emoji: "axe",
        lunarMonth: 2,
        tithiNumber: 18,
        hasIcon: true
    ),
    FestivalRule(
        name: "Buddha Purnima",
        emoji: "buddha",
        lunarMonth: 2,
        tithiNumber: 30,
        hasIcon: true
    ),

    // ── Jyeshtha (3) ──────────────────────────────────────────────────────────
    FestivalRule(name: "Vat Savitri Vrat",     emoji: "🌳", lunarMonth: 3,  tithiNumber: 15),
    FestivalRule(name: "Ganga Dussehra",       emoji: "🌊", lunarMonth: 3,  tithiNumber: 25),
    FestivalRule(name: "Vat Savitri Purnima",  emoji: "🌳", lunarMonth: 3,  tithiNumber: 30),

    // ── Ashadha (4) ───────────────────────────────────────────────────────────
    FestivalRule(
        name: "Jagannath Rath Yatra",
        emoji: "chariot",
        lunarMonth: 4,
        tithiNumber: 17,
        hasIcon: true
    ),
    FestivalRule(
        name: "Guru Purnima",
        emoji: "sacred",
        lunarMonth: 4,
        tithiNumber: 30,
        hasIcon: true
    ),

    // ── Shravana (5) ── [KP after Ashadha Purnima] + [SP → Raksha Bandhan] ───
    FestivalRule(
        name: "Sawan Shivratri",
        emoji: "lordshiv",
        lunarMonth: 5,
        tithiNumber: 14,
        hasIcon: true,
        observationTime: .midnight
    ),
    FestivalRule(name: "Hariyali Teej",        emoji: "🌿", lunarMonth: 5,  tithiNumber: 18),
    FestivalRule(name: "Nag Panchami",         emoji: "🐍", lunarMonth: 5,  tithiNumber: 20),
    FestivalRule(
        name: "Raksha Bandhan",
        emoji: "rakhi",
        lunarMonth: 5,
        tithiNumber: 30,
        hasIcon: true
    ),

    // ── Bhadrapada (6) ── [KP after Shravana Purnima] + [SP → Bhadrapada Purnima]
    FestivalRule(name: "Kajari Teej",          emoji: "🌿", lunarMonth: 6,  tithiNumber: 3),
    FestivalRule(name: "Bahula Chaturthi",     emoji: "🐄", lunarMonth: 6,  tithiNumber: 4),
    FestivalRule(name: "Hal Chhath",           emoji: "🐂", lunarMonth: 6,  tithiNumber: 6),
    FestivalRule(
        name: "Krishna Janmashtami",
        emoji: "krishna",
        lunarMonth: 6,
        tithiNumber: 8,
        hasIcon: true
    ),
    FestivalRule(name: "Hartalika Teej",       emoji: "🌺", lunarMonth: 6,  tithiNumber: 18),
    FestivalRule(
        name: "Ganesh Chaturthi",
        emoji: "ganesh",
        lunarMonth: 6,
        tithiNumber: 19,
        hasIcon: true
    ),
    FestivalRule(name: "Rishi Panchami",       emoji: "🌸", lunarMonth: 6,  tithiNumber: 20),
    FestivalRule(name: "Radha Ashtami",        emoji: "🪈", lunarMonth: 6,  tithiNumber: 23),
    FestivalRule(
        name: "Anant Chaturdashi",
        emoji: "conch-shell",
        lunarMonth: 6,
        tithiNumber: 29,
        hasIcon: true
    ),

    // ── Ashwina (7) ── [KP = Pitru Paksha] + [SP = Navratri → Sharad Purnima] ─
    FestivalRule(name: "Jivitputrika Vrat",    emoji: "🙏", lunarMonth: 7,  tithiNumber: 8),
    FestivalRule(name: "Mahalaya Amavasya",    emoji: "🌚", lunarMonth: 7,  tithiNumber: 15),
    FestivalRule(
        name: "Navratri",
        emoji: "navratri",
        lunarMonth: 7,
        tithiNumber: 16,
        hasIcon: true
    ),
    FestivalRule(
        name: "Durga Ashtami",
        emoji: "lion",
        lunarMonth: 7,
        tithiNumber: 23,
        hasIcon: true
    ),
    FestivalRule(name: "Maha Navami",          emoji: "🪔", lunarMonth: 7,  tithiNumber: 24),
    FestivalRule(name: "Dussehra",             emoji: "🏹", lunarMonth: 7,  tithiNumber: 25,
                 observationTime: .aparahna),
    FestivalRule(name: "Sharad Purnima",       emoji: "🌝", lunarMonth: 7,  tithiNumber: 30),

    // ── Kartika (8) ── [KP = Diwali week] + [SP → Kartik Purnima] ────────────
    FestivalRule(name: "Karwa Chauth",         emoji: "🌝", lunarMonth: 8,  tithiNumber: 4),
    FestivalRule(name: "Ahoi Ashtami",         emoji: "⭐", lunarMonth: 8,  tithiNumber: 8),
    FestivalRule(
        name: "Dhanteras",
        emoji: "dhanteras",
        lunarMonth: 8,
        tithiNumber: 13,
        hasIcon: true
    ),
    FestivalRule(name: "Narak Chaturdashi",    emoji: "🪔", lunarMonth: 8,  tithiNumber: 14),
    FestivalRule(
        name: "Diwali",
        emoji: "diwali",
        lunarMonth: 8,
        tithiNumber: 15,
        hasIcon: true,
        observationTime: .pradoshKaal
    ),
    FestivalRule(name: "Govardhan Puja",       emoji: "🐄", lunarMonth: 8,  tithiNumber: 16),
    FestivalRule(
        name: "Bhai Dooj",
        emoji: "bhaidooj",
        lunarMonth: 8,
        tithiNumber: 17,
        hasIcon: true
    ),
    FestivalRule(name: "Chhath Puja",          emoji: "☀️", lunarMonth: 8,  tithiNumber: 21),
    FestivalRule(name: "Gopashtami",           emoji: "🐄", lunarMonth: 8,  tithiNumber: 23),
    FestivalRule(name: "Dev Uthani Ekadashi",  emoji: "🛕", lunarMonth: 8,  tithiNumber: 26),
    FestivalRule(name: "Tulsi Vivah",          emoji: "🌿", lunarMonth: 8,  tithiNumber: 27),
    FestivalRule(
        name: "Guru Nanak Jayanti",
        emoji: "gurunanak",
        lunarMonth: 8,
        tithiNumber: 30,
        hasIcon: true
    ),
    FestivalRule(name: "Kartik Purnima",       emoji: "🌝", lunarMonth: 8,  tithiNumber: 30),

    // ── Margashirsha (9) ──────────────────────────────────────────────────────
    FestivalRule(name: "Vivah Panchami",       emoji: "💐", lunarMonth: 9,  tithiNumber: 20),

    // ── Pausha (10) ───────────────────────────────────────────────────────────
    FestivalRule(name: "Pausha Purnima",       emoji: "🌝", lunarMonth: 10, tithiNumber: 30),

    // ── Magha (11) ────────────────────────────────────────────────────────────
    FestivalRule(name: "Mauni Amavasya",       emoji: "🤫", lunarMonth: 11, tithiNumber: 15),
    FestivalRule(
        name: "Basant Panchami",
        emoji: "spring",
        lunarMonth: 11,
        tithiNumber: 20,
        hasIcon: true
    ),
    FestivalRule(name: "Ratha Saptami",        emoji: "☀️", lunarMonth: 11, tithiNumber: 22),
    FestivalRule(name: "Magha Purnima",        emoji: "🌝", lunarMonth: 11, tithiNumber: 30),

    // ── Phalguna (12) ── [KP after Magha Purnima] + [SP → Holi] ─────────────
    FestivalRule(
        name: "Maha Shivratri",
        emoji: "lordshiv",
        lunarMonth: 12,
        tithiNumber: 14,
        hasIcon: true,
        observationTime: .midnight
    ),
    FestivalRule(name: "Holika Dahan",         emoji: "🔥", lunarMonth: 12, tithiNumber: 29,
                 observationTime: .pradoshKaal),
    FestivalRule(
        name: "Holi",
        emoji: "holi",
        lunarMonth: 12,
        tithiNumber: 30,
        hasIcon: true
    ),

    // MARK: - The 24 Ekadashis

    // 1. Chaitra
    FestivalRule(name: "Papmochani Ekadashi", emoji: "🛕", lunarMonth: 1, tithiNumber: 11),
    FestivalRule(name: "Kamada Ekadashi",     emoji: "🛕", lunarMonth: 1, tithiNumber: 26),

    // 2. Vaishakha
    FestivalRule(name: "Varuthini Ekadashi",  emoji: "🛕", lunarMonth: 2, tithiNumber: 11),
    FestivalRule(name: "Mohini Ekadashi",     emoji: "🛕", lunarMonth: 2, tithiNumber: 26),

    // 3. Jyeshtha
    FestivalRule(name: "Apara Ekadashi",      emoji: "🛕", lunarMonth: 3, tithiNumber: 11),
    FestivalRule(name: "Nirjala Ekadashi",    emoji: "🛕", lunarMonth: 3, tithiNumber: 26),

    // 4. Ashadha
    FestivalRule(name: "Yogini Ekadashi",     emoji: "🛕", lunarMonth: 4, tithiNumber: 11),
    FestivalRule(name: "Devshayani Ekadashi", emoji: "🛕", lunarMonth: 4, tithiNumber: 26),

    // 5. Shravana
    FestivalRule(name: "Kamika Ekadashi",     emoji: "🛕", lunarMonth: 5, tithiNumber: 11),
    FestivalRule(name: "Shravana Putrada Ekadashi", emoji: "🛕", lunarMonth: 5, tithiNumber: 26),

    // 6. Bhadrapada
    FestivalRule(name: "Aja Ekadashi",        emoji: "🛕", lunarMonth: 6, tithiNumber: 11),
    FestivalRule(name: "Parivartini Ekadashi",emoji: "🛕", lunarMonth: 6, tithiNumber: 26),

    // 7. Ashwina
    FestivalRule(name: "Indira Ekadashi",     emoji: "🛕", lunarMonth: 7, tithiNumber: 11),
    FestivalRule(name: "Papankusha Ekadashi", emoji: "🛕", lunarMonth: 7, tithiNumber: 26),

    // 8. Kartika
    FestivalRule(name: "Rama Ekadashi",       emoji: "🛕", lunarMonth: 8, tithiNumber: 11),
    FestivalRule(name: "Devutthana Ekadashi", emoji: "🛕", lunarMonth: 8, tithiNumber: 26),

    // 9. Margashirsha
    FestivalRule(name: "Utpanna Ekadashi",    emoji: "🛕", lunarMonth: 9, tithiNumber: 11),
    FestivalRule(name: "Mokshada Ekadashi",   emoji: "🛕", lunarMonth: 9, tithiNumber: 26),

    // 10. Pausha
    FestivalRule(name: "Saphala Ekadashi",    emoji: "🛕", lunarMonth: 10, tithiNumber: 11),
    FestivalRule(name: "Pausha Putrada Ekadashi", emoji: "🛕", lunarMonth: 10, tithiNumber: 26),

    // 11. Magha
    FestivalRule(name: "Shattila Ekadashi",   emoji: "🛕", lunarMonth: 11, tithiNumber: 11),
    FestivalRule(name: "Jaya Ekadashi",       emoji: "🛕", lunarMonth: 11, tithiNumber: 26),

    // 12. Phalguna
    FestivalRule(name: "Vijaya Ekadashi",     emoji: "🛕", lunarMonth: 12, tithiNumber: 11),
    FestivalRule(name: "Amalaki Ekadashi",    emoji: "🛕", lunarMonth: 12, tithiNumber: 26),
]

// MARK: - Static (Fixed Gregorian Date) Festival Rule

/// A festival that falls on the same Gregorian month/day every year.
public struct StaticFestivalRule: Sendable {
    public let name:  String
    public let emoji: String
    public let month: Int
    public let day:   Int
    public var hasIcon: Bool = false

    public init(name: String, emoji: String, month: Int, day: Int, hasIcon: Bool = false) {
        self.name = name
        self.emoji = emoji
        self.month = month
        self.day = day
        self.hasIcon = hasIcon
    }
}

// National holidays and universally observed fixed-date festivals for India.
public let allStaticFestivalRules: [StaticFestivalRule] = [
    StaticFestivalRule(name: "New Year's Day",   emoji: "🎆", month: 1,  day: 1),
    StaticFestivalRule(name: "Lohri",            emoji: "🔥", month: 1,  day: 13),
    StaticFestivalRule(name: "Makar Sankranti",  emoji: "🌾", month: 1,  day: 14),
    StaticFestivalRule(name: "Republic Day",     emoji: "🇮🇳", month: 1,  day: 26),
    StaticFestivalRule(name: "Ambedkar Jayanti", emoji: "📜", month: 4,  day: 14),
    StaticFestivalRule(name: "Independence Day", emoji: "🇮🇳", month: 8,  day: 15),
    StaticFestivalRule(name: "Gandhi Jayanti",   emoji: "🕊️", month: 10, day: 2),
    StaticFestivalRule(name: "Children's Day",   emoji: "🧒", month: 11, day: 14),
    StaticFestivalRule(name: "Christmas",        emoji: "🎄", month: 12, day: 25),
]
