import XCTest
@testable import NityaPanchangEphemeris
import SwissEphWrapper

final class NityaPanchangEphemerisTests: XCTestCase {

    // Ujjain — Prime Meridian of Hindu Astronomy
    private let latitude  = 23.1765
    private let longitude = 75.7885

    func testFetchPanchangProducesSaneValues() async throws {
        let repository: PanchaangRepository = EphemerisPanchaangRepository()
        let date = DateComponents(calendar: .init(identifier: .gregorian),
                                   timeZone: TimeZone(identifier: "Asia/Kolkata"),
                                   year: 2026, month: 1, day: 1, hour: 12).date!

        let panchang = await repository.fetchPanchang(for: date, latitude: latitude, longitude: longitude)

        XCTAssertTrue((1...30).contains(panchang.tithiNumber), "tithiNumber out of range: \(panchang.tithiNumber)")
        XCTAssertFalse(panchang.tithi.name.isEmpty)
        XCTAssertFalse(panchang.nakshatra.name.isEmpty)
        XCTAssertTrue((1...12).contains(panchang.lunarMonthNumber))
        XCTAssertLessThan(panchang.sunrise, panchang.sunset)
        XCTAssertEqual(panchang.planetPositions.count, 9, "expected all 9 Navagraha positions")
        XCTAssertEqual(panchang.horas.count, 24, "expected 12 day + 12 night horas")
        XCTAssertFalse(panchang.lagnas.isEmpty)
        XCTAssertEqual(panchang.muhurats.count, 8)
        XCTAssertEqual(panchang.chaughariya.count, 8)
        XCTAssertEqual(panchang.nightChaughariya.count, 8)
    }

    func testFetchBirthChartProducesSaneValues() async throws {
        let repository: PanchaangRepository = EphemerisPanchaangRepository()
        let date = DateComponents(calendar: .init(identifier: .gregorian),
                                   timeZone: TimeZone(identifier: "Asia/Kolkata"),
                                   year: 2000, month: 6, day: 15, hour: 10, minute: 30).date!

        let chart = await repository.fetchBirthChart(for: date, latitude: latitude, longitude: longitude)

        XCTAssertTrue((1...27).contains(chart.nakshatra))
        XCTAssertTrue((1...4).contains(chart.pada))
        XCTAssertTrue((1...12).contains(chart.rashi))
        XCTAssertTrue((1...12).contains(chart.marsRashi))
        XCTAssertTrue((1...12).contains(chart.lagnaRashi))
        XCTAssertEqual(chart.planetPositions.count, 9)
    }

    func testFetchMonthTithisCoversEveryDay() async throws {
        let repository: PanchaangRepository = EphemerisPanchaangRepository()
        let tithis = await repository.fetchMonthTithis(year: 2026, month: 2, latitude: latitude, longitude: longitude)

        XCTAssertEqual(tithis.count, 28, "February 2026 has 28 days")
        for (_, dayTithis) in tithis {
            XCTAssertTrue((1...30).contains(dayTithis.sunriseTithi))
        }
    }

    func testFetchFestivalsFindsDiwali() async throws {
        let repository: PanchaangRepository = EphemerisPanchaangRepository()
        let cal = Calendar(identifier: .gregorian)
        let start = DateComponents(calendar: cal, year: 2026, month: 1, day: 1).date!
        let end   = DateComponents(calendar: cal, year: 2026, month: 12, day: 31).date!

        let festivals = await repository.fetchFestivals(from: start, to: end)

        XCTAssertFalse(festivals.isEmpty)
        XCTAssertTrue(festivals.contains { $0.name == "Diwali" })
    }

    /// Regression test for a real crash: the app creates a separate
    /// EphemerisPanchaangRepository per screen (dashboard, Guna Milan, ...). Swiss
    /// Ephemeris keeps all state in one process-global struct, and swe_set_ephe_path()
    /// (called from init()) closes every open ephemeris file and re-probes the lunar
    /// ephemeris via an internal swe_calc() — so constructing a fresh repository while
    /// another one's computation is in flight used to SIGSEGV inside get_new_segment
    /// (sweph.c) on a real device. This drives many repositories and many concurrent
    /// calculations at once; it must complete without crashing or hanging.
    func testConcurrentRepositoriesDoNotCrash() async throws {
        let date = DateComponents(calendar: .init(identifier: .gregorian),
                                   timeZone: TimeZone(identifier: "Asia/Kolkata"),
                                   year: 2026, month: 3, day: 10, hour: 9).date!

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    // A fresh instance each time — this is what MainTabView + MatchInputView
                    // do today, and is exactly the scenario that used to crash: init()
                    // (swe_set_ephe_path) racing another instance's in-flight computation.
                    let repository = EphemerisPanchaangRepository()
                    _ = await repository.fetchPanchang(for: date, latitude: self.latitude, longitude: self.longitude)
                    _ = await repository.fetchBirthChart(for: date, latitude: self.latitude, longitude: self.longitude)
                }
            }
        }
        // Reaching this line without a crash/hang is the assertion.
    }

    // MARK: - Eclipses (Grahan)

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        DateComponents(calendar: .init(identifier: .gregorian),
                       timeZone: TimeZone(identifier: "Asia/Kolkata"),
                       year: year, month: month, day: day, hour: hour).date!
    }

    func testGrahansAreInternallyConsistent() async throws {
        let repository: PanchaangRepository = EphemerisPanchaangRepository()
        let start = date(2025, 1, 1)
        let end   = date(2028, 1, 1)

        let grahans = await repository.fetchGrahans(from: start, to: end,
                                                    latitude: latitude, longitude: longitude)

        XCTAssertFalse(grahans.isEmpty, "three years should contain at least one eclipse visible from Ujjain")

        var previousPeak = Date.distantPast
        for grahan in grahans {
            XCTAssertGreaterThanOrEqual(grahan.peak, start, "\(grahan.name) peaks before the window")
            XCTAssertLessThanOrEqual(grahan.peak, end, "\(grahan.name) peaks after the window")
            XCTAssertLessThanOrEqual(grahan.begins, grahan.peak, "\(grahan.name) begins after its peak")
            XCTAssertGreaterThanOrEqual(grahan.ends, grahan.peak, "\(grahan.name) ends before its peak")
            XCTAssertGreaterThan(grahan.magnitude, 0, "\(grahan.name) has no magnitude")
            XCTAssertGreaterThanOrEqual(grahan.peak, previousPeak, "results are not in time order")
            previousPeak = grahan.peak

            if let totalityBegins = grahan.totalityBegins, let totalityEnds = grahan.totalityEnds {
                XCTAssertLessThan(totalityBegins, totalityEnds)
                XCTAssertGreaterThanOrEqual(totalityBegins, grahan.begins)
                XCTAssertLessThanOrEqual(totalityEnds, grahan.ends)
            }
        }
    }

    /// The total lunar eclipse of 7–8 September 2025 was visible across India.
    /// Anchors that the local search actually finds real events at this location.
    func testKnownLunarEclipseVisibleFromUjjainIsFound() async throws {
        let repository: PanchaangRepository = EphemerisPanchaangRepository()
        let grahans = await repository.fetchGrahans(from: date(2025, 8, 1), to: date(2025, 10, 1),
                                                    latitude: latitude, longitude: longitude)

        let calendar = Calendar(identifier: .gregorian)
        let match = grahans.first { grahan in
            grahan.kind == .lunar &&
            grahan.occurs(on: self.date(2025, 9, 7), calendar: calendar)
        }

        XCTAssertNotNil(match, "expected the 7 Sep 2025 lunar eclipse; got \(grahans.map(\.name))")
        XCTAssertEqual(match?.extent, .total, "7 Sep 2025 was a total lunar eclipse")
    }

    /// The total solar eclipse of 12 August 2026 tracked over Iceland and Spain —
    /// India was on the night side. It must NOT appear for Ujjain, which is the
    /// whole point of using the location-aware search rather than the global one.
    func testSolarEclipseNotVisibleFromUjjainIsExcluded() async throws {
        let repository: PanchaangRepository = EphemerisPanchaangRepository()
        let grahans = await repository.fetchGrahans(from: date(2026, 8, 1), to: date(2026, 8, 20),
                                                    latitude: latitude, longitude: longitude)

        let calendar = Calendar(identifier: .gregorian)
        let solarOn12Aug = grahans.first { grahan in
            grahan.kind == .solar &&
            grahan.occurs(on: self.date(2026, 8, 12), calendar: calendar)
        }

        XCTAssertNil(solarOn12Aug, "12 Aug 2026 solar eclipse is not visible from Ujjain but was returned")
    }

    /// Holika Dahan/Holi cannot be expressed as "a tithi prevails at an
    /// instant" — the bonfire is lit at Purnima Pradosh unless Bhadra runs
    /// past midnight, in which case it (and Holi, the day after) defer by a
    /// day. These four years are the published reference: 2024/2025 land on
    /// the Purnima day itself, 2023/2026 defer past it.
    func testHolikaDahanAndHoliMatchThePublishedDates() async throws {
        let repository: PanchaangRepository = EphemerisPanchaangRepository()
        let cal = Calendar(identifier: .gregorian)

        let expected: [Int: (dahan: (Int, Int), holi: (Int, Int))] = [
            2023: ((3, 7),  (3, 8)),
            2024: ((3, 24), (3, 25)),
            2025: ((3, 13), (3, 14)),
            2026: ((3, 3),  (3, 4)),
        ]

        for (year, dates) in expected {
            let start = DateComponents(calendar: cal, year: year, month: 1, day: 1).date!
            let end   = DateComponents(calendar: cal, year: year, month: 12, day: 31).date!
            let festivals = await repository.fetchFestivals(from: start, to: end)

            let dahan = festivals.first { $0.name == "Holika Dahan" }
            let holi  = festivals.first { $0.name == "Holi" }
            XCTAssertNotNil(dahan, "\(year): no Holika Dahan found")
            XCTAssertNotNil(holi,  "\(year): no Holi found")

            if let dahan {
                XCTAssertEqual(cal.component(.month, from: dahan.date), dates.dahan.0, "\(year) Holika Dahan month")
                XCTAssertEqual(cal.component(.day,   from: dahan.date), dates.dahan.1, "\(year) Holika Dahan day")
            }
            if let holi {
                XCTAssertEqual(cal.component(.month, from: holi.date), dates.holi.0, "\(year) Holi month")
                XCTAssertEqual(cal.component(.day,   from: holi.date), dates.holi.1, "\(year) Holi day")
            }
        }
    }

    /// Regression test for the calendar's own Pradosh Vrat dating. Ashwin
    /// Shukla Trayodashi 2026 runs 23 Oct 2:35pm - 24 Oct 1:36pm IST: it
    /// overlaps the 23rd's Pradosh Kaal window far more than the 24th's, so
    /// the vrat belongs to the 23rd, not the sunrise-tithi day (24th).
    func testFetchMonthTithisDatesPradoshVratByOverlap() async throws {
        let repository: PanchaangRepository = EphemerisPanchaangRepository()
        let tithis = await repository.fetchMonthTithis(year: 2026, month: 10, latitude: latitude, longitude: longitude)

        XCTAssertEqual(try XCTUnwrap(tithis[23]).isPradoshVrat, true, "23 Oct 2026 should be Pradosh Vrat")
        XCTAssertEqual(try XCTUnwrap(tithis[24]).isPradoshVrat, false, "24 Oct 2026 should not also be Pradosh Vrat")
    }

    /// Reported: no Pradosh Vrat on 1 Mar 2026. Not a kshaya case — Trayodashi
    /// genuinely runs 28 Feb 20:44 - 1 Mar 19:10 (Ujjain), but a single
    /// midpoint sample of each day's Pradosh Kaal window landed at 19:44,
    /// after Trayodashi had already ended, so neither day's old point-sample
    /// matched. By overlap, 1 Mar's window (18:30-20:58) holds Trayodashi's
    /// first ~40 minutes against 28 Feb's ~13, so the vrat belongs to 1 Mar.
    func testFetchMonthTithisResolvesOverlapMiss() async throws {
        let repository: PanchaangRepository = EphemerisPanchaangRepository()
        let march = await repository.fetchMonthTithis(year: 2026, month: 3, latitude: latitude, longitude: longitude)
        let feb   = await repository.fetchMonthTithis(year: 2026, month: 2, latitude: latitude, longitude: longitude)

        XCTAssertEqual(try XCTUnwrap(march[1]).isPradoshVrat, true, "1 Mar 2026 should be Pradosh Vrat")
        XCTAssertEqual(try XCTUnwrap(feb[28]).isPradoshVrat, false, "28 Feb 2026 should not also be Pradosh Vrat")
    }

    /// Same 1 Mar 2026 case via the single-day fetchPanchang path (dashboard
    /// hero pill / day-detail badge) rather than the month scan.
    func testFetchPanchangResolvesOverlapMiss() async throws {
        let repository: PanchaangRepository = EphemerisPanchaangRepository()
        let date = DateComponents(calendar: .init(identifier: .gregorian),
                                   timeZone: TimeZone(identifier: "Asia/Kolkata"),
                                   year: 2026, month: 3, day: 1, hour: 12).date!
        let panchang = await repository.fetchPanchang(for: date, latitude: latitude, longitude: longitude)
        XCTAssertTrue(panchang.isPradoshVrat, "1 Mar 2026 should be Pradosh Vrat")
    }

    /// 6 Feb 2020: the case the earlier (now-superseded) point-sample kshaya
    /// fix was built to handle. The overlap test resolves it too, without
    /// any special-casing — a genuine kshaya tithi cannot reach zero overlap
    /// with both neighbouring Pradosh windows.
    func testFetchMonthTithisResolvesFormerKshayaCase() async throws {
        let repository: PanchaangRepository = EphemerisPanchaangRepository()
        let tithis = await repository.fetchMonthTithis(year: 2020, month: 2, latitude: latitude, longitude: longitude)
        XCTAssertEqual(try XCTUnwrap(tithis[6]).isPradoshVrat, true, "6 Feb 2020 should be Pradosh Vrat")
    }

    /// Published dates for the festivals whose anchors moved, each of which
    /// a sunrise reading gets wrong in at least one of these years.
    ///
    /// Makar Sankranti is solar — the Sun's entry into sidereal Makara — and
    /// defers a day when the ingress lands after sunset, so it is not the
    /// fixed 14 January it was modelled as. Karwa Chauth, Dhanteras and Diwali
    /// are all dusk observances. Akshaya Tritiya is Madhyahna, one daylight
    /// division earlier than Aparahna.
    func testFestivalsWithMovedAnchorsMatchPublishedDates() async throws {
        let repository: PanchaangRepository = EphemerisPanchaangRepository()
        let cal = Calendar(identifier: .gregorian)

        // year: [festival: (month, day)]
        let expected: [Int: [String: (Int, Int)]] = [
            2023: ["Makar Sankranti": (1, 15), "Karwa Chauth": (11, 1),  "Diwali": (11, 12),
                   "Dhanteras": (11, 10), "Akshaya Tritiya": (4, 22)],
            2024: ["Makar Sankranti": (1, 15), "Karwa Chauth": (10, 20), "Diwali": (10, 31),
                   "Dhanteras": (10, 29), "Akshaya Tritiya": (5, 10)],
            2025: ["Makar Sankranti": (1, 14), "Karwa Chauth": (10, 10), "Diwali": (10, 20),
                   "Dhanteras": (10, 18), "Akshaya Tritiya": (4, 30)],
            2026: ["Makar Sankranti": (1, 14), "Dhanteras": (11, 6),     "Akshaya Tritiya": (4, 19)],
            2027: ["Makar Sankranti": (1, 15), "Karwa Chauth": (10, 18), "Diwali": (10, 29)],
        ]

        for (year, festivals) in expected {
            let start = DateComponents(calendar: cal, year: year, month: 1, day: 1).date!
            let end   = DateComponents(calendar: cal, year: year, month: 12, day: 31).date!
            let found = await repository.fetchFestivals(from: start, to: end)

            for (name, date) in festivals {
                let match = found.first { $0.name == name }
                XCTAssertNotNil(match, "\(year): \(name) missing entirely")
                guard let match else { continue }
                XCTAssertEqual(cal.component(.month, from: match.date), date.0, "\(year) \(name) month")
                XCTAssertEqual(cal.component(.day,   from: match.date), date.1, "\(year) \(name) day")
            }
        }
    }

    /// Purnima vanished from the calendar on 23 Dec 2026: it is kshaya, with
    /// the 23rd reading 29 at sunrise and the 24th already reading 1, so no
    /// day carried 30 for the badge to match. The full moon still happens on
    /// the day that held the tithi.
    func testMonthTithisCarriesAKshayaPurnima() async throws {
        let repository: PanchaangRepository = EphemerisPanchaangRepository()
        let tithis = await repository.fetchMonthTithis(year: 2026, month: 12, latitude: latitude, longitude: longitude)

        XCTAssertFalse(tithis.values.contains { $0.sunriseTithi == 30 },
                       "Dec 2026 Purnima is kshaya — no sunrise should carry it")
        XCTAssertEqual(try XCTUnwrap(tithis[23]).lostTithi, 30,
                       "23 Dec 2026 held the lost Purnima")
    }

    /// The nine festivals added across four dating mechanisms, against
    /// published dates.
    ///
    /// Saraswati Puja 2025 is deliberately absent: Magha Shukla Panchami is
    /// kshaya that year and the published date is 2 Feb, but this engine
    /// returns 3 Feb. That is not a fault in the rule — Basant Panchami, which
    /// has always shared it, returns 3 Feb too. See
    /// `testSunriseProxyMissesATithiThatEndsBeforeRealSunrise`.
    func testNineAddedFestivalsMatchPublishedDates() async throws {
        let repository: PanchaangRepository = EphemerisPanchaangRepository()
        let cal = Calendar(identifier: .gregorian)

        let expected: [Int: [String: (Int, Int)]] = [
            2023: ["Good Friday": (4, 7),   "Baisakhi": (4, 14), "Solar New Year": (4, 14),
                   "Vishwakarma Puja": (9, 17), "Shivaji Jayanti": (2, 19),
                   "Vishveshvaraya Jayanti": (9, 15)],
            2024: ["Good Friday": (3, 29),  "Baisakhi": (4, 13), "Solar New Year": (4, 13),
                   "Vishwakarma Puja": (9, 17), "Shankaracharya Jayanti": (5, 12),
                   "Surdas Jayanti": (5, 12), "Saraswati Puja": (2, 14)],
            2025: ["Good Friday": (4, 18),  "Baisakhi": (4, 13), "Solar New Year": (4, 13),
                   "Vishwakarma Puja": (9, 17), "Shankaracharya Jayanti": (5, 2),
                   "Surdas Jayanti": (5, 2)],
            2026: ["Good Friday": (4, 3),   "Vishwakarma Puja": (9, 17),
                   "Saraswati Puja": (1, 23)],
            2027: ["Good Friday": (3, 26),  "Vishwakarma Puja": (9, 17)],
        ]

        for (year, festivals) in expected {
            let start = DateComponents(calendar: cal, year: year, month: 1, day: 1).date!
            let end   = DateComponents(calendar: cal, year: year, month: 12, day: 31).date!
            let found = await repository.fetchFestivals(from: start, to: end)

            for (name, date) in festivals {
                let match = found.first { $0.name == name }
                XCTAssertNotNil(match, "\(year): \(name) missing entirely")
                guard let match else { continue }
                XCTAssertEqual(cal.component(.month, from: match.date), date.0, "\(year) \(name) month")
                XCTAssertEqual(cal.component(.day,   from: match.date), date.1, "\(year) \(name) day")
            }
        }
    }

    /// Real sunrise is what the festival scan reads, not the old 06:00 proxy.
    ///
    /// Sunrise at Ujjain runs from about 05:40 in June to 07:10 in January, so
    /// the proxy sat up to an hour early and read any tithi ending in that gap
    /// as still current. Magha Shukla Panchami ends at 06:5x on 3 Feb 2025:
    /// the proxy saw Panchami and dated Basant Panchami to the 3rd, when the
    /// tithi in fact reaches no sunrise at all and belongs — via the kshaya
    /// fallback — to the 2nd, as published.
    func testSunriseProxyMissesATithiThatEndsBeforeRealSunrise() throws {
        let wrapper = SwissEphWrapper()
        let cal = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.timeZone = TimeZone(identifier: "Asia/Kolkata")
        comps.year = 2025; comps.month = 2; comps.day = 3
        let dayStart = try XCTUnwrap(cal.date(from: comps))

        let proxyJD = wrapper.getJulianDayUTC(from: dayStart.addingTimeInterval(6 * 3600))
        let sun = wrapper.calculateSunriseSunset(for: dayStart, latitude: latitude, longitude: longitude)
        let realJD = try XCTUnwrap(sun["sunriseJD"] as? Double)

        XCTAssertEqual(Int(wrapper.calculateTithiNumber(forJulianDay: proxyJD)), 20,
                       "the 06:00 proxy still reads Panchami")
        XCTAssertEqual(Int(wrapper.calculateTithiNumber(forJulianDay: realJD)), 21,
                       "real sunrise is already past it — so Panchami touches no sunrise")
    }

    /// Festivals whose dates the real-sunrise switch corrects.
    ///
    /// Each of these has a tithi that turns over between 06:00 and real
    /// sunrise, so the old proxy read the wrong day for it.
    func testRealSunriseCorrectsFestivalDates() async throws {
        let repo = EphemerisPanchaangRepository()
        try await assertFestival(repo, "Basant Panchami", on: (2025, 2, 2))
        try await assertFestival(repo, "Saraswati Puja",  on: (2025, 2, 2))
        try await assertFestival(repo, "Chhath Puja",     on: (2025, 10, 27))
    }

    /// A vriddhi Ekadashi — current at two consecutive sunrises — is kept on
    /// the second day; the first is Dashami-viddha.
    ///
    /// The scan otherwise takes the first sunrise a tithi touches, which is
    /// right for every other festival and wrong for exactly these. All four
    /// dates are the published observances.
    func testVriddhiEkadashiIsKeptOnTheSecondSunrise() async throws {
        let repo = EphemerisPanchaangRepository()
        try await assertFestival(repo, "Amalaki Ekadashi", on: (2023, 3, 3))
        try await assertFestival(repo, "Nirjala Ekadashi", on: (2024, 6, 18))
        try await assertFestival(repo, "Rama Ekadashi",    on: (2024, 10, 28))
        try await assertFestival(repo, "Vijaya Ekadashi",  on: (2027, 3, 4))
    }

    /// A kshaya Ekadashi touches no sunrise and stays on the day that held the
    /// greater part of it — it does NOT move forward like a vriddhi one.
    func testKshayaEkadashiStaysOnTheDayThatHeldIt() async throws {
        let repo = EphemerisPanchaangRepository()
        try await assertFestival(repo, "Parivartini Ekadashi", on: (2023, 9, 25))
        try await assertFestival(repo, "Yogini Ekadashi",      on: (2025, 6, 21))
    }

    /// Asserts `name` is produced exactly once in its year, on `on`.
    private func assertFestival(
        _ repo: EphemerisPanchaangRepository,
        _ name: String,
        on expected: (year: Int, month: Int, day: Int),
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let cal = Calendar(identifier: .gregorian)
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        var comps = DateComponents()
        comps.timeZone = tz
        comps.year = expected.year; comps.month = 1; comps.day = 1
        let from = try XCTUnwrap(cal.date(from: comps))
        comps.month = 12; comps.day = 31
        let to = try XCTUnwrap(cal.date(from: comps))

        let matches = try await repo.fetchFestivals(from: from, to: to)
            .filter { $0.name == name }
        XCTAssertEqual(matches.count, 1,
                       "expected one \(name) in \(expected.year)", file: file, line: line)

        let got = try XCTUnwrap(matches.first?.date, file: file, line: line)
        var c = cal; c.timeZone = tz
        let d = c.dateComponents([.year, .month, .day], from: got)
        XCTAssertEqual([d.year, d.month, d.day],
                       [expected.year, expected.month, expected.day],
                       "\(name) is on the wrong day", file: file, line: line)
    }

    /// Vakri comes from real computed motion, not a default.
    ///
    /// The three facts that must hold everywhere: the Sun and Moon are never
    /// retrograde, Rahu and Ketu always are (the mean node only moves
    /// backward, and Ketu is its opposite point), and the five star planets
    /// each turn retrograde some of the time. A flag that was silently never
    /// populated would fail the second and third of those.
    func testRetrogradeIsComputedAndBehavesAsTheBodiesDo() async throws {
        let repo = EphemerisPanchaangRepository()
        let cal = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.timeZone = TimeZone(identifier: "Asia/Kolkata")
        comps.year = 2025; comps.month = 1; comps.day = 1

        var everRetrograde = Set<Int>()
        // Every twelfth day across a year: dense enough to catch each star
        // planet's retrograde spell, the shortest of which runs about three
        // weeks.
        for step in 0..<31 {
            comps.day = 1
            let start = try XCTUnwrap(cal.date(from: comps))
            let date = try XCTUnwrap(cal.date(byAdding: .day, value: step * 12, to: start))
            let chart = await repo.fetchBirthChart(for: date, latitude: latitude, longitude: longitude)

            for planet in chart.planetPositions {
                if planet.isRetrograde { everRetrograde.insert(planet.id) }
                if planet.id == 0 || planet.id == 1 {
                    XCTAssertFalse(planet.isRetrograde,
                                   "\(planet.name) is never retrograde")
                }
                if planet.id == 7 || planet.id == 8 {
                    XCTAssertTrue(planet.isRetrograde,
                                  "\(planet.name) is always retrograde")
                }
            }
        }

        for id in 2...6 {
            XCTAssertTrue(everRetrograde.contains(id),
                          "planet \(id) should turn retrograde at some point in a year")
        }
    }
}
