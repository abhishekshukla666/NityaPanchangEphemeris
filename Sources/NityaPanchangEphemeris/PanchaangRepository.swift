//
//  PanchaangRepository.swift
//  NityaPanchangEphemeris
//
//  Dependency-inversion boundary: callers depend on WHAT is needed;
//  EphemerisPanchaangRepository decides HOW to compute it.
//

import Foundation

public protocol PanchaangRepository: Sendable {
    /// Full Panchang computation for one day at a given location.
    func fetchPanchang(for date: Date, latitude: Double, longitude: Double) async -> PanchangDay

    /// Tithi number (1–30) for every day of a calendar month, evaluated at local sunrise.
    func fetchMonthTithis(year: Int, month: Int, latitude: Double, longitude: Double) async -> [Int: MonthDayTithis]

    /// All festivals whose Panchang-derived date falls between startDate and endDate.
    func fetchFestivals(from startDate: Date, to endDate: Date) async -> [HinduFestival]

    /// Moon nakshatra/pada/rashi + Mars rashi + Lagna rashi for an arbitrary birth
    /// date+time+location — used for Guna Milan (marriage matching) and Kundli charts.
    func fetchBirthChart(for date: Date, latitude: Double, longitude: Double) async -> BirthChart

    /// Eclipses VISIBLE FROM the given location between the two dates, in time order.
    ///
    /// Eclipses not visible from there are omitted rather than returned with a flag:
    /// Sutak is observed only where an eclipse can actually be seen, so a globally
    /// complete list would imply observances that do not apply to this user.
    func fetchGrahans(from startDate: Date, to endDate: Date,
                      latitude: Double, longitude: Double) async -> [Grahan]

    /// One row per day between startDate and endDate — tithi, nakshatra, moon rashi,
    /// vara and lunar month, all evaluated at local sunrise. For a caller matching its
    /// own multi-day rules (e.g. Muhurat finding) against a date range.
    func fetchDailyPanchangSummaries(from startDate: Date, to endDate: Date,
                                      latitude: Double, longitude: Double) async -> [DailyPanchangSummary]

    /// When each of the nine grahas next changes sign, searching forward from
    /// `date`. Omits a graha whose crossing is not found inside the search
    /// window rather than reporting the window's own end as an answer.
    ///
    /// Deliberately not part of `fetchPanchang`. It costs about as much again
    /// as a whole panchang day, and needs no location at all — a sign change is
    /// the same instant everywhere.
    func fetchRashiChanges(from date: Date) async -> [RashiChange]

    /// Where the grahas are at one instant, rather than at a day's sunrise.
    ///
    /// `PanchangDay` reads every position at sunrise, because every panchang
    /// limb is read there — the tithi, the nakshatra and the yoga are the
    /// *day's*, and a panchang day begins at sunrise. That is right for the
    /// limbs and wrong for a card that says where the planets ARE: Mars
    /// entered Karka at 16:35 on 18 September 2026 and a sunrise reading went
    /// on saying Mithun until the following dawn, a quarter of a degree short
    /// of the boundary it had already crossed.
    ///
    /// Needs no location. A graha's longitude is the same from everywhere; only
    /// the rising sign and the day's limbs depend on where you stand.
    func fetchPlanetPositions(at date: Date) async -> PlanetSnapshot
}

/// The twelve bodies at a moment, split the way `PanchangDay` splits them.
///
/// Uranus, Neptune and Pluto stay apart from the nine for the reason they
/// always do: no classical rule has a place for them, and code that reasons
/// about the Navagraha must not pick them up by accident.
public struct PlanetSnapshot: Sendable {
    public let navagraha: [PlanetPosition]
    public let outer: [PlanetPosition]

    public init(navagraha: [PlanetPosition], outer: [PlanetPosition]) {
        self.navagraha = navagraha
        self.outer = outer
    }
}

public extension PanchaangRepository {
    /// Default no-op so existing conformers (preview/test fakes) aren't forced to
    /// implement this the moment it's added — only EphemerisPanchaangRepository
    /// needs the real implementation.
    func fetchDailyPanchangSummaries(from startDate: Date, to endDate: Date,
                                      latitude: Double, longitude: Double) async -> [DailyPanchangSummary] {
        []
    }

    /// Same no-op, for the same reason.
    func fetchRashiChanges(from date: Date) async -> [RashiChange] { [] }

    /// Same no-op again. A caller that gets nothing back falls through to the
    /// sunrise positions on `PanchangDay`, which is what it had before.
    func fetchPlanetPositions(at date: Date) async -> PlanetSnapshot {
        PlanetSnapshot(navagraha: [], outer: [])
    }
}
