// swift-tools-version: 6.0
// Makes the recorded previews bundled in the app (PanWatch/Resources/VoicePreviews), one
// per catalogue voice, with the same FluidAudio Kokoro runtime the app speaks with. Not
// part of the app or of `swift test`; run on a Mac when the catalogue changes:
//   swift run -c release VoicePreviews <out folder> "<line>" af_heart af_bella ...
// It writes <pack>.wav (24 kHz mono) and prints each file's length and peak level; the
// voice-previews workflow converts them to AAC .m4a with afconvert.
import PackageDescription

let package = Package(
    name: "VoicePreviews",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.3"),
    ],
    targets: [
        .executableTarget(
            name: "VoicePreviews",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            path: "Sources"
        ),
    ]
)
