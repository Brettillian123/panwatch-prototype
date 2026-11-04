import Foundation

/// A practice session recorded on the phone: what the camera's analysis saw on every
/// analyzed frame, when the cook said "that was it", and what the app decided. No video
/// and no audio: hand joints, a small picture of the pan box, and a few numbers.
///
/// The file starts with `magic`, then holds records. Each is one type byte and its
/// payload, little-endian:
/// - 1 notes: UInt32 length, UTF-8 text.
/// - 2 tuning: Float64 time, UInt32 length, the base `DetectorSettings` as JSON.
/// - 3 frame: see `encode(_:)`.
/// - 4 marker: Float64 time.
/// - 5 verdict: Float64 time, UInt8 outcome, UInt8 step.
struct PracticeRecording: Equatable, Sendable {
    static let magic = Data("PANWATCH-PRACTICE 1\n".utf8)
    /// The pan box picture is kept at most this many pixels on its long side, with color
    /// at half that, so ten minutes stays near 45 MB.
    static let patchSide = 64

    /// The parts of a step's `AdditionWatch` that change the tuning.
    struct StepWatch: Equatable, Sendable {
        var minimumChange: Double?
        var countsRelease: Bool

        init(minimumChange: Double?, countsRelease: Bool) {
            self.minimumChange = minimumChange
            self.countsRelease = countsRelease
        }

        init(_ watch: AdditionWatch) {
            self.init(minimumChange: watch.minimumChange, countsRelease: watch.countsRelease)
        }

        var watch: AdditionWatch {
            AdditionWatch(ingredient: "", timerLabel: "", timerMinutes: 0, minimumChange: minimumChange, countsRelease: countsRelease)
        }
    }

    /// One analyzed frame.
    struct Frame: Equatable, Sendable {
        /// Capture time in seconds, on the same clock as markers and verdicts.
        var time: Double
        var frameWidth: Int
        var frameHeight: Int
        var stepIndex: Int
        /// Nil on steps the camera doesn't watch.
        var watch: StepWatch?
        /// Whether the app's detector was armed.
        var armed: Bool
        /// Every hand Vision reported, counted or not.
        var hands: [HandReading]
        var region: NormRect?
        /// The pan box, at most `patchSide` on its long side.
        var patch: PanPatch?
    }

    /// One of the app's own decisions.
    struct Verdict: Equatable, Sendable {
        var time: Double
        var outcome: DetectorDecision.Outcome
        var stepIndex: Int
    }

    /// The base tuning in force from `time` on.
    struct Tuning: Equatable, Sendable {
        var time: Double
        var settings: DetectorSettings
    }

    enum ReadError: Error, Equatable {
        case notARecording
        case unknownRecord(UInt8)
    }

    var notes = ""
    var frames: [Frame] = []
    /// Times the cook said "that was it".
    var markers: [Double] = []
    var verdicts: [Verdict] = []
    var tunings: [Tuning] = []

    /// Seconds from the first frame to the last.
    var duration: Double { (frames.last?.time ?? 0) - (frames.first?.time ?? 0) }

    // MARK: Reading

    /// Reads a whole file. A record cut off at the end, as when the app was closed while
    /// writing, is dropped and everything before it kept.
    init(data: Data) throws {
        guard data.starts(with: Self.magic) else { throw ReadError.notARecording }
        var reader = ByteReader(bytes: [UInt8](data.dropFirst(Self.magic.count)))
        while !reader.atEnd {
            let start = reader.offset
            do {
                try readRecord(&reader)
            } catch ByteReader.Truncated.truncated {
                reader.offset = start
                break
            }
        }
    }

    init() {}

    private mutating func readRecord(_ reader: inout ByteReader) throws {
        let type = try reader.u8()
        switch type {
        case 1:
            let length = Int(try reader.u32())
            notes += String(decoding: try reader.bytes(length), as: UTF8.self)
        case 2:
            let time = try reader.f64()
            let length = Int(try reader.u32())
            let json = Data(try reader.bytes(length))
            if let settings = try? JSONDecoder().decode(DetectorSettings.self, from: json) {
                tunings.append(Tuning(time: time, settings: settings))
            }
        case 3:
            frames.append(try Self.readFrame(&reader))
        case 4:
            markers.append(try reader.f64())
        case 5:
            let time = try reader.f64()
            let outcome = Self.outcomes[Int(try reader.u8())] ?? .noChange
            verdicts.append(Verdict(time: time, outcome: outcome, stepIndex: Int(try reader.u8())))
        default:
            throw ReadError.unknownRecord(type)
        }
    }

    private static let outcomes: [Int: DetectorDecision.Outcome] = [0: .addition, 1: .noChange, 2: .lightingChange, 3: .stirring]

    private static func code(_ outcome: DetectorDecision.Outcome) -> UInt8 {
        UInt8(outcomes.first { $0.value == outcome }?.key ?? 1)
    }

    private static func readFrame(_ reader: inout ByteReader) throws -> Frame {
        let time = try reader.f64()
        let width = Int(try reader.u16())
        let height = Int(try reader.u16())
        let step = Int(try reader.u8())
        let flags = try reader.u8()
        let minimumChange = try reader.f64()
        var hands: [HandReading] = []
        for _ in 0..<Int(try reader.u8()) {
            let confidence = Double(try reader.u8()) / 255
            var joints: [HandReading.Joint] = []
            for _ in 0..<Int(try reader.u8()) {
                let name = HandReading.JointName(rawValue: try reader.u8()) ?? .wrist
                let x = Double(try reader.u16()) / 65535
                let y = Double(try reader.u16()) / 65535
                joints.append(HandReading.Joint(name: name, point: NormPoint(x: x, y: y), confidence: Double(try reader.u8()) / 255))
            }
            hands.append(HandReading(confidence: confidence, joints: joints))
        }
        var region: NormRect?
        var patch: PanPatch?
        if flags & 16 != 0 {
            region = NormRect(
                x: Double(try reader.f32()), y: Double(try reader.f32()),
                width: Double(try reader.f32()), height: Double(try reader.f32())
            )
            let w = Int(try reader.u8())
            let h = Int(try reader.u8())
            let luma = try reader.bytes(w * h)
            let (cw, ch) = ((w + 1) / 2, (h + 1) / 2)
            let cb = try reader.bytes(cw * ch)
            let cr = try reader.bytes(cw * ch)
            // Color was kept at half size; each value covers a 2 x 2 block.
            func full(_ half: [UInt8]) -> [UInt8] {
                (0..<(w * h)).map { half[($0 / w) / 2 * cw + ($0 % w) / 2] }
            }
            patch = PanPatch(width: w, height: h, luma: luma, cb: full(cb), cr: full(cr))
        }
        let watch = flags & 2 == 0 ? nil : StepWatch(
            minimumChange: flags & 8 == 0 ? nil : minimumChange,
            countsRelease: flags & 4 != 0
        )
        return Frame(
            time: time, frameWidth: width, frameHeight: height, stepIndex: step, watch: watch,
            armed: flags & 1 != 0, hands: hands, region: region, patch: patch
        )
    }

    // MARK: Writing

    /// The bytes that start a file.
    static func header(notes: String) -> Data {
        var writer = ByteWriter()
        writer.bytes([UInt8](magic))
        let text = [UInt8](notes.utf8)
        writer.u8(1)
        writer.u32(UInt32(text.count))
        writer.bytes(text)
        return writer.data
    }

    static func encode(_ tuning: Tuning) -> Data {
        var writer = ByteWriter()
        let json = [UInt8]((try? JSONEncoder().encode(tuning.settings)) ?? Data())
        writer.u8(2)
        writer.f64(tuning.time)
        writer.u32(UInt32(json.count))
        writer.bytes(json)
        return writer.data
    }

    static func encodeMarker(at time: Double) -> Data {
        var writer = ByteWriter()
        writer.u8(4)
        writer.f64(time)
        return writer.data
    }

    static func encode(_ verdict: Verdict) -> Data {
        var writer = ByteWriter()
        writer.u8(5)
        writer.f64(verdict.time)
        writer.u8(code(verdict.outcome))
        writer.u8(UInt8(clamping: verdict.stepIndex))
        return writer.data
    }

    /// A frame record: Float64 time; UInt16 frame width and height; UInt8 step; UInt8 flags
    /// (1 armed, 2 watched, 4 counts release, 8 has minimum change, 16 has pan box); Float64
    /// minimum change; UInt8 hand count, and per hand UInt8 confidence, UInt8 joint count,
    /// and per joint UInt8 name, UInt16 x, UInt16 y, UInt8 confidence. With a pan box:
    /// Float32 x, y, width, height; UInt8 picture width and height; brightness; then Cb and
    /// Cr at half size. The picture is shrunk to `patchSide` here.
    static func encode(_ frame: Frame) -> Data {
        var writer = ByteWriter()
        writer.u8(3)
        writer.f64(frame.time)
        writer.u16(UInt16(clamping: frame.frameWidth))
        writer.u16(UInt16(clamping: frame.frameHeight))
        writer.u8(UInt8(clamping: frame.stepIndex))
        let patch = frame.region == nil ? nil : frame.patch?.downscaled(longSide: patchSide)
        var flags: UInt8 = frame.armed ? 1 : 0
        if let watch = frame.watch {
            flags |= 2
            if watch.countsRelease { flags |= 4 }
            if watch.minimumChange != nil { flags |= 8 }
        }
        if patch != nil { flags |= 16 }
        writer.u8(flags)
        writer.f64(frame.watch?.minimumChange ?? 0)
        let hands = frame.hands.prefix(255)
        writer.u8(UInt8(hands.count))
        func unit(_ value: Double, _ scale: Double) -> Double { (min(max(value, 0), 1) * scale).rounded() }
        for hand in hands {
            writer.u8(UInt8(unit(hand.confidence, 255)))
            let joints = hand.joints.prefix(255)
            writer.u8(UInt8(joints.count))
            for joint in joints {
                writer.u8(joint.name.rawValue)
                writer.u16(UInt16(unit(joint.point.x, 65535)))
                writer.u16(UInt16(unit(joint.point.y, 65535)))
                writer.u8(UInt8(unit(joint.confidence, 255)))
            }
        }
        if let region = frame.region, let patch {
            for value in [region.x, region.y, region.width, region.height] { writer.f32(Float(value)) }
            writer.u8(UInt8(patch.width))
            writer.u8(UInt8(patch.height))
            writer.bytes(patch.luma)
            writer.bytes(Self.half(patch.cb, width: patch.width, height: patch.height))
            writer.bytes(Self.half(patch.cr, width: patch.width, height: patch.height))
        }
        return writer.data
    }

    /// Averages each 2 x 2 block of a plane.
    private static func half(_ plane: [UInt8], width: Int, height: Int) -> [UInt8] {
        let (cw, ch) = ((width + 1) / 2, (height + 1) / 2)
        var result = [UInt8](repeating: 0, count: cw * ch)
        for row in 0..<ch {
            for column in 0..<cw {
                var sum = 0
                var count = 0
                for y in (row * 2)..<min(row * 2 + 2, height) {
                    for x in (column * 2)..<min(column * 2 + 2, width) {
                        sum += Int(plane[y * width + x])
                        count += 1
                    }
                }
                result[row * cw + column] = UInt8((sum + count / 2) / count)
            }
        }
        return result
    }
}

extension PanPatch {
    /// This picture shrunk so its long side is at most `longSide`, each new pixel the
    /// average of the ones it covers. Already small enough, it comes back unchanged.
    func downscaled(longSide: Int) -> PanPatch {
        let long = max(width, height)
        guard long > longSide, longSide > 0 else { return self }
        let w = max(1, width * longSide / long)
        let h = max(1, height * longSide / long)
        func shrink(_ plane: [UInt8]) -> [UInt8] {
            var result = [UInt8](repeating: 0, count: w * h)
            for row in 0..<h {
                let y0 = row * height / h
                let y1 = max(y0 + 1, (row + 1) * height / h)
                for column in 0..<w {
                    let x0 = column * width / w
                    let x1 = max(x0 + 1, (column + 1) * width / w)
                    var sum = 0
                    for y in y0..<y1 {
                        for x in x0..<x1 { sum += Int(plane[y * width + x]) }
                    }
                    let count = (y1 - y0) * (x1 - x0)
                    result[row * w + column] = UInt8((sum + count / 2) / count)
                }
            }
            return result
        }
        return PanPatch(width: w, height: h, luma: shrink(luma), cb: shrink(cb), cr: shrink(cr))
    }
}

private struct ByteWriter {
    var data = Data()

    mutating func u8(_ value: UInt8) { data.append(value) }
    mutating func u16(_ value: UInt16) { little(UInt64(value), bytes: 2) }
    mutating func u32(_ value: UInt32) { little(UInt64(value), bytes: 4) }
    mutating func f32(_ value: Float) { u32(value.bitPattern) }
    mutating func f64(_ value: Double) { little(value.bitPattern, bytes: 8) }
    mutating func bytes(_ values: [UInt8]) { data.append(contentsOf: values) }

    private mutating func little(_ value: UInt64, bytes count: Int) {
        for index in 0..<count { data.append(UInt8(truncatingIfNeeded: value >> (8 * UInt64(index)))) }
    }
}

private struct ByteReader {
    enum Truncated: Error { case truncated }

    let bytes: [UInt8]
    var offset = 0
    var atEnd: Bool { offset >= bytes.count }

    mutating func u8() throws -> UInt8 { UInt8(try little(1)) }
    mutating func u16() throws -> UInt16 { UInt16(try little(2)) }
    mutating func u32() throws -> UInt32 { UInt32(try little(4)) }
    mutating func f32() throws -> Float { Float(bitPattern: try u32()) }
    mutating func f64() throws -> Double { Double(bitPattern: try little(8)) }

    mutating func bytes(_ count: Int) throws -> [UInt8] {
        guard count >= 0, offset + count <= bytes.count else { throw Truncated.truncated }
        defer { offset += count }
        return Array(bytes[offset..<(offset + count)])
    }

    private mutating func little(_ count: Int) throws -> UInt64 {
        try bytes(count).enumerated().reduce(0) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) }
    }
}
