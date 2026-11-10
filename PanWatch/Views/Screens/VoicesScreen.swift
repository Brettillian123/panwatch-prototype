import AVFoundation
import SwiftUI

/// The voices: what is speaking now, the voices filtered by accent, and the card that opens
/// the make-a-voice sheet. A tap on a row's body uses that voice; its play button only
/// plays a sample. "Next voice" moves the highlight down a row and plays it, so a cook can
/// walk the list hands-free; "use this one" picks it.
struct VoicesScreen: View {
    let session: CookSession
    @State private var filter: VoiceFilter = .all
    /// Nil while the phone is still asking the cook about their Personal Voice.
    @State private var personalStatus: AVSpeechSynthesizer.PersonalVoiceAuthorizationStatus?
    @State private var renaming = false
    @State private var deleting = false
    @State private var newName = ""

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.space16) {
                    ScreenTitle("Voices")
                    NowPlayingCard(session: session)
                    chips
                    if showsNatural, session.naturalState != .ready {
                        NaturalVoicesDownload(session: session)
                    }
                    list
                    makeVoiceCard
                        .padding(.top, Theme.space8)
                }
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, Theme.space24)
                .screenColumn()
            }
            .scrollIndicators(.hidden)
            // "Next voice" may walk past the bottom of the screen or out of the filter.
            .onChange(of: session.highlightedVoiceID) { _, id in
                guard let id else { return }
                if let option = session.voiceOptions.first(where: { $0.id == id }), !filter.contains(option, catalog: fixedPacks) {
                    filter = .all
                }
                withAnimation(Theme.motion) { scroller.scrollTo(id, anchor: .center) }
            }
        }
        .task {
            session.refreshVoices()
            #if DEBUG
            if ScreenshotStage.requested != nil { return }
            #endif
            personalStatus = await Speaker.requestPersonalVoice()
            // A Personal Voice only appears once the cook has allowed it.
            session.refreshVoices()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in
            session.refreshVoices()
        }
        .alert("Rename your voice", isPresented: $renaming) {
            TextField("Name", text: $newName)
                .textInputAutocapitalization(.words)
            Button("Save") { session.renameOwnVoice(newName) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete your voice?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { session.deleteOwnVoice() }
        } message: {
            Text("The recording and the voice made from it are removed from this phone.")
        }
    }

    // MARK: Filter

    private var fixedPacks: Set<String> { Set(VoiceCatalog.voices.map(\.pack)) }

    /// "All", the accents that have voices, "Built in" for Apple's, "Yours" once the cook has one.
    private var filters: [VoiceFilter] {
        let options = session.voiceOptions
        var out: [VoiceFilter] = [.all]
        for accent in VoiceAccent.allCases where options.contains(where: { $0.isNatural && $0.accent == accent }) {
            out.append(.accent(accent))
        }
        if options.contains(where: { !$0.isNatural && !$0.isOwn }) { out.append(.builtIn) }
        if options.contains(where: { VoiceFilter.yours.contains($0, catalog: fixedPacks) }) { out.append(.yours) }
        return out
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.space8) {
                ForEach(filters, id: \.self) { item in
                    FilterChip(title: item.title, isSelected: filter == item) {
                        session.noteTouch()
                        withAnimation(Theme.motion) { filter = item }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private var shown: [VoiceOption] {
        session.voiceOptions.filter { filter.contains($0, catalog: fixedPacks) }
    }

    private var showsNatural: Bool { shown.contains(where: \.isNatural) }

    // MARK: List

    /// The voice speaking now: the one picked, or the best installed when none is.
    private var chosenID: String? { session.voiceID ?? Speaker.best?.identifier }

    @ViewBuilder private var list: some View {
        let options = shown
        let askPersonal = filter == .builtIn && !options.contains(where: \.isPersonal)
        if options.isEmpty && !askPersonal {
            GroupedRows {
                Row(label: "No voices here", detail: "Pick another filter")
            }
        } else {
            // 12 to the play button, its 44, 12 to the name.
            GroupedRows(dividerLeading: 68) {
                ForEach(options) { option in
                    VoiceRow(
                        option: option,
                        caption: caption(option),
                        mark: mark(option),
                        chosen: chosenID == option.id,
                        highlighted: session.highlightedVoiceID == option.id,
                        playing: session.sampleVoiceID == option.id,
                        use: {
                            session.noteTouch()
                            session.useVoice(option)
                        },
                        hear: {
                            session.noteTouch()
                            session.highlightVoice(option.id)
                            if session.sampleVoiceID == option.id {
                                session.stopSample()
                            } else {
                                session.playSample(voiceID: option.id)
                            }
                        }
                    )
                    .contextMenu { menu(for: option) }
                    .id(option.id)
                }
                if askPersonal {
                    personalRow
                }
            }
        }
    }

    /// Accent and character for the natural voices, the region for Apple's.
    private func caption(_ option: VoiceOption) -> String {
        if option.isOwn {
            return ownCaption
        }
        if option.isPersonal { return "Personal Voice" }
        if option.isNatural, let pack = VoiceCatalog.pack(fromID: option.id) {
            let accent = option.accent?.title ?? "American"
            if case .downloading = session.naturalState { return "\(accent) · Downloading" }
            return "\(accent) · \(VoiceCatalog.character(pack: pack))"
        }
        return "\(option.region) · Built in"
    }

    private var ownCaption: String {
        switch session.ownVoice.state {
        case .downloading: "Recorded by you · Downloading"
        case .making: "Recorded by you · Being made"
        case .failed: "Recorded by you · Not ready"
        default: "Recorded by you"
        }
    }

    private func mark(_ option: VoiceOption) -> VoiceMark {
        if chosenID == option.id { return .chosen }
        if option.isNatural {
            switch session.naturalState {
            case .ready: return .none
            case .downloading(let share): return .progress(share)
            case .idle, .failed: return .download
            }
        }
        if option.isOwn {
            switch session.ownVoice.state {
            case .ready: return .none
            case .downloading(let share): return .progress(share)
            case .making: return .working
            case .idle, .failed: return .download
            }
        }
        return .none
    }

    /// A long press on the cook's own voice or one of their mixes: rename, delete, remove.
    @ViewBuilder private func menu(for option: VoiceOption) -> some View {
        if option.isOwn, let saved = session.ownVoice.saved {
            Button("Rename", systemImage: "pencil") {
                session.noteTouch()
                newName = saved.name
                renaming = true
            }
            Button("Delete my voice", systemImage: "trash", role: .destructive) {
                session.noteTouch()
                deleting = true
            }
        } else if isOwnMix(option) {
            Button("Remove this mix", systemImage: "trash", role: .destructive) {
                session.noteTouch()
                session.removeBlend(option)
            }
        }
    }

    private func isOwnMix(_ option: VoiceOption) -> Bool {
        guard option.isNatural, let pack = VoiceCatalog.pack(fromID: option.id) else { return false }
        return !fixedPacks.contains(pack) && option.id != VoiceCatalog.bellaAndSarah.voice.id
    }

    // MARK: Personal Voice

    private var personalRow: some View {
        HStack(spacing: Theme.space12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Personal Voice").font(Theme.bodyStrong).foregroundStyle(Theme.ink)
                Text(personalNote).font(Theme.caption).foregroundStyle(Theme.slate)
            }
            Spacer(minLength: Theme.space8)
            if personalStatus == .notDetermined {
                smallButton("Allow") {
                    Task {
                        personalStatus = await Speaker.requestPersonalVoice()
                        session.refreshVoices()
                    }
                }
            } else if personalStatus == .denied {
                smallButton("Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        }
        .padding(.horizontal, Theme.space16)
        .frame(minHeight: 64)
    }

    /// Every state of the cook's Personal Voice: asking, none made, not allowed, no support.
    private var personalNote: String {
        switch personalStatus {
        case nil: "Asking about Personal Voice"
        case .authorized?: "None on this phone"
        case .denied?: "Not allowed"
        case .unsupported?: "None on this phone"
        default: "Not set up"
        }
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            session.noteTouch()
            action()
        } label: {
            Text(title)
                .font(Theme.bodyStrong)
                .padding(.horizontal, Theme.space16)
                .frame(minHeight: Theme.minTarget)
        }
        .buttonStyle(KitPressStyle(fill: Theme.fill, foreground: Theme.ink))
        .accessibilityLabel(title == "Allow" ? "Allow Personal Voice" : "Open Settings")
    }

    // MARK: Make a voice

    private var makeVoiceCard: some View {
        Button {
            session.noteTouch()
            session.open(.makeVoice)
        } label: {
            HStack(spacing: Theme.space12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 52, height: 52)
                    .background(Theme.card, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Make your own voice").font(Theme.bodyStrong).foregroundStyle(Theme.ink)
                    Text("Blend two, or record yours").font(Theme.caption).foregroundStyle(Theme.slate)
                }
                Spacer(minLength: Theme.space8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityHidden(true)
            }
            .padding(Theme.space12)
            .padding(.trailing, Theme.space8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.blush, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Make your own voice")
        .accessibilityHint("Blend two, or record yours")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Filter

enum VoiceFilter: Hashable {
    case all
    case accent(VoiceAccent)
    case builtIn
    case yours

    var title: String {
        switch self {
        case .all: "All"
        case .accent(let accent): accent.title
        case .builtIn: "Built in"
        case .yours: "Yours"
        }
    }

    /// `catalog`: the packs of the app's own natural voices; any other natural voice is a mix.
    func contains(_ option: VoiceOption, catalog: Set<String>) -> Bool {
        switch self {
        case .all: true
        case .accent(let accent): option.isNatural && option.accent == accent
        case .builtIn: !option.isNatural && !option.isOwn
        case .yours:
            option.isOwn || option.isPersonal
                || (option.isNatural && option.id != VoiceCatalog.bellaAndSarah.voice.id
                    && !catalog.contains(VoiceCatalog.pack(fromID: option.id) ?? ""))
        }
    }
}

// MARK: - Now playing

/// The ink card at the top: the voice in use, or the one sampling, with a pause / play
/// button and a waveform that moves only while audio plays (still with Reduce Motion).
private struct NowPlayingCard: View {
    let session: CookSession

    private var playingID: String? { session.sampleVoiceID }
    private var chosenID: String? { session.voiceID ?? Speaker.best?.identifier }

    private var name: String {
        let id = playingID ?? chosenID
        if let id, let option = session.voiceOptions.first(where: { $0.id == id }) { return option.name }
        return Speaker.voice(for: id)?.name ?? "System voice"
    }

    var body: some View {
        let playing = playingID != nil
        VStack(alignment: .leading, spacing: Theme.space16) {
            HStack(spacing: Theme.space12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(Theme.bodyStrong).foregroundStyle(.white)
                    Text(playing ? "Playing a sample" : "In use").font(Theme.caption).foregroundStyle(Theme.softWhite)
                }
                Spacer(minLength: Theme.space8)
                Button {
                    session.noteTouch()
                    if playing {
                        session.stopSample()
                    } else if let id = chosenID {
                        session.playSample(voiceID: id)
                    }
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 48, height: 48)
                        .background(Color.white, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playing ? "Stop the sample" : "Play a sample of \(name)")
            }
            Waveform(playing: playing)
                .frame(height: 40)
                .accessibilityHidden(true)
        }
        .padding(Theme.margin)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .cardShadow()
        .accessibilityElement(children: .contain)
    }
}

/// Bars of fixed heights; while audio plays each rises and falls on its own beat.
private struct Waveform: View {
    let playing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let heights: [CGFloat] = (0..<40).map { i in
        let x = Double(i)
        return CGFloat(0.3 + 0.7 * abs(sin(x * 1.7) * cos(x * 0.45)))
    }

    var body: some View {
        if playing && !reduceMotion {
            TimelineView(.animation) { context in
                bars(time: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            bars(time: nil)
        }
    }

    private func bars(time: Double?) -> some View {
        GeometryReader { proxy in
            let count = Self.heights.count
            let gap: CGFloat = 3
            let width = max((proxy.size.width - gap * CGFloat(count - 1)) / CGFloat(count), 1)
            HStack(alignment: .center, spacing: gap) {
                ForEach(0..<count, id: \.self) { i in
                    let base = Self.heights[i]
                    let swing = time.map { CGFloat(0.55 + 0.45 * sin($0 * (4 + Double(i % 5)) + Double(i))) } ?? 1
                    Capsule()
                        .fill(playing ? Color.white : Theme.softWhite.opacity(0.5))
                        .frame(width: width, height: max(4, proxy.size.height * base * swing))
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Row

enum VoiceMark: Equatable {
    case none, chosen, download, working
    case progress(Double)
}

/// One voice, 64 tall: a 44 play button that only samples, then a body that uses the voice
/// (name, one caption line, one state mark). The row "next voice" stopped on is shaded.
private struct VoiceRow: View {
    let option: VoiceOption
    let caption: String
    let mark: VoiceMark
    let chosen: Bool
    let highlighted: Bool
    let playing: Bool
    let use: () -> Void
    let hear: () -> Void

    var body: some View {
        HStack(spacing: Theme.space12) {
            RoundIconButton(
                systemImage: playing ? "pause.fill" : "play.fill",
                label: playing ? "Stop \(option.name)" : "Play a sample of \(option.name)",
                style: playing ? .beet : .sky,
                action: hear
            )
            Button(action: use) {
                HStack(spacing: Theme.space12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.name).font(Theme.bodyStrong).foregroundStyle(Theme.ink).lineLimit(1)
                        Text(caption).font(Theme.caption).foregroundStyle(Theme.slate).lineLimit(1)
                    }
                    Spacer(minLength: Theme.space8)
                    StateMark(mark: mark)
                }
                .frame(maxWidth: .infinity, minHeight: 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(chosen ? option.name : "Use \(option.name)")
            .accessibilityValue(chosen ? "In use, \(caption)" : caption)
            .accessibilityAddTraits(chosen ? .isSelected : [])
        }
        .padding(.leading, Theme.space12)
        .padding(.trailing, Theme.space16)
        .background(highlighted ? Theme.fill : Color.clear)
    }
}

private struct StateMark: View {
    let mark: VoiceMark

    var body: some View {
        Group {
            switch mark {
            case .none:
                EmptyView()
            case .chosen:
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Theme.beet, in: Circle())
            case .download:
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.slate)
                    .frame(width: 28, height: 28)
            case .working:
                ProgressView()
                    .tint(Theme.beet)
                    .frame(width: 28, height: 28)
            case .progress(let share):
                ZStack {
                    Circle().stroke(Theme.fill, lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: max(0.04, min(share, 1)))
                        .stroke(Theme.beet, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 24, height: 24)
                .frame(width: 28, height: 28)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Download

/// The natural voices' one-time download, in a card: not started, under way, stopped.
/// Nothing once ready. The make-a-voice sheet shows it too, since blending needs them.
struct NaturalVoicesDownload: View {
    let session: CookSession

    var body: some View {
        switch session.naturalState {
        case .ready:
            EmptyView()
        case .idle:
            Card {
                VStack(alignment: .leading, spacing: Theme.space12) {
                    Text("Natural voices need a one-time download, about 230 MB, on Wi-Fi.")
                        .font(Theme.body).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    QuietButton(title: "Download", systemImage: "arrow.down.to.line") {
                        session.noteTouch()
                        session.prepareNaturalVoices()
                    }
                }
            }
        case .downloading(let share):
            Card {
                VStack(alignment: .leading, spacing: Theme.space12) {
                    Text(share < 0.99 ? "Downloading natural voices" : "Getting the voices ready")
                        .font(Theme.body).foregroundStyle(Theme.ink)
                    VoiceProgressBar(share: share)
                    Text("\(Int(share * 100))% · about 230 MB")
                        .font(Theme.caption).foregroundStyle(Theme.slate).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        case .failed:
            Card {
                VStack(alignment: .leading, spacing: Theme.space12) {
                    Text("The download stopped.").font(Theme.body).foregroundStyle(Theme.ink)
                    QuietButton(title: "Try again", systemImage: "arrow.clockwise") {
                        session.noteTouch()
                        session.prepareNaturalVoices()
                    }
                }
            }
        }
    }
}

/// A 6 tall capsule track in ink 7 % with a beet fill for the share done.
struct VoiceProgressBar: View {
    let share: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fill)
                Capsule().fill(Theme.beet).frame(width: proxy.size.width * CGFloat(max(0, min(share, 1))))
            }
        }
        .frame(height: 6)
        .animation(Theme.motion, value: share)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(share * 100)) percent")
    }
}

#Preview {
    VoicesScreen(session: CookSession())
        .background(Theme.ground)
}
