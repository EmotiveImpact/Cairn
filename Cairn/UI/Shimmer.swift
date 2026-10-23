import SwiftUI

/// A soft band of light that sweeps across text while work is running, like
/// Claude Code's working line. Colour only: the text never moves or resizes.
/// Still with Reduce Motion, and paused while Cairn is in the background.
struct Shimmer: ViewModifier {
    var active: Bool
    var base: Color = Brand.textMuted
    var light: Color = Brand.room
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState

    /// One sweep takes two seconds, then a short rest.
    private static let sweep: Double = 2.0
    private static let period: Double = 2.6

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: activeState == .inactive)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period)
                let p = min(1, t / Self.sweep)
                // The band is half the text wide and travels from just off the left edge to just off the right.
                let start = -1 + 2 * p
                content.foregroundStyle(LinearGradient(
                    stops: [.init(color: base, location: 0.3), .init(color: light, location: 0.5), .init(color: base, location: 0.7)],
                    startPoint: UnitPoint(x: start, y: 0.5), endPoint: UnitPoint(x: start + 1, y: 0.5)))
            }
        } else {
            content.foregroundStyle(base)
        }
    }
}

extension View {
    func shimmer(_ active: Bool) -> some View { modifier(Shimmer(active: active)) }
}
