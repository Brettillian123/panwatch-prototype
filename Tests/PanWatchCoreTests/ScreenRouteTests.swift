import Testing
@testable import PanWatchCore

@Suite("Screens and tabs")
struct ScreenRouteTests {
    @Test func settingsIsTheProfile() {
        #expect(AppScreen.settings == .profile)
        #expect(AppScreen.sayPhrases(screen: .settings) == AppScreen.sayPhrases(screen: .profile))
        #expect(HelpGroup.ordered(for: .settings) == HelpGroup.ordered(for: .profile))
    }

    @Test func closingARecipePageGoesHome() {
        #expect(AppScreen.closing(.recipe, helpFrom: .cook) == .recipes)
    }

    @Test func closingTheMakeAVoiceSheetGoesToTheVoices() {
        #expect(AppScreen.closing(.makeVoice, helpFrom: .cook) == .voices)
    }

    @Test func theMakeAVoiceSheetGoesBackToProfileWhenOpenedThere() {
        #expect(AppScreen.makeVoiceOrigin(.profile) == .profile)
        #expect(AppScreen.closing(.makeVoice, helpFrom: .cook, makeVoiceFrom: .profile) == .profile)
        #expect(AppScreen.closing(.makeVoice, helpFrom: .cook, makeVoiceFrom: .profile, cookUnderWay: false) == .profile)
    }

    @Test func theMakeAVoiceSheetOpenedAnywhereElseGoesBackToTheVoices() {
        for from in AppScreen.allCases where from != .profile {
            #expect(AppScreen.makeVoiceOrigin(from) == .voices, "\(from)")
            #expect(AppScreen.closing(.makeVoice, helpFrom: .cook, makeVoiceFrom: from) == .voices, "\(from)")
        }
    }

    @Test func closingHelpGoesWhereItWasOpened() {
        #expect(AppScreen.closing(.help, helpFrom: .recipe) == .recipe)
        #expect(AppScreen.closing(.help, helpFrom: .profile) == .profile)
        #expect(AppScreen.closing(.help, helpFrom: .help) == .cook)
    }

    @Test func closingAMenuStillGoesToCookMode() {
        for screen in [AppScreen.recipes, .voices, .profile, .cook] {
            #expect(AppScreen.closing(screen, helpFrom: .cook) == .cook, "\(screen)")
        }
    }

    @Test func closingAMenuWithNothingCookingGoesHome() {
        for screen in [AppScreen.recipes, .voices, .profile] {
            #expect(AppScreen.closing(screen, helpFrom: .cook, cookUnderWay: false) == .recipes, "\(screen)")
        }
        #expect(AppScreen.closing(.cook, helpFrom: .cook, cookUnderWay: false) == .cook)
        #expect(AppScreen.closing(.makeVoice, helpFrom: .cook, cookUnderWay: false) == .voices)
        #expect(AppScreen.closing(.help, helpFrom: .voices, cookUnderWay: false) == .voices)
    }

    @Test func theTabBarShowsOnlyOnTopLevelScreens() {
        let shown = AppScreen.allCases.filter(\.showsTabBar)
        #expect(Set(shown) == [.recipes, .voices, .profile])
    }

    @Test func onlyCookModeIsLandscapeOnly() {
        #expect(AppScreen.allCases.filter(\.isLandscapeOnly) == [.cook])
    }

    @Test func eachScreenLightsItsTab() {
        #expect(AppScreen.recipe.tab == .recipes)
        #expect(AppScreen.makeVoice.tab == .voices)
        #expect(AppScreen.profile.tab == .profile)
        #expect(AppScreen.cook.tab == .cook)
        #expect(AppScreen.help.tab == nil)
    }

    @Test func theCookTabOpensCookModeOnlyWhileACookIsUnderWay() {
        #expect(AppScreen.opening(.cook, cookUnderWay: true) == .cook)
        #expect(AppScreen.opening(.cook, cookUnderWay: false) == .recipes)
        #expect(AppScreen.opening(.recipes, cookUnderWay: true) == .recipes)
        #expect(AppScreen.opening(.voices, cookUnderWay: false) == .voices)
        #expect(AppScreen.opening(.profile, cookUnderWay: false) == .profile)
    }

    @Test func theTabsAreFourWithTheirSymbols() {
        #expect(AppTab.allCases.map(\.title) == ["Recipes", "Cook", "Voices", "Profile"])
        #expect(AppTab.allCases.map(\.symbol) == ["fork.knife", "frying.pan", "waveform", "person"])
    }

    @Test func aRecipePageHearsStartCooking() {
        for text in ["start cooking", "let's cook", "start", "start it", "um, start cooking please"] {
            #expect(VoiceCommand.parse(text, screen: .recipe) == .startCooking, "\(text)")
        }
        #expect(VoiceCommand.parse("back", screen: .recipe) == .back)
        #expect(VoiceCommand.parse("done", screen: .recipe) == .done)
    }

    @Test func startAloneStillAnswersAnOfferElsewhere() {
        #expect(VoiceCommand.parse("start", screen: .cook) == .yes)
        #expect(VoiceCommand.parse("start it", screen: .cook) == .yes)
        #expect(VoiceCommand.parse("start over", screen: .recipe) == .startOver)
        #expect(VoiceCommand.parse("start the timer", screen: .recipe) == .startTimer)
    }

    @Test func homeStillStartsADishByName() {
        #expect(VoiceCommand.parse("make the rice", screen: .recipes) == .makeRecipe("Rice"))
        #expect(VoiceCommand.parse("let's do pasta", screen: .recipes, book: DemoBook.voice) == .makeRecipe("Garlic Butter Pasta"))
    }

    @Test func everyNewScreensSayLineWorksThere() {
        #expect(AppScreen.sayPhrases(screen: .recipe) == ["start cooking", "back"])
        #expect(AppScreen.sayPhrases(screen: .makeVoice) == ["use my voice", "done"])
        for screen in AppScreen.allCases {
            for phrase in AppScreen.sayPhrases(screen: screen) {
                #expect(VoiceCommand.parse(phrase, screen: screen) != nil, "\(phrase) on \(screen)")
            }
        }
    }

    @Test func everyDishHasItsFixedPhotoName() {
        for id in DemoBook.ids { #expect(RecipeIndex.bundled.entry(id: id)?.hasPhoto == true, "\(id)") }
        #expect(DemoBook.recipes.map(\.photoName) == [
            "dish-garlic-butter-pasta", "dish-rice", "dish-hard-boiled-eggs",
            "dish-oatmeal", "dish-steamed-broccoli", "dish-pan-seared-chicken",
        ])
        #expect(Recipe.all.map(\.menuIndex) == Array(0..<Recipe.all.count))
    }

    @Test func helpPutsTheNewScreensGroupsFirst() {
        #expect(HelpGroup.ordered(for: .recipe).first == .recipes)
        #expect(HelpGroup.ordered(for: .makeVoice).first == .voice)
        for screen in AppScreen.allCases {
            #expect(Set(HelpGroup.ordered(for: screen)) == Set(HelpGroup.allCases), "\(screen)")
        }
    }
}
