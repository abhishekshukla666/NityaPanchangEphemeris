import XCTest
@testable import NityaPanchangEphemeris

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
}
