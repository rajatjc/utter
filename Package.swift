// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Utter",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic with no UI or system dependencies, so it can be checked in isolation.
        .target(
            name: "UtterCore",
            path: "Sources/UtterCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Utter",
            dependencies: ["UtterCore"],
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
