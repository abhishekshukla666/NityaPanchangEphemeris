import XCTest
import SwissEphWrapper
@testable import NityaPanchangEphemeris

/// How exact the four limb end times are.
final class LimbEndPrecisionTests: XCTestCase {

    private let wrapper = SwissEphWrapper()

    private func jd(_ year: Int, _ month: Int, _ day: Int) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return wrapper.getJulianDayUTC(from: cal.date(from: DateComponents(year: year, month: month, day: day))!)
    }

    /// A reported end time must be the instant the limb actually changes: the
    /// value one second before it still holds, and one second after it does not.
    ///
    /// The searches step in fifteen-minute jumps and used to return the first
    /// sample past the crossing, so every end time the app printed ran late —
    /// 7.3 minutes on average over 240 transitions, up to 14.9. The dashboard's
    /// tithi-end capsule came from one of these.
    private func assertExact(_ label: String, from start: Double, end: Double,
                             value: (Double) -> Int, line: UInt = #line) {
        let second = 1.0 / 86400.0
        let before = value(end - second)
        let after  = value(end + second)
        XCTAssertEqual(before, value(start), "\(label): the limb had already changed before its end time", line: line)
        XCTAssertNotEqual(after, before, "\(label): the limb had not changed by its end time", line: line)
    }

    func testEveryLimbEndsExactlyWhenItSaysItDoes() {
        for day in 1...40 {
            let start = jd(2026, 9, 1) + Double(day)
            assertExact("nakshatra \(day)", from: start,
                        end: wrapper.calculateNakshatraEndTime(forJulianDay: start),
                        value: { Int(self.wrapper.calculateNakshatra(forJulianDay: $0)) })
            assertExact("yoga \(day)", from: start,
                        end: wrapper.calculateYogaEndTime(forJulianDay: start),
                        value: { Int(self.wrapper.calculateYoga(forJulianDay: $0)) })
            assertExact("karana \(day)", from: start,
                        end: wrapper.calculateKaranaEndTime(forJulianDay: start),
                        value: { Int(self.wrapper.calculateKarana(forJulianDay: $0)) })
        }
    }

    /// The tithi end travels a different path — it comes back inside
    /// calculateTithi's dictionary — so it is checked separately.
    func testTheTithiEndIsExactToo() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        for day in 1...20 {
            let date = cal.date(from: DateComponents(year: 2026, month: 9, day: day))!
            let raw = wrapper.calculateTithi(for: date, latitude: 23.1765, longitude: 75.7885)
            let start = raw["julianDay"] as! Double
            let end = raw["tithiEndJD"] as! Double
            assertExact("tithi \(day)", from: start, end: end,
                        value: { Int(self.wrapper.calculateTithiNumber(forJulianDay: $0)) })
        }
    }

    /// A crossing landing inside a minute, not merely inside the old
    /// fifteen-minute grid — the app prints these to the minute.
    func testAnEndTimeIsAccurateToTheMinute() {
        let minute = 1.0 / 1440.0
        for day in 1...20 {
            let start = jd(2026, 9, 1) + Double(day)
            let end = wrapper.calculateNakshatraEndTime(forJulianDay: start)
            let starting = Int(wrapper.calculateNakshatra(forJulianDay: start))
            XCTAssertEqual(Int(wrapper.calculateNakshatra(forJulianDay: end - minute)), starting,
                           "day \(day): still a minute of slack before the reported end")
        }
    }
}
