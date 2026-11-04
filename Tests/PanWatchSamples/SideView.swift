import Foundation
@testable import PanWatchCore

/// Pictures of the pan box, 32 x 32, as a phone propped low on the counter sees it: no
/// stand, looking across at the side of the pot, not down into it. The box covers the pot
/// and the space just above its rim, where steam rises and the cook's body moves.
enum SideView {
    static let side = 32
    /// Rows above this are the space above the rim; the rest is the side of the pot.
    static let rim = 12
    static let pot = PanPatch(width: side, height: side, luma: 70)
        .filling(x: 0..<side, y: 0..<rim, luma: 150)

    /// Steam above the rim: a few bright specks that move every frame.
    static func steam(_ frame: Int, over base: PanPatch = pot) -> PanPatch {
        var copy = base
        for y in 0..<rim {
            for x in 0..<side where (x * 7 + y * 3 + frame * 5) % 13 == 0 {
                copy.luma[y * side + x] = 230
            }
        }
        return copy
    }

    /// Pasta ends sticking up out of the pot, the only part of a pour this view still sees.
    static let somePasta = pot.paintingPasta(columns: [4, 12])
    /// `somePasta` and a second handful.
    static let morePasta = somePasta.paintingPasta(columns: [20, 26])

    /// An arm and a bag reaching over the rim: a large block that shifts every frame.
    static func arm(_ frame: Int, over base: PanPatch = pot) -> PanPatch {
        let left = (frame % 4) * 4
        return base.filling(x: left..<(left + 14), y: 0..<(rim + 6), luma: 200)
    }

    /// The whole box brighter, as when the hood light switches on.
    static func brighter(_ base: PanPatch) -> PanPatch {
        var copy = base
        copy.luma = copy.luma.map { UInt8(min(255, Int($0) + 50)) }
        return copy
    }

    /// The cook leaning in: a dark body over the space above the rim and the top of the pot.
    static let cookLeaningIn = pot.filling(x: 0..<side, y: 0..<(rim + 8), luma: 40)
    /// Foam on the water after stirring, along the rim.
    static let foam = pot.filling(x: 0..<side, y: rim..<(rim + 4), luma: 200)
}

extension PanPatch {
    func filling(x: Range<Int>, y: Range<Int>, luma newLuma: UInt8, cb newCb: UInt8 = 128, cr newCr: UInt8 = 128) -> PanPatch {
        var copy = self
        for row in y where row >= 0 && row < height {
            for column in x where column >= 0 && column < width {
                let index = row * width + column
                copy.luma[index] = newLuma
                copy.cb[index] = newCb
                copy.cr[index] = newCr
            }
        }
        return copy
    }

    /// Pale pasta ends, four pixels wide, rising above the rim at each column.
    func paintingPasta(columns: [Int]) -> PanPatch {
        columns.reduce(self) { $0.filling(x: $1..<($1 + 4), y: (SideView.rim - 6)..<(SideView.rim + 2), luma: 210, cb: 100, cr: 150) }
    }
}

/// Steps from the garlic butter pasta.
enum Watches {
    static let pasta = AdditionWatch(ingredient: "pasta", timerLabel: "Pasta", timerMinutes: 9, minimumChange: 0.02, countsRelease: true)
    static let garlic = AdditionWatch(ingredient: "garlic", timerLabel: "Garlic", timerMinutes: 1, minimumChange: 0)
}

/// Hands as Vision reads them.
enum Hands {
    /// A hand centered on `center`, with the named joints spread around it.
    static func reading(at center: NormPoint, confidence: Double, joints: [HandReading.JointName], jointConfidence: Double = 0.9) -> HandReading {
        HandReading(confidence: confidence, joints: joints.enumerated().map { index, name in
            let angle = Double(index) * 0.9
            let point = NormPoint(x: center.x + 0.03 * cos(angle), y: center.y + 0.03 * sin(angle))
            return HandReading.Joint(name: name, point: point, confidence: jointConfidence)
        })
    }

    /// A hand in plain view: every joint.
    static let open = HandReading.JointName.allCases
    /// A hand gripping a bag: a few knuckles, no wrist, no fingertips.
    static let gripping: [HandReading.JointName] = [.indexMCP, .middleMCP, .ringMCP, .thumbIP, .thumbTip]
}

/// A practice session recorded from a low counter angle, 28 seconds at 15 frames a second,
/// on the pasta step: a bag pour whose hand Vision barely trusts, a handful from a hand
/// that hides its wrist, and a hand reaching past. The cook said "that was it" after
/// both adds; the phone itself offered only for the second.
enum SamplePractice {
    static let region = NormRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
    static let markers = [108.5, 117.0]

    static func recording() -> PracticeRecording {
        var recording = PracticeRecording()
        recording.notes = "Synthetic practice, low counter angle"
        recording.tunings = [PracticeRecording.Tuning(time: 100, settings: DetectorSettings())]
        var time = 100.0
        var frame = 0
        func hold(_ seconds: Double, hand: (Int) -> HandReading? = { _ in nil }, patch: (Int) -> PanPatch) {
            for index in 0..<Int((seconds * 15).rounded()) {
                recording.frames.append(PracticeRecording.Frame(
                    time: time, frameWidth: 1920, frameHeight: 1080, stepIndex: 1,
                    watch: PracticeRecording.StepWatch(Watches.pasta), armed: true,
                    hands: hand(index).map { [$0] } ?? [], region: region, patch: patch(index)
                ))
                time += 1.0 / 15
                frame += 1
            }
        }
        func moving(_ index: Int) -> NormPoint { NormPoint(x: 0.4 + 0.006 * Double(index), y: 0.32) }

        hold(5) { _ in SideView.steam(frame) }
        // The bag pour: Vision is only 45% sure of the hand.
        hold(2, hand: { Hands.reading(at: moving($0), confidence: 0.45, joints: Hands.open) }) { SideView.arm($0) }
        hold(7) { _ in SideView.steam(frame, over: SideView.somePasta) }
        // A handful: Vision is sure of the hand but sees no wrist.
        hold(1.5, hand: { Hands.reading(at: moving($0), confidence: 0.7, joints: Hands.gripping) }) {
            SideView.arm($0, over: SideView.somePasta)
        }
        hold(8.5) { _ in SideView.steam(frame, over: SideView.morePasta) }
        // Reaching past: a clear hand, there for a moment.
        hold(0.2, hand: { Hands.reading(at: moving($0), confidence: 0.9, joints: Hands.open) }) {
            SideView.arm($0, over: SideView.morePasta)
        }
        hold(3.8) { _ in SideView.steam(frame, over: SideView.morePasta) }

        recording.markers = markers
        recording.verdicts = [PracticeRecording.Verdict(time: 119.0, outcome: .addition, stepIndex: 1)]
        return recording
    }

    /// `recording()` as the phone writes it.
    static func data() -> Data {
        let recording = recording()
        var data = PracticeRecording.header(notes: recording.notes)
        data.append(PracticeRecording.encode(recording.tunings[0]))
        var markers = recording.markers[...]
        for frame in recording.frames {
            data.append(PracticeRecording.encode(frame))
            while let marker = markers.first, marker <= frame.time {
                data.append(PracticeRecording.encodeMarker(at: marker))
                markers.removeFirst()
            }
            for verdict in recording.verdicts where abs(verdict.time - frame.time) < 0.5 / 15 {
                data.append(PracticeRecording.encode(verdict))
            }
        }
        return data
    }
}
