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
    /// Whether Pradosh Vrat is kept on this day.
    ///
    /// Decided by how much Trayodashi falls inside each day's Pradosh Kaal
    /// window rather than by a tithi read at one instant, because the vrat
    /// is dated by the tithi *prevailing during* dusk. A Trayodashi usually
    /// touches two consecutive windows and belongs to whichever holds more
    /// of it.
    public let isPradoshVrat: Bool

    /// Whether Sankashti Chaturthi is kept on this day.
    ///
    /// Like Pradosh above, and for the same kind of reason, this cannot be read
    /// off `tithiNumber`: the vrat is dated by the tithi at moonrise, since the
    /// fast is broken on sighting the moon, and that is regularly a different
    /// day from the one Chaturthi reaches at sunrise.
    public let isSankashtiChaturthi: Bool

    /// Whether a Vishti (Bhadra) karana touches this panchang day.
    ///
    /// Read from the karanas at this sunrise and the next rather than from the
    /// sunrise karana alone: a karana runs ten to thirteen hours against a
    /// twenty-four hour day, so about half of all Bhadras cover neither sunrise
    /// and a sunrise reading would miss them.
    public let hasBhadra: Bool

    public init(date: Date, tithiNumber: Int, nakshatraName: String, moonRashiNumber: Int,
                vara: String, lunarMonth: Int, isAdhikMaas: Bool, isPradoshVrat: Bool = false,
                isSankashtiChaturthi: Bool = false, hasBhadra: Bool = false) {
        self.date = date
        self.tithiNumber = tithiNumber
        self.nakshatraName = nakshatraName
        self.moonRashiNumber = moonRashiNumber
        self.vara = vara
        self.lunarMonth = lunarMonth
        self.isAdhikMaas = isAdhikMaas
        self.isPradoshVrat = isPradoshVrat
        self.isSankashtiChaturthi = isSankashtiChaturthi
        self.hasBhadra = hasBhadra
    }
}
