import CoreImage
import CoreVideo
import Foundation
#if compiler(>=6.4) && canImport(FoundationModels)
import FoundationModels
#endif

// AI confirm: the app's half of "rules propose, on-device AI confirms". The looser rules in
// `PanWatcher` propose candidates; this keeps a few cropped frames of each hand visit, asks
// Apple's on-device model whether a hand is adding food, and offers only on a confident yes.
// A timeout or an error falls back to today's rules. Nothing is saved or leaves the phone.

/// One on-device check, for the debug panel. Only small thumbnails stay after the decision.
struct AICheckRecord: Identifiable, @unchecked Sendable {
    let id: Int
    let thumbnails: [CGImage]
    let resolution: AddConfirmGate.Resolution
    let verdict: AddVerdict?
    let milliseconds: Int?
    let offered: Bool
    /// Later candidates that joined this check.
    let joined: Int

    var answer: String {
        switch resolution {
        case .confirmed, .declined, .unsure:
            guard let verdict else { return resolution.rawValue }
            let food = verdict.food.isEmpty ? "" : ": \(verdict.food)"
            return (verdict.adding ? "Yes" + food : "No") + String(format: " (%.0f%% sure)", verdict.confidence * 100)
        case .timedOut: return "No answer in 3 s; the rules decided"
        case .failed: return "The model failed; the rules decided"
        case .stale: return "Step changed; answer dropped"
        }
    }
}

/// The on-device model: Apple's Foundation Models with image input, iOS 27 and later.
enum AddModel {
    /// Whether this build has the check at all. It needs the iOS 27 SDK (Xcode 27).
    static var isBuilt: Bool {
        #if compiler(>=6.4) && canImport(FoundationModels)
        return true
        #else
        return false
        #endif
    }

    /// Whether the check can run now: iOS 27 and Apple's on-device model ready.
    static var isAvailable: Bool {
        #if compiler(>=6.4) && canImport(FoundationModels)
        if #available(iOS 27.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// For the debug panel.
    static var status: String {
        if !isBuilt { return "Off: this build has no AI check (needs Xcode 27)" }
        return isAvailable ? "On: Apple's on-device model confirms each add" : "Off: needs iOS 27 and Apple Intelligence ready"
    }

    /// Asks the model about `frames`, giving up after `timeout` seconds.
    static func ask(frames: [CGImage], context: String, timeout: Double) async -> AddConfirmGate.Reply {
        let race = ReplyRace()
        let images = Frames(images: frames)
        return await withCheckedContinuation { continuation in
            race.start(continuation)
            let work = Task.detached(priority: .userInitiated) {
                race.finish(await AddModel.reply(images, context))
            }
            Task.detached {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if race.finish(.timedOut) { work.cancel() }
            }
        }
    }

    private static func reply(_ frames: Frames, _ context: String) async -> AddConfirmGate.Reply {
        #if compiler(>=6.4) && canImport(FoundationModels)
        if #available(iOS 27.0, *) {
            do {
                return .verdict(try await verify(frames.images, context))
            } catch {
                return .failed
            }
        }
        #endif
        return .failed
    }
}

/// Crops handed to a background task.
private struct Frames: @unchecked Sendable {
    let images: [CGImage]
}

/// The first of the model's reply and the timeout wins.
private final class ReplyRace: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<AddConfirmGate.Reply, Never>?

    func start(_ continuation: CheckedContinuation<AddConfirmGate.Reply, Never>) {
        lock.withLock { self.continuation = continuation }
    }

    /// True when this reply won.
    @discardableResult
    func finish(_ reply: AddConfirmGate.Reply) -> Bool {
        let waiting: CheckedContinuation<AddConfirmGate.Reply, Never>? = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        waiting?.resume(returning: reply)
        return waiting != nil
    }
}

#if compiler(>=6.4) && canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct AddAnswer {
    @Guide(description: "True only if a hand is putting food or an ingredient into the pot in these frames.")
    var handAddingFood: Bool
    @Guide(description: "What is going into the pot, in a few words. Empty if nothing is.")
    var food: String
    @Guide(description: "How sure you are, from 0 to 100.", .range(0...100))
    var confidence: Int
}

@available(iOS 27.0, *)
extension AddModel {
    static let instructions = """
        You watch a cooking pot through a phone propped on the kitchen counter, level with the stove. \
        You get a few frames in time order: a hand arriving over the pot, the moment it opened or was \
        lowest, the hand leaving, and the pot after. Say whether a hand put food or an ingredient into \
        the pot. Wiping the stove, tasting, stirring, putting on or lifting a lid, moving the pot, or a \
        hand feeling the heat is not adding. Food often sinks out of sight, so look for it in the hand \
        or falling.
        """

    /// One structured question about the frames, on the on-device model. Nothing leaves the phone.
    static func verify(_ frames: [CGImage], _ context: String) async throws -> AddVerdict {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(generating: AddAnswer.self) {
            context
            "The frames, in order:"
            for frame in frames {
                Attachment(frame)
            }
            "Is a hand adding food or an ingredient into the pot?"
        }
        let answer = response.content
        return AddVerdict(adding: answer.handAddingFood, food: answer.food, confidence: Double(answer.confidence) / 100)
    }
}
#endif

/// Keeps each visit's keyframes, runs the gate, and asks the model. Thread-safe: frames
/// arrive on the camera queue, answers on a background task.
final class AddChecker: @unchecked Sendable {
    /// The crops' long side, in pixels.
    static let cropSide = 448.0
    /// The pan box plus this share of its size on each side, so the hand above the rim shows.
    static let cropMargin = 0.35
    /// How many checks the debug panel keeps.
    static let kept = 6

    private let lock = NSLock()
    private var gate = AddConfirmGate()
    private var keyframes = Keyframes<CGImage>()
    private var stepIndex = -1
    private var instruction = ""
    private var serial = 0
    private var deliver: (@Sendable (DetectorDecision) -> Void)?
    private var recordHandler: (@Sendable ([AICheckRecord]) -> Void)?
    private var records: [AICheckRecord] = []
    /// Each running check's crops and start, until its decision.
    private var running: [Int: (frames: [CGImage], started: Double)] = [:]
    private var availability: (time: Double, value: Bool)?
    private let images = CIContext(options: [.cacheIntermediates: false])

    /// Called with the latest checks, newest first.
    var onRecords: (@Sendable ([AICheckRecord]) -> Void)? {
        get { lock.withLock { recordHandler } }
        set { lock.withLock { recordHandler = newValue } }
    }

    /// Whether the on-device check is on. Rechecked once a second, since the model can
    /// finish downloading during a cook.
    var isChecking: Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if let cached = lock.withLock({ availability }), now - cached.time < 1 { return cached.value }
        let value = AddModel.isAvailable
        lock.withLock { availability = (now, value) }
        return value
    }

    /// The recipe step, for the check's context. A new step drops any answer still coming.
    func setStep(_ index: Int, instruction newInstruction: String) {
        let ended: AddConfirmGate.Outcome? = lock.withLock {
            guard index != stepIndex || newInstruction != instruction else { return nil }
            stepIndex = index
            instruction = newInstruction
            serial += 1
            keyframes.clear()
            return gate.setStep(serial)
        }
        if let ended { finish(ended) }
    }

    /// Feeds one analyzed frame. Offers go out through `deliver`.
    func observe(
        time: Double, checking: Bool, result: PanWatcher.Result, opened: Double, settings: DetectorSettings,
        pixelBuffer: CVPixelBuffer, region: NormRect?, deliver: (@Sendable (DetectorDecision) -> Void)?
    ) {
        lock.lock()
        self.deliver = deliver
        guard checking, let region else {
            gate.checking = false
            keyframes.clear()
            lock.unlock()
            return
        }
        gate.checking = true
        keyframes.observe(
            time: time, handInZone: result.handInZone, handPoint: result.handPoint,
            released: opened >= settings.candidateRules.releaseThreshold
        ) { crop(pixelBuffer, region) }
        if result.handInZone { gate.noteHand(at: time) }
        let context = "The recipe step says: \(instruction)"
        let step = gate.receive(rules: result.decision, candidate: result.candidate, at: time, context: context)
        var asked: (AddConfirmGate.Check, [CGImage])?
        if let check = step.ask {
            let frames = keyframes.take(at: time, after: crop(pixelBuffer, region)).map(\.image)
            running[check.id] = (frames, ProcessInfo.processInfo.systemUptime)
            asked = (check, frames)
        }
        lock.unlock()

        if let ended = step.ended { finish(ended) }
        if let offer = step.offer { deliver?(offer) }
        if case let (check, frames)? = asked {
            let images = Frames(images: frames)
            Task.detached(priority: .userInitiated) { [weak self] in
                // With no frame of a hand there is nothing to judge: the rules decide, as without the model.
                let reply = images.images.count < 2
                    ? AddConfirmGate.Reply.failed
                    : await AddModel.ask(frames: images.images, context: check.context, timeout: 3)
                self?.answered(check.id, reply)
            }
        }
    }

    private func answered(_ id: Int, _ reply: AddConfirmGate.Reply) {
        let (outcome, deliver) = lock.withLock { (gate.answer(id, reply), self.deliver) }
        guard let outcome else {
            // Already ended by the timeout or a new step; just free its crops.
            lock.withLock { _ = running.removeValue(forKey: id) }
            return
        }
        finish(outcome)
        if let offer = outcome.offer { deliver?(offer) }
    }

    /// Records a check's end for the debug panel and frees its crops.
    private func finish(_ outcome: AddConfirmGate.Outcome) {
        let (handler, list): ((@Sendable ([AICheckRecord]) -> Void)?, [AICheckRecord]) = lock.withLock {
            let ran = running.removeValue(forKey: outcome.check.id)
            let record = AICheckRecord(
                id: outcome.check.id,
                thumbnails: ran?.frames.compactMap(thumbnail) ?? [],
                resolution: outcome.resolution,
                verdict: outcome.verdict,
                milliseconds: ran.map { Int(((ProcessInfo.processInfo.systemUptime - $0.started) * 1000).rounded()) },
                offered: outcome.offer != nil,
                joined: outcome.check.joined
            )
            records.insert(record, at: 0)
            if records.count > Self.kept { records.removeLast(records.count - Self.kept) }
            return (recordHandler, records)
        }
        handler?(list)
    }

    /// The pan box plus a margin, about 448 pixels on the long side. In memory only.
    private func crop(_ pixelBuffer: CVPixelBuffer, _ region: NormRect) -> CGImage? {
        let width = Double(CVPixelBufferGetWidth(pixelBuffer))
        let height = Double(CVPixelBufferGetHeight(pixelBuffer))
        let box = region.expanded(by: Self.cropMargin).clippedToFrame()
        // Core Image's origin is the bottom left; `NormRect`'s is the top left.
        let rect = CGRect(
            x: box.x * width, y: (1 - box.y - box.height) * height,
            width: box.width * width, height: box.height * height
        ).integral
        guard rect.width > 1, rect.height > 1 else { return nil }
        let scale = min(1, Self.cropSide / max(rect.width, rect.height))
        let image = CIImage(cvPixelBuffer: pixelBuffer)
            .cropped(to: rect)
            .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return images.createCGImage(image, from: image.extent.integral)
    }

    private func thumbnail(_ image: CGImage) -> CGImage? {
        let scale = 96 / Double(max(image.width, image.height, 1))
        let small = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return images.createCGImage(small, from: small.extent.integral)
    }
}
