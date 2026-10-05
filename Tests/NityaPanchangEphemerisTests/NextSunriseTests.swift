//
//  NextSunriseTests.swift
//  NityaPanchangEphemerisTests
//
//  The end of the Vedic day, which every limb period is scoped by.
//

import XCTest
@testable import NityaPanchangEphemeris

final class NextSunriseTests: XCTestCase {

    private let repo = EphemerisPanchaangRepository()
    private let delhi = (lat: 28.61, lon: 77.21)

    private func day(_ year: Int, _ month: Int, _ d: Int) async -> PanchangDay {
        let zone = TimeZone(identifier: "Asia/Kolkata")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let date = cal.date(from: DateComponents(timeZone: zone, year: year, month: month,
                                                 day: d, hour: 9))!
        return await repo.fetchPanchang(for: date, latitude: delhi.lat, longitude: delhi.lon)
    }

    /// It is there, and it is after this day's sunrise by roughly a day.
    func testItIsAboutTwentyFourHoursAfterSunrise() async throws {
        let today = await day(2026, 6, 15)
        let next = try XCTUnwrap(today.nextSunrise)
        let gap = next.timeIntervalSince(today.sunrise) / 3600
        XCTAssertTrue((23.5 ... 24.5).contains(gap),
                      "sunrise to next sunrise was \(gap) hours")
        XCTAssertGreaterThan(next, today.sunset, "the day must end after it gets dark")
    }

    /// And it is the NEXT day's sunrise, not an approximation of it. Checked
    /// against the following day's own reading, which is the only thing that
    /// distinguishes a real value from `sunrise + 86400` — the two differ by a
    /// minute or two, which is exactly the error this field exists to avoid.
    func testItMatchesTheFollowingDaysOwnSunrise() async throws {
        let today = await day(2026, 6, 15)
        let tomorrow = await day(2026, 6, 16)
        let next = try XCTUnwrap(today.nextSunrise)
        XCTAssertEqual(next.timeIntervalSince1970,
                       tomorrow.sunrise.timeIntervalSince1970,
                       accuracy: 60,
                       "this day's end should be the next day's dawn")
    }

    /// Every limb period starts inside the day it is listed on. This is the
    /// property the field is for: the arrays are bounded by it at the START and
    /// NOT at the end, so a caller reporting a window has to clip against it.
    /// 25 February 2010 is the case that prompted the field — Pushya begins at
    /// 02:19 on the 26th, inside Thursday's day, and runs to 23:45, well past it.
    func testLimbsStartInsideTheDayButMayEndBeyondIt() async throws {
        let thursday = await day(2010, 2, 25)
        let next = try XCTUnwrap(thursday.nextSunrise)
        for limb in thursday.nakshatras {
            XCTAssertGreaterThanOrEqual(limb.startTime, thursday.sunrise,
                                        "\(limb.name) starts before the day does")
            XCTAssertLessThan(limb.startTime, next, "\(limb.name) starts after the day ends")
        }
        let pushya = thursday.nakshatras.first { $0.name == "Pushya" }
        XCTAssertNotNil(pushya, "Pushya belongs to this day — it arrives at 02:19")
        XCTAssertGreaterThan(try XCTUnwrap(pushya).endTime, next,
                             "and runs past the day's end, which is why clipping is needed")
    }
}
