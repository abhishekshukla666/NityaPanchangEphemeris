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
    case pradoshKaal // For Diwali Laxmi Puja — the tithi must prevail in the first
                     // fifth of the night after sunset (Pradosh-vyapini)
    case aparahna    // For Dussehra/Vijayadashami — the tithi must prevail in the fourth
                     // of five equal divisions of daylight (Aparahna-vyapini)
    case madhyahna   // For Akshaya Tritiya — the THIRD of the five divisions, so midday
                     // rather than afternoon. One division apart from Aparahna, which is
                     // enough to pick a different day whenever the tithi turns over
                     // between the two.
}


// MARK: - Region

/// Which regional calendar keeps a festival.
///
/// A set rather than a single value: most days are kept everywhere, and the
/// ones that are not are often kept in two regions but not a third. Bestu
/// Varas is Gujarat's new year on the same day Karnataka keeps Balipadyami,
/// and both fall on the Kartika Shukla Pratipada the north calls Govardhan
/// Puja — one date, three names, three audiences.
///
/// Existing rules are all `.all`, deliberately. Tagging the Hindi-belt days
/// (Chhath, Karwa Chauth, Ahoi Ashtami) as north-only would silently remove
/// festivals that readers of the shipped app already see, which is a decision
/// for the app's owner rather than a side effect of adding three languages.
/// Narrowing them later is a one-word change per rule.
public struct FestivalRegion: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let north     = FestivalRegion(rawValue: 1 << 0)
    public static let gujarat   = FestivalRegion(rawValue: 1 << 1)
    public static let karnataka = FestivalRegion(rawValue: 1 << 2)
    public static let telugu    = FestivalRegion(rawValue: 1 << 3)

    /// Kept everywhere the app is read.
    public static let all: FestivalRegion = [.north, .gujarat, .karnataka, .telugu]
    /// The two southern calendars, which share most of what the north does not.
    public static let south: FestivalRegion = [.karnataka, .telugu]
}

// MARK: - Festival Entity

public struct HinduFestival: Identifiable, Sendable {
    public let id = UUID()
    public let name:  String
    public let date:  Date
    public let emoji: String
    public let hasIcon: Bool
    /// Where this day is kept. Defaulted so every existing call site — and any
    /// caller that does not care — keeps compiling and keeps meaning "kept
    /// everywhere".
    public let regions: FestivalRegion

    public init(name: String, date: Date, emoji: String, hasIcon: Bool,
                regions: FestivalRegion = .all) {
        self.name = name
        self.date = date
        self.emoji = emoji
        self.hasIcon = hasIcon
        self.regions = regions
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
    public var regions: FestivalRegion = .all

    /// Upper bound when the rule matches a RANGE of tithis rather than one.
    ///
    /// Varalakshmi Vratam is the Friday before Shravana Purnima, which is not
    /// a tithi at all — it is whichever tithi that Friday happens to land on.
    /// Pairing a range with `weekday` expresses it exactly: the Friday whose
    /// tithi falls in the week before the full moon, and there is only ever one.
    public var tithiUpperBound: Int?

    /// Gregorian weekday (1 = Sunday, as `Calendar.component(.weekday:)`
    /// reports it) the day must fall on, when the observance is defined by the
    /// weekday rather than by the tithi alone.
    public var weekday: Int?

    /// A vriddhi Ekadashi — one whose tithi is current at two consecutive
    /// sunrises — is kept on the **second** day, not the first.
    ///
    /// The first day is Dashami-viddha: Dashami was still running into it, and
    /// the vrat may not be kept on such a day. Published dates agree across
    /// Amalaki 2023 (3 Mar), Nirjala 2024 (18 Jun), Rama 2024 (28 Oct) and
    /// Vijaya 2027 (4 Mar) — in each the tithi holds both sunrises and the
    /// observance is the later one. Ordinary festivals take the *first*
    /// sunrise their tithi touches, which is why this cannot be the default.
    ///
    /// Only vriddhi. A *kshaya* Ekadashi, touching no sunrise at all, stays on
    /// the day that held the greater part of it — the ordinary fallback — as
    /// Parivartini 2023 (25 Sep) and Yogini 2025 (21 Jun) both show.
    ///
    /// Derived from the tithi rather than set per rule, so all twenty-four
    /// Ekadashis are covered without per-rule bookkeeping.
    public var resolvesForward: Bool { tithiNumber == 11 || tithiNumber == 26 }

    public init(name: String, emoji: String, lunarMonth: Int, tithiNumber: Int,
                hasIcon: Bool = false, observationTime: ObservationTime = .sunrise,
                regions: FestivalRegion = .all,
                tithiUpperBound: Int? = nil, weekday: Int? = nil) {
        self.name = name
        self.emoji = emoji
        self.lunarMonth = lunarMonth
        self.tithiNumber = tithiNumber
        self.hasIcon = hasIcon
        self.observationTime = observationTime
        self.regions = regions
        self.tithiUpperBound = tithiUpperBound
        self.weekday = weekday
    }

    /// Whether `tithi` satisfies this rule, single value or range.
    public func matches(tithi: Int) -> Bool {
        guard let upper = tithiUpperBound else { return tithi == tithiNumber }
        return (tithiNumber...upper).contains(tithi)
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

/// Every tithi-derived rule the engine evaluates: the pan-Indian table plus
/// the regional one. Kept as a computed join rather than by pasting the
/// regional days into the main table, so "which of these is regional" stays
/// answerable by reading one list.
public let allFestivalRules: [FestivalRule] = panIndianFestivalRules + regionalFestivalRules

public let panIndianFestivalRules: [FestivalRule] = [

    // ── Chaitra (1) ── [KP after Phalguna Purnima] + [SP → Chaitra Purnima] ──
    FestivalRule(name: "Sheetala Ashtami",     emoji: "🙏", lunarMonth: 1,  tithiNumber: 8),
    FestivalRule(name: "Ugadi",                emoji: "🪷", lunarMonth: 1,  tithiNumber: 16),
    FestivalRule(name: "Gudi Padwa",           emoji: "🌾", lunarMonth: 1,  tithiNumber: 16),
    FestivalRule(name: "Navratri (Chaitra)",   emoji: "🎊", lunarMonth: 1,  tithiNumber: 16),
    FestivalRule(
        name: "Ram Navami",
        emoji: "ram",
        lunarMonth: 1,
        tithiNumber: 24,
        hasIcon: true
    ),
    FestivalRule(
        name: "Hanuman Jayanti",
        emoji: "hanuman",
        lunarMonth: 1,
        tithiNumber: 30,
        hasIcon: true
    ),

    // ── Vaishakha (2) ─────────────────────────────────────────────────────────
    // Madhyahna, not sunrise: Tritiya at midday is what dates these. In 2026
    // it reaches sunrise only on 20 Apr but holds midday on the 19th, and 2023
    // splits the same way.
    FestivalRule(
        name: "Akshaya Tritiya",
        emoji: "gold-pot",
        lunarMonth: 2,
        tithiNumber: 18,
        hasIcon: true,
        observationTime: .madhyahna
    ),
    FestivalRule(
        name: "Parshuram Jayanti",
        emoji: "axe",
        lunarMonth: 2,
        tithiNumber: 18,
        hasIcon: true,
        observationTime: .madhyahna
    ),
    FestivalRule(
        name: "Buddha Purnima",
        emoji: "buddha",
        lunarMonth: 2,
        tithiNumber: 30,
        hasIcon: true
    ),

    // Vaishakha Shukla Panchami, shared by both (2024 12 May, 2025 2 May).
    FestivalRule(name: "Shankaracharya Jayanti", emoji: "🕉️", lunarMonth: 2, tithiNumber: 20),
    FestivalRule(name: "Surdas Jayanti",        emoji: "🎵", lunarMonth: 2, tithiNumber: 20),

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
        emoji: "guru",
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
    // Ganesha was born in the Hindu midday, so the festival is kept on the day
    // whose Madhyahna holds Chaturthi — the same madhyahna-vyapini rule Akshaya
    // Tritiya above is dated by. It sat on the default sunrise reading, which is
    // a different day whenever the tithi turns over between sunrise and midday.
    FestivalRule(
        name: "Ganesh Chaturthi",
        emoji: "ganesh",
        lunarMonth: 6,
        tithiNumber: 19,
        hasIcon: true,
        observationTime: .madhyahna
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
    // Mahalaya Amavasya, Sarva Pitru Amavasya and Pitra Amavasya name the same
    // day — the Amavasya that closes Pitru Paksha and carries the last tarpan.
    // Pitra Amavasya is what it is asked for by.
    FestivalRule(name: "Pitra Amavasya",       emoji: "🌚", lunarMonth: 7,  tithiNumber: 15),
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
    FestivalRule(name: "Maha Navami",          emoji: "🪔", lunarMonth: 7,  tithiNumber: 24,
                 observationTime: .aparahna),
    FestivalRule(name: "Dussehra",             emoji: "🏹", lunarMonth: 7,  tithiNumber: 25,
                 observationTime: .aparahna),
    // Nishita, not sunrise: the whole observance is the Kojagara moon-viewing at
    // night, so the day is the one whose night holds Purnima. A Purnima that
    // begins in the afternoon and ends the next morning covers one night while
    // reaching two sunrises, which is why the two readings disagree in most
    // years. 2024 belongs on 16 Oct against the sunrise reading's 17th, and
    // 2025 on 6 Oct against its 7th — both published as the earlier date.
    FestivalRule(name: "Sharad Purnima",       emoji: "🌝", lunarMonth: 7,  tithiNumber: 30,
                 observationTime: .midnight),

    // ── Kartika (8) ── [KP = Diwali week] + [SP → Kartik Purnima] ────────────
    // Pradosh, not sunrise: the whole observance is the evening moon sighting,
    // so the day is the one whose dusk holds Chaturthi. In 2027 Chaturthi runs
    // 18 Oct 17:53 to 19 Oct 16:43 — it fills the 18th's window and is long
    // gone before the 19th's, while the sunrise reading pointed at the 19th.
    FestivalRule(name: "Karwa Chauth",         emoji: "karwa-chauth", lunarMonth: 8,  tithiNumber: 4, hasIcon: true,
                 observationTime: .pradoshKaal),
    FestivalRule(
        name: "Ahoi Ashtami",
        emoji: "⭐",
        lunarMonth: 8,
        tithiNumber: 8,
        observationTime: .pradoshKaal
    ),
    // Pradosh: the Dhanteras puja is at dusk, like Diwali two days later.
    // Sunrise put it a day late in 2023, 2024, 2025 and 2026 alike.
    FestivalRule(
        name: "Dhanteras",
        emoji: "dhanteras",
        lunarMonth: 8,
        tithiNumber: 13,
        hasIcon: true,
        observationTime: .pradoshKaal
    ),
    
    FestivalRule(
        name: "Diwali",
        emoji: "diwali",
        lunarMonth: 8,
        tithiNumber: 15,
        hasIcon: true,
        observationTime: .pradoshKaal
    ),
    FestivalRule(name: "Narak Chaturdashi",    emoji: "🪔", lunarMonth: 8,  tithiNumber: 14),
    FestivalRule(
        name: "Govardhan Puja",
        emoji: "goverdhan",
        lunarMonth: 8,
        tithiNumber: 16,
        hasIcon: true
    ),
    FestivalRule(
        name: "Bhai Dooj",
        emoji: "bhaidooj",
        lunarMonth: 8,
        tithiNumber: 17,
        hasIcon: true
    ),
    FestivalRule(name: "Chhath Puja",          emoji: "☀️", lunarMonth: 8,  tithiNumber: 21),
    FestivalRule(name: "Gopashtami",           emoji: "🐄", lunarMonth: 8,  tithiNumber: 23),
    // Kartika Shukla Ekadashi is listed once, in the 24 Ekadashis below, as
    // "Devutthana Ekadashi" -- the spelling PanchaangHelper's Ekadashi table
    // also uses. A second rule here under "Dev Uthani Ekadashi" put the same
    // day in the list twice, which Hindi showed as two names and Kannada,
    // Telugu and Gujarati showed as the same name twice.
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
    // The same day under its other name — Vasant Panchami is when Saraswati
    // is worshipped.
    FestivalRule(name: "Saraswati Puja",       emoji: "📖", lunarMonth: 11, tithiNumber: 20),
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
    // Holika Dahan and Holi are NOT in this table. Neither can be expressed
    // as "a tithi prevails at an instant": Holika Dahan is the Purnima
    // Pradosh unless Bhadra runs past midnight, in which case it defers a
    // day, and Holi is simply the day after whichever day that lands on.
    // See EphemerisPanchaangRepository.holiFestivals.

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


// MARK: - Regional Festival Rules
//
// Days kept in one regional calendar but not across all of them. Tithi numbers
// follow the same Purnimanta convention as the table above — Krishna 1–15,
// Shukla 16–30 — because every rule in this file matches on the Purnimanta
// month the ephemeris carries, whatever convention the app happens to display.
//
// Several of these fall on a day the main table already names: Bestu Varas is
// the Kartika Shukla Pratipada the north calls Govardhan Puja, Gowri Habba the
// Bhadrapada Shukla Tritiya the north calls Hartalika Teej. They are separate
// rules rather than aliases because a Gujarati reader looking for their new
// year will not find it under "Govardhan Puja", and the two are genuinely
// different observances that happen to share a date.

public let regionalFestivalRules: [FestivalRule] = [

    // ── Gujarat ───────────────────────────────────────────────────────────
    // Bestu Varas opens the Gujarati year on Kartika Shukla Pratipada — the
    // day after Diwali, not the Chaitra new year the Deccan keeps.
    FestivalRule(name: "Bestu Varas",       emoji: "🪔", lunarMonth: 8, tithiNumber: 16, regions: .gujarat),
    FestivalRule(name: "Labh Pancham",      emoji: "📿", lunarMonth: 8, tithiNumber: 20, regions: .gujarat),
    FestivalRule(name: "Vagh Baras",        emoji: "🐄", lunarMonth: 8, tithiNumber: 12, regions: .gujarat),
    FestivalRule(name: "Jaya Parvati Vrat", emoji: "🌺", lunarMonth: 4, tithiNumber: 28, regions: .gujarat),
    FestivalRule(name: "Randhan Chhath",    emoji: "🍲", lunarMonth: 5, tithiNumber: 6,  regions: .gujarat),
    FestivalRule(name: "Shitala Satam",     emoji: "🙏", lunarMonth: 5, tithiNumber: 7,  regions: .gujarat),

    // ── Karnataka ─────────────────────────────────────────────────────────
    // Gowri Habba is the day before Ganesha Chaturthi — Gauri is received on
    // the Tritiya and her son follows on the Chaturthi.
    FestivalRule(name: "Gowri Habba",       emoji: "🌺", lunarMonth: 6, tithiNumber: 18, regions: .karnataka),
    FestivalRule(name: "Ayudha Puja",       emoji: "🛠️", lunarMonth: 7, tithiNumber: 24, regions: [.karnataka, .telugu]),
    FestivalRule(name: "Basava Jayanti",    emoji: "🙏", lunarMonth: 2, tithiNumber: 18, regions: .karnataka),
    FestivalRule(name: "Balipadyami",       emoji: "🪔", lunarMonth: 8, tithiNumber: 16, regions: .karnataka),

    // ── Telugu ────────────────────────────────────────────────────────────
    // Bathukamma runs the nine nights from Bhadrapada Amavasya; this marks the
    // first (Engili Pula) day, which is how a calendar prints it.
    FestivalRule(name: "Bathukamma",        emoji: "💐", lunarMonth: 7, tithiNumber: 15, regions: .telugu),
    FestivalRule(name: "Atla Tadde",        emoji: "🥞", lunarMonth: 7, tithiNumber: 3,  regions: .telugu),
    FestivalRule(name: "Nagula Chavithi",   emoji: "🐍", lunarMonth: 8, tithiNumber: 19, regions: .telugu),
    FestivalRule(name: "Boddemma",          emoji: "💐", lunarMonth: 6, tithiNumber: 23, regions: .telugu),

    // ── Shared by both southern calendars ─────────────────────────────────
    // Varalakshmi Vratam is the Friday before Shravana Purnima, so it is dated
    // by weekday rather than by tithi — the range is the week that precedes the
    // full moon, and exactly one Friday falls inside it.
    FestivalRule(name: "Varalakshmi Vratam", emoji: "🪷", lunarMonth: 5,
                 tithiNumber: 23, regions: .south, tithiUpperBound: 29, weekday: 6),
    // Vaikuntha Ekadashi is the Mokshada Ekadashi of Margashirsha under the
    // name the south keeps it by, and the one day of the year the Vaikuntha
    // Dwara is opened.
    FestivalRule(name: "Vaikuntha Ekadashi", emoji: "🛕", lunarMonth: 9, tithiNumber: 26, regions: .south),
]

// National holidays and universally observed fixed-date festivals for India.
public let allStaticFestivalRules: [StaticFestivalRule] = [
    StaticFestivalRule(name: "New Year's Day",   emoji: "🎆", month: 1,  day: 1),
    // Neither Lohri nor Makar Sankranti is here: both are solar, not fixed
    // Gregorian dates. See the computed festivals in
    // EphemerisPanchaangRepository.festivals(from:to:).

    StaticFestivalRule(name: "Republic Day",     emoji: "🇮🇳", month: 1,  day: 26),
    // Observed on the Gregorian date by the Maharashtra government, which is
    // how it is printed on calendars; the tithi reckoning (Phalguna Krishna
    // Tritiya) is a separate observance and not what most people look for.
    StaticFestivalRule(name: "Shivaji Jayanti",  emoji: "🚩", month: 2,  day: 19),
    StaticFestivalRule(name: "Ambedkar Jayanti", emoji: "📜", month: 4,  day: 14),
    StaticFestivalRule(name: "Independence Day", emoji: "🇮🇳", month: 8,  day: 15),
    // Engineer's Day — Sir M. Visvesvaraya's birth anniversary, a fixed date.
    StaticFestivalRule(name: "Vishveshvaraya Jayanti", emoji: "⚙️", month: 9, day: 15),
    StaticFestivalRule(name: "Gandhi Jayanti",   emoji: "🕊️", month: 10, day: 2),
    StaticFestivalRule(name: "Children's Day",   emoji: "🧒", month: 11, day: 14),
    StaticFestivalRule(name: "Christmas",        emoji: "🎄", month: 12, day: 25),
]
