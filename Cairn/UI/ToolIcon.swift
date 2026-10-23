import SwiftUI
import AppKit

/// A soft rounded tinted tile holding an SF symbol — the premium "app-icon-ish"
/// treatment used across headers, rows, and cards.
struct IconTile: View {
    var systemImage: String
    var tint: Color = Brand.blue
    var size: CGFloat = 40
    var glyphScale: CGFloat = 0.46

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(tint.opacity(0.12))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: size * glyphScale, weight: .semibold))
                    .foregroundStyle(tint)
            )
    }
}
