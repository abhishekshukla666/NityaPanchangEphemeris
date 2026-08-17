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
    func fetchMonthTithis(year: Int, month: Int, latitude: Double, longitude: Double) async -> [Int: Int]

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
}
