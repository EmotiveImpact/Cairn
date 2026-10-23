import SwiftUI
import AppKit

/// A transparent overlay that installs a pointing-hand cursor rect. Reliable on
/// macOS 13/14 (which have no SwiftUI link-cursor); passes clicks straight
/// through so the underlying button still works.
/// Shows the pointing-hand cursor on hover — macOS controls don't do this by
/// default, so links and clickable rows/cards feel properly interactive.
///
/// IMPORTANT: this is deliberately plain SwiftUI. An earlier `NSViewRepresentable`
/// version installed an NSTrackingArea in `updateTrackingAreas()`; mutating
/// tracking areas triggers layout, which calls `updateTrackingAreas()` again —
/// an infinite layout/render loop. Applied to ~25 sites it pinned the main thread
/// inside SwiftUI's run-loop observer and froze navigation across the whole app.
/// `onHover` costs nothing and cannot feed back into layout.
struct PointerCursor: ViewModifier {
    func body(content: Content) -> some View {
        // Currently a NO-OP, deliberately. Two implementations of the pointing-hand
        // cursor each caused a runaway main-thread loop:
        //
        //  1. An NSViewRepresentable installing an NSTrackingArea in
        //     `updateTrackingAreas()` — mutating tracking areas triggers layout,
        //     which calls `updateTrackingAreas()` again.
        //  2. `onHover { NSCursor.pointingHand.push() / .pop() }` — pushing a cursor
        //     provokes an AppKit cursor-update, which SwiftUI surfaces as another
        //     hover change, which pushes again. With ten always-visible sidebar rows
        //     this pinned the CPU at 100% and froze navigation app-wide.
        //
        // The call sites are kept so the intent (and the fix location) is obvious.
        // Revisit with `.onContinuousHover` and a single owner for cursor state.
        content
    }
}
extension View { func pointerCursor() -> some View { modifier(PointerCursor()) } }

/// UI-layer mappings that depend on SwiftUI (kept out of the Foundation models).
extension Severity {
    var color: Color {
        switch self {
        case .safe: return Brand.safeCyan
        case .review: return Brand.amber
        case .risky: return Brand.danger
        }
    }
    var tint: Color { color }
}

extension CategoryGroup {
    var title: String {
        switch self {
        case .developer: return "Developer"
        case .ai: return "AI Models & Caches"
        case .creative: return "Creative Pro"
        case .general: return "General"
        }
    }
}

/// Compatibility entry points share the approved component surface.
struct BrandButtonStyle: ButtonStyle {
    var enabled = true
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        CairnControlSurface(label: configuration.label, primary: true, pressed: configuration.isPressed,
                            available: enabled, prominent: prominent)
    }
}
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CairnControlSurface(label: configuration.label, pressed: configuration.isPressed)
    }
}
/// Plain ice text link (card links, Connect). Brightens and underlines on hover.
struct QuietLinkStyle: ButtonStyle {
    var color: Color = Brand.deepBlue
    func makeBody(configuration: Configuration) -> some View { QuietLinkLabel(label: configuration.label, color: color, pressed: configuration.isPressed) }
}
private struct QuietLinkLabel<Label: View>: View {
    let label: Label
    let color: Color
    let pressed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    var body: some View {
        label.foregroundStyle(color.opacity(pressed ? 0.6 : hovered ? 1 : 0.86))
            .underline(hovered, color: color.opacity(0.5))
            .offset(x: hovered && !reduceMotion ? 2 : 0)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovered)
    }
}

/// Reusable card chrome — white, hairline border, soft layered shadow. `level`
/// selects the elevation ramp so cards can sit at distinct depths.
struct CardBackground: View {
    var radius: CGFloat = Brand.rCard
    var level: Elevation = .med
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Brand.surfaceElevated)
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Brand.border, lineWidth: 1))
            .shadow(color: level.color, radius: level.radius, y: level.y)
    }
}

extension View {
    /// Wrap content in a Cairn card (padding + white rounded surface + shadow).
    func cairnCard(_ padding: CGFloat = 16, radius: CGFloat = Brand.rCard, level: Elevation = .med) -> some View {
        self.padding(padding).background(CardBackground(radius: radius, level: level))
    }
}
