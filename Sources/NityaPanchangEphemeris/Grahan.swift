//
//  Grahan.swift
//  NityaPanchangEphemeris
//
//  An eclipse (grahan) as observed from one place on Earth.
//
//  Only locally visible eclipses are ever produced. Swiss Ephemeris can also
//  enumerate every eclipse globally, but for panchang purposes that would be
//  misleading: Sutak is observed only where the eclipse is actually visible, so
//  an eclipse over the Pacific is not an event in the user's almanac.
//

import Foundation

public enum GrahanKind: String, Sendable {
    case solar   // Surya Grahan
    case lunar   // Chandra Grahan
}

public enum GrahanExtent: String, Sendable {
    case total
    case annular      // solar only
    case partial
    case penumbral    // lunar only
}

public struct Grahan: Sendable, Identifiable, Equatable {
    public let kind:   GrahanKind
    public let extent: GrahanExtent

    /// Greatest eclipse as seen from the requested location.
    public let peak: Date
    /// First and last local contact — the span over which anything is visible.
    /// For a solar eclipse these are first/fourth contact; for a lunar one the
    /// penumbral bounds when present, otherwise the partial bounds.
    public let begins: Date
    public let ends:   Date
    /// Totality (or annularity) window, when the eclipse reaches that phase here.
    public let totalityBegins: Date?
    public let totalityEnds:   Date?

    /// Fraction of the disc covered at greatest eclipse, as seen from this place.
    public let magnitude: Double

    public var id: String { "\(kind.rawValue)-\(peak.timeIntervalSince1970)" }

    public init(kind: GrahanKind, extent: GrahanExtent, peak: Date, begins: Date, ends: Date,
                totalityBegins: Date?, totalityEnds: Date?, magnitude: Double) {
        self.kind = kind
        self.extent = extent
        self.peak = peak
        self.begins = begins
        self.ends = ends
        self.totalityBegins = totalityBegins
        self.totalityEnds = totalityEnds
        self.magnitude = magnitude
    }

    /// Untranslated name; the app maps this through its own dictionary.
    public var name: String {
        switch (kind, extent) {
        case (.solar, .total):     return "Total Solar Eclipse"
        case (.solar, .annular):   return "Annular Solar Eclipse"
        case (.solar, _):          return "Partial Solar Eclipse"
        case (.lunar, .total):     return "Total Lunar Eclipse"
        case (.lunar, .penumbral): return "Penumbral Lunar Eclipse"
        case (.lunar, _):          return "Partial Lunar Eclipse"
        }
    }

    /// Whether any part of this eclipse falls on the given local day.
    /// Compared over the whole visible span, not just the peak — an eclipse that
    /// begins before midnight and peaks after it belongs to both days.
    public func occurs(on date: Date, calendar: Calendar = .current) -> Bool {
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        return begins < dayEnd && ends >= dayStart
    }
}
