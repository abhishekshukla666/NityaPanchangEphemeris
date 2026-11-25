//
//  NakshatraWindows.swift
//  NityaPanchangEphemeris
//
//  Amrit Kaal and Varjyam: the two windows a nakshatra holds at fixed points in itself.
//
//  Each nakshatra is sixty ghatis long, however many hours the Moon takes to cross it. Amrit
//  Kaal begins at a set ghati of each -- Rohini's at 52, Mrigashira's at 38 -- and Varjyam,
//  the window to keep clear of, at another; each lasts four ghatis. So both are fractions of
//  the nakshatra they fall in, and stretch or shrink with it: about 85 minutes on a fast
//  Moon, nearer 100 on a slow one. Mula alone holds two Varjyams.
//
//  Checked against Drik Panchang's daily times for New Delhi, 25 November to 29 December
//  2026: every one of the 27 nakshatras' Amrit Kaal, and 24 of them for Varjyam, lands within
//  a twentieth of a ghati -- a minute -- of the published start, using Drik's own nakshatra
//  times. The other three Varjyam points (Bharani, Pushya, Magha) are Drik's own table of
//  tyajya ghatis, from which every checked one also agrees.
//
//  The app used to show the Amrit chaughariya, an eighth of the daytime, as "Amrit Kaal". It
//  is a different thing, and on Wednesdays it is the same eighth as Yamaganda and on Thursdays
//  as Rahu Kaal, so the app called a time to avoid the best of the day one day in seven.
//

import Foundation

enum NakshatraWindows {
    /// The ghati of its nakshatra at which Amrit Kaal begins, Ashwini (1) to Revati (27).
    static let amritGhati: [Double] = [
        42, 48, 54, 52, 38, 35, 54, 44, 56,     // Ashwini … Ashlesha
        54, 44, 42, 45, 44, 38, 38, 34, 38,     // Magha … Jyeshtha
        44, 48, 44, 34, 34, 42, 40, 48, 54,     // Mula … Revati
    ]

    /// The ghatis at which Varjyam begins, likewise. Mula has two.
    static let varjyamGhatis: [[Double]] = [
        [50], [24], [30], [40], [14], [21], [30], [20], [32],
        [30], [20], [18], [21], [20], [14], [14], [10], [14],
        [20, 56], [24], [20], [10], [10], [18], [16], [24], [30],
    ]

    /// Both last four ghatis of their nakshatra.
    static let lengthGhatis = 4.0

    /// The windows a nakshatra holds, as (start, end) in the same units as its own start and
    /// end -- Julian days, or seconds. `number` is 1-27.
    static func windows(at ghatis: [Double], nakshatraStart start: Double,
                        end: Double) -> [(start: Double, end: Double)] {
        let ghati = (end - start) / 60
        return ghatis.map { (start + $0 * ghati, start + ($0 + lengthGhatis) * ghati) }
    }

    static func amrit(nakshatra number: Int, start: Double, end: Double) -> [(start: Double, end: Double)] {
        guard (1...27).contains(number) else { return [] }
        return windows(at: [amritGhati[number - 1]], nakshatraStart: start, end: end)
    }

    static func varjyam(nakshatra number: Int, start: Double, end: Double) -> [(start: Double, end: Double)] {
        guard (1...27).contains(number) else { return [] }
        return windows(at: varjyamGhatis[number - 1], nakshatraStart: start, end: end)
    }
}
