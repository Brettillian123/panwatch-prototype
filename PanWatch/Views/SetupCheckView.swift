import SwiftUI

/// The setup check inside the camera box: a small card at the box's bottom with what to do
/// now in a caption line, a thin line for the seconds left, and Skip. "Ready" shows there
/// too, with OK. A warning (too dark, a hand in view, flicker) is `SetupCheckNotice`, in
/// the right column. Nothing shows when no check is running or showing its result.
struct SetupCheckView: View {
    let check: SetupCheck

    var body: some View {
        switch check.stage {
        case .idle:
            EmptyView()
        case .still:
            card(text: "Keep your hands away, checking the light", running: true)
        case .hand:
            card(text: "Now hold one hand over the pot", running: true)
        case .done(let result):
            if result.fix == nil {
                card(text: "Ready. Detection is set for this kitchen.", running: false)
            }
        }
    }

    private func card(text: String, running: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.space8) {
            HStack(spacing: Theme.space8) {
                Text(text)
                    .font(Theme.cookCaption)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(running ? "Skip" : "OK") {
                    if running { check.skip() } else { check.dismiss() }
                }
                .font(Theme.cookCaption.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .frame(minWidth: Theme.minTarget, minHeight: Theme.minTarget)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .accessibilityLabel(running ? "Skip the check" : "OK")
            }
            if running {
                TimelineView(.animation) { context in
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.divider)
                            Capsule().fill(Theme.beet)
                                .frame(width: proxy.size.width * min(max(check.progress(at: context.date), 0), 1))
                        }
                    }
                    .frame(height: 3)
                }
                .accessibilityHidden(true)
            }
        }
        .padding(.leading, Theme.space12)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusField, style: .continuous))
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .transition(.opacity)
    }
}

/// A setup check warning, one caption line in ink on blush above the cook screen's buttons,
/// with OK. Only when the check finished with something to fix.
struct SetupCheckNotice: View {
    let check: SetupCheck

    var body: some View {
        if case .done(let result) = check.stage, let fix = result.fix {
            HStack(spacing: Theme.space8) {
                Text("\(fix.title). \(fix.fix)")
                    .font(Theme.cookCaption)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("OK") { check.dismiss() }
                    .font(Theme.cookCaption.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(minWidth: Theme.minTarget, minHeight: Theme.minTarget)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
            }
            .padding(.leading, Theme.space12)
            .frame(height: 36)
            .background(Theme.blush, in: Capsule(style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }
}
