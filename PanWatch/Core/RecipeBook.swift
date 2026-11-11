import Foundation

/// The recipe book: one JSON file per recipe, `<slug>.json`, in `PanWatch/Core/Recipes`.
/// The format is described in `Recipes/README.md`. One loader serves both places the
/// files live: the Core package's resource bundle in the tests (`Bundle.module`, the
/// `Recipes` folder copied whole) and the app bundle, where Xcode's synchronized group
/// copies each file to the top of the bundle.
enum RecipeBook {
    /// The folder holding the recipe files that shipped with this build.
    static func bundledFolder() -> URL? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let root = bundle.resourceURL else { return nil }
        let nested = root.appendingPathComponent("Recipes", isDirectory: true)
        var isFolder: ObjCBool = false
        if FileManager.default.fileExists(atPath: nested.path, isDirectory: &isFolder), isFolder.boolValue {
            return nested
        }
        return root
    }

    /// The bundled recipes in book order. A file that fails to load is left out; the
    /// checker and the tests make sure none does.
    static func bundled() -> [Recipe] {
        guard let folder = bundledFolder() else { return [] }
        return load(from: folder).recipes
    }

    /// A file that could not be read as a recipe, and why, in plain words.
    struct FileProblem: Equatable, Sendable {
        let file: String
        let problem: String
        var line: String { "\(file): \(problem)" }
    }

    /// Every `*.json` file in `folder` that is a recipe, in book order, and the files that
    /// look like recipes (they have "steps") but could not be read. Other JSON files, which
    /// sit beside the recipes at the top of the app bundle, are skipped.
    static func load(from folder: URL) -> (recipes: [Recipe], problems: [FileProblem]) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var recipes: [Recipe] = []
        var problems: [FileProblem] = []
        for name in names.sorted() where name.hasSuffix(".json") {
            guard let data = FileManager.default.contents(atPath: folder.appendingPathComponent(name).path) else { continue }
            guard looksLikeRecipe(data) else { continue }
            switch decode(data) {
            case .success(let recipe):
                recipes.append(recipe)
                let expected = recipe.id + ".json"
                if name != expected {
                    problems.append(FileProblem(file: name, problem: "the file name must be the id: \(expected)."))
                }
            case .failure(let error):
                problems.append(FileProblem(file: name, problem: error.text))
            }
        }
        return (inBookOrder(recipes), problems)
    }

    /// By category in `RecipeCategory` order, then by title.
    static func inBookOrder(_ recipes: [Recipe]) -> [Recipe] {
        recipes.sorted {
            ($0.category.index, $0.title.lowercased()) < ($1.category.index, $1.title.lowercased())
        }
    }

    private static func looksLikeRecipe(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Not an object at all: only a problem if it was meant as a recipe, which a
            // broken file can't say. A file that doesn't parse is reported.
            return (try? JSONSerialization.jsonObject(with: data)) == nil
        }
        return object["steps"] != nil
    }

    // MARK: Reading one file

    struct ReadError: Error, Equatable {
        let text: String
    }

    /// One recipe from the JSON of its file.
    static func decode(_ data: Data) -> Result<Recipe, ReadError> {
        let file: RecipeFile
        do {
            file = try JSONDecoder().decode(RecipeFile.self, from: data)
        } catch let DecodingError.keyNotFound(key, context) {
            return .failure(ReadError(text: "missing \"\(key.stringValue)\"\(where_(context))."))
        } catch let DecodingError.typeMismatch(_, context) {
            return .failure(ReadError(text: "wrong kind of value\(where_(context))."))
        } catch let DecodingError.valueNotFound(_, context) {
            return .failure(ReadError(text: "empty value\(where_(context))."))
        } catch {
            return .failure(ReadError(text: "not valid JSON."))
        }
        guard let category = RecipeCategory(rawValue: file.category) else {
            let known = RecipeCategory.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")
            return .failure(ReadError(text: "unknown category \"\(file.category)\"; use one of \(known)."))
        }
        guard let method = CookMethod(rawValue: file.method) else {
            let known = CookMethod.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")
            return .failure(ReadError(text: "unknown method \"\(file.method)\"; use one of \(known)."))
        }
        let steps = file.steps.enumerated().map { index, step in
            RecipeStep(
                id: index + 1,
                instruction: step.instruction,
                watch: step.watch.map {
                    AdditionWatch(ingredient: $0.ingredient, timerLabel: $0.timerLabel, timerMinutes: $0.timerMinutes,
                                  minimumChange: $0.minimumChange, countsRelease: $0.countsRelease ?? false)
                },
                cue: step.cue.map { StepCue(timerLabel: $0.timerLabel, secondsLeft: $0.secondsLeft) },
                spoken: step.spoken,
                timer: step.timer.map { StepTimer(label: $0.label, minutes: $0.minutes) }
            )
        }
        return .success(Recipe(
            id: file.id, title: file.title, category: category, method: method,
            source: RecipeSource(name: file.source.name, url: file.source.url ?? ""),
            steps: steps, items: file.ingredients.map { Ingredient(name: $0.name, amount: $0.amount) },
            totalMinutes: file.totalMinutes, serves: file.serves
        ))
    }

    private static func where_(_ context: DecodingError.Context) -> String {
        let path = context.codingPath.map { key in key.intValue.map { "item \($0 + 1)" } ?? key.stringValue }
        return path.isEmpty ? "" : " at " + path.joined(separator: " > ")
    }

    /// The file's shape, field for field.
    private struct RecipeFile: Decodable {
        let id: String
        let title: String
        let category: String
        let method: String
        let source: Source
        let serves: Int
        let totalMinutes: Int
        let ingredients: [Item]
        let steps: [Step]

        struct Source: Decodable { let name: String; let url: String? }
        struct Item: Decodable { let amount: String; let name: String }
        struct Step: Decodable {
            let instruction: String
            let spoken: String?
            let watch: Watch?
            let cue: Cue?
            let timer: Timer?
        }
        struct Watch: Decodable {
            let ingredient: String
            let timerLabel: String
            let timerMinutes: Int
            let minimumChange: Double?
            let countsRelease: Bool?
        }
        struct Cue: Decodable { let timerLabel: String; let secondsLeft: Int }
        struct Timer: Decodable { let label: String; let minutes: Int }
    }
}
