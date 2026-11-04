import Foundation

/// The usage log on the phone: one JSON event per line, only ever appended. Past `limit`
/// bytes the oldest lines are dropped, keeping about three quarters of it. There's no
/// network code here or anywhere the log is used; the cook can share the file themselves.
struct UsageLogFile: Sendable {
    let url: URL
    var limit = 5_000_000

    init(url: URL, limit: Int = 5_000_000) {
        self.url = url
        self.limit = limit
    }

    func append(_ events: [UsageEvent]) throws {
        guard !events.isEmpty else { return }
        let encoder = Self.encoder()
        var data = Data()
        for event in events {
            data.append(try encoder.encode(event))
            data.append(Self.newline)
        }
        let manager = FileManager.default
        let size: Int
        if manager.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            size = Int(try handle.seekToEnd()) + data.count
            try handle.write(contentsOf: data)
        } else {
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            size = data.count
        }
        if size > limit { try trim() }
    }

    /// Every event in the file, oldest first. A line that can't be read is skipped.
    func load() -> [UsageEvent] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = Self.decoder()
        return data.split(separator: Self.newline).compactMap { try? decoder.decode(UsageEvent.self, from: Data($0)) }
    }

    /// Drops the oldest whole lines until about three quarters of the limit is left.
    private func trim() throws {
        let data = try Data(contentsOf: url)
        let keep = limit * 3 / 4
        guard data.count > keep else { return }
        let start = data.index(data.endIndex, offsetBy: -keep)
        // Cut just after the newline that ends the line `start` falls in.
        let cut = data[data.index(before: start)...].firstIndex(of: Self.newline).map { data.index(after: $0) } ?? data.endIndex
        try Data(data[cut...]).write(to: url, options: .atomic)
    }

    private static let newline = UInt8(ascii: "\n")

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
