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

/// A horizontal strip of mission cards.
struct MissionsBar: View {
    let store: ScanStore
    var onRun: (Mission) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SPACE MISSIONS")
                .font(.system(size: 11, weight: .black)).tracking(1.6)
                .foregroundStyle(Brand.textMuted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: 12)], spacing: 12) {
                ForEach(Mission.all) { mission in
                    MissionCard(mission: mission) { onRun(mission) }
                }
            }
        }
    }
}

private struct MissionCard: View {
    let mission: Mission
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: mission.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(mission.tint)
                Spacer(minLength: 0)
                Text(mission.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Brand.textPrimary)
                    .lineLimit(1)
                Text(mission.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.textMuted)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Brand.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(hovering ? mission.tint.opacity(0.5) : Brand.border, lineWidth: 1)
                    )
            )
            .offset(y: hovering ? -2 : 0)
        }
        .buttonStyle(.plain).pointerCursor()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}
