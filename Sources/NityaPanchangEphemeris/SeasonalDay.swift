//
//  SeasonalDay.swift
//  NityaPanchangEphemeris
//
//  The season and the sacred calendar for one day, as a food guide reads them:
//  the Ritu, the lunar month, whether it is Chaturmas, whether it is a vrat, and
//  whether the Ritu is about to turn or has just turned (Ritu Sandhi).
//
//  Built on the protocol's own summaries and festivals rather than on new
//  ephemeris calls, so every conformer gets it and it can never disagree with
//  the dates the calendar screens already show: the Ekadashi here is the
//  Ekadashi the festival list names, under the same tradition.
//

import Foundation

// MARK: - Ritu

/// The six seasons, each two consecutive lunar months — the pairing Charaka gives
/// (Sutrasthana 6): Chaitra and Vaishakha are Vasanta, and so on to Magha and
/// Phalguna, which are Shishira.
public enum Ritu: Int, CaseIterable, Sendable {
    case vasanta, grishma, varsha, sharad, hemanta, shishira

    /// The Ritu of a 1–12 lunar month number, Chaitra first. An Adhik month
    /// carries the number of the month it precedes, and so that month's Ritu.
    public init(lunarMonth: Int) {
        let zeroBased = ((lunarMonth - 1) % 12 + 12) % 12
        self = Ritu(rawValue: zeroBased / 2)!
    }

    /// The Ritu six months on. South of the equator the year's weather is
    /// reversed, so the season a reader actually lives in is this one.
    public var southernHemisphere: Ritu { Ritu(rawValue: (rawValue + 3) % 6)! }
}

// MARK: - Seasonal Day

/// Which month boundary a reader counts by: Purnimanta (the month ends at the
/// full moon, as in the north) or Amanta (at the new moon, as in the south,
/// Gujarat and Maharashtra).
public enum LunarMonthSystem: Sendable {
    case purnimanta, amanta
}

/// The vrats a food guide plans around.
public enum VratDay: Sendable {
    /// The day the Ekadashi is kept, under the chosen tradition.
    case ekadashi
    /// Chaitra or Sharad Navratri, from Pratipada to the Navami that closes it.
    case navratri
}

public struct SeasonalDay: Sendable, Equatable {
    /// By the month in the chosen system, and six months on south of the equator.
    public let ritu: Ritu
    /// 1–12 in the chosen system. Not shifted for the hemisphere: a month is a
    /// count of moons, the same everywhere.
    public let lunarMonth: Int
    public let isAdhikMaas: Bool
    /// From Devshayani Ekadashi (Ashadha Shukla 11) to Devutthana (Prabodhini)
    /// Ekadashi (Kartika Shukla 11), both days included, as the festival list dates them.
    public let isChaturmas: Bool
    public let vrat: VratDay?
    /// The last seven days of a Ritu and the first seven of the next — the
    /// fortnight Ashtanga Hridaya (Sutrasthana 3) asks the diet to change over.
    public let isRituSandhi: Bool

    public init(ritu: Ritu, lunarMonth: Int, isAdhikMaas: Bool, isChaturmas: Bool, vrat: VratDay?,
                isRituSandhi: Bool) {
        self.ritu = ritu
        self.lunarMonth = lunarMonth
        self.isAdhikMaas = isAdhikMaas
        self.isChaturmas = isChaturmas
        self.vrat = vrat
        self.isRituSandhi = isRituSandhi
    }
}

public extension PanchaangRepository {
    /// The season and sacred calendar for the day containing `date`.
    ///
    /// The Ritu follows the month in `system`, so it always agrees with the
    /// month a reader is shown: an Amanta reader's Ritu turns at the new moon,
    /// a Purnimanta reader's at the full moon. (`.purnimanta` gives exactly the
    /// Ritu the Panchang app has always shown.) Months and tithis are read at
    /// sunrise where the reader is; the vrat and Chaturmas dates come from the
    /// festival list, which dates them nationally, as a printed calendar does.
    ///
    /// Nil when the repository can't answer — a test double with no summaries,
    /// or a fixture built before `amantaMonth` existed asked for Amanta.
    func fetchSeasonalDay(for date: Date, latitude: Double, longitude: Double,
                          system: LunarMonthSystem,
                          tradition: EkadashiTradition = .default) async -> SeasonalDay? {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        func offset(_ days: Int) -> Date { cal.date(byAdding: .day, value: days, to: day)! }

        // Ritu Sandhi needs the Ritu a week either side; a Ritu lasts about
        // fifty-nine days, so a week away differs exactly when a turn falls
        // within that week.
        let summaries = await fetchDailyPanchangSummaries(from: offset(-7), to: offset(7),
                                                          latitude: latitude, longitude: longitude)
        func summary(_ days: Int) -> DailyPanchangSummary? {
            summaries.first { cal.isDate($0.date, inSameDayAs: offset(days)) }
        }
        func month(_ s: DailyPanchangSummary) -> (number: Int, adhik: Bool)? {
            switch system {
            case .purnimanta: return (s.lunarMonth, s.isPurnimantaAdhikMaas)
            case .amanta: return s.amantaMonth == 0 ? nil : (s.amantaMonth, s.isAdhikMaas)
            }
        }
        func ritu(_ s: DailyPanchangSummary) -> Ritu? {
            month(s).map { latitude < 0 ? Ritu(lunarMonth: $0.number).southernHemisphere : Ritu(lunarMonth: $0.number) }
        }
        guard let today = summary(0), let thisMonth = month(today), let thisRitu = ritu(today),
              let weekAgo = summary(-7).flatMap(ritu), let weekOn = summary(7).flatMap(ritu) else {
            return nil
        }

        // Navratri runs up to ten days, so twelve either side holds both its
        // first day and its Navami whenever `day` is inside one.
        let festivals = await fetchFestivals(from: offset(-12), to: offset(12), tradition: tradition)
        func dates(_ name: String) -> [Date] { festivals.filter { $0.name == name }.map { cal.startOfDay(for: $0.date) } }

        return SeasonalDay(ritu: thisRitu,
                           lunarMonth: thisMonth.number,
                           isAdhikMaas: thisMonth.adhik,
                           isChaturmas: Self.isChaturmas(day, today, dates),
                           vrat: Self.vrat(on: day, festivals: festivals, dates: dates, calendar: cal),
                           isRituSandhi: weekAgo != thisRitu || weekOn != thisRitu)
    }
}

// MARK: - Rules

private let ekadashiNames: Set<String> = Set(PanchaangHelper.shuklaEkadashiNames + PanchaangHelper.krishnaEkadashiNames)
    .union([PanchaangHelper.getEkadashiName(lunarMonth: 1, paksha: .shukla, isAdhik: true)])
private let devshayani = PanchaangHelper.getEkadashiName(lunarMonth: 4, paksha: .shukla)
private let devutthana = PanchaangHelper.getEkadashiName(lunarMonth: 8, paksha: .shukla)
/// Each Navratri's first day and the Navami that closes it, by their names in the festival rules.
private let navratris = [("Navratri (Chaitra)", "Ram Navami"), ("Navratri", "Maha Navami")]

private extension PanchaangRepository {
    /// Whether `day` falls in Chaturmas.
    ///
    /// Read from the Purnimanta month and tithi at sunrise, which settle every
    /// day but the few around each end. There a vriddhi or kshaya Ekadashi can
    /// move the observed day off the sunrise reading, so the answer comes from
    /// the festival list's own Devshayani and Devutthana dates instead.
    /// Purnimanta tithis run 1–15 Krishna, 16–30 Shukla; Ekadashi Shukla is 26.
    static func isChaturmas(_ day: Date, _ s: DailyPanchangSummary, _ dates: (String) -> [Date]) -> Bool {
        let (month, tithi, adhik) = (s.lunarMonth, s.tithiNumber, s.isPurnimantaAdhikMaas)
        switch month {
        case 4 where adhik:
            return false                          // Adhik Ashadha comes before Devshayani
        case 4 where (24...27).contains(tithi):
            return dates(devshayani).contains { $0 <= day } || (dates(devshayani).isEmpty && tithi >= 26)
        case 4:
            return tithi >= 28                    // the last Shukla days of Ashadha
        case 5, 6, 7:
            return true                           // Adhik or not, the heart of the four months
        case 8 where adhik:
            return true                           // Adhik Kartika comes before the real one
        case 8 where (25...28).contains(tithi):
            return dates(devutthana).contains { $0 >= day } || (dates(devutthana).isEmpty && tithi <= 26)
        case 8:
            return tithi <= 24                    // Krishna paksha and early Shukla of Kartika
        default:
            return false
        }
    }

    static func vrat(on day: Date, festivals: [HinduFestival], dates: (String) -> [Date],
                     calendar cal: Calendar) -> VratDay? {
        if festivals.contains(where: { ekadashiNames.contains($0.name) && cal.isDate($0.date, inSameDayAs: day) }) {
            return .ekadashi
        }
        for (first, navami) in navratris {
            if let start = dates(first).last(where: { $0 <= day }),
               dates(navami).contains(where: { $0 >= day && $0 >= start }) {
                return .navratri
            }
        }
        return nil
    }
}
