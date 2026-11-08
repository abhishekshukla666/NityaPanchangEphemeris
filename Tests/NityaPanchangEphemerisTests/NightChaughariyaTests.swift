import XCTest
@testable import NityaPanchangEphemeris

/// The night's Choghadiya, against the order every panchang prints and against Drik Panchang's
/// Diwali 2026 for New Delhi.
final class NightChaughariyaTests: XCTestCase {

    private let repo = EphemerisPanchaangRepository()

    private var ist: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal
    }

    /// Sunday to Saturday night, as the standard tables give them.
    private let standard: [[String]] = [
        ["Shubh", "Amrit", "Char", "Rog", "Kaal", "Labh", "Udveg", "Shubh"],
        ["Char", "Rog", "Kaal", "Labh", "Udveg", "Shubh", "Amrit", "Char"],
        ["Kaal", "Labh", "Udveg", "Shubh", "Amrit", "Char", "Rog", "Kaal"],
        ["Udveg", "Shubh", "Amrit", "Char", "Rog", "Kaal", "Labh", "Udveg"],
        ["Amrit", "Char", "Rog", "Kaal", "Labh", "Udveg", "Shubh", "Amrit"],
        ["Rog", "Kaal", "Labh", "Udveg", "Shubh", "Amrit", "Char", "Rog"],
        ["Labh", "Udveg", "Shubh", "Amrit", "Char", "Rog", "Kaal", "Labh"],
    ]

    func testEveryNightOfTheWeekRunsInTheStandardOrder() async {
        let cal = ist
        let sunday = cal.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 12))!
        for offset in 0..<7 {
            let date = cal.date(byAdding: .day, value: offset, to: sunday)!
            let p = await repo.fetchPanchang(for: date, latitude: 23.1765, longitude: 75.7885)
            XCTAssertEqual(p.nightChaughariya.map(\.name), standard[offset], "weekday \(offset + 1)")
        }
    }

    /// Drik: Evening (Shubha, Amrita, Chara) 5:31–10:27 PM, Night (Labha) 1:43–3:22 AM,
    /// Early Morning (Shubha) 5:00–6:39 AM.
    func testDiwali2026InNewDelhiMatchesDrik() async {
        let cal = ist
        let p = await repo.fetchPanchang(for: cal.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 12))!,
                                         latitude: 28.6355, longitude: 77.2244)
        let n = p.nightChaughariya
        XCTAssertEqual(Array(n[0...2].map(\.name)), ["Shubh", "Amrit", "Char"])
        XCTAssertEqual(n[5].name, "Labh")
        XCTAssertEqual(n[7].name, "Shubh")
        func hm(_ d: Date) -> Int { cal.component(.hour, from: d) * 60 + cal.component(.minute, from: d) }
        XCTAssertEqual(Double(hm(n[2].endTime)), Double(22 * 60 + 27), accuracy: 2)
        XCTAssertEqual(Double(hm(n[5].startTime)), Double(1 * 60 + 43), accuracy: 2)
        XCTAssertEqual(Double(hm(n[7].startTime)), Double(5 * 60), accuracy: 2)
    }
}
