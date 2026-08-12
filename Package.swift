// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NityaPanchangEphemeris",
    platforms: [
        .iOS(.v16),
        .watchOS(.v9),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "NityaPanchangEphemeris",
            targets: ["NityaPanchangEphemeris"]
        )
    ],
    targets: [
        // The Swiss Ephemeris C library (Astrodienst), unmodified computation core.
        .target(
            name: "CSwissEphemeris",
            path: "Sources/CSwissEphemeris",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include")
            ]
        ),
        // Objective-C wrapper around the C API (SwissEphWrapper).
        .target(
            name: "SwissEphWrapper",
            dependencies: ["CSwissEphemeris"],
            path: "Sources/SwissEphWrapper",
            publicHeadersPath: "include"
        ),
        // Public Swift API: Panchang models, repository, helpers.
        .target(
            name: "NityaPanchangEphemeris",
            dependencies: ["SwissEphWrapper", "CSwissEphemeris"],
            path: "Sources/NityaPanchangEphemeris",
            resources: [
                .copy("Resources/EphemerisData")
            ]
        ),
        .testTarget(
            name: "NityaPanchangEphemerisTests",
            dependencies: ["NityaPanchangEphemeris"],
            path: "Tests/NityaPanchangEphemerisTests"
        )
    ]
)
