import SwiftUI

/// Soft blue dots rising from the foot of the sidebar. The more space is
/// ready to free, the higher they reach. Static: it never moves on its own.
struct SidebarSpaceField: View {
    let readyBytes: Int64

    /// Share of the sidebar's height the dots reach, in five steps.
    static func reach(for bytes: Int64) -> CGFloat {
        let gb = Double(bytes) / 1_000_000_000
        switch gb {
        case ..<0.05: return 0.05   // nothing to free
        case ..<5:    return 0.12
        case ..<20:   return 0.24
        case ..<50:   return 0.38
        default:      return 0.52
        }
    }

    private static let dot = Color(red: 0x5d / 255, green: 0x9b / 255, blue: 0xff / 255)
    private static let spacing: CGFloat = 7
    private static let maxOpacity = 0.55
    /// The Settings row: 10 pt bottom padding plus a 39 pt row, 11 pt in from each side.
    private static let settingsInset = (bottom: CGFloat(10), height: CGFloat(39), side: CGFloat(11))

    var body: some View {
        Canvas { context, size in
            let inset = Self.settingsInset
            // Measured from the top of the Settings row, so even the lowest level shows.
            let base = inset.bottom + inset.height
            let reach = base + (size.height - base) * Self.reach(for: readyBytes)
            let cols = Int(size.width / Self.spacing)
            let rows = Int(reach / Self.spacing)
            let baseRow = base / Self.spacing
            let settings = CGRect(x: inset.side, y: size.height - inset.bottom - inset.height,
                                  width: size.width - inset.side * 2, height: inset.height)
            for row in 0...rows {
                let y = size.height - Self.spacing / 2 - CGFloat(row) * Self.spacing
                // Full strength up to the top of Settings, then fading upward.
                let rise = CGFloat(row) <= baseRow ? 1
                    : 1 - Double(CGFloat(row) - baseRow) / Double(max(CGFloat(rows) - baseRow, 1))
                for col in 0..<cols {
                    let x = Self.spacing / 2 + CGFloat(col) * Self.spacing
                    let noise = Self.noise(col, row)
                    // Thin out towards the top so the edge breaks up softly.
                    guard noise < 0.35 + 0.6 * rise else { continue }
                    var opacity = Self.maxOpacity * pow(rise, 1.6) * (0.45 + 0.55 * Self.noise(row, col + 97))
                    if settings.insetBy(dx: -4, dy: -4).contains(CGPoint(x: x, y: y)) { opacity *= 0.12 }
                    guard opacity > 0.02 else { continue }
                    let r = CGFloat(0.8 + 0.5 * Self.noise(col + 31, row + 7))
                    context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                 with: .color(Self.dot.opacity(opacity)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Fixed pseudo-random value in 0..<1, so the pattern is the same every launch.
    private static func noise(_ a: Int, _ b: Int) -> Double {
        var h = UInt64(truncatingIfNeeded: a &* 73_856_093 ^ b &* 19_349_663)
        h ^= h >> 33; h &*= 0xff51afd7ed558ccd; h ^= h >> 33
        return Double(h % 10_000) / 10_000
    }
}
