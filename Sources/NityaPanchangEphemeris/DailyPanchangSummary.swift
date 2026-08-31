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
    public let tithiNumber:   Int      // 1–30, at sunrise (Udaya Tithi)
    public let nakshatraName: String
    public let moonRashiNumber: Int    // 1–12, Aries…Pisces
    public let vara:          String   // "Sunday"…"Saturday"
    public let lunarMonth:    Int      // 1–12
    public let isAdhikMaas:   Bool
    /// Tithi prevailing at Pradosh Kaal (first fifth of the night after
    /// sunset, sampled at its midpoint) rather than at sunrise. Trayodashi
    /// (13/28) is conventionally dated by this reading, not Udaya Tithi —
    /// "Pradosh" literally means dusk — so a plain `tithiNumber` match would
    /// pick the wrong day whenever Trayodashi starts after sunrise and is
    /// still active that evening but has ended by the next sunrise.
    public let pradoshTithiNumber: Int  // 1–30

    public init(date: Date, tithiNumber: Int, nakshatraName: String, moonRashiNumber: Int,
                vara: String, lunarMonth: Int, isAdhikMaas: Bool, pradoshTithiNumber: Int) {
        self.date = date
        self.tithiNumber = tithiNumber
        self.nakshatraName = nakshatraName
        self.moonRashiNumber = moonRashiNumber
        self.vara = vara
        self.lunarMonth = lunarMonth
        self.isAdhikMaas = isAdhikMaas
        self.pradoshTithiNumber = pradoshTithiNumber
    }
}
