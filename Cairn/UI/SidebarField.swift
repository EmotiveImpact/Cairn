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
    fileprivate static let spacing: CGFloat = 5
    /// Strongest dot at the very bottom, as in the mock (drawn at 2x).
    private var maxOpacity: Double { displayScale < 2 ? 0.55 : 0.42 }
    private var sizeBoost: CGFloat { displayScale < 2 ? 1.3 : 1 }
    /// Still when motion is reduced or the window is in the background, to save battery.
    private var still: Bool { reduceMotion || activeState == .inactive }

    /// The dot layout is worked out once per size and level; each frame only
    /// recomputes the glow, which keeps the idle cost low.
    @State private var layout = DotLayout()
    /// When the dots last started to appear: on launch and whenever the level changes.
    @State private var revealStart = Date()
    @State private var revealing = true
    private static let revealLength: TimeInterval = 3.9

    var body: some View {
        // Smooth while the dots appear, then eight frames a second is plenty for a slow glow.
        TimelineView(.animation(minimumInterval: revealing ? 1.0 / 30 : 1.0 / 8, paused: still)) { timeline in
            let time = still ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let sinceReveal = still ? .infinity : timeline.date.timeIntervalSince(revealStart)
            let maxOpacity = self.maxOpacity, sizeBoost = self.sizeBoost, reach = Self.reach(for: readyBytes)
            Canvas { context, size in
                for dot in layout.dots(size: size, reach: reach, maxOpacity: maxOpacity, sizeBoost: sizeBoost) {
                    // Appear from the bottom up: each dot fades in and grows to size on its own cue.
                    let p = min(1, max(0, (sinceReveal - dot.delay) / 1.4))
                    guard p > 0 else { continue }
                    let eased = 1 - pow(1 - p, 3)
                    var opacity = dot.opacity * eased
                    // Each dot breathes on its own slow beat.
                    if time != 0 { opacity *= 0.75 + 0.25 * sin(time * dot.speed + dot.phase) }
                    let rect = eased < 1 ? dot.rect.insetBy(dx: dot.rect.width * (1 - eased) * 0.35,
                                                            dy: dot.rect.height * (1 - eased) * 0.35) : dot.rect
                    context.fill(Path(ellipseIn: rect), with: .color(Self.dot.opacity(opacity)))
                }
            }
        }
        .task(id: Self.reach(for: readyBytes)) {
            revealStart = Date()
            revealing = true
            try? await Task.sleep(for: .seconds(Self.revealLength))
            revealing = false
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    struct Dot { let rect: CGRect; let opacity: Double; let speed: Double; let phase: Double; let delay: Double }

    final class DotLayout {
        private var key: [Double] = []
        private var cached: [Dot] = []

        func dots(size: CGSize, reach: CGFloat, maxOpacity: Double, sizeBoost: CGFloat) -> [Dot] {
            let newKey: [Double] = [Double(size.width), Double(size.height), Double(reach), maxOpacity, Double(sizeBoost)]
            if newKey == key { return cached }
            key = newKey
            cached = []
            let cols = Int(size.width / SidebarSpaceField.spacing)
            let rows = Int(size.height * reach / SidebarSpaceField.spacing)
            guard rows > 0 else { return cached }
            for row in 0...rows {
                let y = size.height - 3 - CGFloat(row) * SidebarSpaceField.spacing
                let fade = 1 - Double(row) / Double(rows)   // 1 at the bottom, 0 at the top
                for col in 0..<cols {
                    // Fewer dots higher up, so the top edge breaks up softly.
                    guard noise(col, row) < 0.05 + 0.85 * fade else { continue }
                    let opacity = min(maxOpacity, maxOpacity * fade * (0.55 + 0.6 * noise(row, col + 97)))
                    guard opacity > 0.015 else { continue }
                    let x = 3 + CGFloat(col) * SidebarSpaceField.spacing
                    let r: CGFloat = (noise(col + 31, row + 7) > 0.7 ? 1.25 : 0.85) * sizeBoost
                    cached.append(Dot(rect: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2),
                                      opacity: opacity,
                                      speed: 2 * .pi / (2.8 + 3.2 * noise(col + 13, row + 41)),
                                      phase: 2 * .pi * noise(col + 59, row + 3),
                                      // Lower rows first, with a little scatter so it doesn't read as a wipe.
                                      delay: 0.15 + 1.8 * (1 - fade) + 0.45 * noise(col + 71, row + 19)))
                }
            }
            return cached
        }

        private func noise(_ a: Int, _ b: Int) -> Double { SidebarSpaceField.noise(a, b) }
    }

    /// Fixed pseudo-random value in 0..<1, so the pattern is the same every launch.
    fileprivate static func noise(_ a: Int, _ b: Int) -> Double {
        var h = UInt64(truncatingIfNeeded: (a &* 73_856_093) ^ (b &* 19_349_663))
        h ^= h >> 33; h &*= 0xff51afd7ed558ccd; h ^= h >> 33
        return Double(h % 10_000) / 10_000
    }
}
