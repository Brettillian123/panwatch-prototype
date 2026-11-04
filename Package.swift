// swift-tools-version: 6.0
// Builds only the platform-independent detection logic in PanWatch/Core, so it can be
// compiled and unit-tested anywhere Swift runs (including Linux). The iPhone app itself
// is built from PanWatch.xcodeproj.
import PackageDescription

let package = Package(
    name: "PanWatchCore",
    targets: [
        .target(name: "PanWatchCore", path: "PanWatch/Core"),
        // Synthetic practice seen from a phone propped low on the counter, shared by the
        // tests and the replay.
        .target(name: "PanWatchSamples", dependencies: ["PanWatchCore"], path: "Tests/PanWatchSamples"),
        // Scores practice recordings from the phone: swift run PanWatchReplay <file.pwrec> [--sweep]
        .executableTarget(
            name: "PanWatchReplay",
            dependencies: ["PanWatchCore", "PanWatchSamples"],
            path: "Tests/PanWatchReplay"
        ),
        .testTarget(
            name: "PanWatchCoreTests",
            dependencies: ["PanWatchCore", "PanWatchSamples"],
            path: "Tests/PanWatchCoreTests"
        ),
    ]
)
