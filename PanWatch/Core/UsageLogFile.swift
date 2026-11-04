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
        if try add(data) > limit { try trim() }
    }

    /// Adds `data` to the end of the file, making it if needed, and returns the new size.
    private func add(_ data: Data) throws -> Int {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else {
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            return data.count
        }
        if #available(macOS 10.15.4, iOS 13.4, *) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            let end = try handle.seekToEnd()
            try handle.write(contentsOf: data)
            return Int(end) + data.count
        }
        // Only for the package's tests on an old macOS target: rewrite the whole file.
        var all = try Data(contentsOf: url)
        all.append(data)
        try all.write(to: url)
        return all.count
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
        encoder.outputFormatting = .sortedKeys
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
