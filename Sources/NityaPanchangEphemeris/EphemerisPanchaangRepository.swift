//
//  EphemerisPanchaangRepository.swift
//  NityaPanchangEphemeris
//
//  Concrete implementation of PanchaangRepository backed by the Swiss Ephemeris C library.
//
//  Thread-safety: the Swiss Ephemeris C library keeps ALL of its state (open file
//  handles, segment caches, ayanamsha/sidereal mode, ...) in one process-global struct
//  (`swed`). That state is not just non-reentrant for calculation calls — even
//  swe_set_ephe_path() mutates it (it closes every open ephemeris file and re-probes
//  the lunar ephemeris via an internal swe_calc() call). Two EphemerisPanchaangRepository
//  instances each owning their own private serial queue therefore does NOT make Swiss
//  Ephemeris calls safe: one instance's swe_set_ephe_path() can free segment buffers a
//  second instance is mid-read of on another thread, crashing inside get_new_segment
//  (sweph.c) — this is exactly the SIGSEGV this design previously produced when the app
//  created a repository per screen (MainTabView + MatchInputView, both live in the same
//  process). All Swiss Ephemeris access — including the one-time ephe-path setup — must
//  therefore funnel through a single queue shared by every instance in the process.
//

import CSwissEphemeris
import Foundation
import SwissEphWrapper

private enum EphKey {
    static let queueLabel = "com.nitya.panchangam.ephemeris"
}

public final class EphemerisPanchaangRepository: PanchaangRepository, @unchecked Sendable {

    // Shared across every instance in the process — NOT an instance property. Swiss
    // Ephemeris's global C state can only ever be touched from one thread at a time,
    // no matter how many EphemerisPanchaangRepository instances the app creates.
    private static let queue = DispatchQueue(label: EphKey.queueLabel, qos: .userInitiated)

    // Runs swe_set_ephe_path exactly once per process (Swift's static-let initialization
    // is itself thread-safe), and only ever on `queue`, so it can never race a
    // calculation already in flight on another instance.
    private static let configureEphePath: Void = {
        guard let path = Bundle.module.resourcePath?.appending("/EphemerisData") else { return }
        path.withCString { swe_set_ephe_path(UnsafeMutablePointer(mutating: $0)) }
    }()

    private let wrapper = SwissEphWrapper()
    private var queue: DispatchQueue { Self.queue }

    public init() {
        Self.queue.sync { _ = Self.configureEphePath }
    }

    // MARK: - PanchaangRepository

    public func fetchPanchang(for date: Date, latitude: Double, longitude: Double) async -> PanchangDay {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: computePanchang(for: date, latitude: latitude, longitude: longitude))
            }
        }
    }

    public func fetchMonthTithis(year: Int, month: Int, latitude: Double, longitude: Double) async -> [Int: Int] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: computeMonthTithis(year: year, month: month,
                                                                   latitude: latitude, longitude: longitude))
            }
        }
    }

    public func fetchFestivals(from startDate: Date, to endDate: Date) async -> [HinduFestival] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: computeFestivals(from: startDate, to: endDate))
            }
        }
    }

    public func fetchBirthChart(for date: Date, latitude: Double, longitude: Double) async -> BirthChart {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: computeBirthChart(for: date, latitude: latitude, longitude: longitude))
            }
        }
    }

    public func fetchGrahans(from startDate: Date, to endDate: Date,
                             latitude: Double, longitude: Double) async -> [Grahan] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: computeGrahans(from: startDate, to: endDate,
                                                              latitude: latitude, longitude: longitude))
            }
        }
    }

    public func fetchDailyPanchangSummaries(from startDate: Date, to endDate: Date,
                                             latitude: Double, longitude: Double) async -> [DailyPanchangSummary] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: computeDailySummaries(from: startDate, to: endDate,
                                                                      latitude: latitude, longitude: longitude))
            }
        }
    }

    // MARK: - Private computation (always called from `queue`)

    private func computeDailySummaries(from startDate: Date, to endDate: Date,
                                        latitude: Double, longitude: Double) -> [DailyPanchangSummary] {
        let cal = Calendar.current
        var results: [DailyPanchangSummary] = []
        var current = cal.startOfDay(for: startDate)
        let end = cal.startOfDay(for: endDate)

        while current <= end {
            let sunData  = wrapper.calculateSunriseSunset(for: current, latitude: latitude, longitude: longitude)
            let rawSunriseJD = sunData["sunriseJD"] as? Double ?? 0
            let jdSunrise = rawSunriseJD > 2_400_000
                ? rawSunriseJD
                : wrapper.getJulianDayUTC(from: current.addingTimeInterval(6 * 3600))

            results.append(DailyPanchangSummary(
                date:            current,
                tithiNumber:     Int(wrapper.calculateTithiNumber(forJulianDay: jdSunrise)),
                nakshatraName:   PanchaangHelper.getNakshatraName(Int(wrapper.calculateNakshatra(forJulianDay: jdSunrise))),
                moonRashiNumber: Int(wrapper.calculateMoonRashi(forJulianDay: jdSunrise)),
                vara:            PanchaangHelper.getVaraName(for: current),
                lunarMonth:      Int(wrapper.calculatePurnimantaMonth(forJulianDay: jdSunrise)),
                isAdhikMaas:     wrapper.calculateIsAdhikMaas(forJulianDay: jdSunrise)
            ))

            current = cal.date(byAdding: .day, value: 1, to: current) ?? end.addingTimeInterval(1)
        }
        return results
    }

    private func computePanchang(for date: Date, latitude: Double, longitude: Double) -> PanchangDay {
        let dayStart = Calendar.current.startOfDay(for: date)

        // Sunrise must be computed first — all panchang limbs are evaluated at sunrise
        let sunData    = wrapper.calculateSunriseSunset(for: dayStart, latitude: latitude, longitude: longitude)
        let sunriseJD  = sunData["sunriseJD"]  as? Double ?? 0
        let sunsetJD   = sunData["sunsetJD"]   as? Double ?? 0
        let moonriseJD = sunData["moonriseJD"] as? Double ?? 0
        let moonsetJD  = sunData["moonsetJD"]  as? Double ?? 0

        // JD for modern dates is ~2.46 million; 0 means swe_rise_trans found nothing
        let moonrise: Date? = moonriseJD > 2_400_000 ? jdToDate(moonriseJD) : nil
        let moonset:  Date? = moonsetJD  > 2_400_000 ? jdToDate(moonsetJD)  : nil

        let refDate = sunriseJD > 2_400_000 ? jdToDate(sunriseJD) : dayStart
        let raw     = wrapper.calculateTithi(for: refDate, latitude: latitude, longitude: longitude)

        let refJD        = raw["julianDay"]      as? Double ?? sunriseJD
        let tithiEndJD   = raw["tithiEndJD"]     as? Double ?? 0
        let tithiNum     = raw["tithiNumber"]     as? Int   ?? 1
        let nakshatraNum = raw["nakshatraNumber"] as? Int   ?? 1
        let yogaNum      = raw["yogaNumber"]      as? Int   ?? 1
        let karanaNum    = raw["karanaNumber"]    as? Int   ?? 1

        let tithiEnd     = jdToDate(tithiEndJD)
        let nakshatraEnd = jdToDate(wrapper.calculateNakshatraEndTime(forJulianDay: refJD))
        let yogaEnd      = jdToDate(wrapper.calculateYogaEndTime(forJulianDay: refJD))

        let rashiNum  = Int(wrapper.calculateMoonRashi(forJulianDay: refJD))
        let moonRashi = "\(PanchaangHelper.getRashiSymbol(rashiNum)) \(PanchaangHelper.getMoonRashiName(rashiNum))"

        // Purnimanta Adhik: the month is Adhik when the upcoming Purnima (which closes the
        // month) is inside an Amanta Adhik window. This ends the Adhik period at the Purnima
        // so the next regular month (e.g. Ashadha) gets its full ~29 days.
        // Amanta/Solar Adhik: standard Amavasya-to-Amavasya boundary.
        let isAdhik: Bool = wrapper.calculateIsPurnimantaAdhikMaas(forJulianDay: refJD)

        let monthNum: Int32 = wrapper.calculatePurnimantaMonth(forJulianDay: refJD)

        let monthName = PanchaangHelper.getLunarMonthName(Int(monthNum), isAdhik: isAdhik)

        let weekday = Calendar.current.component(.weekday, from: dayStart)
        let mData   = wrapper.calculateMuhurats(withSunrise: sunriseJD, sunset: sunsetJD, weekday: Int32(weekday))

        func jdTime(_ key: String) -> Date { jdToDate(mData[key] as? Double ?? 0) }

        let muhurats: [Muhurat] = [
            Muhurat(name: "Brahma Muhurat",  startTime: jdTime("brahmaStart"),  endTime: jdTime("brahmaEnd"),  type: .auspicious),
            Muhurat(name: "Amrit Kaal",      startTime: jdTime("amritStart"),   endTime: jdTime("amritEnd"),   type: .auspicious),
            Muhurat(name: "Abhijit Muhurat", startTime: jdTime("abhijitStart"), endTime: jdTime("abhijitEnd"), type: .auspicious),
            Muhurat(name: "Vijaya Muhurat",  startTime: jdTime("vijayaStart"),  endTime: jdTime("vijayaEnd"),  type: .auspicious),
            Muhurat(name: "Godhuli Muhurat", startTime: jdTime("godhuliStart"), endTime: jdTime("godhuliEnd"), type: .neutral),
            Muhurat(name: "Rahu Kaal",       startTime: jdTime("rahuStart"),    endTime: jdTime("rahuEnd"),    type: .inauspicious),
            Muhurat(name: "Yamaganda",       startTime: jdTime("yamaStart"),    endTime: jdTime("yamaEnd"),    type: .inauspicious),
            Muhurat(name: "Gulik Kaal",      startTime: jdTime("gulikStart"),   endTime: jdTime("gulikEnd"),   type: .neutral),
        ].sorted { $0.startTime < $1.startTime }

        // Navagraha positions at sunrise
        let rawPlanets      = wrapper.calculatePlanetPositions(forJulianDay: refJD)
        let planetPositions = PanchaangHelper.buildPlanetPositions(from: rawPlanets as? [[String: Any]] ?? [])

        // Vedic Ayana: Sun in Capricorn–Gemini (≤3 or ≥10) = Uttarayana; else Dakshinayana
        let sunRashiNum = planetPositions.first(where: { $0.id == 0 })?.rashiNumber ?? 1
        let vedaAyana   = (sunRashiNum <= 3 || sunRashiNum >= 10) ? "Uttarayana" : "Dakshinayana"

        // Ravi Yoga: Moon's nakshatra is the ruling nakshatra of the current weekday
        let varaRaviNakshatras: [[Int]] = [
            [3, 12, 21],  // Sun: Krittika, Uttara Phalguni, Uttara Ashadha
            [4, 13, 22],  // Mon: Rohini, Hasta, Shravana
            [5, 14, 23],  // Tue: Mrigashira, Chitra, Dhanishta
            [9, 18, 27],  // Wed: Ashlesha, Jyeshtha, Revati
            [7, 16, 25],  // Thu: Punarvasu, Vishakha, Purva Bhadrapada
            [2, 11, 20],  // Fri: Bharani, Purva Phalguni, Purva Ashadha
            [8, 17, 26],  // Sat: Pushya, Anuradha, Uttara Bhadrapada
        ]
        let raviYoga = varaRaviNakshatras[weekday - 1].contains(nakshatraNum)

        // Chaughariya: 8 equal day segments (sunrise→sunset) and 8 night segments
        let chaughariyaNames:  [String]      = ["Udveg", "Char", "Labh", "Amrit", "Kaal", "Shubh", "Rog"]
        let chaughariyaTypes:  [MuhuratType] = [.inauspicious, .neutral, .auspicious, .auspicious,
                                                 .inauspicious, .auspicious, .inauspicious]

        let dayStarts = [0, 3, 6, 2, 5, 1, 4]
        let daySegLen = (sunsetJD - sunriseJD) / 8.0
        let chaughariya: [Muhurat] = (0..<8).map { i in
            let nameIdx = (dayStarts[weekday - 1] + i) % 7
            return Muhurat(name: chaughariyaNames[nameIdx],
                           startTime: jdToDate(sunriseJD + Double(i) * daySegLen),
                           endTime:   jdToDate(sunriseJD + Double(i + 1) * daySegLen),
                           type: chaughariyaTypes[nameIdx])
        }

        let nextDayStart  = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        let nextSunData   = wrapper.calculateSunriseSunset(for: nextDayStart, latitude: latitude, longitude: longitude)
        let nextSunriseJD = nextSunData["sunriseJD"] as? Double ?? (sunriseJD + 1.0)
        let nightStarts   = [5, 1, 4, 0, 3, 6, 2]
        let nightSegLen   = max(nextSunriseJD - sunsetJD, 1.0 / 1440.0) / 8.0
        let nightChaughariya: [Muhurat] = (0..<8).map { i in
            let nameIdx = (nightStarts[weekday - 1] + i) % 7
            return Muhurat(name: chaughariyaNames[nameIdx],
                           startTime: jdToDate(sunsetJD + Double(i) * nightSegLen),
                           endTime:   jdToDate(sunsetJD + Double(i + 1) * nightSegLen),
                           type: chaughariyaTypes[nameIdx])
        }

        let horas  = computeHoras(sunriseJD: sunriseJD, sunsetJD: sunsetJD,
                                   nextSunriseJD: nextSunriseJD, weekday: weekday)
        let lagnas = computeLagnas(sunriseJD: sunriseJD, sunsetJD: sunsetJD, nextSunriseJD: nextSunriseJD,
                                   latitude: latitude, longitude: longitude)
        let bhadraKaal = computeBhadraKaal(sunriseJD: sunriseJD, nextSunriseJD: nextSunriseJD)

        return PanchangDay(
            date:              date,
            lunarMonth:        monthName,
            lunarMonthNumber:  Int(monthNum),
            isAdhikMaas:       isAdhik,
            sunrise:           jdToDate(sunriseJD),
            sunset:            jdToDate(sunsetJD),
            moonrise:          moonrise,
            moonset:           moonset,
            tithi:             Tithi(name: PanchaangHelper.getTithiName(tithiNum),
                                     endTime: tithiEnd,
                                     paksha:  tithiNum <= 15 ? .krishna : .shukla),
            tithiNumber:       tithiNum,
            nakshatra:         Nakshatra(name: PanchaangHelper.getNakshatraName(nakshatraNum), endTime: nakshatraEnd),
            yoga:              MinorLimb(name: PanchaangHelper.getYogaName(yogaNum),    endTime: yogaEnd),
            karana:            MinorLimb(name: PanchaangHelper.getKaranaName(karanaNum), endTime: nil),
            vara:              PanchaangHelper.getVaraName(for: dayStart),
            moonRashi:         moonRashi,
            muhurats:          muhurats,
            chaughariya:       chaughariya,
            nightChaughariya:  nightChaughariya,
            planetPositions:   planetPositions,
            vedaAyana:         vedaAyana,
            raviYoga:          raviYoga,
            horas:             horas,
            lagnas:            lagnas,
            bhadraKaal:        bhadraKaal
        )
    }

    /// Scans the calendar day (sunrise → next sunrise) for a Vishti (Bhadra)
    /// karana window, the classically inauspicious half-tithi period most
    /// commonly known for the Raksha Bandhan "don't tie during Bhadra" rule.
    /// A karana already in progress at sunrise is walked backward to its true
    /// start rather than clipped — a warning needs an accurate start time to
    /// be useful, not just "some time before now."
    private func computeBhadraKaal(sunriseJD: Double, nextSunriseJD: Double) -> Muhurat? {
        let step: Double = 15.0 / 1440.0
        var searchJD = sunriseJD

        while searchJD < nextSunriseJD {
            let karanaNum = Int(wrapper.calculateKarana(forJulianDay: searchJD))
            let endJD = wrapper.calculateKaranaEndTime(forJulianDay: searchJD)
            // Vishti sits at index 6 of the 7-karana movable cycle (numbers
            // 2–57); the four fixed karanas (1, 58–60) never match this.
            let isVishti = karanaNum >= 2 && karanaNum <= 57 && (karanaNum - 2) % 7 == 6

            if isVishti {
                var startJD = searchJD
                while startJD - step >= sunriseJD - 0.833,
                      Int(wrapper.calculateKarana(forJulianDay: startJD - step)) == karanaNum {
                    startJD -= step
                }
                return Muhurat(name: "Bhadra Kaal", startTime: jdToDate(startJD),
                               endTime: jdToDate(min(endJD, nextSunriseJD)), type: .inauspicious)
            }
            searchJD = endJD
        }
        return nil
    }

    // MARK: - Birth Chart (Guna Milan) — Moon nakshatra/pada/rashi + Mars + Lagna

    private func computeBirthChart(for date: Date, latitude: Double, longitude: Double) -> BirthChart {
        let jd = wrapper.getJulianDayUTC(from: date)

        let nakshatraNum = Int(wrapper.calculateNakshatra(forJulianDay: jd))
        let rashiNum      = Int(wrapper.calculateMoonRashi(forJulianDay: jd))
        let lagnaLongitude = wrapper.calculateAscendant(atJD: jd, latitude: latitude, longitude: longitude)
        let lagnaRashi      = Int(lagnaLongitude / 30.0) + 1

        let rawPlanets = wrapper.calculatePlanetPositions(forJulianDay: jd) as? [[String: Any]] ?? []
        let planetPositions = PanchaangHelper.buildPlanetPositions(from: rawPlanets)
        let moonLongitude = planetPositions.first(where: { $0.id == 1 })?.longitude ?? 0
        let marsRashi      = planetPositions.first(where: { $0.id == 2 })?.rashiNumber ?? 1

        // Pada: each nakshatra spans 13°20′ (13.3333°), split into 4 padas of 3°20′ each.
        let nakshatraSpan = 360.0 / 27.0
        let offsetInNakshatra = moonLongitude.truncatingRemainder(dividingBy: nakshatraSpan)
        let pada = Int(offsetInNakshatra / (nakshatraSpan / 4.0)) + 1

        return BirthChart(
            nakshatra:     nakshatraNum,
            pada:          min(max(pada, 1), 4),
            rashi:         rashiNum,
            moonLongitude: moonLongitude,
            marsRashi:     marsRashi,
            lagnaRashi:    min(max(lagnaRashi, 1), 12),
            lagnaLongitude:  lagnaLongitude,
            planetPositions: planetPositions
        )
    }

    // MARK: - Hora (Planetary Hour) — pure calculation, no ephemeris needed

    private func computeHoras(sunriseJD: Double, sunsetJD: Double,
                               nextSunriseJD: Double, weekday: Int) -> [HoraInfo] {
        // Chaldean order (slowest to fastest): Saturn Jupiter Mars Sun Venus Mercury Moon
        let chaldean: [(planet: String, symbol: String, type: MuhuratType)] = [
            ("Saturn",  "♄", .inauspicious),
            ("Jupiter", "♃", .auspicious),
            ("Mars",    "♂", .inauspicious),
            ("Sun",     "☉", .neutral),
            ("Venus",   "♀", .auspicious),
            ("Mercury", "☿", .auspicious),
            ("Moon",    "☽", .auspicious),
        ]
        // weekday 1–7 (1=Sunday) → starting Chaldean index for day-1 hora
        let startIndices = [3, 6, 2, 5, 1, 4, 0]
        let startIdx  = startIndices[max(0, min(weekday - 1, 6))]
        let dayLen    = (sunsetJD - sunriseJD) / 12.0
        let nightLen  = max(nextSunriseJD - sunsetJD, 1.0 / 1440.0) / 12.0
        var result: [HoraInfo] = []
        for i in 0..<12 {
            let p = chaldean[(startIdx + i) % 7]
            result.append(HoraInfo(id: i, planet: p.planet, symbol: p.symbol,
                                   startTime: jdToDate(sunriseJD + Double(i) * dayLen),
                                   endTime:   jdToDate(sunriseJD + Double(i + 1) * dayLen),
                                   isDay: true, type: p.type))
        }
        for i in 0..<12 {
            let p = chaldean[(startIdx + 12 + i) % 7]
            result.append(HoraInfo(id: 12 + i, planet: p.planet, symbol: p.symbol,
                                   startTime: jdToDate(sunsetJD + Double(i) * nightLen),
                                   endTime:   jdToDate(sunsetJD + Double(i + 1) * nightLen),
                                   isDay: false, type: p.type))
        }
        return result
    }

    // MARK: - Lagna (Rising Sign) — samples ascendant every 15 min via swe_houses_ex

    private func computeLagnas(sunriseJD: Double, sunsetJD: Double, nextSunriseJD: Double,
                                latitude: Double, longitude: Double) -> [LagnaPeriod] {
        let step = 15.0 / 1440.0   // 15-minute sample interval in JD
        var lagnas: [LagnaPeriod] = []

        let firstAsc  = wrapper.calculateAscendant(atJD: sunriseJD, latitude: latitude, longitude: longitude)
        var prevRashi = Int(firstAsc / 30.0) + 1
        var periodStart = sunriseJD
        var currentJD   = sunriseJD + step

        while currentJD <= nextSunriseJD {
            let asc   = wrapper.calculateAscendant(atJD: currentJD, latitude: latitude, longitude: longitude)
            let rashi = Int(asc / 30.0) + 1
            if rashi != prevRashi {
                let boundary = findLagnaTransition(from: currentJD - step, to: currentJD,
                                                   prevRashi: prevRashi, latitude: latitude, longitude: longitude)
                lagnas.append(LagnaPeriod(
                    id: lagnas.count, rashiNumber: prevRashi,
                    rashiName:   PanchaangHelper.getMoonRashiName(prevRashi),
                    rashiSymbol: PanchaangHelper
                        .getRashiSymbol(prevRashi),
                    isDay:  periodStart < sunsetJD,
                    startTime:   jdToDate(periodStart),
                    endTime:     jdToDate(boundary)))
                periodStart = boundary
                prevRashi   = rashi
            }
            currentJD += step
        }
        // Final period ends at next sunrise
        lagnas.append(LagnaPeriod(
            id: lagnas.count, rashiNumber: prevRashi,
            rashiName:   PanchaangHelper.getMoonRashiName(prevRashi),
            rashiSymbol: PanchaangHelper
                .getRashiSymbol(prevRashi),
            isDay: periodStart < sunsetJD,
            startTime:   jdToDate(periodStart),
            endTime:     jdToDate(nextSunriseJD)))
        return lagnas
    }

    // Binary search for the moment the Ascendant moves from prevRashi into the next sign.
    // 12 iterations → precision ≈ 15 min / 2^12 ≈ 22 seconds.
    private func findLagnaTransition(from startJD: Double, to endJD: Double,
                                     prevRashi: Int, latitude: Double, longitude: Double) -> Double {
        var lo = startJD, hi = endJD
        for _ in 0..<12 {
            let mid   = (lo + hi) / 2.0
            let asc   = wrapper.calculateAscendant(atJD: mid, latitude: latitude, longitude: longitude)
            let rashi = Int(asc / 30.0) + 1
            if rashi != prevRashi { hi = mid } else { lo = mid }
        }
        return (lo + hi) / 2.0
    }

    // Tithi is evaluated at local sunrise — matching the dashboard's computePanchang logic.
    // Using midnight UTC caused mismatches in IST (+5:30) where 00:00 IST = 18:30 UTC (previous day).
    private func computeMonthTithis(year: Int, month: Int, latitude: Double, longitude: Double) -> [Int: Int] {
        let cal = Calendar.current
        var comps = DateComponents(year: year, month: month, day: 1)
        guard let first = cal.date(from: comps),
              let count = cal.range(of: .day, in: .month, for: first)?.count else { return [:] }
        var results: [Int: Int] = [:]
        for day in 1...count {
            comps.day = day
            guard let date = cal.date(from: comps) else { continue }
            let sunData   = wrapper.calculateSunriseSunset(for: date, latitude: latitude, longitude: longitude)
            let sunriseJD = sunData["sunriseJD"] as? Double ?? 0
            let refJD     = sunriseJD > 2_400_000 ? sunriseJD : wrapper.getJulianDayUTC(from: date)
            results[day]  = Int(wrapper.calculateTithiNumber(forJulianDay: refJD))
        }
        return results
    }

    // Pradosh Kaal (Diwali, Holika Dahan) and Aparahna (Dussehra) windows are computed
    // from real sunrise/sunset, but for a fixed reference point — Ujjain, the traditional
    // reference meridian for Indian panchangs — rather than the user's live location.
    // These dates are meant to be one nationally-agreed day, the way a printed calendar
    // publishes them, not something that shifts with the viewer's GPS the way a personal
    // Muhurat/Chaughariya rightly does.
    private static let referenceLatitude  = 23.1765
    private static let referenceLongitude = 75.7885

    private func computeFestivals(from startDate: Date, to endDate: Date) -> [HinduFestival] {
        let cal = Calendar.current
        var festivals: [HinduFestival] = []
        var seen: Set<String> = []
        var current = startDate

        while current <= endDate {
            let calYear = cal.component(.year, from: current)
            let startOfDay = cal.startOfDay(for: current)

            // 1. ALWAYS calculate Sunrise (Base metrics for the day)
            let jdSunrise = wrapper.getJulianDayUTC(from: startOfDay.addingTimeInterval(6 * 3600))
            let tithiSunrise = Int(wrapper.calculateTithiNumber(forJulianDay: jdSunrise))
            let monthSunrise = Int(wrapper.calculatePurnimantaMonth(forJulianDay: jdSunrise))
            let isAdhikSunrise = wrapper.calculateIsAdhikMaas(forJulianDay: jdSunrise)

            // 2. Setup Lazy Caches — one per non-sunrise observation instant, each only
            // computed the first time a rule actually needs it that day.
            var cachedMidnightTithi: Int?
            var cachedMidnightMonth: Int?
            var cachedMidnightAdhik: Bool?
            var cachedPradoshTithi: Int?
            var cachedPradoshMonth: Int?
            var cachedPradoshAdhik: Bool?
            var cachedAparahnaTithi: Int?
            var cachedAparahnaMonth: Int?
            var cachedAparahnaAdhik: Bool?

            // 3. Evaluate Rules
            for rule in allFestivalRules {
                let activeTithi: Int
                let activeMonth: Int
                let isAdhik: Bool

                // 🚀 PROXIMITY SHORT-CIRCUIT (shared by every non-sunrise instant): if the
                // Sunrise Tithi is nowhere near the rule's target Tithi, the real instant
                // (midnight/pradosh/aparahna, all within ~a day of sunrise) cannot be either.
                // (We check >= 28 to handle the wrap-around from Amavasya to Pratipada.)
                func nearSunrise() -> Bool {
                    let diff = abs(tithiSunrise - rule.tithiNumber)
                    return diff <= 2 || diff >= 28
                }

                switch rule.observationTime {
                case .midnight:
                    guard nearSunrise() else { continue }

                    // ⚡️ LAZY EVALUATION: Only calculate midnight if we passed the proximity check
                    if cachedMidnightTithi == nil {
                        let jdMidnight = wrapper.getJulianDayUTC(from: startOfDay.addingTimeInterval(23 * 3600 + 59 * 60))
                        cachedMidnightTithi = Int(wrapper.calculateTithiNumber(forJulianDay: jdMidnight))
                        cachedMidnightMonth = Int(wrapper.calculatePurnimantaMonth(forJulianDay: jdMidnight))
                        cachedMidnightAdhik = wrapper.calculateIsAdhikMaas(forJulianDay: jdMidnight)
                    }

                    activeTithi = cachedMidnightTithi!
                    activeMonth = cachedMidnightMonth!
                    isAdhik = cachedMidnightAdhik!

                case .pradoshKaal:
                    guard nearSunrise() else { continue }

                    if cachedPradoshTithi == nil {
                        let sunData      = wrapper.calculateSunriseSunset(
                            for: startOfDay, latitude: Self.referenceLatitude, longitude: Self.referenceLongitude)
                        let sunsetJD     = sunData["sunsetJD"] as? Double ?? jdSunrise
                        let nextDayStart = cal.date(byAdding: .day, value: 1, to: startOfDay)!
                        let nextSunData  = wrapper.calculateSunriseSunset(
                            for: nextDayStart, latitude: Self.referenceLatitude, longitude: Self.referenceLongitude)
                        let nextSunriseJD = nextSunData["sunriseJD"] as? Double ?? (sunsetJD + 0.5)

                        // Pradosh Kaal: the first fifth of the night (sunset → next sunrise),
                        // sampled at its midpoint.
                        let nightLen  = max(nextSunriseJD - sunsetJD, 1.0 / 1440.0)
                        let jdPradosh = sunsetJD + nightLen / 10.0
                        cachedPradoshTithi = Int(wrapper.calculateTithiNumber(forJulianDay: jdPradosh))
                        cachedPradoshMonth = Int(wrapper.calculatePurnimantaMonth(forJulianDay: jdPradosh))
                        cachedPradoshAdhik = wrapper.calculateIsAdhikMaas(forJulianDay: jdPradosh)
                    }

                    activeTithi = cachedPradoshTithi!
                    activeMonth = cachedPradoshMonth!
                    isAdhik = cachedPradoshAdhik!

                case .aparahna:
                    guard nearSunrise() else { continue }

                    if cachedAparahnaTithi == nil {
                        let sunData      = wrapper.calculateSunriseSunset(
                            for: startOfDay, latitude: Self.referenceLatitude, longitude: Self.referenceLongitude)
                        let sunriseRefJD = sunData["sunriseJD"] as? Double ?? jdSunrise
                        let sunsetRefJD  = sunData["sunsetJD"]  as? Double ?? (sunriseRefJD + 0.5)

                        // Aparahna Kaal: the third of five equal divisions of daylight,
                        // sampled at its midpoint.
                        let dayLen     = max(sunsetRefJD - sunriseRefJD, 1.0 / 1440.0)
                        let jdAparahna = sunriseRefJD + dayLen * 2.5 / 5.0
                        cachedAparahnaTithi = Int(wrapper.calculateTithiNumber(forJulianDay: jdAparahna))
                        cachedAparahnaMonth = Int(wrapper.calculatePurnimantaMonth(forJulianDay: jdAparahna))
                        cachedAparahnaAdhik = wrapper.calculateIsAdhikMaas(forJulianDay: jdAparahna)
                    }

                    activeTithi = cachedAparahnaTithi!
                    activeMonth = cachedAparahnaMonth!
                    isAdhik = cachedAparahnaAdhik!

                case .sunrise:
                    activeTithi = tithiSunrise
                    activeMonth = monthSunrise
                    isAdhik = isAdhikSunrise
                }

                // Fast-Fail: Skip if it's Adhik Maas or an invalid month
                guard !isAdhik, (1...12).contains(activeMonth) else { continue }

                // Check for an exact match
                if rule.lunarMonth == activeMonth && rule.tithiNumber == activeTithi {
                    let key = "\(rule.name)-\(calYear)"

                    if seen.insert(key).inserted {
                        festivals.append(
                            HinduFestival(
                                name: rule.name,
                                date: current,
                                emoji: rule.emoji,
                                hasIcon: rule.hasIcon
                            )
                        )
                    }
                }
            }
            // Static (fixed Gregorian date) holidays — checked for free inside the existing iteration
            let gregMonth = cal.component(.month, from: startOfDay)
            let gregDay   = cal.component(.day,   from: startOfDay)
            for rule in allStaticFestivalRules where rule.month == gregMonth && rule.day == gregDay {
                let key = "\(rule.name)-\(calYear)"
                if seen.insert(key).inserted {
                    festivals.append(HinduFestival(name: rule.name, date: current,
                                                   emoji: rule.emoji, hasIcon: rule.hasIcon))
                }
            }

            current = cal.date(byAdding: .day, value: 1, to: current) ?? endDate.addingTimeInterval(1)
        }

        festivals += kshayaFallbackFestivals(from: startDate, to: endDate, seen: &seen)
        return festivals.sorted { $0.date < $1.date }
    }

    // MARK: - Kshaya Tithi Fallback
    //
    // A tithi is "kshaya" (lost) when it starts after one sunrise and ends before
    // the next — it never touches ANY sunrise, so the primary loop above (which
    // only asks "what tithi is it AT sunrise") never finds it, and any festival
    // pinned to that tithi silently never fires that year.
    //
    // The fix doesn't need the tithi's exact start/end times: a kshaya tithi is,
    // by definition, fully contained within exactly one sunrise-to-next-sunrise
    // window — the window of whichever day's sunrise tithi is followed, at the
    // very next sunrise, by a number more than one higher than expected. That
    // gap identifies both which tithi(s) were skipped and which single day
    // contains them, unambiguously — no heuristic tie-break needed.
    //
    // Scoped to `.sunrise`-observed rules only (the vast majority). Midnight,
    // Pradosh Kaal and Aparahna rules have their own anchor instants and would
    // need their own gap-tracking to fix correctly — a deliberate follow-on,
    // not bundled here.
    private func kshayaFallbackFestivals(from startDate: Date, to endDate: Date,
                                          seen: inout Set<String>) -> [HinduFestival] {
        let cal = Calendar.current
        let windowStart = cal.startOfDay(for: startDate)
        let windowEnd   = cal.startOfDay(for: endDate)

        // One extra day on each side so a kshaya tithi sitting right at the
        // window's edge is still caught: the pair that reveals it may straddle
        // the boundary, even though the day it belongs to is inside the window.
        guard let scanStart = cal.date(byAdding: .day, value: -1, to: windowStart),
              let scanEnd   = cal.date(byAdding: .day, value: 1, to: windowEnd) else { return [] }

        var fallback: [HinduFestival] = []
        var current = scanStart
        var previous: (date: Date, tithi: Int, month: Int, isAdhik: Bool)?

        while current <= scanEnd {
            let startOfDay = cal.startOfDay(for: current)
            let jdSunrise  = wrapper.getJulianDayUTC(from: startOfDay.addingTimeInterval(6 * 3600))
            let tithi      = Int(wrapper.calculateTithiNumber(forJulianDay: jdSunrise))
            let month      = Int(wrapper.calculatePurnimantaMonth(forJulianDay: jdSunrise))
            let isAdhik    = wrapper.calculateIsAdhikMaas(forJulianDay: jdSunrise)

            if let prev = previous, !prev.isAdhik, !isAdhik,
               prev.date >= windowStart, prev.date <= windowEnd {

                // How many tithis were skipped between prev's sunrise and this
                // one's. A real kshaya skips exactly one tithi, very rarely two
                // in a row; anything higher (e.g. 29, from a same-tithi repeat
                // on a vriddhi day) is not a kshaya and must not be treated as one.
                let gap = ((tithi - prev.tithi - 1) % 30 + 30) % 30
                if gap >= 1, gap <= 2 {
                    for offset in 1...gap {
                        let skipped = ((prev.tithi - 1 + offset) % 30) + 1
                        // Tithi 1 always opens the new lunar month, so a skipped
                        // Pratipada belongs to the day AFTER the gap, not before.
                        let skippedMonth = skipped == 1 ? month : prev.month
                        guard (1...12).contains(skippedMonth) else { continue }

                        for rule in allFestivalRules
                        where rule.observationTime == .sunrise
                            && rule.tithiNumber == skipped && rule.lunarMonth == skippedMonth {
                            let calYear = cal.component(.year, from: prev.date)
                            let key = "\(rule.name)-\(calYear)"
                            if seen.insert(key).inserted {
                                fallback.append(HinduFestival(name: rule.name, date: prev.date,
                                                              emoji: rule.emoji, hasIcon: rule.hasIcon))
                            }
                        }
                    }
                }
            }

            previous = (startOfDay, tithi, month, isAdhik)
            current = cal.date(byAdding: .day, value: 1, to: current) ?? scanEnd.addingTimeInterval(1)
        }

        return fallback
    }

    private func jdToDate(_ jd: Double) -> Date {
        Date(timeIntervalSince1970: (jd - 2_440_587.5) * 86_400)
    }

    // MARK: - Eclipses (always called from `queue`)

    /// Walks the solar and lunar local-eclipse searches forward independently and
    /// merges them. Each Swiss Ephemeris call answers only "the next one after
    /// this instant", so finding a range means stepping past each hit and asking
    /// again — hence the loop rather than a single call.
    private func computeGrahans(from startDate: Date, to endDate: Date,
                                latitude: Double, longitude: Double) -> [Grahan] {
        guard endDate > startDate else { return [] }
        let startJD = wrapper.getJulianDayUTC(from: startDate)
        let endJD   = wrapper.getJulianDayUTC(from: endDate)

        var found: [Grahan] = []

        // Guards against a malformed result whose peak does not advance, which
        // would otherwise spin forever asking for "the next eclipse after the
        // same instant". Also caps pathological inputs — eclipses come at most a
        // handful of times a year, so this is far above any real answer.
        let maxIterations = 200

        // Solar
        var cursor = startJD
        for _ in 0..<maxIterations {
            guard let raw = wrapper.nextSolarEclipseVisible(fromJD: cursor,
                                                            latitude: latitude,
                                                            longitude: longitude,
                                                            maxDaysAhead: endJD - cursor),
                  let peakJD = raw["maxJD"] as? Double, peakJD > cursor
            else { break }

            found.append(solarGrahan(from: raw, peakJD: peakJD))
            cursor = peakJD + 1.0   // step clear of this eclipse before searching again
            if cursor >= endJD { break }
        }

        // Lunar
        cursor = startJD
        for _ in 0..<maxIterations {
            guard let raw = wrapper.nextLunarEclipseVisible(fromJD: cursor,
                                                            latitude: latitude,
                                                            longitude: longitude,
                                                            maxDaysAhead: endJD - cursor),
                  let peakJD = raw["maxJD"] as? Double, peakJD > cursor
            else { break }

            found.append(lunarGrahan(from: raw, peakJD: peakJD))
            cursor = peakJD + 1.0
            if cursor >= endJD { break }
        }

        return found.sorted { $0.peak < $1.peak }
    }

    private func solarGrahan(from raw: [AnyHashable: Any], peakJD: Double) -> Grahan {
        func jd(_ key: String) -> Double { raw[key] as? Double ?? 0 }
        func flag(_ key: String) -> Bool { (raw[key] as? NSNumber)?.boolValue ?? false }

        let extent: GrahanExtent = flag("isTotal")   ? .total
                                 : flag("isAnnular") ? .annular
                                                     : .partial

        // Second/third contact are zero unless the eclipse actually reaches
        // totality or annularity at this location.
        let totalityStart = jd("secondContactJD")
        let totalityEnd   = jd("thirdContactJD")

        // Fall back to the peak when a contact time is missing, so the visible
        // span is never a zero-date from 4713 BC.
        let first  = jd("firstContactJD")
        let fourth = jd("fourthContactJD")

        return Grahan(
            kind: .solar,
            extent: extent,
            peak:   jdToDate(peakJD),
            begins: jdToDate(first  > 0 ? first  : peakJD),
            ends:   jdToDate(fourth > 0 ? fourth : peakJD),
            totalityBegins: totalityStart > 0 ? jdToDate(totalityStart) : nil,
            totalityEnds:   totalityEnd   > 0 ? jdToDate(totalityEnd)   : nil,
            magnitude: raw["magnitude"] as? Double ?? 0
        )
    }

    private func lunarGrahan(from raw: [AnyHashable: Any], peakJD: Double) -> Grahan {
        func jd(_ key: String) -> Double { raw[key] as? Double ?? 0 }
        func flag(_ key: String) -> Bool { (raw[key] as? NSNumber)?.boolValue ?? false }

        let extent: GrahanExtent = flag("isTotal")     ? .total
                                 : flag("isPartial")   ? .partial
                                 : .penumbral

        let totalityStart = jd("totalBeginJD")
        let totalityEnd   = jd("totalEndJD")

        // Outermost phase that actually occurs: penumbral encloses partial, which
        // encloses totality. A penumbral-only eclipse has no partial times at all.
        let penumbralStart = jd("penumbralBeginJD")
        let penumbralEnd   = jd("penumbralEndJD")
        let partialStart   = jd("partialBeginJD")
        let partialEnd     = jd("partialEndJD")

        let begins = penumbralStart > 0 ? penumbralStart : (partialStart > 0 ? partialStart : peakJD)
        let ends   = penumbralEnd   > 0 ? penumbralEnd   : (partialEnd   > 0 ? partialEnd   : peakJD)

        // A penumbral eclipse never reaches the umbra, so its umbral magnitude is
        // legitimately 0 — falling back to the penumbral figure keeps the reported
        // magnitude meaningful instead of reading as "nothing happened".
        let umbral    = raw["umbralMagnitude"]    as? Double ?? 0
        let penumbral = raw["penumbralMagnitude"] as? Double ?? 0

        return Grahan(
            kind: .lunar,
            extent: extent,
            peak:   jdToDate(peakJD),
            begins: jdToDate(begins),
            ends:   jdToDate(ends),
            totalityBegins: totalityStart > 0 ? jdToDate(totalityStart) : nil,
            totalityEnds:   totalityEnd   > 0 ? jdToDate(totalityEnd)   : nil,
            magnitude: umbral > 0 ? umbral : penumbral
        )
    }
}
