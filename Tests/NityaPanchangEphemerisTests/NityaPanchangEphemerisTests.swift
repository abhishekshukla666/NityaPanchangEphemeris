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
        for (_, tithi) in tithis {
            XCTAssertTrue((1...30).contains(tithi))
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
}
