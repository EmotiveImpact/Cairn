import SwiftUI
import AppKit

/// Native, compact Developer review. Each row is built from the existing scan
/// store; selection still flows into the established ReviewSheet and cleaner.
struct DeveloperCleanupView: View {
    let store: ScanStore
    var section: NavSection = .developer
    var searchText: String = ""
    @Binding var inspectorVisible: Bool
    var onReview: () -> Void

    @State private var expandedBuckets: Set<String> = []
    @State private var previewBuckets = DeveloperCleanupView.makePreviewBuckets()
    private let previewMode = CommandLine.arguments.contains("--preview-ui")

    private var sourceBuckets: [ScanStore.Bucket] {
        previewMode ? previewBuckets : section.buckets(store)
    }

    private struct VisibleBucket: Identifiable {
        let bucket: ScanStore.Bucket
        var items: [ScanItem]
        var id: String { bucket.id }
        var bytes: Int64 { items.reduce(0) { $0 + $1.allocatedSize } }
    }

    private var visibleBuckets: [VisibleBucket] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let found: [VisibleBucket] = sourceBuckets.compactMap { bucket in
            guard !bucket.items.isEmpty else { return nil }
            let items: [ScanItem]
            if query.isEmpty || bucket.info.title.localizedCaseInsensitiveContains(query) {
                items = bucket.items
            } else {
                items = bucket.items.filter {
                    $0.url.lastPathComponent.localizedCaseInsensitiveContains(query)
                    || $0.resolvedURL.path.localizedCaseInsensitiveContains(query)
                }
            }
            guard !items.isEmpty else { return nil }
            return VisibleBucket(bucket: bucket, items: items.sorted { $0.allocatedSize > $1.allocatedSize })
        }
        return found.sorted { $0.bytes > $1.bytes }
    }
    private var largestBytes: Int64 { max(1, visibleBuckets.first?.bytes ?? 1) }
    private var pageSelected: [ScanItem] { sourceBuckets.flatMap(\.items).filter(\.selected) }
    private var pageSelectedBytes: Int64 { pageSelected.reduce(0) { $0 + $1.allocatedSize } }
    private var outsideSelectedCount: Int { previewMode ? 0 : max(0, store.selectedCount - pageSelected.count) }

    var body: some View {
        NightPage(eyebrow: eyebrow, title: pageTitle, subtitle: headerSubtitle) {
            Button { rescan() } label: {
                Label(store.isScanning ? "Stop scan" : "Rescan", systemImage: store.isScanning ? "stop.circle" : "arrow.clockwise")
            }
            .buttonStyle(ControlPanelButtonStyle(size: .small))
            .keyboardShortcut("r", modifiers: .command)
            .disabled((previewMode && !Showcase.active) || store.isCleaning)
        } content: {
            if visibleBuckets.isEmpty {
                emptyState
            } else {
                NightList {
                    ForEach(visibleBuckets) { group in
                        bucketRow(group)
                        if expandedBuckets.contains(group.id) {
                            ForEach(group.items.prefix(60)) { itemRow($0) }
                            if group.items.count > 60 {
                                Text("and \(group.items.count - 60) more").font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                                    .padding(.leading, 36).nightRow()
                            }
                        }
                    }
                }
            }
        } footer: {
            // The same total as the button, including picks on other pages.
            NightTotal(strong: Fmt.size(outsideSelectedCount > 0 ? store.selectedTotal : pageSelectedBytes), rest: footerNote)
            Spacer()
            if pageSelected.isEmpty {
                Button("Select all ready") { selectAllReady() }
                    .buttonStyle(ControlPanelButtonStyle(size: .large))
                    .disabled(!visibleBuckets.contains { $0.items.contains(where: isReady) })
            } else {
                Button("Select none") { clearPageSelection() }
                    .buttonStyle(ControlPanelButtonStyle(size: .large))
            }
            if Showcase.active {
                // The sample ticks live on this page, not in the store.
                Button("Review and free \(Fmt.size(pageSelectedBytes))") { onReview() }
                    .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
                    .disabled(pageSelected.isEmpty)
            } else {
                Button(store.selectedCount == 0 ? "Review and free" : "Review and free \(Fmt.size(store.selectedTotal))") { onReview() }
                    .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
                    .disabled(previewMode || store.selectedCount == 0 || store.isScanning)
            }
        }
        .onAppear { if previewMode && section != .developer { previewBuckets = PreviewLibrary.buckets(section) } }
        .onChange(of: section) { _, value in
            expandedBuckets = []
            if previewMode { previewBuckets = value == .developer ? Self.makePreviewBuckets() : PreviewLibrary.buckets(value) }
        }
    }

    private var footerNote: String {
        var note = "selected"
        if !pageSelected.isEmpty {
            note += pageSelected.allSatisfy(\.isRegenerable) ? " · rebuilt on their own" : " · \(pageSelected.count) items"
        }
        if outsideSelectedCount > 0 { note += " · including \(outsideSelectedCount) from other pages" }
        return note
    }

    // MARK: Header

    private var eyebrow: String {
        if Showcase.active { return "Clean · scanned \(Showcase.scanDate.formatted(.relative(presentation: .named)))" }
        if previewMode { return "Clean · sample results" }
        if store.isScanning { return "Clean · scanning" }
        if store.phase == .cancelled { return "Clean · scan stopped early" }
        if let date = store.lastScanDate { return "Clean · scanned \(date.formatted(.relative(presentation: .named)))" }
        return "Clean · not scanned yet"
    }
    private var pageTitle: String {
        switch section {
        case .smartScan: return "Everything"
        case .general: return "General"
        case .browsers: return "Browsers"
        case .developer: return "Developer"
        case .ai: return "AI models"
        case .creative: return "Creative"
        default: return section.title
        }
    }
    private var headerSubtitle: String {
        switch section {
        case .smartScan: return "Everything the scan found, biggest first. Nothing goes until you review it."
        case .developer: return "Build files, caches and simulators your tools make again when needed."
        case .general: return "App caches, logs and leftovers your Mac and apps make again."
        case .browsers: return "Browser caches. Your logins, history and bookmarks stay."
        case .ai: return "Local models and generated media. Some may need downloading again."
        case .creative: return "Render and preview files from your creative apps."
        default: return "Review before anything is removed."
        }
    }

    // MARK: Rows

    private func bucketRow(_ group: VisibleBucket) -> some View {
        let selected = group.items.contains(where: \.selected)
        let selectable = group.items.contains(where: isReady)
        return HStack(spacing: 14) {
            NightCheck(on: selected, enabled: selected || selectable) {
                toggleBucketSelection(group.id, clear: selected)
            }
            .accessibilityLabel(selected ? "Clear \(group.bucket.info.title)" : "Select \(group.bucket.info.title)")
            Button { expandedBuckets.formSymmetricDifference([group.id]) } label: {
                NightName(logo: BrandLogo.forCategory(group.id, size: 25),
                          title: group.bucket.info.title,
                          subtitle: group.bucket.info.subtitle.isEmpty ? "\(group.items.count) items" : group.bucket.info.subtitle)
            }
            .buttonStyle(.plain)
            .help(expandedBuckets.contains(group.id) ? "Hide items" : "Show the \(group.items.count) items")
            NightMeter(share: Double(group.bytes) / Double(largestBytes))
            Text(Fmt.size(group.bytes)).font(.system(size: 13, weight: .medium)).monospacedDigit()
                .frame(width: 90, alignment: .trailing)
            status(for: group.items).frame(width: 150, alignment: .leading)
        }
        .nightRow()
    }

    private func itemRow(_ item: ScanItem) -> some View {
        let canSelect = item.severity != .risky && item.isActionable
        return HStack(spacing: 14) {
            NightCheck(on: item.selected, enabled: canSelect) { toggleItemSelection(item.id) }
                .accessibilityLabel(item.selected ? "Deselect \(item.url.lastPathComponent)" : "Select \(item.url.lastPathComponent)")
            NightName(logo: nil, title: item.url.lastPathComponent, subtitle: shortPath(item.resolvedURL.path))
            Spacer().frame(width: 150)
            Text(Fmt.size(item.allocatedSize)).font(.system(size: 12.5)).foregroundStyle(Brand.textSecondary).monospacedDigit()
                .frame(width: 90, alignment: .trailing)
            status(for: [item]).frame(width: 150, alignment: .leading)
        }
        .padding(.leading, 36)
        .nightRow()
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.resolvedURL]) }
                .disabled(previewMode)
            Button("Copy path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.resolvedURL.path, forType: .string)
            }
            Divider()
            Button("Never show this location") {
                AppSettings.shared.add(item.resolvedURL)
                if item.selected { store.toggle(item.id) }
            }.disabled(previewMode)
        }
        .help(item.note.isEmpty ? consequence(for: item) : item.note)
    }

    private func isReady(_ item: ScanItem) -> Bool {
        item.severity == .safe && item.isRegenerable && item.isActionable
    }

    /// Ready, Close X first or Needs you. Advice-only items say so.
    private func status(for items: [ScanItem]) -> some View {
        let running = RunningApps.displayNames(for: RunningApps.running(amongst: Array(Set(items.flatMap(\.requiresQuitBundleIDs)))))
        if let app = running.first { return NightPill(text: "Close \(app) first", tone: .warn) }
        if items.allSatisfy({ !$0.isActionable }) { return NightPill(text: "Advice only") }
        if items.allSatisfy(isReady) { return NightPill(text: "Ready", tone: .ok) }
        return NightPill(text: "Needs you")
    }

    @ViewBuilder private var emptyState: some View {
        if store.isScanning {
            NightEmpty(title: "Reading your files", message: store.progressText.isEmpty ? "Results appear as the scan goes. Nothing is removed." : store.progressText, busy: true)
        } else if store.phase == .cancelled {
            NightEmpty(title: "The scan was stopped early", message: "Press Rescan to measure everything before choosing what to free.")
        } else if !store.hasScanned && !previewMode {
            NightEmpty(title: "Nothing scanned yet", message: "Press Rescan to measure this Mac. Nothing is removed until you review it.")
        } else if !searchText.isEmpty {
            NightEmpty(title: "No matches", message: "Try another name or path. Escape clears the filter.")
        } else {
            NightEmpty(title: "Nothing here", message: "The last scan found nothing to free on this page.")
        }
    }

    private func rescan() {
        guard !previewMode else { return }
        if store.isScanning { store.cancel() } else { store.rescan() }
    }

    private func selectAllReady() {
        for group in visibleBuckets where group.items.contains(where: isReady) {
            toggleBucketSelection(group.id, clear: false)
        }
    }

    private func consequence(for item: ScanItem) -> String {
        if !item.isActionable { return "Cairn provides guidance only and does not remove this path." }
        if case .emptyTrash = item.cleanMethod { return "Items already in Trash are permanently removed." }
        if item.isRegenerable { return "The owning tool may download or rebuild these files when next used." }
        return "This may be the only local copy. Check the path and make a backup before proceeding."
    }
    private func shortPath(_ path: String) -> String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private func toggleBucketSelection(_ bucketID: String, clear: Bool) {
        if previewMode {
            guard let b = previewBuckets.firstIndex(where: { $0.id == bucketID }) else { return }
            for i in previewBuckets[b].items.indices {
                let item = previewBuckets[b].items[i]
                if clear || (item.severity == .safe && item.isRegenerable && item.isActionable) {
                    previewBuckets[b].setSelected(at: i, !clear)
                }
            }
        } else if clear {
            store.selectNone(in: bucketID)
        } else {
            store.selectAllSafe(in: bucketID)
        }
    }

    private func toggleItemSelection(_ itemID: UUID) {
        if previewMode {
            for b in previewBuckets.indices {
                if let i = previewBuckets[b].items.firstIndex(where: { $0.id == itemID }) {
                    previewBuckets[b].toggleSelected(at: i)
                    return
                }
            }
        } else {
            store.toggle(itemID)
        }
    }

    private func clearPageSelection() {
        if previewMode {
            for b in previewBuckets.indices {
                for i in previewBuckets[b].items.indices {
                    previewBuckets[b].setSelected(at: i, false)
                }
            }
        } else {
            for bucket in section.buckets(store) { store.selectNone(in: bucket.id) }
        }
    }

    /// Fixed, non-actionable display data for `--preview-ui`. The URLs are never
    /// enumerated; AppShell disables this entire content subtree in preview.
    private static func makePreviewBuckets() -> [ScanStore.Bucket] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let gib: Int64 = 1_000_000_000
        func example(_ path: String, _ bytes: Int64, _ category: String,
                     _ note: String, severity: Severity = .safe,
                     method: CleanMethod = .trash, selected: Bool = false,
                     quit: [String] = []) -> ScanItem {
            ScanItem(url: home.appendingPathComponent(path), allocatedSize: bytes,
                     categoryID: category, severity: severity,
                     requiresQuitBundleIDs: quit, cleanMethod: method,
                     note: note, selected: selected)
        }
        func group(_ id: String, _ title: String, _ subtitle: String,
                   _ symbol: String, _ items: [ScanItem]) -> ScanStore.Bucket {
            var bucket = ScanStore.Bucket(info: CategoryInfo(
                id: id, title: title, subtitle: subtitle, systemImage: symbol,
                group: .developer, requiresFDA: false))
            for item in items { bucket.append(item) }
            return bucket
        }
        // The same 38.6 GB as Home and the review sheet: Xcode, Docker,
        // node_modules and npm are ready and ticked; the rest need a decision.
        return [
            group("xcode", "Xcode build output", "DerivedData for two projects", "hammer.fill", [
                example("Library/Developer/Xcode/DerivedData/MyApp", 9 * gib + gib / 10,
                        "xcode", "Rebuilds during the next Xcode build", selected: true,
                        quit: ["com.apple.dt.Xcode"]),
                example("Library/Developer/Xcode/DerivedData/DataTools", 5 * gib + gib / 10,
                        "xcode", "Rebuilds during the next Xcode build", selected: true,
                        quit: ["com.apple.dt.Xcode"]),
            ]),
            group("docker", "Docker build cache", "Cleaned with Docker's own command", "shippingbox.fill", [
                example("Library/Containers/com.docker.docker/Data/build-cache", 9 * gib + 8 * gib / 10,
                        "docker", "Docker builds it again when needed; Docker.raw is never touched",
                        method: .tool(ToolCommand(tool: "docker", arguments: ["builder", "prune", "-f"], display: "docker builder prune -f")),
                        selected: true),
            ]),
            group("dev-projects", "Project build artifacts", "node_modules in three idle projects", "folder.fill", [
                example("Developer/storefront-web/node_modules", 5 * gib + 2 * gib / 10,
                        "dev-projects", "Installed again by npm install", selected: true),
                example("Developer/design-system/node_modules", 2 * gib + 5 * gib / 10,
                        "dev-projects", "Installed again by npm install", selected: true),
                example("Developer/marketing-site/node_modules", gib + 8 * gib / 10,
                        "dev-projects", "Installed again by npm install", selected: true),
            ]),
            group("npm", "npm cache", "Downloaded packages and metadata", "shippingbox.fill", [
                example(".npm/_cacache", 5 * gib + gib / 10, "npm",
                        "npm downloads packages again when needed", selected: true),
            ]),
            group("android", "Android system images", "Review before removing", "candybarphone", [
                example("Library/Android/sdk/system-images", 4 * gib + 8 * gib / 10,
                        "android", "SDK Manager owns installed system images",
                        severity: .review, method: .adviceOnly),
            ]),
            group("git-bloat", "Git maintenance", "Repository objects", "arrow.triangle.branch", [
                example("Developer/storefront-web/.git", gib + 6 * gib / 10,
                        "git-bloat", "Use Git maintenance; do not remove .git",
                        severity: .review,
                        method: .adviceOnly),
            ]),
            group("ide-caches", "Editor caches", "Close the editor first", "chevron.left.forwardslash.chevron.right", [
                example("Library/Application Support/Code/Cache", gib + 3 * gib / 10,
                        "ide-caches", "Editor cache; close the app first",
                        quit: ["com.microsoft.VSCode"]),
            ]),
        ]
    }
}
