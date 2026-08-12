# NityaPanchangEphemeris

A Swift Package wrapping the [Swiss Ephemeris](https://www.astro.com/swisseph/) C library
for computing Hindu Panchang (tithi, nakshatra, yoga, karana, muhurats, choghadiya, hora,
lagna), festivals, and birth charts (for Guna Milan / Kundli).

Ported out of the [NityaPanchangam](https://github.com/) iOS app so it can be reused
across projects (and, eventually, a watchOS/other Apple-platform target) via a single
Swift Package Manager dependency.

## Installation

In Xcode: **File → Add Package Dependencies…** and paste this repository's URL, or add
it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/<your-org>/NityaPanchangEphemeris.git", from: "1.0.0")
]
```

Then add `"NityaPanchangEphemeris"` to your target's dependencies.

## Usage

```swift
import NityaPanchangEphemeris

let repository: PanchaangRepository = EphemerisPanchaangRepository()

let panchang = await repository.fetchPanchang(
    for: Date(),
    latitude: 23.1765,   // Ujjain
    longitude: 75.7885
)

print(panchang.tithi.name, panchang.nakshatra.name, panchang.lunarMonth)
```

`EphemerisPanchaangRepository` is the only type you need to instantiate. Everything it
returns (`PanchangDay`, `HinduFestival`, `BirthChart`, etc.) is a plain, dependency-free
Swift value type, so it's safe to pass straight into SwiftUI views or across module
boundaries.

### Available calls

```swift
protocol PanchaangRepository: Sendable {
    func fetchPanchang(for date: Date, latitude: Double, longitude: Double) async -> PanchangDay
    func fetchMonthTithis(year: Int, month: Int, latitude: Double, longitude: Double) async -> [Int: Int]
    func fetchFestivals(from startDate: Date, to endDate: Date) async -> [HinduFestival]
    func fetchBirthChart(for date: Date, latitude: Double, longitude: Double) async -> BirthChart
}
```

## What's inside

| Layer | Contents |
|---|---|
| `CSwissEphemeris` (C target) | Astrodienst's Swiss Ephemeris core (`sweph.c`, `swecl.c`, `swemplan.c`, `swemmoon.c`, `swehouse.c`, `swejpl.c`, `swedate.c`, `swephlib.c`) — unmodified, plus the Sun/Moon compressed ephemeris data files (`sepl_18.se1`, `semo_18.se1`) bundled as package resources. |
| `NityaPanchangEphemeris` (Swift target) | An Objective-C wrapper (`SwissEphWrapper`) around the C API, `EphemerisPanchaangRepository`, the `PanchaangRepository` protocol, Panchang/festival/birth-chart value types, and `PanchaangHelper` name/lookup tables. |

All ephemeris computation runs on a dedicated serial `DispatchQueue` internally (the C
library's globals are not thread-safe), so every `PanchaangRepository` call is safe to
await concurrently from Swift.

## License

Swiss Ephemeris is dual-licensed by Astrodienst AG under the **GNU Affero General
Public License v3** or a paid **Swiss Ephemeris Professional License**
(see https://www.astro.com/swisseph/). This package bundles the AGPL-licensed source, so
the whole package — including `EphemerisPanchaangRepository` and the Swift wrapper code
in this repository — is distributed under **AGPL-3.0** (see [LICENSE](LICENSE)).

If you need to use this in a closed-source / non-AGPL app, you must purchase a Swiss
Ephemeris Professional License from Astrodienst and are responsible for complying with
its terms.
