import Foundation
import Testing
@testable import PanWatchCore

/// Where the book's sources and packed files sit in the repo.
enum BookPaths {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let sources = repo.appendingPathComponent("Recipes", isDirectory: true)
    static let packed = repo.appendingPathComponent("PanWatch/Core/RecipeBook", isDirectory: true)
    static let assets = repo.appendingPathComponent("PanWatch/Assets.xcassets", isDirectory: true)

    /// A fresh temp folder, removed by the caller.
    static func temp(_ name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A copy of the book's sources to change freely.
    static func copyOfBook() throws -> URL {
        let folder = try temp("book")
        for name in try FileManager.default.contentsOfDirectory(atPath: sources.path) {
            try FileManager.default.copyItem(at: sources.appendingPathComponent(name), to: folder.appendingPathComponent(name))
        }
        return folder
    }

    /// The rice recipe's file under a new id and title, from `source` (with a link).
    static func riceFile(id: String, title: String, source: String = "Sous Vision", url: String? = nil) throws -> Data {
        let rice = try String(contentsOf: sources.appendingPathComponent("rice.json"), encoding: .utf8)
        let sourceJSON = url.map { "{ \"name\": \"\(source)\", \"url\": \"\($0)\" }" } ?? "{ \"name\": \"\(source)\" }"
        return Data(rice
            .replacingOccurrences(of: #""id": "rice""#, with: "\"id\": \"\(id)\"")
            .replacingOccurrences(of: #""title": "Rice""#, with: "\"title\": \"\(title)\"")
            .replacingOccurrences(of: #""source": { "name": "Sous Vision" }"#, with: "\"source\": \(sourceJSON)").utf8)
    }

    /// The process's resident memory in KB, where the system reports it (Linux); else 0.
    static func residentKB() -> Int {
        guard let status = try? String(contentsOfFile: "/proc/self/status", encoding: .utf8),
              let line = status.split(separator: "\n").first(where: { $0.hasPrefix("VmRSS:") }) else { return 0 }
        return Int(line.split(separator: " ").dropFirst().first ?? "") ?? 0
    }
}

@Suite struct RecipePackTests {
    @Test func theBookShipsAsAFixedHandfulOfDistinctlyNamedFiles() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: BookPaths.packed.path).sorted()
        #expect(names == RecipeBook.packedFiles.sorted())
        #expect(names.count == 2 + RecipeBook.shardCount)
        #expect(names.allSatisfy { $0.hasPrefix("recipebook-") })
        // No per-recipe file ships: every recipe is in exactly one shard, once.
        let sourceIDs = RecipeBook.load(from: BookPaths.sources).recipes.map(\.id)
        var seen: [String] = []
        for number in 0..<RecipeBook.shardCount {
            seen += RecipeBook.shard(number, in: BookPaths.packed).keys
        }
        #expect(seen.sorted() == sourceIDs.sorted())
    }

    @Test func aShardHoldsEachSourceFileWithItsWhitespaceTakenOut() throws {
        let text = #"{ "a": "two  words, a \"quote\" and \\ ", "b": [1, 2.5] }"#
        #expect(RecipeBook.minified(Data(text.utf8)) == #"{"a":"two  words, a \"quote\" and \\ ","b":[1,2.5]}"#)
        for recipe in Recipe.all {
            let data = try Data(contentsOf: BookPaths.sources.appendingPathComponent(recipe.id + ".json"))
            guard case .success(let source) = RecipeBook.decode(data) else { Issue.record("\(recipe.id)"); continue }
            #expect(RecipeBook.recipe(id: recipe.id) == source)
        }
    }

    @Test func theShardIsTheSameOnEveryPlatform() {
        #expect(RecipeBook.shardNumber(of: "rice") == RecipeBook.shardNumber(of: "rice"))
        #expect(RecipeBook.shardNumber(of: "") == Int(2_166_136_261 % 16))
        let spread = Set(SyntheticBook.entries.map { RecipeBook.shardNumber(of: $0.id) })
        #expect(spread.count == 16)
    }

    // MARK: At 1,500

    @Test func fifteenHundredRecipesPackAndOpenFast() throws {
        let folder = try SyntheticBook.folder(count: 1500)
        defer { try? FileManager.default.removeItem(at: folder) }
        var times: [Int: (cold: Double, warm: Double, bytes: Int)] = [:]
        let id = SyntheticBook.entries[777].id
        for shards in [8, 16, 32] {
            let packed = folder.appendingPathComponent("packed-\(shards)")
            try FileManager.default.createDirectory(at: packed, withIntermediateDirectories: true)
            let files = RecipeBook.pack(sources: folder, assets: nil, shards: shards)
            for (name, data) in files { try data.write(to: packed.appendingPathComponent(name)) }
            // Read the shard the way the app does, but at this shard count.
            let number = RecipeBook.shardNumber(of: id, shards: shards)
            var found: Recipe?
            let cold = SyntheticBook.milliseconds { found = RecipeBook.shard(number, in: packed)[id] }
            let warm = SyntheticBook.milliseconds { found = RecipeBook.shard(number, in: packed)[id] }
            #expect(found?.title == SyntheticBook.entries[777].title)
            times[shards] = (cold, warm, files.values.reduce(0) { $0 + $1.count })
        }
        for shards in [8, 16, 32] {
            let t = times[shards]!
            print("RecipePack \(shards) shards: open cold \(String(format: "%.2f", t.cold)) ms, warm \(String(format: "%.3f", t.warm)) ms, packed \(t.bytes) bytes")
        }

        // The shipped layout: 16 shards, through the app's own calls.
        let packed = folder.appendingPathComponent("packed")
        let started = DispatchTime.now().uptimeNanoseconds
        try RecipeBook.writePack(sources: folder, assets: nil, to: packed)
        let packMs = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        let names = try FileManager.default.contentsOfDirectory(atPath: packed.path)
        #expect(names.sorted() == RecipeBook.packedFiles.sorted())
        let bytes = try names.reduce(0) { $0 + (try Data(contentsOf: packed.appendingPathComponent($1))).count }
        var index: RecipeIndex?
        let indexMs = SyntheticBook.milliseconds {
            index = FileManager.default.contents(atPath: packed.appendingPathComponent(RecipeBook.packedIndexFile).path)
                .flatMap { try? RecipeIndex.decode($0) }
        }
        #expect(index?.entries.count == 1500)
        let memoryBefore = BookPaths.residentKB()
        var cold = 0.0, warm = 0.0
        // 50 spread over the book, each equal to its source file.
        for place in stride(from: 13, to: 1500, by: 30) {
            let entry = SyntheticBook.entries[place]
            var recipe: Recipe?
            let ms = SyntheticBook.milliseconds { recipe = RecipeBook.recipe(id: entry.id, in: packed) }
            if place == 13 { cold = ms }
            if place == 13 { warm = SyntheticBook.milliseconds { recipe = RecipeBook.recipe(id: entry.id, in: packed) } }
            let data = try Data(contentsOf: folder.appendingPathComponent(entry.id + ".json"))
            guard case .success(let source) = RecipeBook.decode(data) else { Issue.record("\(entry.id)"); continue }
            #expect(recipe == source)
        }
        for number in 0..<RecipeBook.shardCount { _ = RecipeBook.shard(number, in: packed) }
        let memoryKB = BookPaths.residentKB() - memoryBefore
        print("RecipePack 1500: \(names.count) files, \(bytes) bytes; packed in \(String(format: "%.0f", packMs)) ms; index load \(String(format: "%.1f", indexMs)) ms; open cold \(String(format: "%.2f", cold)) ms, warm \(String(format: "%.3f", warm)) ms; all 16 shards kept: +\(memoryKB) KB resident")
        #expect(cold < 50 * SyntheticBook.slack)
        #expect(indexMs < 100 * SyntheticBook.slack)
        #expect(RecipeBook.stalePackedFiles(sources: folder, assets: nil, packed: packed) == [])
    }

    // MARK: Adding

    @Test func aGoodBatchIsAddedCreditedAndPacked() throws {
        let book = try BookPaths.copyOfBook()
        let incoming = try BookPaths.temp("batch")
        defer { try? FileManager.default.removeItem(at: book); try? FileManager.default.removeItem(at: incoming) }
        let packed = book.appendingPathComponent("packed")
        let before = RecipeBook.load(from: book).recipes.count
        try BookPaths.riceFile(id: "brown-rice", title: "Brown Rice", source: "Test Kitchen", url: "https://test.example/rice/brown")
            .write(to: incoming.appendingPathComponent("brown-rice.json"))
        try BookPaths.riceFile(id: "jasmine-rice", title: "Jasmine Rice").write(to: incoming.appendingPathComponent("jasmine-rice.json"))
        let result = RecipeBook.add(from: incoming, book: book, packed: packed, assets: nil)
        #expect(result.problems == [], "\(result.problems)")
        #expect(result.added.map(\.id).sorted() == ["brown-rice", "jasmine-rice"])
        #expect(result.book.count == before + 2)
        #expect(result.newSources == [RecipeSourceCredit(name: "Test Kitchen", credit: "Recipes adapted from Test Kitchen.", url: "https://test.example/")])
        #expect(RecipeBook.sources(in: book).contains { $0.name == "Test Kitchen" })
        #expect(RecipeLibraryTests.withoutAwaitedNumberLines(RecipeBook.check(folder: book)) == [])
        #expect(RecipeBook.stalePackedFiles(sources: book, assets: nil, packed: packed) == [])
        #expect(RecipeBook.recipe(id: "brown-rice", in: packed)?.title == "Brown Rice")
        #expect(result.summary.first == "Added 2 recipes; the book has \(before + 2).")
        #expect(result.summary.contains { $0.contains("Pasta and grains") && $0.contains("(+2)") }, "\(result.summary)")
    }

    @Test func aHeldRecipeGoesInWithoutItsNote() throws {
        let book = try BookPaths.copyOfBook()
        let incoming = try BookPaths.temp("held")
        defer { try? FileManager.default.removeItem(at: book); try? FileManager.default.removeItem(at: incoming) }
        let packed = book.appendingPathComponent("packed")
        // A held recipe: its "_held" note, no serving count, and a credit on its source.
        var object = try #require(JSONSerialization.jsonObject(with: BookPaths.riceFile(id: "wild-rice", title: "Wild Rice")) as? [String: Any])
        object["_held"] = "serves not given"
        object.removeValue(forKey: "serves")
        object["source"] = ["name": "Sous Vision", "credit": "Healthy Kitchen Program"]
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            .write(to: incoming.appendingPathComponent("wild-rice.json"))
        #expect(RecipeBook.check(folder: incoming) == [], "the checker skips the note too")
        let result = RecipeBook.add(from: incoming, book: book, packed: packed, assets: nil)
        #expect(result.problems == [], "\(result.problems)")
        let written = String(decoding: try Data(contentsOf: book.appendingPathComponent("wild-rice.json")), as: UTF8.self)
        #expect(!written.contains("_held"))
        let added = try #require(RecipeBook.recipe(id: "wild-rice", in: packed))
        #expect(added.serves == nil)
        #expect(added.source.credit == "Healthy Kitchen Program")
        #expect(RecipeBook.stalePackedFiles(sources: book, assets: nil, packed: packed) == [])
        // A file without the note is copied byte for byte.
        let plain = try BookPaths.riceFile(id: "red-rice", title: "Red Rice")
        #expect(RecipeBook.withoutHeld(plain) == plain)
    }

    @Test func aBatchWithAnyProblemIsRefusedWhole() throws {
        let book = try BookPaths.copyOfBook()
        let incoming = try BookPaths.temp("batch")
        defer { try? FileManager.default.removeItem(at: book); try? FileManager.default.removeItem(at: incoming) }
        let packed = book.appendingPathComponent("packed")
        let names = try FileManager.default.contentsOfDirectory(atPath: book.path).sorted()
        try BookPaths.riceFile(id: "brown-rice", title: "Brown Rice").write(to: incoming.appendingPathComponent("brown-rice.json"))
        try BookPaths.riceFile(id: "rice-again", title: "Rice").write(to: incoming.appendingPathComponent("rice-again.json"))
        try BookPaths.riceFile(id: "oatmeal", title: "Other oats").write(to: incoming.appendingPathComponent("oatmeal.json"))
        try Data(#"{"id": "bad", "steps": []}"#.utf8).write(to: incoming.appendingPathComponent("bad.json"))
        let result = RecipeBook.add(from: incoming, book: book, packed: packed, assets: nil)
        #expect(result.problems.contains { $0.hasPrefix("oatmeal.json: already in the book") }, "\(result.problems)")
        #expect(result.problems.contains { $0.contains("the title \"Rice\" is already used by") }, "\(result.problems)")
        #expect(result.problems.contains { $0.hasPrefix("bad.json: missing") }, "\(result.problems)")
        #expect(result.added.isEmpty)
        #expect(result.summary.first?.hasPrefix("Nothing added") == true)
        #expect(try FileManager.default.contentsOfDirectory(atPath: book.path).sorted() == names)
        #expect(!FileManager.default.fileExists(atPath: packed.path))
    }

    @Test func aStalePackIsCaught() throws {
        let book = try BookPaths.copyOfBook()
        defer { try? FileManager.default.removeItem(at: book) }
        let packed = book.appendingPathComponent("packed")
        try RecipeBook.writePack(sources: book, assets: nil, to: packed)
        #expect(RecipeBook.stalePackedFiles(sources: book, assets: nil, packed: packed) == [])
        try BookPaths.riceFile(id: "brown-rice", title: "Brown Rice").write(to: book.appendingPathComponent("brown-rice.json"))
        let stale = RecipeBook.stalePackedFiles(sources: book, assets: nil, packed: packed)
        #expect(stale.contains { $0.hasPrefix(RecipeBook.packedIndexFile) })
        #expect(stale.contains { $0.hasPrefix(RecipeBook.shardFile(RecipeBook.shardNumber(of: "brown-rice"))) })
    }
}
