import Testing
@testable import PanWatchCore

/// Voice against a real-sized book: the shipped one and the made-up 1,500. These hold however
/// many recipes are added; none of them names a dish the book might later gain or lose.
@Suite("Voice with a full book")
struct RealBookVoiceTests {
    /// Every title whose words no other title shares exactly, short enough to say as a command.
    private func sayable(_ book: VoiceTitles) -> [String] {
        var count: [Set<String>: Int] = [:]
        for words in book.words { count[words, default: 0] += 1 }
        return zip(book.titles, book.words).compactMap { title, words in
            count[words] == 1 && VoiceCommand.words(in: "make " + title).count <= VoiceCommand.maximumWords ? title : nil
        }
    }

    private func expectEveryTitleWins(_ book: VoiceTitles, sourceLocation: SourceLocation = #_sourceLocation) {
        let titles = sayable(book)
        #expect(titles.count * 10 >= book.titles.count * 8, "most titles can be said", sourceLocation: sourceLocation)
        for title in titles {
            #expect(VoiceCommand.parse("make " + title, book: book) == .makeRecipe(title), "\(title)", sourceLocation: sourceLocation)
            #expect(VoiceCommand.parse(title, screen: .recipes, book: book) == .makeRecipe(title), "\(title)", sourceLocation: sourceLocation)
        }
    }

    @Test func anExactTitleWinsInTheShippedBook() {
        let book = RecipeIndex.bundled.voice
        #expect(book.titles.filter { $0.lowercased().contains("rice") }.count > 1)
        for (text, screen) in [("make the rice", AppScreen.cook), ("rice", .recipes), ("cook rice", .cook), ("cook rice", .recipes)] {
            #expect(VoiceCommand.parse(text, screen: screen) == .makeRecipe("Rice"), "\(text)")
        }
        expectEveryTitleWins(book)
    }

    @Test func anExactTitleWinsInFifteenHundred() {
        expectEveryTitleWins(SyntheticBook.index.voice)
    }

    /// A word many titles share asks: by name for two or three, with the list for more.
    @Test func aSharedWordAsksAndNeverStartsTheWrongDish() {
        let crowded = DemoBook.crowded
        guard case .askWhichRecipe(let pasta) = VoiceCommand.parse("let's do pasta", book: crowded) else {
            Issue.record("pasta among three"); return
        }
        #expect(Set(pasta) == ["Garlic Butter Pasta", "Pasta Salad", "Penne Pasta Bake"])
        #expect(VoiceCommand.whichRecipeQuestion(pasta) != VoiceCommand.severalFound)
        guard case .askWhichRecipe(let eggs) = VoiceCommand.parse("eggs", screen: .recipes, book: crowded) else {
            Issue.record("eggs among two"); return
        }
        #expect(Set(eggs) == ["Hard-Boiled Eggs", "Deviled Eggs"])
        #expect(VoiceCommand.parse("broccoli", screen: .recipes, book: crowded) == .makeRecipe("Steamed Broccoli"))
        #expect(VoiceCommand.parse("rice", screen: .recipes, book: crowded) == .makeRecipe("Rice"))

        // In the shipped and the made-up book, a word starts only a dish whose title has it.
        for book in [RecipeIndex.bundled.voice, SyntheticBook.index.voice] {
            for word in ["pasta", "eggs", "chicken", "broccoli", "soup", "rice", "lemon", "salad", "beans"] {
                switch VoiceCommand.parse(word, screen: .recipes, book: book) {
                case .makeRecipe(let title):
                    #expect(VoiceCommand.distinctiveWords(of: title).contains(VoiceCommand.distinctiveWords(of: word).first ?? word), "\(word): \(title)")
                case .askWhichRecipe(let titles):
                    #expect(titles.count > 1 && titles.allSatisfy { VoiceCommand.distinctiveWords(of: $0).isSuperset(of: VoiceCommand.distinctiveWords(of: word)) }, "\(word)")
                    if titles.count > 3 { #expect(VoiceCommand.whichRecipeQuestion(titles) == VoiceCommand.severalFound) }
                default: break
                }
            }
        }
    }

    /// "Let's do pasta" with many pasta dishes says "I found several. Here they are." and shows them.
    @Test func letsDoPastaInTheShippedBookShowsThePastaDishes() {
        let pastas = RecipeIndex.bundled.titles.filter { VoiceCommand.distinctiveWords(of: $0).contains("pasta") }
        guard pastas.count > 1 else { return }
        #expect(VoiceCommand.parse("let's do pasta", screen: .recipes) == .askWhichRecipe(pastas))
    }

    @Test func aShownListIsPickedByPlaceOrName() {
        let shown = Array(SyntheticBook.index.titles.prefix(20))
        #expect(VoiceCommand.parse("the first one", choosing: shown) == .makeRecipe(shown[0]))
        #expect(VoiceCommand.parse("number two", choosing: shown) == .makeRecipe(shown[1]))
        #expect(VoiceCommand.parse("the third one", choosing: shown) == .makeRecipe(shown[2]))
        #expect(VoiceCommand.parse(shown[7], choosing: shown) == .makeRecipe(shown[7]))
    }
}
