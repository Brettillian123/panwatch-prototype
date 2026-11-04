// Scores practice recordings from the phone: runs each through the detector with the
// given tuning and counts offers against the cook's "that was it" markers.
//
//   swift run PanWatchReplay <recording.pwrec>... [--sweep] [--set name=value]...
//   swift run PanWatchReplay --demo <path>     writes a synthetic low-counter-angle recording
//
// --set changes a DetectorSettings field by name, like --set handConfidence=0.4.
// --sweep also tries a few variations of that tuning.
import Foundation
@testable import PanWatchCore
@testable import PanWatchSamples

/// Variations tried by --sweep, each a few settings changed by name.
let sweep: [(name: String, changes: [String: String])] = [
    ("before this round", ["countVisibleChange": "false", "holdingHandConfidence": "2"]),
    ("no holding hands", ["holdingHandConfidence": "2"]),
    ("no change alone", ["countVisibleChange": "false"]),
    ("hand sure 0.4", ["handConfidence": "0.4"]),
    ("hand sure 0.6", ["handConfidence": "0.6"]),
    ("holding sure 0.5", ["holdingHandConfidence": "0.5"]),
    ("change x1.5", ["visibleChangeFactor": "1.5"]),
    ("change x3", ["visibleChangeFactor": "3"]),
    ("hold 1 s", ["visibleChangeHold": "1"]),
    ("hold 2.5 s", ["visibleChangeHold": "2.5"]),
    ("no lighting veto", ["lightingVeto": "false"]),
    ("settle 1 s", ["settleHold": "1"]),
]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

var arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "--demo" {
    guard arguments.count == 2 else { fail("usage: PanWatchReplay --demo <path>") }
    do {
        try SamplePractice.data().write(to: URL(fileURLWithPath: arguments[1]))
    } catch {
        fail("couldn't write \(arguments[1]): \(error)")
    }
    print("Wrote a synthetic recording to \(arguments[1])")
    exit(0)
}

var paths: [String] = []
var base = DetectorSettings()
var changed: [String] = []
var sweeping = false
while !arguments.isEmpty {
    let argument = arguments.removeFirst()
    switch argument {
    case "--sweep":
        sweeping = true
    case "--set":
        guard !arguments.isEmpty else { fail("--set needs name=value") }
        let pair = arguments.removeFirst().split(separator: "=", maxSplits: 1).map(String.init)
        guard pair.count == 2, let next = PracticeReplay.setting(pair[0], to: pair[1], in: base) else {
            fail("no setting matches \(pair.joined(separator: "="))")
        }
        base = next
        changed.append(pair.joined(separator: "="))
    default:
        paths.append(argument)
    }
}
guard !paths.isEmpty else {
    fail("usage: PanWatchReplay <recording.pwrec>... [--sweep] [--set name=value]...   or   --demo <path>")
}

var variants: [(name: String, settings: DetectorSettings)] = [(changed.isEmpty ? "default" : changed.joined(separator: " "), base)]
if sweeping {
    for variation in sweep {
        let settings = variation.changes.reduce(base) { PracticeReplay.setting($1.key, to: $1.value, in: $0) ?? $0 }
        variants.append((variation.name, settings))
    }
}

func row(_ cells: [String]) -> String {
    let widths = [26, 22, 4, 4, 5, 5]
    return zip(cells, widths).map { $0.padding(toLength: $1, withPad: " ", startingAt: 0) }.joined(separator: " ")
}

print(row(["recording", "settings", "TP", "FP", "miss", "F1"]))
var totals: [String: (tp: Int, fp: Int, miss: Int)] = [:]
for path in paths {
    let recording: PracticeRecording
    do {
        recording = try PracticeRecording(data: Data(contentsOf: URL(fileURLWithPath: path)))
    } catch {
        fail("couldn't read \(path): \(error)")
    }
    let name = URL(fileURLWithPath: path).lastPathComponent
    let rows = [("phone, live", PracticeReplay.liveScore(recording))]
        + variants.map { ($0.name, PracticeReplay.score(recording, settings: $0.settings)) }
    for (label, score) in rows {
        print(row([name, label, "\(score.truePositives)", "\(score.falsePositives)", "\(score.misses)", String(format: "%.2f", score.f1)]))
        let total = totals[label] ?? (0, 0, 0)
        totals[label] = (total.tp + score.truePositives, total.fp + score.falsePositives, total.miss + score.misses)
    }
    print(String(format: "  %.0f s, %d frames, %d markers. ", recording.duration, recording.frames.count, recording.markers.count) + recording.notes)
}
if paths.count > 1 {
    for label in ["phone, live"] + variants.map(\.name) {
        guard let total = totals[label] else { continue }
        let score = DetectionScore(truePositives: total.tp, falsePositives: total.fp, misses: total.miss)
        print(row(["all", label, "\(total.tp)", "\(total.fp)", "\(total.miss)", String(format: "%.2f", score.f1)]))
    }
}
