import SwiftUI
import AppKit

/// Games (games.png): every game the scan found, with its launcher and when
/// it was last played. A game whose launcher is gone can go to the Bin through
/// the normal review; the rest are removed in their own launcher.
struct GamesWorkspace: View {
    let store: ScanStore
    var onReview: () -> Void
    var onOpen: (NavSection) -> Void
    @State private var focused: UUID?
    private let preview = CommandLine.arguments.contains("--preview-ui")
    private typealias Key = GamesScanner.Key

    private var games: [ScanItem] {
        let found = preview ? Self.sample : (store.buckets.first { $0.id == "games" }?.items ?? [])
        return found.sorted { a, b in
            if canBin(a) != canBin(b) { return canBin(a) }
            return a.allocatedSize > b.allocatedSize
        }
    }
    private func canBin(_ game: ScanItem) -> Bool { game.isActionable }

    var body: some View {
        let games = games
        let total = games.reduce(Int64(0)) { $0 + $1.allocatedSize }
        let binnable = games.filter(canBin)
        let left = binnable.reduce(Int64(0)) { $0 + $1.allocatedSize }
        let focus = games.first { $0.id == focused } ?? binnable.first ?? games.first
        NightHeroPage(eyebrow: "Apps · Games",
                      lead: "Steam, Epic and CrossOver games live outside Applications, so they stay behind when the launcher goes.") {
            NightHeroNumber(number: Fmt.size(total), label: "of games")
        } trailing: {
            Button { if store.isScanning { store.cancel() } else { store.rescan() } } label: {
                Label(store.isScanning ? "Stop scan" : "Rescan", systemImage: store.isScanning ? "stop.circle" : "arrow.clockwise")
            }
            .buttonStyle(ControlPanelButtonStyle(size: .small))
            .disabled(preview || store.isCleaning)
        } content: {
            if games.isEmpty {
                empty
            } else {
                NightList { ForEach(games) { row($0, focused: $0.id == focus?.id) } }
            }
        } footer: {
            if left > 0 {
                NightTotal(strong: Fmt.size(left), rest: binnable.allSatisfy { $0.detail[Key.launcherGone] == "1" }
                           ? "left behind by a launcher you removed" : "left behind by uninstalls", large: true)
            } else if total > 0 {
                NightTotal(strong: Fmt.size(total), rest: "of games · remove them in their launcher", large: true)
            }
            Spacer()
            if let focus {
                Button("Show in Finder") { if !preview { NSWorkspace.shared.activateFileViewerSelecting([focus.resolvedURL]) } }
                    .buttonStyle(ControlPanelButtonStyle(size: .large))
                primary(focus)
            }
        }
    }

    // MARK: Rows

    private func row(_ game: ScanItem, focused isFocused: Bool) -> some View {
        let name = game.detail[Key.name] ?? game.url.lastPathComponent
        let launcher = game.detail[Key.launcher] ?? ""
        return Button { focused = game.id } label: {
            HStack(spacing: 16) {
                NightName(logo: nil, title: name, subtitle: subtitle(game, launcher: launcher), symbol: "gamecontroller", titleSize: 13.5)
                Text(launcher).font(.system(size: 12)).foregroundStyle(Brand.textMuted).lineLimit(1)
                    .frame(width: 110, alignment: .leading)
                Text(played(game)).font(.system(size: 12)).foregroundStyle(Brand.textMuted).lineLimit(1)
                    .frame(width: 140, alignment: .leading)
                Text(Fmt.size(game.allocatedSize)).font(.system(size: 13.5, weight: .medium)).monospacedDigit()
                    .frame(width: 70, alignment: .trailing)
                pill(game, launcher: launcher).frame(width: 120, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .nightHeroRow()
        .background {
            if isFocused {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(canBin(game) ? Brand.amber.opacity(0.05) : Brand.wash(0.035))
            }
        }
        .help(game.note)
        .accessibilityAddTraits(isFocused ? .isSelected : [])
    }

    private func subtitle(_ game: ScanItem, launcher: String) -> String {
        if canBin(game) { return game.resolvedURL.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
        switch launcher {
        case "Download": return "Downloaded"
        case "CrossOver": return "CrossOver bottle"
        default: return "Installed with \(launcher)"
        }
    }

    private func lastPlayed(_ game: ScanItem) -> Date? {
        game.detail[Key.lastPlayed].flatMap { Double($0) }.map { Date(timeIntervalSince1970: $0) }
    }

    private func played(_ game: ScanItem) -> String {
        guard let date = lastPlayed(game) else { return "Not known" }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if canBin(game) {
            let format = DateFormatter()
            format.dateFormat = days < 300 ? "MMMM" : "MMMM yyyy"
            return "Not played since \(format.string(from: date))"
        }
        if days < 1 { return "Played today" }
        if days == 1 { return "Played yesterday" }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .full
        return relative.localizedString(for: date, relativeTo: Date())
    }

    @ViewBuilder private func pill(_ game: ScanItem, launcher: String) -> some View {
        if game.detail[Key.launcherGone] == "1" {
            NightPill(text: "\(launcher) is gone", tone: .warn)
        } else if game.detail[Key.leftBehind] == "1" {
            NightPill(text: "Left behind", tone: .warn)
        } else if let date = lastPlayed(game) {
            NightPill(text: Date().timeIntervalSince(date) <= 30 * 86_400 ? "Playing" : "Idle")
        }
    }

    // MARK: Actions

    /// Bin when the launcher is gone; otherwise the launcher's own uninstall.
    @ViewBuilder private func primary(_ game: ScanItem) -> some View {
        let name = game.detail[Key.name] ?? game.url.lastPathComponent
        let launcher = game.detail[Key.launcher] ?? ""
        if canBin(game) {
            Button("Move \(name) to the Bin") { review(game) }
                .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
                .disabled(!preview && (store.isScanning || store.isCleaning))
        } else if let link = game.detail[Key.uninstallURL], let url = URL(string: link) {
            Button("Uninstall in \(launcher)") { if !preview { NSWorkspace.shared.open(url) } }
                .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
        } else if launcher == "App Store" || launcher == "Download" {
            Button("Remove in Apps") { onOpen(.apps) }
                .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
        } else if let app = Self.launcherApp(launcher) {
            Button("Open \(launcher)") { if !preview { NSWorkspace.shared.open(app) } }
                .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
        }
    }

    static func launcherApp(_ launcher: String) -> URL? {
        let names = ["Steam": "Steam.app", "Epic Games": "Epic Games Launcher.app", "CrossOver": "CrossOver.app"]
        guard let file = names[launcher] else { return nil }
        return [URL(fileURLWithPath: "/Applications"), FileScan.home.appendingPathComponent("Applications")]
            .map { $0.appendingPathComponent(file) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Just this game, through the normal review and the safety checks.
    private func review(_ game: ScanItem) {
        guard !preview else { return }
        store.clearSelection()
        store.select { item, _ in item.id == game.id }
        if store.selectedCount > 0 { onReview() }
    }

    @ViewBuilder private var empty: some View {
        if store.isScanning {
            NightEmpty(title: "Looking for games", message: "Steam, Epic, CrossOver and the games in Applications.", busy: true)
        } else if !store.hasScanned {
            NightEmpty(title: "Nothing scanned yet", message: "Press Rescan to find the games on this Mac. Nothing is removed until you review it.")
        } else {
            NightEmpty(title: "No games found", message: "The last scan found no Steam, Epic or CrossOver games, and no games in Applications.")
        }
    }

    /// The approved picture's numbers. Preview only; never acted on.
    private static let sample: [ScanItem] = {
        func game(_ name: String, _ launcher: String, _ daysAgo: Double, _ gb: Double, gone: Bool = false) -> ScanItem {
            var item = ScanItem(url: FileScan.home.appendingPathComponent("Library/Application Support/Steam/steamapps/common/" + name), allocatedSize: Int64(gb * 1_000_000_000),
                                categoryID: "games", severity: .review, isRegenerable: false, cleanMethod: gone ? .trash : .adviceOnly)
            item.detail = [Key.name: name, Key.launcher: launcher,
                           Key.lastPlayed: String(Int(Date().timeIntervalSince1970 - daysAgo * 86_400))]
            if gone { item.detail[Key.launcherGone] = "1" }
            return item
        }
        return [game("BeamNG.drive", "Steam", 220, 57, gone: true), game("Baldur's Gate 3", "Steam", 1, 122),
                game("Fortnite", "Epic Games", 120, 38), game("Cyberpunk 2077", "App Store", 14, 71),
                game("Elden Ring", "CrossOver", 240, 49)]
    }()
}
