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
}
