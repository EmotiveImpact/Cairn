import SwiftUI

/// Soft blue dots rising from the foot of the sidebar, copied from the approved
/// mock (sidebar-levels.png). The more space is ready to free, the higher they
/// reach. Each dot glows and dims slowly on its own, so the field feels alive
/// without anything sliding; with Reduce Motion it holds still.
struct SidebarSpaceField: View {
    let readyBytes: Int64
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    /// 1 on a standard display, where fine dots need a little more size and strength.
    @Environment(\.displayScale) private var displayScale

    /// Share of the sidebar's height the dots reach, in five steps.
    static func reach(for bytes: Int64) -> CGFloat {
        let gb = Double(bytes) / 1_000_000_000
        switch gb {
        case ..<0.05: return 0.06   // nothing to free
        case ..<5:    return 0.15
        case ..<20:   return 0.25
        case ..<50:   return 0.38
        default:      return 0.52
        }
    }

    private static let dot = Color(red: 0x5d / 255, green: 0x9b / 255, blue: 0xff / 255)
    private static let spacing: CGFloat = 5
    /// Strongest dot at the very bottom, as in the mock (drawn at 2x).
    private var maxOpacity: Double { displayScale < 2 ? 0.55 : 0.42 }
    private var sizeBoost: CGFloat { displayScale < 2 ? 1.3 : 1 }
    /// Still when motion is reduced or the window is in the background, to save battery.
    private var still: Bool { reduceMotion || activeState == .inactive }

    var body: some View {
        // Ten frames a second is plenty for a slow glow and keeps idle CPU low.
        TimelineView(.animation(minimumInterval: 1.0 / 10, paused: still)) { timeline in
            let time = still ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let maxOpacity = self.maxOpacity, sizeBoost = self.sizeBoost
            Canvas { context, size in
                let reach = size.height * Self.reach(for: readyBytes)
                let cols = Int(size.width / Self.spacing)
                let rows = Int(reach / Self.spacing)
                guard rows > 0 else { return }
                for row in 0...rows {
                    let y = size.height - 3 - CGFloat(row) * Self.spacing
                    let fade = 1 - Double(row) / Double(rows)   // 1 at the bottom, 0 at the top
                    for col in 0..<cols {
                        // Fewer dots higher up, so the top edge breaks up softly.
                        guard Self.noise(col, row) < 0.05 + 0.85 * fade else { continue }
                        let x = 3 + CGFloat(col) * Self.spacing
                        var opacity = maxOpacity * fade * (0.55 + 0.6 * Self.noise(row, col + 97))
                        if time != 0 {
                            // Each dot breathes on its own slow beat, between half and full strength.
                            let period = 2.8 + 3.2 * Self.noise(col + 13, row + 41)
                            let phase = 2 * .pi * Self.noise(col + 59, row + 3)
                            opacity *= 0.75 + 0.25 * sin(time * 2 * .pi / period + phase)
                        }
                        guard opacity > 0.015 else { continue }
                        let r: CGFloat = (Self.noise(col + 31, row + 7) > 0.7 ? 1.25 : 0.85) * sizeBoost
                        context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                     with: .color(Self.dot.opacity(min(opacity, maxOpacity))))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Fixed pseudo-random value in 0..<1, so the pattern is the same every launch.
    private static func noise(_ a: Int, _ b: Int) -> Double {
        var h = UInt64(truncatingIfNeeded: (a &* 73_856_093) ^ (b &* 19_349_663))
        h ^= h >> 33; h &*= 0xff51afd7ed558ccd; h ^= h >> 33
        return Double(h % 10_000) / 10_000
    }
}
