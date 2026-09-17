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

    public func fetchMonthTithis(year: Int, month: Int, latitude: Double, longitude: Double) async -> [Int: MonthDayTithis] {
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

    public func fetchRashiChanges(from date: Date) async -> [RashiChange] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: computeRashiChanges(from: date))
            }
        }
    }

    // MARK: - Private computation (always called from `queue`)

    /// The twelve bodies' next sign changes, in planet order — the nine, then
    /// Uranus, Neptune and Pluto.
    ///
    /// The destination sign is read a minute past the crossing rather than
    /// computed as "one more than the current one": a retrograde graha leaves
    /// through the boundary behind it, so the sign it lands in is one *less* —
    /// and at the sign boundary between Meena and Mesha either direction wraps.
    private func computeRashiChanges(from date: Date) -> [RashiChange] {
        let jd = wrapper.getJulianDayUTC(from: date)
        return (0...11).compactMap { planet in
            let changeJD = wrapper.calculateRashiChangeJD(forPlanet: Int32(planet), fromJulianDay: jd)
            // Zero means the search ran its full window without finding one,
            // which no real graha should do — but reporting nothing is the only
            // honest answer if it happens.
            guard changeJD > 0 else { return nil }
            let justAfter = wrapper.calculatePlanetLongitude(forPlanet: Int32(planet),
                                                             julianDay: changeJD + 1.0 / 1440.0)
            return RashiChange(planetID: planet,
                               date: jdToDate(changeJD),
                               toRashi: Int(justAfter / 30.0) + 1)
        }
    }

    private func computeDailySummaries(from startDate: Date, to endDate: Date,
                                        latitude: Double, longitude: Double) -> [DailyPanchangSummary] {
        let cal = Calendar.current
        var results: [DailyPanchangSummary] = []
        var current = cal.startOfDay(for: startDate)
        let end = cal.startOfDay(for: endDate)

        while current <= end {
            let sunData  = wrapper.calculateSunTimes(for: current, latitude: latitude, longitude: longitude)
            let rawSunriseJD = sunData.riseJD
            let jdSunrise = rawSunriseJD > 2_400_000
                ? rawSunriseJD
                : wrapper.getJulianDayUTC(from: current.addingTimeInterval(6 * 3600))

            // Pradosh Vrat, decided at the caller's own location rather than
            // the fixed Ujjain reference the festival rules use: a vrat is
            // kept where the observer is. The two neighbouring days are
            // only fetched when today actually holds some Trayodashi.
            let jdDayStart = wrapper.getJulianDayUTC(from: current)
            let ownPradoshOverlap = pradoshOverlap(jdDayStart: jdDayStart, latitude: latitude, longitude: longitude)
            var isPradoshVratDay = false
            if ownPradoshOverlap > 0 {
                let previousOverlap = pradoshOverlap(jdDayStart: jdDayStart - 1.0, latitude: latitude, longitude: longitude)
                let nextOverlap     = pradoshOverlap(jdDayStart: jdDayStart + 1.0, latitude: latitude, longitude: longitude)
                isPradoshVratDay = isPradoshDay(own: ownPradoshOverlap, previous: previousOverlap, next: nextOverlap)
            }

            // Only the days a Krishna Chaturthi could touch pay for a moonrise.
            let sunriseTithiNumber = Int(wrapper.calculateTithiNumber(forJulianDay: jdSunrise))
            let isSankashti = (3...5).contains(sunriseTithiNumber)
                && isSankashtiDay(date: current, sunriseTithi: sunriseTithiNumber,
                                  latitude: latitude, longitude: longitude)

            results.append(DailyPanchangSummary(
                date:            current,
                tithiNumber:     sunriseTithiNumber,
                nakshatraName:   PanchaangHelper.getNakshatraName(Int(wrapper.calculateNakshatra(forJulianDay: jdSunrise))),
                moonRashiNumber: Int(wrapper.calculateMoonRashi(forJulianDay: jdSunrise)),
                vara:            PanchaangHelper.getVaraName(for: current),
                lunarMonth:      Int(wrapper.calculatePurnimantaMonth(forJulianDay: jdSunrise)),
                isAdhikMaas:     wrapper.calculateIsAdhikMaas(forJulianDay: jdSunrise),
                isPradoshVrat:   isPradoshVratDay,
                isSankashtiChaturthi: isSankashti
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

        // Amanta — display-only parallel to the Purnimanta name above. Every
        // internal rule (festivals, Ekadashi, Samvat) keeps matching against
        // the Purnimanta month/tithi computed above regardless of this value.
        let isAdhikAmanta   = wrapper.calculateIsAdhikMaas(forJulianDay: refJD)
        let amantaMonthNum  = wrapper.calculateAmantaMonth(forJulianDay: refJD)
        let amantaMonthName = PanchaangHelper.getLunarMonthName(Int(amantaMonthNum), isAdhik: isAdhikAmanta)

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
        // Uranus, Neptune and Pluto, kept apart from the nine. Three more
        // ephemeris calls on a path that already makes dozens.
        let rawOuter      = wrapper.calculateOuterPlanetPositions(forJulianDay: refJD)
        let outerPlanets  = PanchaangHelper.buildPlanetPositions(from: rawOuter as? [[String: Any]] ?? [])

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
        let nextSunData   = wrapper.calculateSunTimes(for: nextDayStart, latitude: latitude, longitude: longitude)
        let nextSunriseJD = nextSunData.riseJD
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

        // The day's limbs as periods, so a caller can show what is running now
        // beside the Udaya reading that names the day.
        let nakshatraPeriods = limbPeriods(
            sunriseJD: sunriseJD, nextSunriseJD: nextSunriseJD,
            valueAt: { Int(self.wrapper.calculateNakshatra(forJulianDay: $0)) },
            endFrom: { self.wrapper.calculateNakshatraEndTime(forJulianDay: $0) },
            name: PanchaangHelper.getNakshatraName)
        let yogaPeriods = limbPeriods(
            sunriseJD: sunriseJD, nextSunriseJD: nextSunriseJD,
            valueAt: { Int(self.wrapper.calculateYoga(forJulianDay: $0)) },
            endFrom: { self.wrapper.calculateYogaEndTime(forJulianDay: $0) },
            name: PanchaangHelper.getYogaName)
        // The Moon's sign. Named with its symbol so it matches `moonRashi`, which
        // is what every caller already knows how to localise.
        let rashiPeriods = limbPeriods(
            sunriseJD: sunriseJD, nextSunriseJD: nextSunriseJD,
            valueAt: { Int(self.wrapper.calculateMoonRashi(forJulianDay: $0)) },
            endFrom: { self.wrapper.calculateMoonRashiEndTime(forJulianDay: $0) },
            name: { "\(PanchaangHelper.getRashiSymbol($0)) \(PanchaangHelper.getMoonRashiName($0))" })
        let karanaPeriods = limbPeriods(
            sunriseJD: sunriseJD, nextSunriseJD: nextSunriseJD,
            valueAt: { Int(self.wrapper.calculateKarana(forJulianDay: $0)) },
            endFrom: { self.wrapper.calculateKaranaEndTime(forJulianDay: $0) },
            name: PanchaangHelper.getKaranaName)

        // Pradosh Vrat. Reuses nextSunriseJD above to close tonight's
        // window; the two neighbouring days are only fetched when tonight
        // actually holds some Trayodashi, which is a handful of days a
        // month rather than every call to this hot path.
        let ownPradoshOverlap = trayodashiMinutesInPradosh(sunsetJD: sunsetJD, nextSunriseJD: nextSunriseJD)
        var isPradoshVratDay = false
        if ownPradoshOverlap > 0 {
            let jdDayStart = wrapper.getJulianDayUTC(from: dayStart)
            let previousOverlap = pradoshOverlap(jdDayStart: jdDayStart - 1.0, latitude: latitude, longitude: longitude)
            let nextOverlap     = pradoshOverlap(jdDayStart: jdDayStart + 1.0, latitude: latitude, longitude: longitude)
            isPradoshVratDay = isPradoshDay(own: ownPradoshOverlap, previous: previousOverlap, next: nextOverlap)
        }

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
            // The Udaya karana's end, which had no value to give before the day's
            // karanas were walked. Same period by construction: both start at
            // sunrise.
            karana:            MinorLimb(name: PanchaangHelper.getKaranaName(karanaNum),
                                         endTime: karanaPeriods.first?.endTime),
            vara:              PanchaangHelper.getVaraName(for: dayStart),
            moonRashi:         moonRashi,
            moonRashiNumber:   rashiNum,
            muhurats:          muhurats,
            chaughariya:       chaughariya,
            nightChaughariya:  nightChaughariya,
            planetPositions:   planetPositions,
            vedaAyana:         vedaAyana,
            raviYoga:          raviYoga,
            horas:             horas,
            lagnas:            lagnas,
            bhadraKaal:        bhadraKaal,
            amantaMonth:       amantaMonthName,
            isPradoshVrat:     isPradoshVratDay,
            nakshatras:        nakshatraPeriods,
            yogas:             yogaPeriods,
            karanas:           karanaPeriods,
            rashis:            rashiPeriods,
            outerPlanets:      outerPlanets
        )
    }

    /// Scans the calendar day (sunrise → next sunrise) for a Vishti (Bhadra)
    /// karana window, the classically inauspicious half-tithi period most
    /// commonly known for the Raksha Bandhan "don't tie during Bhadra" rule.
    /// A karana already in progress at sunrise is walked backward to its true
    /// Every period of one limb touching a panchang day, sunrise to next sunrise.
    ///
    /// Walks by taking each period's end as the next one's start, which is only
    /// sound because the end-time searches now land just past the crossing — a
    /// boundary instant that still read as the old value would leave this
    /// stepping on the spot. See NPRefineCrossing.
    ///
    /// The first period's start is clipped to sunrise. The limb itself usually
    /// began the previous evening, but the panchang day starts at sunrise and
    /// finding the true start would cost a second scan backwards for a time no
    /// caller shows. Bounded at eight so a limb that somehow fails to advance
    /// cannot spin, since this runs inside the ephemeris queue.
    private func limbPeriods(sunriseJD: Double, nextSunriseJD: Double,
                             valueAt: (Double) -> Int,
                             endFrom: (Double) -> Double,
                             name: (Int) -> String) -> [LimbPeriod] {
        var periods: [LimbPeriod] = []
        var startJD = sunriseJD
        while startJD < nextSunriseJD, periods.count < 8 {
            let endJD = endFrom(startJD)
            guard endJD > startJD else { break }
            periods.append(LimbPeriod(id: periods.count,
                                      name: name(valueAt(startJD)),
                                      startTime: jdToDate(startJD),
                                      endTime: jdToDate(endJD)))
            startJD = endJD
        }
        return periods
    }

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

    // Sunrise tithi is evaluated at local sunrise — matching the dashboard's
    // computePanchang logic. Using midnight UTC caused mismatches in IST
    // (+5:30) where 00:00 IST = 18:30 UTC (previous day).
    //
    // Pradosh Vrat is decided here too, by overlap with each day's Pradosh
    // Kaal window (see isPradoshDay below) rather than a sunrise reading —
    // the calendar's trident cannot be derived from the sunrise tithi alone.
    private func computeMonthTithis(year: Int, month: Int, latitude: Double, longitude: Double) -> [Int: MonthDayTithis] {
        let cal = Calendar.current
        let comps = DateComponents(year: year, month: month, day: 1)
        guard let first = cal.date(from: comps),
              let count = cal.range(of: .day, in: .month, for: first)?.count else { return [:] }

        // Sunrise and sunset for the whole month plus a day either side, in
        // one pass. Index `i` is the day `i - 1` days from the 1st, so `i = 0`
        // is the day before the month and `i = count + 2` the second day after
        // it. The Pradosh overlap below needs sunset at `i` against sunrise at
        // `i + 1`, and the lost-tithi check needs the sunrise past the last
        // day, which is what the padding at both ends covers.
        //
        // These used to be gathered twice: this loop took the sunrises, then
        // the overlap pass called pradoshOverlap per day, which fetched a
        // sunrise and a sunset of its own — about 97 calls a month where 33
        // suffice.
        var sunrises = [Double](repeating: 0, count: count + 3)
        var sunsets  = [Double](repeating: 0, count: count + 3)
        for i in 0...(count + 2) {
            guard let date = cal.date(byAdding: .day, value: i - 1, to: first) else { continue }
            let jd        = wrapper.getJulianDayUTC(from: date)
            let sunData   = wrapper.calculateSunTimes(for: date, latitude: latitude, longitude: longitude)
            sunrises[i] = sunData.riseJD > 2_400_000 ? sunData.riseJD : jd
            sunsets[i]  = sunData.setJD
        }

        // Pradosh Kaal overlap for every day plus the two the month's edges
        // compare against, so the 1st and the last can be judged against
        // neighbours outside the month. Index `offset+1` holds the day
        // `offset - 1` days from the 1st (offset 0 = the day before the
        // month starts, offset count+1 = the day after it ends).
        var overlap = [Int](repeating: 0, count: count + 3)
        for offset in 0...(count + 1) {
            overlap[offset + 1] = trayodashiMinutesInPradosh(sunsetJD: sunsets[offset],
                                                            nextSunriseJD: sunrises[offset + 1])
        }

        var results: [Int: MonthDayTithis] = [:]
        for day in 1...count {
            let tithi = Int(wrapper.calculateTithiNumber(forJulianDay: sunrises[day]))
            // Tithis skipped between this sunrise and the next belong to this
            // day, which held them. Only a gap of one or two is a real kshaya;
            // anything wider is a vriddhi artifact — the same bound the
            // festival fallback uses. Where two are lost at once, the one the
            // calendar can actually draw wins.
            let nextTithi = Int(wrapper.calculateTithiNumber(forJulianDay: sunrises[day + 1]))
            let gap = ((nextTithi - tithi - 1) % 30 + 30) % 30
            let skipped = (1...2).contains(gap)
                ? (1...gap).map { ((tithi - 1 + $0) % 30) + 1 }
                : []

            let dayDate = cal.date(byAdding: .day, value: day - 1, to: first)
            let isSankashti = (3...5).contains(tithi) && dayDate.map {
                isSankashtiDay(date: $0, sunriseTithi: tithi,
                               latitude: latitude, longitude: longitude)
            } ?? false

            results[day] = MonthDayTithis(
                sunriseTithi: tithi,
                lostTithi: skipped.first { $0 == 15 || $0 == 30 } ?? skipped.first ?? 0,
                isPradoshVrat: isPradoshDay(own: overlap[day + 1], previous: overlap[day], next: overlap[day + 2]),
                isSankashtiChaturthi: isSankashti
            )
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
            let jdSunrise = referenceSunriseJD(for: startOfDay)
            let tithiSunrise = Int(wrapper.calculateTithiNumber(forJulianDay: jdSunrise))
            let monthSunrise = Int(wrapper.calculatePurnimantaMonth(forJulianDay: jdSunrise))
            let isAdhikSunrise = wrapper.calculateIsAdhikMaas(forJulianDay: jdSunrise)

            // 2. Setup Lazy Caches — one per non-sunrise observation instant, each only
            // computed the first time a rule actually needs it that day.
            var cachedMidnightTithi: Int?
            var cachedMidnightMonth: Int?
            var cachedMidnightAdhik: Bool?
            /// Last night's reading, for the no-night fallback below.
            var cachedPreviousMidnightTithi: Int?
            var cachedAparahnaTithi: Int?
            var cachedAparahnaMonth: Int?
            var cachedAparahnaAdhik: Bool?
            var cachedMadhyahnaTithi: Int?
            var cachedMadhyahnaMonth: Int?
            var cachedMadhyahnaAdhik: Bool?

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
                    // A ranged rule is near sunrise if ANY tithi in its range
                    // is — measuring only from the lower bound would discard a
                    // week-wide rule five days before it was due to fire.
                    let upper = rule.tithiUpperBound ?? rule.tithiNumber
                    return (rule.tithiNumber...upper).contains(where: { target in
                        let diff = abs(tithiSunrise - target)
                        return diff <= 2 || diff >= 28
                    })
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

                    // A tithi is sampled once a night and averages under
                    // twenty-four hours, so a short one can begin after one
                    // midnight and end before the next, reaching no night at
                    // all. Ashwina Purnima does exactly that in 2041 — running
                    // from before sunrise on 9 October to before that evening —
                    // which dropped Sharad Purnima from the year entirely. The
                    // ordinary kshaya fallback cannot rescue it, being scoped to
                    // sunrise rules by construction.
                    //
                    // The day holding the tithi at sunrise takes it instead,
                    // which is what the tradition prescribes when no night
                    // qualifies: the first of the two candidate days. This can
                    // only ever add a day. It is reached once the previous night
                    // has been ruled out, and a tithi running at a sunrise but
                    // not at that night's midnight has ended during the day, so
                    // it cannot reach the next midnight either.
                    if cachedMidnightTithi! != rule.tithiNumber,
                       tithiSunrise == rule.tithiNumber {
                        if cachedPreviousMidnightTithi == nil {
                            // 23:59 of yesterday is one minute before this day begins.
                            let jd = wrapper.getJulianDayUTC(from: startOfDay.addingTimeInterval(-60))
                            cachedPreviousMidnightTithi = Int(wrapper.calculateTithiNumber(forJulianDay: jd))
                        }
                        if cachedPreviousMidnightTithi! == rule.tithiNumber {
                            // Last night held it; that night owns the observance.
                            continue
                        }
                        activeTithi = tithiSunrise
                        activeMonth = monthSunrise
                        isAdhik = isAdhikSunrise
                    } else {
                        activeTithi = cachedMidnightTithi!
                        activeMonth = cachedMidnightMonth!
                        isAdhik = cachedMidnightAdhik!
                    }

                case .pradoshKaal:
                    guard nearSunrise() else { continue }

                    // Overlap with the window, not a reading at its midpoint.
                    // Diwali 2027 is the case that forces this: Amavasya covers
                    // 17:51–19:07 on 29 Oct and the midpoint sample sits at
                    // 19:07, the very minute it ends, so no day matched at all
                    // and Diwali vanished from that year.
                    let jdDayStart = wrapper.getJulianDayUTC(from: startOfDay)
                    let own = pradoshOverlapOfTithi(jdDayStart: jdDayStart, tithi: rule.tithiNumber)
                    guard own > 0 else { continue }
                    // A tithi normally reaches two consecutive windows; the
                    // festival belongs to whichever holds more of it. Only the
                    // next day needs checking: the scan runs forward and `seen`
                    // keeps the first match of the year, so losing to the next
                    // day here is what lets that day win instead.
                    guard own >= pradoshOverlapOfTithi(jdDayStart: jdDayStart + 1.0,
                                                        tithi: rule.tithiNumber) else { continue }

                    let anchor = anchorAtTithiInPradosh(jdDayStart: jdDayStart, tithi: rule.tithiNumber)
                    activeTithi = anchor.tithi
                    activeMonth = anchor.month
                    isAdhik     = anchor.isAdhik

                case .madhyahna:
                    guard nearSunrise() else { continue }

                    if cachedMadhyahnaTithi == nil {
                        let sunData      = wrapper.calculateSunTimes(
                            for: startOfDay, latitude: Self.referenceLatitude, longitude: Self.referenceLongitude)
                        let sunriseRefJD = sunData.riseJD
                        let sunsetRefJD  = sunData.setJD

                        // Madhyahna Kaal: the third of five equal divisions of
                        // daylight, sampled at its midpoint — one division
                        // earlier than Aparahna.
                        let dayLen       = max(sunsetRefJD - sunriseRefJD, 1.0 / 1440.0)
                        let jdMadhyahna  = sunriseRefJD + dayLen * 2.5 / 5.0
                        cachedMadhyahnaTithi = Int(wrapper.calculateTithiNumber(forJulianDay: jdMadhyahna))
                        cachedMadhyahnaMonth = Int(wrapper.calculatePurnimantaMonth(forJulianDay: jdMadhyahna))
                        cachedMadhyahnaAdhik = wrapper.calculateIsAdhikMaas(forJulianDay: jdMadhyahna)
                    }

                    activeTithi = cachedMadhyahnaTithi!
                    activeMonth = cachedMadhyahnaMonth!
                    isAdhik = cachedMadhyahnaAdhik!

                case .aparahna:
                    guard nearSunrise() else { continue }

                    if cachedAparahnaTithi == nil {
                        let sunData      = wrapper.calculateSunTimes(
                            for: startOfDay, latitude: Self.referenceLatitude, longitude: Self.referenceLongitude)
                        let sunriseRefJD = sunData.riseJD
                        let sunsetRefJD  = sunData.setJD

                        // Aparahna Kaal: the fourth of five equal divisions of daylight
                        // (Pratahkal, Sangava, Madhyahna, Aparahna, Sayahna — in that order),
                        // sampled at its midpoint.
                        let dayLen     = max(sunsetRefJD - sunriseRefJD, 1.0 / 1440.0)
                        let jdAparahna = sunriseRefJD + dayLen * 3.5 / 5.0
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

                // A rule defined by weekday — Varalakshmi Vratam is the Friday
                // before Shravana Purnima — only fires on that weekday. Checked
                // against the day being evaluated, in the reference zone the
                // rest of this computation already uses.
                if let weekday = rule.weekday,
                   cal.component(.weekday, from: startOfDay) != weekday { continue }

                // Check for a match
                if rule.lunarMonth == activeMonth && rule.matches(tithi: activeTithi) {
                    // Vriddhi: when the tithi also holds tomorrow's sunrise,
                    // an Ekadashi belongs to that second day, not this first
                    // one — today is the Dashami-viddha side. Everything else
                    // keeps the first sunrise it touches, which is what the
                    // `seen` set already gives it.
                    if rule.resolvesForward, rule.tithiUpperBound == nil,
                       rule.observationTime == .sunrise,
                       let tomorrow = cal.date(byAdding: .day, value: 1, to: startOfDay),
                       Int(wrapper.calculateTithiNumber(forJulianDay: referenceSunriseJD(for: tomorrow))) == rule.tithiNumber {
                        continue
                    }

                    let key = "\(rule.name)-\(calYear)"

                    if seen.insert(key).inserted {
                        festivals.append(
                            HinduFestival(
                                name: rule.name,
                                date: current,
                                emoji: rule.emoji,
                                hasIcon: rule.hasIcon,
                                regions: rule.regions
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
        festivals += holiFestivals(from: startDate, to: endDate, seen: &seen)

        // Festivals no tithi rule can express: two solar ingresses under
        // different conventions, and one Gregorian computus.
        let windowStart = cal.startOfDay(for: startDate)
        let windowEnd   = cal.startOfDay(for: endDate)
        for year in cal.component(.year, from: startDate)...cal.component(.year, from: endDate) {
            let mesha = solarIngressJD(year: year, month: 4, day: 8, targetLongitude: 0)
            // The fourth element is the region, defaulted at each append that
            // does not care — these are mostly nationally-kept days.
            var computed: [(name: String, date: Date, emoji: String, regions: FestivalRegion)] = []

            if let jd = solarIngressJD(year: year, month: 1, day: 10, targetLongitude: 270) {
                let makarSankranti = sankrantiDeferringPastSunset(ingressJD: jd)
                computed.append(("Makar Sankranti", makarSankranti, "🌾", .all))

                // Lohri is the last night of Poh — the eve of Maghi — so it follows the
                // Sankranti rather than sitting on a fixed 13 January, which is the same
                // reasoning that already keeps Makar Sankranti itself off a fixed 14th.
                // The static date is right in most years and wrong in the two-in-five
                // where the Sankranti falls on the 15th: 2023, 2024, 2027, 2028, 2031,
                // 2032 and 2035 all belong on 14 January, and 2023 and 2024 were both
                // published as such.
                //
                // Taken from the observed Sankranti rather than the raw ingress day,
                // which is what settles 2023: the ingress was on the 14th at 20:45 IST,
                // after sunset, so Maghi deferred to the 15th and Lohri moved with it.
                if let lohri = cal.date(byAdding: .day, value: -1, to: makarSankranti) {
                    computed.append(("Lohri", lohri, "🔥", .all))
                }

                // The Telugu Sankranti is three days, and the outer two are
                // taken from the middle one for the same reason Lohri is: they
                // are defined as its eve and its morrow, not as fixed dates, so
                // they follow it into the years it falls on the 15th.
                if let bhogi = cal.date(byAdding: .day, value: -1, to: makarSankranti) {
                    computed.append(("Bhogi", bhogi, "🔥", FestivalRegion.telugu))
                }
                if let kanuma = cal.date(byAdding: .day, value: 1, to: makarSankranti) {
                    computed.append(("Kanuma", kanuma, "🐄", FestivalRegion.telugu))
                }
            }

            // The other two cardinal ingresses. Karka opens Dakshinayana and
            // Tula opens the second half of the ritual year; both are seasonal
            // markers kept across regions rather than a single region's day.
            if let jd = solarIngressJD(year: year, month: 7, day: 12, targetLongitude: 90) {
                computed.append(("Karka Sankranti", sankrantiByHinduDay(ingressJD: jd), "🌧️", .all))
            }
            if let jd = solarIngressJD(year: year, month: 10, day: 13, targetLongitude: 180) {
                computed.append(("Tula Sankranti", sankrantiByHinduDay(ingressJD: jd), "🍂", .all))
            }
            if let jd = solarIngressJD(year: year, month: 9, day: 12, targetLongitude: 150) {
                computed.append(("Vishwakarma Puja", sankrantiDeferringPastSunset(ingressJD: jd), "🛠️", .all))
            }
            if let jd = mesha {
                computed.append(("Baisakhi",        sankrantiByHinduDay(ingressJD: jd), "🌾", .all))
                computed.append(("Solar New Year",  sankrantiByHinduDay(ingressJD: jd), "☀️", .all))
            }
            if let date = goodFriday(year: year) {
                computed.append(("Good Friday", date, "✝️", .all))
            }

            for (name, date, emoji, regions) in computed {
                guard date >= windowStart, date <= windowEnd,
                      seen.insert("\(name)-\(year)").inserted else { continue }
                festivals.append(HinduFestival(name: name, date: date, emoji: emoji,
                                               hasIcon: false, regions: regions))
            }
        }

        return festivals.sorted { $0.date < $1.date }
    }

    // MARK: - Holika Dahan / Holi (Bhadra rule)
    //
    // Neither can be expressed as "a tithi prevails at an instant", so they
    // live outside `allFestivalRules` entirely.
    //
    // Holika Dahan is lit in Pradosh Kaal on the day Phalguna Purnima
    // prevails there, but Bhadra must be avoided. If Bhadra ends before
    // midnight the bonfire is lit later that same night; if it runs past
    // midnight the observance defers to the next day. Holi is then simply
    // the day after, whichever day that turned out to be — which is why it
    // is not a fixed tithi either: in 2024 and 2025 it fell on the Purnima
    // sunrise day, in 2023 and 2026 on Chaitra Krishna Pratipada.
    //
    // Verified against the ephemeris for 2023–2026, where the Bhadra end
    // time discriminates the deferred years from the rest exactly:
    //
    //   2023  Bhadra ends 05:17 next morning  -> deferred  -> 7 Mar
    //   2024  Bhadra ends 23:14 same night    -> same day  -> 24 Mar
    //   2025  Bhadra ends 23:28 same night    -> same day  -> 13 Mar
    //   2026  Bhadra ends 05:29 next morning  -> deferred  -> 3 Mar
    //
    // Dated at the Ujjain reference like the other Pradosh and Aparahna
    // rules, since these are nationally agreed dates rather than personal
    // observances.
    private func holiFestivals(from startDate: Date, to endDate: Date,
                                seen: inout Set<String>) -> [HinduFestival] {
        let cal = Calendar.current
        var out: [HinduFestival] = []

        // A day either side: Holika Dahan can defer forward out of the
        // window, and Holi is a further day on, so the Purnima that
        // produces them may sit just before the start.
        guard let cursorStart = cal.date(byAdding: .day, value: -2, to: cal.startOfDay(for: startDate)),
              let scanEnd = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: endDate)) else { return [] }

        var cursor = cursorStart
        while cursor <= scanEnd {
            let dayStart = cal.startOfDay(for: cursor)
            let sunData = wrapper.calculateSunTimes(for: dayStart, latitude: Self.referenceLatitude, longitude: Self.referenceLongitude)
            let nextDayStart = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let nextSunData = wrapper.calculateSunTimes(for: nextDayStart, latitude: Self.referenceLatitude, longitude: Self.referenceLongitude)

            let sunsetJD      = sunData.setJD
            let nextSunriseJD = nextSunData.riseJD
            let nightLen  = max(nextSunriseJD - sunsetJD, 1.0 / 1440.0)
            let pradoshJD = sunsetJD + nightLen / 10.0
            let anchorTithi   = Int(wrapper.calculateTithiNumber(forJulianDay: pradoshJD))
            let anchorMonth   = Int(wrapper.calculatePurnimantaMonth(forJulianDay: pradoshJD))
            let anchorIsAdhik = wrapper.calculateIsPurnimantaAdhikMaas(forJulianDay: pradoshJD)

            // Phalguna Purnima at Pradosh: the one day a year this can fire.
            if anchorTithi == 30, anchorMonth == 12, !anchorIsAdhik {
                let bhadraEnds = bhadraEndAfter(windowStart: sunsetJD, windowEnd: sunsetJD + nightLen / 5.0)
                let nextMidnight = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
                let defer_ = bhadraEnds.map { $0 >= nextMidnight } ?? false

                let dahan = defer_ ? nextMidnight : dayStart
                let holi  = cal.date(byAdding: .day, value: 1, to: dahan) ?? dahan
                let year  = cal.component(.year, from: dahan)

                if seen.insert("Holika Dahan-\(year)").inserted {
                    out.append(HinduFestival(name: "Holika Dahan", date: dahan, emoji: "🔥", hasIcon: false))
                }
                if seen.insert("Holi-\(year)").inserted {
                    out.append(HinduFestival(name: "Holi", date: holi, emoji: "holi", hasIcon: true))
                }
            }
            cursor = cal.date(byAdding: .day, value: 1, to: cursor) ?? scanEnd.addingTimeInterval(1)
        }

        let windowStart = cal.startOfDay(for: startDate)
        let windowEnd   = cal.startOfDay(for: endDate)
        return out.filter { $0.date >= windowStart && $0.date <= windowEnd }
    }

    /// End of the Bhadra window overlapping `windowStart`...`windowEnd`, or
    /// nil when none does.
    ///
    /// Only the end matters here: whether it lands before or after midnight
    /// is what decides the deferral, and a Bhadra that never touches Pradosh
    /// cannot block the bonfire at all.
    private func bhadraEndAfter(windowStart: Double, windowEnd: Double) -> Date? {
        let step: Double = 15.0 / 1440.0
        var t = windowStart
        var found = false
        while t <= windowEnd {
            if isVishtiKarana(forJulianDay: t) { found = true; break }
            t += step
        }
        guard found else { return nil }
        // Walk to the end of this karana. Bounded: a karana runs well under a day.
        var end = t
        while isVishtiKarana(forJulianDay: end), end < t + 1.0 { end += step }
        return jdToDate(end)
    }

    private func isVishtiKarana(forJulianDay jd: Double) -> Bool {
        let k = Int(wrapper.calculateKarana(forJulianDay: jd))
        return k >= 2 && k <= 57 && (k - 2) % 7 == 6
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
            let jdSunrise  = referenceSunriseJD(for: startOfDay)
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
                                // regions must be carried here too. Without it a
                                // festival whose tithi is kshaya that year came
                                // back as .all and appeared for every reader --
                                // Datta Jayanti did exactly that in 2026, when
                                // the Margashirsha Purnima is skipped.
                                fallback.append(HinduFestival(name: rule.name, date: prev.date,
                                                              emoji: rule.emoji, hasIcon: rule.hasIcon,
                                                              regions: rule.regions))
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

    // MARK: - Pradosh Vrat (overlap with Pradosh Kaal)
    //
    // Pradosh Vrat is kept on the day Trayodashi *prevails during* Pradosh
    // Kaal — an overlap with a window, not a tithi read at one instant.
    // Sampling a single point inside the window (the midpoint) can miss a
    // Trayodashi that covers only part of it: on 1 Mar 2026, Trayodashi ran
    // 28 Feb 20:44 – 1 Mar 19:10 while the midpoint sample sat at 19:44, so
    // neither day matched and the vrat vanished from that fortnight — not a
    // kshaya case, since Trayodashi genuinely touched a Pradosh window.
    //
    // A Trayodashi normally touches two consecutive windows; the vrat
    // belongs to whichever holds more of it, ties going to the later day.
    // Checked day by day across 2020–2043, this selects exactly one day per
    // Trayodashi — which also retires the kshaya special case entirely,
    // since a Trayodashi that reaches no window at all cannot occur.

    /// Minutes of Trayodashi falling inside this day's Pradosh Kaal window
    /// (sunset to sunset + 1/5 of the night).
    private func trayodashiMinutesInPradosh(sunsetJD: Double, nextSunriseJD: Double) -> Int {
        let nightLen  = max(nextSunriseJD - sunsetJD, 1.0 / 1440.0)
        let windowEnd = sunsetJD + nightLen / 5.0
        let windowMinutes = Int(((windowEnd - sunsetJD) * 1440.0).rounded())
        guard windowMinutes > 0 else { return 0 }

        func isTrayodashi(_ tithi: Int) -> Bool { tithi == 13 || tithi == 28 }

        let atStart = Int(wrapper.calculateTithiNumber(forJulianDay: sunsetJD))
        let atEnd   = Int(wrapper.calculateTithiNumber(forJulianDay: windowEnd))

        // A tithi runs 19–26 hours and this window is a fifth of one night, so
        // at most one tithi boundary can fall inside it. That makes the two
        // end readings enough to classify the whole window: if they agree, that
        // one tithi fills it, and if neither is Trayodashi, none of it is.
        // Reading the ends first is what keeps this cheap — it settles the
        // ~26 days a month where no Trayodashi is anywhere near dusk, in two
        // ephemeris calls instead of one per minute.
        if atStart == atEnd { return isTrayodashi(atStart) ? windowMinutes : 0 }
        guard isTrayodashi(atStart) || isTrayodashi(atEnd) else { return 0 }

        // Exactly one boundary inside: bisect to it (~8 calls to land inside a
        // minute) rather than sampling all ~144 minutes. More precise than the
        // sampling it replaces, not just faster.
        var lo = sunsetJD
        var hi = windowEnd
        while hi - lo > 1.0 / 1440.0 {
            let mid = (lo + hi) / 2.0
            if Int(wrapper.calculateTithiNumber(forJulianDay: mid)) == atStart { lo = mid } else { hi = mid }
        }
        let boundary = (lo + hi) / 2.0
        let held = isTrayodashi(atStart) ? boundary - sunsetJD : windowEnd - boundary
        return max(0, Int((held * 1440.0).rounded()))
    }

    /// `trayodashiMinutesInPradosh` for the day starting at `jdDayStart`.
    private func pradoshOverlap(jdDayStart: Double, latitude: Double, longitude: Double) -> Int {
        let dayStart = jdToDate(jdDayStart)
        let sunData = wrapper.calculateSunTimes(for: dayStart, latitude: latitude, longitude: longitude)
        let sunsetJD = sunData.setJD
        let nextDayStart = jdToDate(jdDayStart + 1.0)
        let nextSunData = wrapper.calculateSunTimes(for: nextDayStart, latitude: latitude, longitude: longitude)
        let nextSunriseJD = nextSunData.riseJD
        return trayodashiMinutesInPradosh(sunsetJD: sunsetJD, nextSunriseJD: nextSunriseJD)
    }

    /// Whether this is the day to keep Pradosh Vrat: it must hold some
    /// Trayodashi, at least as much as yesterday, and strictly more than
    /// tomorrow — the asymmetry is what sends a tie to the later day.
    private func isPradoshDay(own: Int, previous: Int, next: Int) -> Bool {
        own > 0 && own >= previous && own > next
    }

    /// Whether Chaturthi is the tithi running at this day's moonrise.
    ///
    /// Moonrise is the expensive half of a rise/set search — about 60% of it,
    /// which is why every other caller here uses the sun-only variant — so this
    /// is asked only of the two or three days a month that can possibly qualify.
    private func chaturthiAtMoonrise(on date: Date, latitude: Double, longitude: Double) -> Bool {
        let times = wrapper.calculateSunriseSunset(for: date, latitude: latitude, longitude: longitude)
        guard let moonriseJD = times["moonriseJD"] as? Double, moonriseJD > 2_400_000 else { return false }
        return Int(wrapper.calculateTithiNumber(forJulianDay: moonriseJD)) == 4
    }

    /// Whether Sankashti Chaturthi is kept on this day.
    ///
    /// Dated by the tithi at moonrise, not at sunrise: the fast is broken on
    /// sighting the moon, so the day that matters is the one whose moonrise
    /// falls inside Chaturthi. The two readings are not interchangeable —
    /// measured across 2026 at Ujjain they disagree in most months, and a
    /// sunrise reading loses January entirely, where Chaturthi began after
    /// sunrise on the 6th and ended before sunrise on the 7th and so reached no
    /// sunrise at all.
    ///
    /// Two failure directions, not one. A long Chaturthi can catch two
    /// consecutive moonrises; a short one can catch none. The tie goes to
    /// the day that also holds it at sunrise, so the fast is kept over a day
    /// that is Chaturthi throughout rather than one it only reaches by evening.
    /// That tie-break is reasoned rather than sourced — unlike Ekadashi's
    /// Dashami-viddha rule, which the tradition states outright — so it is
    /// worth checking against a published panchang.
    private func isSankashtiDay(date: Date, sunriseTithi: Int,
                                latitude: Double, longitude: Double) -> Bool {
        let cal = Calendar.current
        guard chaturthiAtMoonrise(on: date, latitude: latitude, longitude: longitude) else {
            // A Chaturthi can reach no moonrise at all. Moonrise runs about an
            // hour later each night while a tithi averages under twenty-four
            // hours, so one that begins just after an evening's moonrise can end
            // before the next — and then a moonrise test selects no day and the
            // vrat vanishes from that month, exactly the way a sunrise test
            // loses a kshaya tithi. Six months over 2026–2031 were empty for
            // this reason, 24 Feb 2027 among them: Chaturthi had not begun at
            // the 23rd's moonrise at 20:59 and was already over by the 24th's
            // at 21:58, though the 24th held it at sunrise.
            //
            // So the day that holds Chaturthi at sunrise keeps the vrat, which
            // is the day a devotee actually fasts, breaking it at that evening's
            // moonrise even though the tithi has just ended. Reached only after
            // both neighbouring moonrises have been ruled out, so it can never
            // take a day the moonrise rule has already given to another.
            guard sunriseTithi == 4 else { return false }
            guard let previous = cal.date(byAdding: .day, value: -1, to: date) else { return true }
            return !chaturthiAtMoonrise(on: previous, latitude: latitude, longitude: longitude)
        }
        guard sunriseTithi != 4 else { return true }
        guard let next = cal.date(byAdding: .day, value: 1, to: date) else { return true }
        return !chaturthiAtMoonrise(on: next, latitude: latitude, longitude: longitude)
    }

    /// Minutes of `tithi` falling inside the Pradosh Kaal window of the day
    /// starting at `jdDayStart`, at the Ujjain reference the other festival
    /// anchors use.
    ///
    /// Classified from the two window ends and bisected only when a boundary
    /// is inside — the same shape as `trayodashiMinutesInPradosh`, which does
    /// this for Pradosh Vrat at the caller's own location. A tithi is far
    /// longer than this window, so at most one boundary can fall in it.
    private func pradoshOverlapOfTithi(jdDayStart: Double, tithi: Int) -> Int {
        let dayStart = jdToDate(jdDayStart)
        let sunData = wrapper.calculateSunTimes(for: dayStart, latitude: Self.referenceLatitude, longitude: Self.referenceLongitude)
        let sunsetJD = sunData.setJD
        let nextSunData = wrapper.calculateSunTimes(for: jdToDate(jdDayStart + 1.0), latitude: Self.referenceLatitude, longitude: Self.referenceLongitude)
        let nextSunriseJD = nextSunData.riseJD

        let nightLen      = max(nextSunriseJD - sunsetJD, 1.0 / 1440.0)
        let windowEnd     = sunsetJD + nightLen / 5.0
        let windowMinutes = Int(((windowEnd - sunsetJD) * 1440.0).rounded())
        guard windowMinutes > 0 else { return 0 }

        let atStart = Int(wrapper.calculateTithiNumber(forJulianDay: sunsetJD))
        let atEnd   = Int(wrapper.calculateTithiNumber(forJulianDay: windowEnd))
        if atStart == atEnd { return atStart == tithi ? windowMinutes : 0 }
        guard atStart == tithi || atEnd == tithi else { return 0 }

        var lo = sunsetJD
        var hi = windowEnd
        while hi - lo > 1.0 / 1440.0 {
            let mid = (lo + hi) / 2.0
            if Int(wrapper.calculateTithiNumber(forJulianDay: mid)) == atStart { lo = mid } else { hi = mid }
        }
        let boundary = (lo + hi) / 2.0
        let held = atStart == tithi ? boundary - sunsetJD : windowEnd - boundary
        return max(0, Int((held * 1440.0).rounded()))
    }

    /// The anchor to match a Pradosh festival against, read where `tithi`
    /// actually sits inside the window rather than at a fixed point — so the
    /// lunar month travels with the tithi that qualified, not with whatever
    /// happens to occupy the midpoint.
    private func anchorAtTithiInPradosh(jdDayStart: Double, tithi: Int) -> (tithi: Int, month: Int, isAdhik: Bool) {
        let sunData = wrapper.calculateSunTimes(for: jdToDate(jdDayStart), latitude: Self.referenceLatitude, longitude: Self.referenceLongitude)
        let sunsetJD = sunData.setJD
        let nextSunData = wrapper.calculateSunTimes(for: jdToDate(jdDayStart + 1.0), latitude: Self.referenceLatitude, longitude: Self.referenceLongitude)
        let nextSunriseJD = nextSunData.riseJD
        let windowEnd = sunsetJD + max(nextSunriseJD - sunsetJD, 1.0 / 1440.0) / 5.0
        let at = Int(wrapper.calculateTithiNumber(forJulianDay: sunsetJD)) == tithi ? sunsetJD : windowEnd
        return anchor(at: at)
    }

    /// Sunrise at the Ujjain reference for the day starting at `startOfDay` —
    /// the instant every Udaya Tithi festival rule is matched against.
    ///
    /// This was 06:00 local standing in for sunrise. Real sunrise at Ujjain
    /// runs from about 05:40 in June to 07:10 in January, so the proxy sat up
    /// to an hour early and read any tithi ending inside that gap as still
    /// current. Magha Shukla Panchami ends at 06:5x on 3 Feb 2025: the proxy
    /// saw Panchami and dated Basant Panchami and Saraswati Puja to the 3rd,
    /// when the tithi in fact reaches no sunrise at all and belongs — via the
    /// kshaya fallback — to the 2nd, as published.
    ///
    /// Falls back to the old proxy only where sunrise genuinely does not
    /// occur, matching computeDailySummaries: a scan must still yield a row.
    private func referenceSunriseJD(for startOfDay: Date) -> Double {
        let sunData = wrapper.calculateSunTimes(
            for: startOfDay, latitude: Self.referenceLatitude, longitude: Self.referenceLongitude)
        let sunriseJD = sunData.riseJD
        return sunriseJD > 2_400_000
            ? sunriseJD
            : wrapper.getJulianDayUTC(from: startOfDay.addingTimeInterval(6 * 3600))
    }

    private func anchor(at jd: Double) -> (tithi: Int, month: Int, isAdhik: Bool) {
        (Int(wrapper.calculateTithiNumber(forJulianDay: jd)),
         Int(wrapper.calculatePurnimantaMonth(forJulianDay: jd)),
         wrapper.calculateIsAdhikMaas(forJulianDay: jd))
    }

    /// The instant the Sun reaches `targetLongitude` sidereally, bisected
    /// inside a ten-day window opening on `month`/`day`, across which the
    /// longitude rises monotonically.
    ///
    /// The wrap handling matters for Mesha, whose target is 0°: without it the
    /// comparison would read the Sun at 359° as being past the target.
    private func solarIngressJD(year: Int, month: Int, day: Int, targetLongitude: Double) -> Double? {
        let cal = Calendar.current
        guard let from = cal.date(from: DateComponents(year: year, month: month, day: day)),
              let to   = cal.date(byAdding: .day, value: 10, to: from) else { return nil }

        func sunLongitude(_ jd: Double) -> Double {
            let raw = wrapper.calculatePlanetPositions(forJulianDay: jd) as? [[String: Any]] ?? []
            return raw.first(where: { ($0["planetIndex"] as? Int) == 0 })?["longitude"] as? Double ?? 0
        }
        var lo = wrapper.getJulianDayUTC(from: from)
        var hi = wrapper.getJulianDayUTC(from: to)
        while hi - lo > 1.0 / 86_400.0 {
            let mid = (lo + hi) / 2.0
            var delta = sunLongitude(mid) - targetLongitude
            if delta < -180 { delta += 360 }
            if delta >  180 { delta -= 360 }
            if delta < 0 { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2.0
    }

    /// Makar Sankranti and Vishwakarma Puja: the ingress day, or the next one
    /// when the Sankranti itself falls after sunset, its punya kaal needing
    /// daylight.
    ///
    /// Reproduces Makar Sankranti 2024 15 Jan, 2025 14, 2026 14, 2027 15,
    /// 2028 15, 2029 14, 2030 14, 2031 15, and Vishwakarma Puja on
    /// 17 September through 2023–2027.
    private func sankrantiDeferringPastSunset(ingressJD: Double) -> Date {
        let cal = Calendar.current
        let ingressDayStart = cal.startOfDay(for: jdToDate(ingressJD))
        let sunData = wrapper.calculateSunTimes(for: ingressDayStart, latitude: Self.referenceLatitude, longitude: Self.referenceLongitude)
        if ingressJD > sunData.setJD {
            return cal.date(byAdding: .day, value: 1, to: ingressDayStart) ?? ingressDayStart
        }
        return ingressDayStart
    }

    /// Baisakhi and the solar new year: the *Hindu* day holding the ingress,
    /// which runs sunrise to sunrise rather than midnight to midnight.
    ///
    /// Deliberately not the rule above. Mesha Sankranti fell at 03:21 on
    /// 14 Apr 2025 and Baisakhi was kept on the 13th, because 03:21 still
    /// belongs to the day that began at the 13th's sunrise. Reproduces
    /// 2023 14 Apr, 2024 13 Apr, 2025 13 Apr, where deferring past sunset
    /// instead would miss both 2024 and 2025.
    private func sankrantiByHinduDay(ingressJD: Double) -> Date {
        let cal = Calendar.current
        let clockDayStart = cal.startOfDay(for: jdToDate(ingressJD))
        let sunData = wrapper.calculateSunTimes(for: clockDayStart, latitude: Self.referenceLatitude, longitude: Self.referenceLongitude)
        if ingressJD < sunData.riseJD {
            return cal.date(byAdding: .day, value: -1, to: clockDayStart) ?? clockDayStart
        }
        return clockDayStart
    }

    /// Good Friday — the Friday before Easter, by the Gregorian computus.
    ///
    /// Neither solar nor lunar in this calendar's sense: Easter is the first
    /// Sunday after the ecclesiastical full moon on or after 21 March,
    /// computed from tables rather than from an ephemeris, so it cannot come
    /// from a tithi rule. Gives 2023 7 Apr, 2024 29 Mar, 2025 18 Apr,
    /// 2026 3 Apr, 2027 26 Mar.
    private func goodFriday(year: Int) -> Date? {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31        // 3 = March, 4 = April
        let day   = ((h + l - 7 * m + 114) % 31) + 1

        let cal = Calendar.current
        guard let easter = cal.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        return cal.date(byAdding: .day, value: -2, to: easter)   // Easter Sunday → Good Friday
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
