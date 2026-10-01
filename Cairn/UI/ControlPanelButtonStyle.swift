import SwiftUI

/// Approved component treatment, shared by workspaces, sheets and legacy CTAs.
/// Feedback changes the surface only; labels never shrink or move.
struct ControlPanelButtonStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        CairnControlSurface(label: configuration.label, primary: primary, pressed: configuration.isPressed)
    }
}

struct CairnControlSurface<Label: View>: View {
    let label: Label
    var primary = false
    var pressed = false
    var available = true
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovered = false
    private var enabled: Bool { isEnabled && available }
    var body: some View {
        label.font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 13).frame(minHeight: 32)
            .frame(maxWidth: prominent ? .infinity : nil)
            .foregroundStyle(primary && enabled ? Color.white : Brand.textPrimary)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(primary && enabled ? AnyShapeStyle(Brand.brand) : AnyShapeStyle(Color.white.opacity(hovered && enabled ? 0.10 : 0.065)))
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(enabled && (pressed || (primary && hovered)) ? 0.06 : 0))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(.white.opacity(contrast == .increased ? 0.45 : primary && enabled ? 0.14 : 0.06), lineWidth: 0.5)
            }
            .opacity(enabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
    }
}

/// Native menu pickers retain their keyboard and accessibility behaviour.
struct CairnFilterSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.pickerStyle(.menu).buttonStyle(.plain).controlSize(.regular)
            .padding(.leading, 8).padding(.trailing, 22).frame(minHeight: 32)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .trailing) { Image(systemName: "chevron.down").font(.system(size: 9, weight: .medium)).foregroundStyle(Brand.textMuted).padding(.trailing, 9).allowsHitTesting(false).accessibilityHidden(true) }
    }
}
extension View {
    func cairnFilterSurface() -> some View { modifier(CairnFilterSurface()) }
}
