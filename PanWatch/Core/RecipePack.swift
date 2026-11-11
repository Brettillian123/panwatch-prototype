import Foundation

/// The packed book: what ships in the app and in the test bundle, made from the per-recipe
/// sources in `Recipes/` by `swift run -c release PanWatchScenarios --add-recipes <folder>`
/// (or `--pack`). Always the same 18 files however many recipes there are:
///
/// - `recipebook-index.json`: the index (`RecipeIndex`), one entry per line.
/// - `recipebook-sources.json`: the outside sources' credits, a copy of `Recipes/sources.json`.
/// - `recipebook-shard-00.json` … `-15.json`: the full recipes, each in the shard its id
///   hashes to, as `{"version":1,"recipes":{"<id>": <the source file, whitespace taken out>}}`.
///
/// Each recipe's data is in the app once. Opening a recipe reads its shard once and keeps
/// every recipe in it. The packed files are generated and committed; never edit them.
extension RecipeBook {
    /// The folder in `PanWatch/Core` that holds the packed files, and that the tests' bundle
    /// copies whole.
    static let packedFolderName = "RecipeBook"
    static let packedIndexFile = "recipebook-index.json"
    static let packedSourcesFile = "recipebook-sources.json"
    /// 16 shards: at 1,500 recipes about 94 a shard, read in a few milliseconds.
    static let shardCount = 16

    static func shardFile(_ number: Int) -> String {
        "recipebook-shard-" + (number < 10 ? "0" : "") + String(number) + ".json"
    }

    /// Every packed file's name, in a fixed order.
    static var packedFiles: [String] {
        [packedIndexFile, packedSourcesFile] + (0..<shardCount).map(shardFile)
    }

    /// The shard a recipe's id goes in: FNV-1a over its bytes, the same on every platform.
    static func shardNumber(of id: String, shards: Int = shardCount) -> Int {
        var hash: UInt32 = 2_166_136_261
        for byte in id.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return Int(hash % UInt32(shards))
    }

    // MARK: Packing

    /// The packed files for the sources in `sources`, by name. A recipe has a photo when the
    /// asset catalog `assets` holds `dish-<id>.imageset`. Files that don't read as recipes
    /// are left out; the checker runs before anything is packed.
    static func pack(sources: URL, assets: URL?, shards: Int = shardCount) -> [String: Data] {
        var texts: [Int: [(id: String, json: String)]] = [:]
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: sources.path)) ?? []).sorted()
        for name in names where name.hasSuffix(".json") && name != sourcesFile && name != indexFile {
            guard let data = FileManager.default.contents(atPath: sources.appendingPathComponent(name).path),
                  case .success(let recipe) = decode(data) else { continue }
            texts[shardNumber(of: recipe.id, shards: shards), default: []].append((recipe.id, minified(data)))
        }
        var out: [String: Data] = [:]
        out[packedIndexFile] = RecipeIndex.encode(RecipeIndex.build(folder: sources, assets: assets))
        out[packedSourcesFile] = FileManager.default.contents(atPath: sources.appendingPathComponent(sourcesFile).path) ?? Data("[]\n".utf8)
        for number in 0..<shards {
            let lines = (texts[number] ?? []).sorted { $0.id < $1.id }.map { "\"\($0.id)\":\($0.json)" }
            let body = lines.isEmpty ? "" : "\n" + lines.joined(separator: ",\n") + "\n"
            out[shardFile(number)] = Data(("{\"version\":1,\"recipes\":{" + body + "}}\n").utf8)
        }
        return out
    }

    /// Writes the packed files into `packed`, replacing what is there.
    static func writePack(sources: URL, assets: URL?, to packed: URL) throws {
        try FileManager.default.createDirectory(at: packed, withIntermediateDirectories: true)
        for (name, data) in pack(sources: sources, assets: assets) {
            try data.write(to: packed.appendingPathComponent(name))
        }
    }

    /// The packed files in `packed` that don't match the sources byte for byte, one line each.
    /// Empty means the packed book is current.
    static func stalePackedFiles(sources: URL, assets: URL?, packed: URL) -> [String] {
        let fresh = pack(sources: sources, assets: assets)
        var lines: [String] = []
        for name in packedFiles {
            let committed = FileManager.default.contents(atPath: packed.appendingPathComponent(name).path)
            if committed == nil {
                lines.append("\(name): missing from \(packed.path); run the pack command.")
            } else if committed != fresh[name] {
                lines.append("\(name): out of date with Recipes/; run the pack command, never edit it by hand.")
            }
        }
        return lines
    }

    /// The JSON with the whitespace outside strings taken out: the same value, byte for byte
    /// inside every string and number.
    static func minified(_ data: Data) -> String {
        var out: [UInt8] = []
        out.reserveCapacity(data.count)
        var inString = false, escaped = false
        for byte in data {
            if inString {
                out.append(byte)
                if escaped { escaped = false } else if byte == UInt8(ascii: "\\") { escaped = true } else if byte == UInt8(ascii: "\"") { inString = false }
            } else if byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r") || byte == UInt8(ascii: "\t") {
                continue
            } else {
                if byte == UInt8(ascii: "\"") { inString = true }
                out.append(byte)
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    // MARK: Reading

    private struct ShardFile: Decodable {
        let recipes: [String: RecipeFile]
    }

    /// Every recipe in shard `number` of the packed book in `folder`, by id: read the first
    /// time it is asked for, then kept.
    static func shard(_ number: Int, in folder: URL) -> [String: Recipe] {
        let key = folder.path + "#" + String(number)
        if let kept = RecipeCache.shared.get(key) { return kept }
        var recipes: [String: Recipe] = [:]
        if let data = FileManager.default.contents(atPath: folder.appendingPathComponent(shardFile(number)).path),
           let file = try? JSONDecoder().decode(ShardFile.self, from: data) {
            for (id, recipeFile) in file.recipes {
                if case .success(let recipe) = recipe(from: recipeFile) { recipes[id] = recipe }
            }
        }
        RecipeCache.shared.put(key, recipes)
        return recipes
    }

    /// One recipe from the packed book: its shard is read once, then kept.
    static func recipe(id: String, in folder: URL? = packedFolder()) -> Recipe? {
        guard let folder else { return nil }
        return shard(shardNumber(of: id), in: folder)[id]
    }

    /// The outside sources' credits that shipped with this build.
    static func bundledSources() -> [RecipeSourceCredit] {
        guard let folder = packedFolder(),
              let data = FileManager.default.contents(atPath: folder.appendingPathComponent(packedSourcesFile).path) else { return [] }
        return (try? JSONDecoder().decode([RecipeSourceCredit].self, from: data)) ?? []
    }
}

/// Shards already read this run, by folder and number.
final class RecipeCache: @unchecked Sendable {
    static let shared = RecipeCache()
    private let lock = NSLock()
    private var kept: [String: [String: Recipe]] = [:]

    func get(_ key: String) -> [String: Recipe]? {
        lock.lock(); defer { lock.unlock() }
        return kept[key]
    }

    func put(_ key: String, _ recipes: [String: Recipe]) {
        lock.lock(); defer { lock.unlock() }
        kept[key] = recipes
    }
}
