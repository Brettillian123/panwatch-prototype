import SwiftUI

/// The camera picture with the pan box, hand joints, and the drawing gesture on top.
struct CameraStage: View {
    let session: CookSession

    var body: some View {
        GeometryReader { proxy in
            let imageRect = aspectFitRect(content: session.frameSize, in: proxy.size)
            ZStack {
                CameraPreview(analyzer: session.camera.analyzer)
                PanOverlay(session: session, imageRect: imageRect)
                    .allowsHitTesting(false)
                if session.isMarkingPan {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(drawGesture(in: imageRect))
                        .accessibilityLabel("Camera picture. Drag a box around the pan.")
                }
            }
        }
    }

    private func drawGesture(in imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                session.draftRegion = NormRect(
                    corner: normalized(value.startLocation, in: imageRect),
                    to: normalized(value.location, in: imageRect)
                )
            }
            .onEnded { value in
                let distance = hypot(value.location.x - value.startLocation.x, value.location.y - value.startLocation.y)
                let end = normalized(value.location, in: imageRect)
                if distance < 16 {
                    // A tap: drop a pan-sized box centered where the finger landed.
                    session.draftRegion = NormRect(center: end, width: 0.3, height: 0.4).atLeast(0.08)
                } else {
                    session.draftRegion = NormRect(corner: normalized(value.startLocation, in: imageRect), to: end)
                        .atLeast(0.08)
                }
            }
    }
}

/// Draws the pan box colored by what the detector is doing, the hand zone, and the hand joints.
struct PanOverlay: View {
    let session: CookSession
    let imageRect: CGRect

    var body: some View {
        // Read observed values here, not inside the Canvas closure, so SwiftUI tracks them.
        let live = session.live
        let marking = session.isMarkingPan
        let box = marking ? session.draftRegion : session.region
        let zone = session.showDebug && !marking ? session.region?.expanded(by: session.settings.handZoneMargin) : nil
        let hands = session.showDebug ? live.hands : []
        let color = marking ? Color.white : PhaseStyle.color(for: live.phase)
        let label = PhaseStyle.label(for: live.phase)
        let rect = imageRect

        Canvas { context, _ in
            if let zone {
                context.stroke(
                    Path(roundedRect: zone.cgRect(in: rect), cornerRadius: 14),
                    with: .color(.white.opacity(0.35)),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 6])
                )
            }
            if let box {
                let boxRect = box.cgRect(in: rect)
                context.stroke(
                    Path(roundedRect: boxRect, cornerRadius: 14),
                    with: .color(color),
                    style: StrokeStyle(lineWidth: 4, dash: marking ? [12, 8] : [])
                )
                if !marking {
                    let y = boxRect.minY > 36 ? boxRect.minY - 18 : boxRect.minY + 18
                    context.draw(
                        Text(label).font(.headline.weight(.semibold)).foregroundStyle(color),
                        at: CGPoint(x: boxRect.midX, y: y)
                    )
                }
            }
            for hand in hands {
                for joint in hand {
                    let point = joint.cgPoint(in: rect)
                    context.fill(
                        Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)),
                        with: .color(live.handInZone ? .yellow : .cyan)
                    )
                }
            }
        }
    }
}

/// Where a picture of `content` size lands inside `container` when scaled to fit,
/// matching the preview's `.resizeAspect`.
func aspectFitRect(content: CGSize, in container: CGSize) -> CGRect {
    guard content.width > 0, content.height > 0 else { return CGRect(origin: .zero, size: container) }
    let scale = min(container.width / content.width, container.height / content.height)
    let size = CGSize(width: content.width * scale, height: content.height * scale)
    return CGRect(
        x: (container.width - size.width) / 2,
        y: (container.height - size.height) / 2,
        width: size.width,
        height: size.height
    )
}

/// A screen point as a normalized image point, clamped to the picture.
func normalized(_ point: CGPoint, in imageRect: CGRect) -> NormPoint {
    guard imageRect.width > 0, imageRect.height > 0 else { return NormPoint(x: 0.5, y: 0.5) }
    return NormPoint(
        x: min(max((point.x - imageRect.minX) / imageRect.width, 0), 1),
        y: min(max((point.y - imageRect.minY) / imageRect.height, 0), 1)
    )
}

extension NormPoint {
    func cgPoint(in imageRect: CGRect) -> CGPoint {
        CGPoint(x: imageRect.minX + x * imageRect.width, y: imageRect.minY + y * imageRect.height)
    }
}

extension NormRect {
    func cgRect(in imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + x * imageRect.width,
            y: imageRect.minY + y * imageRect.height,
            width: width * imageRect.width,
            height: height * imageRect.height
        )
    }
}

/// How each detector phase looks and reads on screen.
enum PhaseStyle {
    static func color(for phase: AdditionDetector.Phase) -> Color {
        switch phase {
        case .disarmed: .gray
        case .warmingUp: .white
        case .watching: .green
        case .handInPan: .yellow
        case .settling: .orange
        case .cooldown: .cyan
        }
    }

    static func label(for phase: AdditionDetector.Phase) -> String {
        switch phase {
        case .disarmed: "Not watching this step"
        case .warmingUp: "Learning the pan"
        case .watching: "Watching"
        case .handInPan: "Hand over the pan"
        case .settling: "Checking the pan"
        case .cooldown: "Spotted it"
        }
    }

    static func symbol(for phase: AdditionDetector.Phase) -> String {
        switch phase {
        case .disarmed: "eye.slash"
        case .warmingUp: "hourglass"
        case .watching: "eye"
        case .handInPan: "hand.raised.fill"
        case .settling: "magnifyingglass"
        case .cooldown: "checkmark.circle.fill"
        }
    }
}
