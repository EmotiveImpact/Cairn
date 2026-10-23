import SwiftUI

/// The established Cairn toolbar mark. Keep its blue tone fixed; the colourful
/// application tile belongs in the Dock, not inside the window chrome.
struct CairnLogo: View {
    var size: CGFloat = 34
    var monochrome = false
    /// Scan progress, 0 to 1, while a scan runs: the stones go on one at a
    /// time from the bottom, the next one waiting faintly. Nil shows the whole stack.
    var building: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Stones from the bottom that are in place.
    private var placed: Int {
        guard let building, !reduceMotion else { return 4 }
        return min(3, max(0, Int(building * 4)))
    }

    var body: some View {
        // Every stone keeps its place in the stack, so nothing beside the logo moves.
        VStack(spacing: size * 0.035) {
            stone(3, width: 0.24, height: 0.12)
            stone(2, width: 0.40, height: 0.15)
            stone(1, width: 0.56, height: 0.18)
            stone(0, width: 0.74, height: 0.23)
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.8), value: placed)
    }

    private func stone(_ level: Int, width: CGFloat, height: CGFloat) -> some View {
        let state = level < placed ? 1.0 : level == placed ? 0.55 : 0
        return Ellipse()
            .fill(monochrome ? AnyShapeStyle(Color.black) : AnyShapeStyle(
                LinearGradient(colors: [Color(red: 0.57, green: 0.79, blue: 0.98), Brand.blue], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .frame(width: size * width, height: size * height)
            .opacity(state)
            // A stone settles from just above its place.
            .offset(y: state == 1 ? 0 : -size * 0.06)
    }
}
