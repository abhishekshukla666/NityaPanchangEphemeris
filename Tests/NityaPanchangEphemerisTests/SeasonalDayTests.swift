import XCTest
@testable import NityaPanchangEphemeris

/// The season and sacred calendar a food guide reads for a day.
///
/// The boundaries are checked against the festival list's own dates rather than
/// against numbers typed in here: Chaturmas must begin on the day the calendar
/// names Devshayani Ekadashi, whatever a vriddhi or kshaya Ekadashi does to it
/// that year. The festival dates themselves are tested where they are made.
final class SeasonalDayTests: XCTestCase {

    private let repo = EphemerisPanchaangRepository()
    private let lat = 23.1765, lon = 75.7885     // Ujjain, the festival list's own reference

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func shift(_ date: Date, _ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: date)!
    }

    private func seasonal(_ date: Date, _ system: LunarMonthSystem = .purnimanta,
                          latitude: Double? = nil) async throws -> SeasonalDay {
        let day = await repo.fetchSeasonalDay(for: date, latitude: latitude ?? lat, longitude: lon, system: system)
        return try XCTUnwrap(day, "no seasonal day for \(date)")
    }

    private func festivalDate(_ name: String, in year: Int) async throws -> Date {
        let festivals = await repo.fetchFestivals(from: date(year, 1, 1), to: date(year, 12, 31))
        return try XCTUnwrap(festivals.first { $0.name == name }?.date, "\(name) not found in \(year)")
    }

    // MARK: - Ritu

    func testRituPairsTheMonthsAsCharakaDoes() {
        let expected: [Ritu] = [.vasanta, .vasanta, .grishma, .grishma, .varsha, .varsha,
                                .sharad, .sharad, .hemanta, .hemanta, .shishira, .shishira]
        XCTAssertEqual((1...12).map(Ritu.init(lunarMonth:)), expected)
        XCTAssertEqual(Ritu(lunarMonth: 13), .vasanta, "wraps like the month number does")
    }

    func testSouthOfTheEquatorTheRituIsSixMonthsOn() async throws {
        XCTAssertEqual(Ritu.allCases.map(\.southernHemisphere), [.sharad, .hemanta, .shishira, .vasanta, .grishma, .varsha])

        let north = try await seasonal(date(2026, 9, 1))
        let south = try await seasonal(date(2026, 9, 1), latitude: -lat)
        XCTAssertEqual(south.ritu, north.ritu.southernHemisphere)
        XCTAssertEqual(south.lunarMonth, north.lunarMonth, "a month is a count of moons, not shifted")
    }

    func testAmantaAndPurnimantaAgreeInShuklaAndDifferInKrishna() async throws {
        let summaries = await repo.fetchDailyPanchangSummaries(from: date(2026, 9, 1), to: date(2026, 10, 31),
                                                               latitude: lat, longitude: lon)
        XCTAssertFalse(summaries.isEmpty)
        for s in summaries where !s.isAdhikMaas && !s.isPurnimantaAdhikMaas {
            let behind = s.lunarMonth == 1 ? 12 : s.lunarMonth - 1
            XCTAssertEqual(s.amantaMonth, s.tithiNumber > 15 ? s.lunarMonth : behind,
                           "tithi \(s.tithiNumber) on \(s.date)")
        }
    }

    func testThePurnimantaRituIsThePanchangAppsAndTheAmantaRituFollowsItsOwnMonth() async throws {
        // A Krishna-paksha day across the Sharad–Hemanta turn: Purnimanta has
        // already reached Margashirsha, Amanta is still in Kartika.
        let summaries = await repo.fetchDailyPanchangSummaries(from: date(2026, 11, 1), to: date(2026, 12, 31),
                                                               latitude: lat, longitude: lon)
        let krishna = try XCTUnwrap(summaries.first { $0.lunarMonth == 9 && $0.tithiNumber <= 15 })
        let purnimanta = try await seasonal(krishna.date, .purnimanta)
        let amanta = try await seasonal(krishna.date, .amanta)
        XCTAssertEqual(purnimanta.ritu, Ritu(lunarMonth: krishna.lunarMonth), "the Panchang app's Ritu")
        XCTAssertEqual(purnimanta.ritu, .hemanta)
        XCTAssertEqual(amanta.lunarMonth, 8)
        XCTAssertEqual(amanta.ritu, .sharad)
    }

    // MARK: - Ritu Sandhi

    func testRituSandhiIsTheWeekEitherSideOfTheTurn() async throws {
        // Find the first sunrise of Purnimanta Margashirsha: the turn into Hemanta.
        let summaries = await repo.fetchDailyPanchangSummaries(from: date(2026, 11, 1), to: date(2026, 12, 31),
                                                               latitude: lat, longitude: lon)
        let turn = try XCTUnwrap(summaries.first { Ritu(lunarMonth: $0.lunarMonth) == .hemanta }?.date)

        for days in -7...6 {
            let day = try await seasonal(shift(turn, days))
            XCTAssertTrue(day.isRituSandhi, "\(days) days from the turn")
        }
        let tooEarly = try await seasonal(shift(turn, -8))
        let tooLate = try await seasonal(shift(turn, 7))
        XCTAssertFalse(tooEarly.isRituSandhi)
        XCTAssertFalse(tooLate.isRituSandhi)
        XCTAssertEqual(tooEarly.ritu, .sharad)
        XCTAssertEqual(tooLate.ritu, .hemanta)
    }

    // MARK: - Chaturmas

    func testChaturmasRunsFromDevshayaniToDevutthanaInclusive() async throws {
        let start = try await festivalDate("Devshayani Ekadashi", in: 2026)
        let end = try await festivalDate("Devutthana Ekadashi", in: 2026)
        XCTAssertLessThan(start, end)

        let dayBefore = try await seasonal(shift(start, -1))
        let first = try await seasonal(start)
        let middle = try await seasonal(date(2026, 9, 15))
        let last = try await seasonal(end)
        let dayAfter = try await seasonal(shift(end, 1))
        XCTAssertFalse(dayBefore.isChaturmas)
        XCTAssertTrue(first.isChaturmas)
        XCTAssertTrue(middle.isChaturmas)
        XCTAssertTrue(last.isChaturmas)
        XCTAssertFalse(dayAfter.isChaturmas)
    }

    func testNoChaturmasInSpring() async throws {
        let spring = try await seasonal(date(2026, 3, 20))
        XCTAssertFalse(spring.isChaturmas)
    }

    // MARK: - Vrat

    func testTheObservedEkadashiIsAVratAndTheDayBeforeIsNot() async throws {
        let ekadashi = try await festivalDate("Devutthana Ekadashi", in: 2026)
        let day = try await seasonal(ekadashi)
        let before = try await seasonal(shift(ekadashi, -1))
        XCTAssertEqual(day.vrat, .ekadashi)
        XCTAssertNil(before.vrat)
    }

    func testSharadNavratriRunsToMahaNavami() async throws {
        let first = try await festivalDate("Navratri", in: 2026)
        let navami = try await festivalDate("Maha Navami", in: 2026)
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: first),
                                                   to: Calendar.current.startOfDay(for: navami)).day!
        XCTAssertTrue((7...9).contains(days), "a Navratri is eight to ten days, got \(days + 1)")

        for d in 0...days {
            let day = try await seasonal(shift(first, d))
            XCTAssertEqual(day.vrat, .navratri, "day \(d + 1)")
        }
        let before = try await seasonal(shift(first, -1))
        let dussehra = try await seasonal(shift(navami, 1))
        XCTAssertNil(before.vrat)
        XCTAssertNil(dussehra.vrat)
    }

    func testChaitraNavratriToo() async throws {
        let first = try await festivalDate("Navratri (Chaitra)", in: 2026)
        let day = try await seasonal(shift(first, 2))
        XCTAssertEqual(day.vrat, .navratri)
        XCTAssertEqual(day.ritu, .vasanta)
    }

    // MARK: - No answer

    func testARepositoryWithoutSummariesGivesNoSeasonalDay() async {
        struct Silent: PanchaangRepository {
            func fetchPanchang(for date: Date, latitude: Double, longitude: Double) async -> PanchangDay { fatalError() }
            func fetchMonthTithis(year: Int, month: Int, latitude: Double, longitude: Double) async -> [Int: MonthDayTithis] { [:] }
            func fetchFestivals(from startDate: Date, to endDate: Date) async -> [HinduFestival] { [] }
            func fetchBirthChart(for date: Date, latitude: Double, longitude: Double) async -> BirthChart { fatalError() }
            func fetchGrahans(from startDate: Date, to endDate: Date, latitude: Double, longitude: Double) async -> [Grahan] { [] }
        }
        let day = await Silent().fetchSeasonalDay(for: date(2026, 9, 1), latitude: lat, longitude: lon, system: .amanta)
        XCTAssertNil(day)
    }
}
