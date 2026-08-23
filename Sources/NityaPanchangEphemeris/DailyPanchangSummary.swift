//
//  DailyPanchangSummary.swift
//  NityaPanchangEphemeris
//
//  A cheap, sunrise-sampled summary of one day's Panchang — just enough for a
//  caller to match its own classical rules against a date range (Muhurat
//  finding, event dating) without paying for a full PanchangDay's muhurats,
//  horas, chaughariya and planet positions on every one of those days.
//
//  Deliberately carries only raw facts, no rule logic: which tithi/nakshatra/
//  vara combination is auspicious for which occasion is a domain concern for
//  the caller, not something this package should encode per-feature.
//

import Foundation

public struct DailyPanchangSummary: Sendable {
    public let date:          Date
    public let tithiNumber:   Int      // 1–30
    public let nakshatraName: String
    public let moonRashiNumber: Int    // 1–12, Aries…Pisces
    public let vara:          String   // "Sunday"…"Saturday"
    public let lunarMonth:    Int      // 1–12
    public let isAdhikMaas:   Bool

    public init(date: Date, tithiNumber: Int, nakshatraName: String, moonRashiNumber: Int,
                vara: String, lunarMonth: Int, isAdhikMaas: Bool) {
        self.date = date
        self.tithiNumber = tithiNumber
        self.nakshatraName = nakshatraName
        self.moonRashiNumber = moonRashiNumber
        self.vara = vara
        self.lunarMonth = lunarMonth
        self.isAdhikMaas = isAdhikMaas
    }
}
