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

/// A soft ambient glow background — the studio "signature" (purple top-centre,
/// cyan top-right) that makes panels feel lit rather than flat.
struct AmbientBackground: View {
    var body: some View {
        ZStack {
            Brand.panel
            RadialGradient(colors: [Brand.purple.opacity(0.16), .clear],
                           center: .init(x: 0.32, y: -0.08), startRadius: 0, endRadius: 560)
            RadialGradient(colors: [Brand.cyan.opacity(0.10), .clear],
                           center: .init(x: 0.95, y: -0.05), startRadius: 0, endRadius: 460)
        }
        .ignoresSafeArea()
    }
}

/// Primary button — the blue→teal brand gradient + a soft colored shadow, with
/// the studio press-scale. `prominent` makes it full-width and a touch larger for
/// hero/footer CTAs. This is the single primary-CTA identity across the app.
struct BrandButtonStyle: ButtonStyle {
    var enabled: Bool = true
    var prominent: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: prominent ? 15 : 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, prominent ? 22 : 18)
            .padding(.vertical, prominent ? 13 : 10)
            .frame(maxWidth: prominent ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous)
                    .fill(Brand.brand).opacity(enabled ? 1 : 0.45)
            )
            .shadow(color: Brand.blue.opacity(enabled ? (configuration.isPressed ? 0.18 : 0.28) : 0),
                    radius: configuration.isPressed ? 5 : 10, y: configuration.isPressed ? 2 : 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .pointerCursor()
    }
}

/// Hover-lift for clickable cards/rows — a small rise on hover + press-scale.
/// Premium apps give feedback on every target; this is the shared treatment.
struct HoverButtonStyle: ButtonStyle {
    var lift: CGFloat = 2
    func makeBody(configuration: Configuration) -> some View { HoverBody(configuration: configuration, lift: lift) }
    struct HoverBody: View {
        let configuration: Configuration
        let lift: CGFloat
        @State private var hovering = false
        var body: some View {
            configuration.label
                .offset(y: hovering && !configuration.isPressed ? -lift : 0)
                .scaleEffect(configuration.isPressed ? 0.985 : 1)
                .animation(.easeOut(duration: 0.14), value: hovering)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .pointerCursor()
        }
    }
}

/// White filled button with a hairline border — the reference's secondary CTA
/// (e.g. "Configure Scan"). Matches the primary button's height.
struct WhiteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Brand.textPrimary)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).fill(.white)
                    .overlay(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).stroke(Brand.inputBorder, lineWidth: 1))
            )
            .shadow(color: Brand.shadowColor.opacity(0.05), radius: 6, y: 2)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .pointerCursor()
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { GhostBody(configuration: configuration) }
    struct GhostBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false
        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(hovering && isEnabled ? Brand.textPrimary : Brand.textSecondary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: Brand.rSm, style: .continuous)
                        .fill(hovering && isEnabled ? Brand.surfaceSubtle : .clear)
                        .overlay(RoundedRectangle(cornerRadius: Brand.rSm, style: .continuous)
                            .stroke(hovering && isEnabled ? Brand.inputBorder : Brand.border, lineWidth: 1))
                )
                .opacity(isEnabled ? 1 : 0.4)               // visible-but-disabled
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.12), value: hovering)
                .onHover { if isEnabled { hovering = $0 } }
                .pointerCursor()
        }
    }
}

/// The one canonical status/severity pill — single shape, font ramp, and tint.
/// Use `StatusPill(severity:)` for SAFE/REVIEW/RISKY or `StatusPill(_:color:)`
/// for labelled tags (Intel, KEEP, counts).
struct StatusPill: View {
    let text: String
    var color: Color = Brand.textMuted
    init(_ text: String, color: Color = Brand.textMuted) { self.text = text; self.color = color }
    init(severity: Severity) {
        switch severity {
        case .safe:   self.init("Safe", color: Brand.safeCyan)
        case .review: self.init("Review", color: Brand.amber)
        case .risky:  self.init("Risky", color: Brand.danger)
        }
    }
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.13)))
    }
}

/// A byte total that counts up to its value instead of snapping, and re-counts
/// whenever the value changes (so a clean visibly drops the number). Tabular
/// figures keep it from jittering mid-roll. Honors Reduce Motion.
struct CountingSize: View {
    let bytes: Int64
    var size: CGFloat = 34
    var weight: Font.Weight = .bold
    var color: Color = Brand.textPrimary

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // `Animatable` on the inner view is what makes the digits interpolate —
        // a plain Text can't be animated by mutating a @State Double.
        RollingBytes(value: appeared || reduceMotion ? Double(bytes) : 0,
                     size: size, weight: weight, color: color)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.9), value: appeared)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.9), value: bytes)
            .onAppear { appeared = true }
    }
}

/// The animatable half of `CountingSize`: SwiftUI interpolates `animatableData`
/// and re-renders the label each frame, producing a real count-up.
private struct RollingBytes: View, Animatable {
    var value: Double
    let size: CGFloat
    let weight: Font.Weight
    let color: Color

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(Fmt.size(Int64(max(0, value))))
            .font(.system(size: size, weight: weight, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1).minimumScaleFactor(0.6)
    }
}

/// Reusable empty/idle state — icon-in-tinted-circle + headline + caption.
struct EmptyState: View {
    let icon: String
    let title: String
    var caption: String = ""
    var tint: Color = Brand.textMuted
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 24, weight: .medium)).foregroundStyle(tint)
                .frame(width: 56, height: 56)
                .background(Circle().fill(tint.opacity(0.10)))
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Brand.textPrimary)
            if !caption.isEmpty {
                Text(caption).font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                    .multilineTextAlignment(.center).frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 44)
    }
}

/// Reusable loading state — consistent spinner + label.
struct LoadingState: View {
    var label: String = "Scanning…"
    var body: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text(label).font(.system(size: 13)).foregroundStyle(Brand.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 44)
    }
}

/// A small colored severity dot with a soft halo.
struct SeverityDot: View {
    let severity: Severity
    var body: some View {
        Circle()
            .fill(severity.color)
            .frame(width: 8, height: 8)
            .shadow(color: severity.color.opacity(0.7), radius: 4)
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
