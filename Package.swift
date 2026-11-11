// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Utter",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Parakeet speech recognition on the Neural Engine (Core ML), built into
        // the app so buyers don't need Python. Text normalization is turned off
        // (traits: []) because it pulls in a prebuilt binary Utter doesn't use.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7", traits: []),
    ],
    targets: [
        // Pure logic with no UI or system dependencies, so it can be checked in isolation.
        .target(
            name: "UtterCore",
            path: "Sources/UtterCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Utter",
            dependencies: ["UtterCore", .product(name: "FluidAudio", package: "FluidAudio")],
            path: "Sources/Utter",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // `swift run UtterChecks`: XCTest and swift-testing need full Xcode, so the
        // core logic is checked by a plain program instead.
        .executableTarget(
            name: "UtterChecks",
            dependencies: ["UtterCore"],
            path: "Sources/UtterChecks",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
