import SwiftUI

/// Compact controls for the quieter Overview composition. No cursor or layout hooks.
struct ControlPanelButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: primary ? .medium : .regular))
            .foregroundStyle(primary && isEnabled ? Color(hex: 0x081726) : Brand.textPrimary)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(primary && isEnabled ? Color(hex: 0x58A8F8) : Brand.surfaceSubtle))
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.75 : 1)
    }
}
