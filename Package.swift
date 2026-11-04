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

// Scenario suite: synthetic counter-height kitchen situations scored against the detector.
// A report, not a gate: `swift run -c release PanWatchScenarios`. Kept in one block so it
// merges cleanly with changes to the targets above.
package.targets += [
    .executableTarget(name: "PanWatchScenarios", dependencies: ["PanWatchCore"], path: "Sources/PanWatchScenarios"),
    .testTarget(
        name: "PanWatchScenariosTests",
        dependencies: ["PanWatchScenarios", "PanWatchCore"],
        path: "Tests/PanWatchScenariosTests"
    ),
]
// The runner drives the core's internal types, so a release build compiles the core testable too.
for target in package.targets where target.name == "PanWatchCore" {
    target.swiftSettings = (target.swiftSettings ?? []) + [.unsafeFlags(["-enable-testing"], .when(configuration: .release))]
}
