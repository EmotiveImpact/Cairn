import SwiftUI

/// "Space Missions" — one-click intents that select the right items across
/// categories, then drop the user into Review. More human than a single Clean
/// button, and they make the three-pillar coverage tangible.
struct Mission: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    /// Mutates the store's selection. The UI then opens the Review sheet.
    let apply: @MainActor (ScanStore) -> Void

    static let all: [Mission] = [
        Mission(id: "fast10", title: "Free 10 GB Fast", subtitle: "Biggest safe wins first",
                systemImage: "bolt.fill", tint: Brand.cyan) { s in
            s.selectSafeUpTo(bytes: 10 * 1024 * 1024 * 1024)
        },
        Mission(id: "dev", title: "Clean Developer Junk", subtitle: "Caches, build artifacts",
                systemImage: "hammer.fill", tint: Brand.purple) { s in
            s.clearSelection()
            s.select { it, g in g == .developer && it.severity == .safe && it.isRegenerable }
        },
        Mission(id: "ai", title: "Clean AI Models", subtitle: "Re-downloadable weights",
                systemImage: "brain.head.profile", tint: Brand.blue) { s in
            s.clearSelection()
            s.select { _, g in g == .ai }
        },
        Mission(id: "creator", title: "Clean Creator Cache", subtitle: "Render & media caches",
                systemImage: "film.fill", tint: Brand.safeCyan) { s in
            s.clearSelection()
            s.select { it, g in g == .creative && it.severity == .safe }
        },
        Mission(id: "giants", title: "Find Forgotten Giants", subtitle: "Everything over 1 GB",
                systemImage: "scalemass.fill", tint: Brand.amber) { s in
            s.clearSelection()
            s.select { it, _ in it.allocatedSize >= 1_000_000_000 }
        },
        Mission(id: "update", title: "Prepare for Update", subtitle: "Clear safe caches for macOS",
                systemImage: "arrow.down.circle.fill", tint: Brand.blue) { s in
            s.clearSelection()
            s.select { it, _ in it.severity == .safe && it.isRegenerable }
        },
        Mission(id: "travel", title: "Prepare for Travel", subtitle: "Reclaim all regenerable space",
                systemImage: "airplane", tint: Brand.purple) { s in
            s.clearSelection()
            s.select { it, _ in it.isRegenerable && (it.severity == .safe || it.severity == .review) }
        },
        Mission(id: "emergency", title: "Emergency Free Space", subtitle: "Maximize, you review first",
                systemImage: "exclamationmark.octagon.fill", tint: Brand.danger) { s in
            s.clearSelection()
            s.select { it, _ in it.isRegenerable }
        },
    ]
}
