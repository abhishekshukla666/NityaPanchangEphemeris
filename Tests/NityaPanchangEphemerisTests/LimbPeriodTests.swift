import XCTest
@testable import NityaPanchangEphemeris

/// The day's limbs as periods, beside the Udaya reading that names the day.
final class LimbPeriodTests: XCTestCase {

    private let repo = EphemerisPanchaangRepository()
    private let lat = 23.1765, lon = 75.7885     // Ujjain

    private var ist: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) async -> PanchangDay {
        await repo.fetchPanchang(for: ist.date(from: DateComponents(year: y, month: m, day: d))!,
                                 latitude: lat, longitude: lon)
    }

    /// The reason this exists. A karana lasts about eleven hours, so the sunrise
    /// reading is describing something already finished by mid-morning: on
    /// 10 Sep 2026 at Ujjain the Udaya karana Shakuni ends at 10:33 AM and two
    /// more follow it. Showing only the Udaya value left the chip wrong for most
    /// of the waking day.
    func testADayCarriesEveryKaranaThatTouchesIt() async {
        let p = await day(2026, 9, 10)
        XCTAssertEqual(p.karanas.count, 3, "expected three karanas, got \(p.karanas.map(\.name))")
        XCTAssertEqual(p.karanas.first?.name, p.karana.name, "the first must be the Udaya reading")
    }

    /// Two or three of each, never none — a limb always holds some value.
    func testEveryLimbIsCoveredEveryDay() async {
        for d in 1...20 {
            let p = await day(2026, 9, d)
            XCTAssertFalse(p.nakshatras.isEmpty, "day \(d)")
            XCTAssertFalse(p.yogas.isEmpty, "day \(d)")
            XCTAssertFalse(p.karanas.isEmpty, "day \(d)")
            XCTAssertTrue((1...4).contains(p.nakshatras.count), "day \(d): \(p.nakshatras.count)")
            XCTAssertTrue((1...4).contains(p.karanas.count), "day \(d): \(p.karanas.count)")
        }
    }

    /// The first period is the Udaya reading, which is what names the day and
    /// what every festival here is dated by. If these ever disagree the whole
    /// arrangement is wrong.
    func testTheFirstPeriodIsAlwaysTheUdayaReading() async {
        for d in 1...20 {
            let p = await day(2026, 9, d)
            XCTAssertEqual(p.nakshatras.first?.name, p.nakshatra.name, "day \(d)")
            XCTAssertEqual(p.yogas.first?.name, p.yoga.name, "day \(d)")
            XCTAssertEqual(p.karanas.first?.name, p.karana.name, "day \(d)")
        }
    }

    /// The Udaya end times must agree with the first period's, since they are
    /// the same stretch of time reached two ways.
    func testTheUdayaEndTimesMatchTheFirstPeriod() async throws {
        for d in 1...10 {
            let p = await day(2026, 9, d)
            let nakshatraPeriodEnd = try XCTUnwrap(p.nakshatras.first?.endTime)
            XCTAssertEqual(nakshatraPeriodEnd.timeIntervalSince1970,
                           p.nakshatra.endTime.timeIntervalSince1970, accuracy: 1, "day \(d)")

            let karanaPeriodEnd = try XCTUnwrap(p.karanas.first?.endTime)
            let udayaKaranaEnd = try XCTUnwrap(p.karana.endTime,
                                               "day \(d): the Udaya karana had no end time at all before this")
            XCTAssertEqual(karanaPeriodEnd.timeIntervalSince1970,
                           udayaKaranaEnd.timeIntervalSince1970, accuracy: 1, "day \(d)")
        }
    }

    /// Contiguous and in order: each begins where the last ended, so a caller
    /// can ask which one holds an instant and get exactly one answer.
    func testPeriodsAreContiguousAndCoverTheDay() async throws {
        for d in 1...15 {
            let p = await day(2026, 9, d)
            for limbs in [p.nakshatras, p.yogas, p.karanas] {
                let firstStart = try XCTUnwrap(limbs.first?.startTime)
                XCTAssertEqual(firstStart.timeIntervalSince1970,
                               p.sunrise.timeIntervalSince1970, accuracy: 1,
                               "day \(d): the day starts at sunrise")
                for (a, b) in zip(limbs, limbs.dropFirst()) {
                    XCTAssertEqual(a.endTime, b.startTime, "day \(d): a gap between periods")
                }
                XCTAssertTrue(limbs.last!.endTime > p.sunrise.addingTimeInterval(24 * 3600 - 60),
                              "day \(d): the day is not covered to the next sunrise")
            }
        }
    }

    /// Exactly one period holds any instant inside the day — which is what lets
    /// a view ask "what is running now" and get a single answer.
    func testExactlyOnePeriodHoldsAnyInstantOfTheDay() async {
        let p = await day(2026, 9, 10)
        for hour in stride(from: 7, to: 29, by: 1) {
            let instant = p.sunrise.addingTimeInterval(Double(hour - 6) * 3600)
            guard instant < p.karanas.last!.endTime else { continue }
            XCTAssertEqual(p.karanas.filter { $0.contains(instant) }.count, 1,
                           "hour \(hour): \(p.karanas.filter { $0.contains(instant) }.map(\.name))")
        }
    }

    /// Before sunrise nothing is running, matching the hora and lagna lists:
    /// the panchang day has not begun.
    func testNothingIsActiveBeforeSunrise() async {
        let p = await day(2026, 9, 10)
        let beforeSunrise = p.sunrise.addingTimeInterval(-3600)
        XCTAssertTrue(p.nakshatras.allSatisfy { !$0.contains(beforeSunrise) })
        XCTAssertTrue(p.karanas.allSatisfy { !$0.contains(beforeSunrise) })
    }
}
