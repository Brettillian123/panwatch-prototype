import AVFoundation
import FluidAudio
import Foundation

// VoicePreviews <out folder> "<line>" <pack> <pack> ...
// Says <line> in each Kokoro voice pack through FluidAudio's ANE-v3 runtime (the one
// KokoroVoice uses in the app) and writes <out>/<pack>.wav, 24 kHz mono float. Exits
// non-zero if any voice fails, comes out silent, or is outside 1.5 to 6 seconds.

let args = CommandLine.arguments
guard args.count >= 4 else {
    print("usage: VoicePreviews <out folder> \"<line>\" <pack> [<pack> ...]")
    exit(2)
}
let out = URL(fileURLWithPath: args[1], isDirectory: true)
let line = args[2]
let packs = Array(args[3...])

let models = FileManager.default.temporaryDirectory.appendingPathComponent("kokoro-previews", isDirectory: true)
try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let store = KokoroAneModelStore(directory: models, version: .v3)
let manager = KokoroAneManager(modelStore: store)
let started = Date()
do {
    try await manager.initialize()
} catch {
    print("FAILED initialize: \(error)")
    exit(1)
}
print("model ready in \(Int(Date().timeIntervalSince(started))) s")

var failed = false
for pack in packs {
    do {
        _ = try await store.voicePack(pack)
        let result = try await manager.synthesizeDetailed(text: line, voice: pack, speed: 1.0)
        let samples = result.samples
        let rate = Double(result.sampleRate)
        let seconds = Double(samples.count) / rate
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else {
            print("FAILED \(pack): no buffer")
            failed = true
            continue
        }
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress { channel.update(from: base, count: samples.count) }
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let url = out.appendingPathComponent("\(pack).wav")
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        let ok = peak > 0.05 && seconds >= 1.5 && seconds <= 6
        print(String(format: "%@ %@ %.2f s peak %.3f", ok ? "OK" : "BAD", pack, seconds, peak))
        if !ok { failed = true }
    } catch {
        print("FAILED \(pack): \(error)")
        failed = true
    }
}
exit(failed ? 1 : 0)
