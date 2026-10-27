import SwiftUI
import AppKit

/// Chat apps (chat.png): WhatsApp and Telegram measured and pointed to their own
/// storage screens, with Slack, Discord, Teams and Zoom caches beside them.
/// Only the caches that rebuild on their own are offered for review here.
struct ChatAppsWorkspace: View {
    let store: ScanStore
    var onReview: () -> Void
    @State private var explained: String?
    private let preview = CommandLine.arguments.contains("--preview-ui")

    /// One app's findings from every scanner, joined by name.
    struct AppRow: Identifiable {
        let name: String
        var items: [ScanItem]
        var id: String { name }
        var bytes: Int64 { items.reduce(0) { $0 + $1.allocatedSize } }
        /// WhatsApp and Telegram: measured, never cleared by Cairn.
        var advice: ScanItem? { items.first { $0.categoryID == "chat-apps" } }
        var ready: [ScanItem] { items.filter { $0.severity == .safe && $0.isRegenerable && $0.isActionable } }
        var readyBytes: Int64 { ready.reduce(0) { $0 + $1.allocatedSize } }
    }

    /// Scanners whose findings can belong to a chat app.
    private static let sources: Set<String> = ["chat-apps", "comm-caches", "app-caches", "logs"]

    private var rows: [AppRow] {
        if preview { return Self.sample }
        var byApp: [String: [ScanItem]] = [:]
        for bucket in store.buckets where Self.sources.contains(bucket.id) {
            for item in bucket.items {
                if let name = ChatAppsScanner.chatApp(for: item) { byApp[name, default: []].append(item) }
            }
        }
        return byApp.map { AppRow(name: $0.key, items: $0.value) }
            .sorted { ($0.advice != nil) == ($1.advice != nil) ? $0.bytes > $1.bytes : $0.advice != nil }
    }

    var body: some View {
        let rows = rows
        let total = rows.reduce(Int64(0)) { $0 + $1.bytes }
        let ready = rows.reduce(Int64(0)) { $0 + $1.readyBytes }
        let largest = max(1, rows.map(\.bytes).max() ?? 1)
        NightHeroPage(eyebrow: "Clean · Chat apps",
                      lead: "WhatsApp and Telegram keep a copy of everything. Their own storage screens let you choose which chats to trim.") {
            NightHeroNumber(number: Fmt.size(total), label: "in chat apps")
        } trailing: {
            Button { if store.isScanning { store.cancel() } else { store.rescan() } } label: {
                Label(store.isScanning ? "Stop scan" : "Rescan", systemImage: store.isScanning ? "stop.circle" : "arrow.clockwise")
            }
            .buttonStyle(ControlPanelButtonStyle(size: .small))
            .disabled(preview || store.isCleaning)
        } content: {
            if rows.isEmpty {
                empty
            } else {
                NightList {
                    ForEach(rows) { row in
                        rowView(row, share: Double(row.bytes) / Double(largest))
                        if let advice = row.advice, explainedID(rows) == row.id {
                            NightExplain(strong: "Cairn won't clear inside \(row.name)'s folder",
                                         rest: ", because that can sign you out or lose chats. " + (advice.detail[ChatAppsScanner.Key.howTo] ?? ""))
                                .padding(.leading, 34).padding(.bottom, 10)
                        }
                    }
                }
            }
        } footer: {
            NightTotal(strong: Fmt.size(ready), rest: "Cairn can clear safely · \(Fmt.size(total - ready)) needs you", large: true)
            Spacer()
            Button(ready > 0 ? "Review \(Fmt.size(ready))" : "Review") { review(rows) }
                .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
                .disabled(ready == 0 || (!preview && (store.isScanning || store.isCleaning)))
        }
    }

    /// The first app Cairn won't clear shows its explanation until another is picked.
    private func explainedID(_ rows: [AppRow]) -> String? {
        explained ?? rows.first { $0.advice != nil }?.id
    }

    private func rowView(_ row: AppRow, share: Double) -> some View {
        HStack(spacing: 16) {
            Button { explained = row.advice == nil ? explained : row.id } label: {
                NightName(logo: nil, title: row.name, subtitle: line(row), symbol: "bubble.left", titleSize: 13.5)
            }
            .buttonStyle(.plain)
            NightMeter(share: share, width: 140)
            Text(row.advice?.permissionDenied == true && row.bytes == 0 ? "–" : Fmt.size(row.bytes))
                .font(.system(size: 13.5, weight: .medium)).monospacedDigit()
                .frame(width: 70, alignment: .trailing)
            action(row).frame(width: 170, alignment: .trailing)
        }
        .nightHeroRow()
        .contextMenu {
            if let url = row.items.first?.resolvedURL {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.disabled(preview)
            }
        }
    }

    private func line(_ row: AppRow) -> String {
        if let advice = row.advice {
            if advice.permissionDenied && !store.fdaGranted { return "Give Cairn Full Disk Access to measure all of it" }
            return ChatAppsScanner.apps.first { $0.name == row.name }?.line ?? "Photos and videos you've been sent"
        }
        if row.ready.count == row.items.count { return "Cache, rebuilds on its own" }
        return "Cache and logs · some need a look"
    }

    @ViewBuilder private func action(_ row: AppRow) -> some View {
        if row.advice != nil {
            if row.advice?.permissionDenied == true && !store.fdaGranted && !preview {
                Button("Open Settings ↗") { FullDiskAccess.openSettings() }
                    .buttonStyle(.plain).font(.system(size: 13.5)).foregroundStyle(Brand.textPrimary)
            } else {
                Button("Open \(row.name) storage ↗") { open(row) }
                    .buttonStyle(.plain).font(.system(size: 13.5)).foregroundStyle(Brand.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .help("Opens \(row.name). Its storage screen lets you choose which chats to trim.")
            }
        } else {
            let running = RunningApps.displayNames(for: RunningApps.running(amongst: Array(Set(row.items.flatMap(\.requiresQuitBundleIDs)))))
            if let app = running.first { NightPill(text: "Close \(app) first", tone: .warn) }
            else if !row.ready.isEmpty && row.ready.count == row.items.count { NightPill(text: "Ready", tone: .ok) }
            else if !row.ready.isEmpty { NightPill(text: "Part ready", tone: .ok) }
            else { NightPill(text: "Needs you") }
        }
    }

    @ViewBuilder private var empty: some View {
        if store.isScanning {
            NightEmpty(title: "Reading your files", message: "Results appear as the scan goes. Nothing is removed.", busy: true)
        } else if !store.hasScanned {
            NightEmpty(title: "Nothing scanned yet", message: "Press Rescan to measure your chat apps. Nothing is removed until you review it.")
        } else {
            NightEmpty(title: "No chat apps here", message: "The last scan found no WhatsApp, Telegram, Slack, Discord, Teams or Zoom files.")
        }
    }

    private func open(_ row: AppRow) {
        guard !preview, let app = ChatAppsScanner.apps.first(where: { $0.name == row.name }) else { return }
        explained = row.id
        if let url = ChatAppsScanner.installedApp(app) {
            NSWorkspace.shared.open(url)
        } else if let folder = row.advice?.resolvedURL {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        }
    }

    /// The ready caches on this page only, then the normal review.
    private func review(_ rows: [AppRow]) {
        guard !preview else { return }
        let ids = Set(rows.flatMap(\.ready).map(\.id))
        store.clearSelection()
        store.select { item, _ in ids.contains(item.id) }
        if store.selectedCount > 0 { onReview() }
    }

    /// The approved picture's numbers. Preview only; never acted on.
    private static let sample: [AppRow] = {
        func item(_ path: String, _ gb: Double, advice: String? = nil) -> ScanItem {
            var item = ScanItem(url: URL(fileURLWithPath: "/Sample/" + path), allocatedSize: Int64(gb * 1_000_000_000),
                                categoryID: advice == nil ? "comm-caches" : "chat-apps", severity: advice == nil ? .safe : .review,
                                isRegenerable: advice == nil, cleanMethod: advice == nil ? .trash : .adviceOnly)
            if let advice {
                item.detail = [ChatAppsScanner.Key.app: advice,
                               ChatAppsScanner.Key.howTo: ChatAppsScanner.apps.first { $0.name == advice }?.howTo ?? ""]
            }
            return item
        }
        return [AppRow(name: "WhatsApp", items: [item("WhatsApp", 18, advice: "WhatsApp")]),
                AppRow(name: "Telegram", items: [item("Telegram", 11, advice: "Telegram")]),
                AppRow(name: "Slack", items: [item("Slack", 1.4)]),
                AppRow(name: "Discord", items: [item("Discord", 0.62)])]
    }()
}
