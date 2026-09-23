// swift-tools-version: 6.0
// Builds only the platform-independent detection logic in PanWatch/Core, so it can be
// compiled and unit-tested anywhere Swift runs (including Linux). The iPhone app itself
// is built from PanWatch.xcodeproj.
import PackageDescription

let package = Package(
    name: "PanWatchCore",
    targets: [
        .target(name: "PanWatchCore", path: "PanWatch/Core"),
        .testTarget(
            name: "PanWatchCoreTests",
            dependencies: ["PanWatchCore"],
            path: "Tests/PanWatchCoreTests"
        ),
    ]
)
