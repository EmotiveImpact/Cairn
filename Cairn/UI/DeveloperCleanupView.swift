import SwiftUI
import AppKit
import QuickLook

/// Native, compact Developer review. Each row is built from the existing scan
/// store; selection still flows into the established ReviewSheet and cleaner.
struct DeveloperCleanupView: View {
    let store: ScanStore
    var section: NavSection = .developer
    var searchText: String = ""
    @Binding var inspectorVisible: Bool
    var onReview: () -> Void

    @State private var expandedBuckets: Set<String> = ["xcode"]
    @State private var inspectedBucketID: String? = "xcode"
    @State private var inspectedItemID: UUID?
    @State private var sortBySize = true
    @State private var fileFilter = "All Files"
    @State private var fileSort = "Size"
    @State private var showMap = false
    @State private var showProtected = false
    @State private var quickLookURL: URL?
    @State private var previewBuckets = DeveloperCleanupView.makePreviewBuckets()
    private let previewMode = CommandLine.arguments.contains("--preview-ui")

    private var sourceBuckets: [ScanStore.Bucket] {
        previewMode ? previewBuckets : section.buckets(store)
    }

    private struct VisibleBucket: Identifiable {
        let bucket: ScanStore.Bucket
        var items: [ScanItem]
        var id: String { bucket.id }
        var bytes: Int64 {
            items.reduce(0) { $0 + $1.allocatedSize }
        }
    }

    private var visibleBuckets: [VisibleBucket] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let found: [VisibleBucket] = sourceBuckets.compactMap { bucket in
            guard !bucket.items.isEmpty else { return nil }
            var items: [ScanItem]
            if query.isEmpty || bucket.info.title.localizedCaseInsensitiveContains(query) {
                items = bucket.items
            } else {
                items = bucket.items.filter {
                    $0.url.lastPathComponent.localizedCaseInsensitiveContains(query)
                    || $0.resolvedURL.path.localizedCaseInsensitiveContains(query)
                    || $0.note.localizedCaseInsensitiveContains(query)
                }
            }
            if section == .largeFiles { items = items.filter(matchesFileFilter).sorted {
                switch fileSort {
                case "Name": return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
                case "Modified": return $0.latestModified > $1.latestModified
                default: return $0.allocatedSize > $1.allocatedSize
                }
            } }
            guard !items.isEmpty else { return nil }
            return VisibleBucket(bucket: bucket, items: items)
        }
        return found.sorted {
            sortBySize ? $0.bytes > $1.bytes :
                $0.bucket.info.title.localizedCaseInsensitiveCompare($1.bucket.info.title) == .orderedAscending
        }
    }
    private var visibleFiles: [ScanItem] {
        visibleBuckets.flatMap(\.items).sorted {
            switch fileSort {
            case "Name": return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            case "Modified": return $0.latestModified > $1.latestModified
            default: return $0.allocatedSize > $1.allocatedSize
            }
        }
    }
    private var developerSelected: [ScanItem] {
        sourceBuckets.flatMap(\.items).filter(\.selected)
    }
    private var developerSelectedBytes: Int64 {
        developerSelected.reduce(0) { $0 + $1.allocatedSize }
    }
    private var outsideSelectedCount: Int {
        previewMode ? 0 : max(0, store.selectedCount - developerSelected.count)
    }
    private var inspectedBucket: ScanStore.Bucket? {
        sourceBuckets.first(where: { $0.id == inspectedBucketID })
            ?? visibleBuckets.first?.bucket
    }
    private var inspectedItem: ScanItem? {
        guard let inspectedItemID else { return section == .largeFiles ? visibleFiles.first : nil }
        return sourceBuckets.flatMap(\.items).first(where: { $0.id == inspectedItemID })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    listToolbar
                    if section == .smartScan {
                        smartScanSummary
                    } else if section != .largeFiles {
                        categorySummary
                    }
                    if section == .largeFiles {
                        HStack {
                            Picker("File type", selection: $fileFilter) { ForEach(["All Files", "Videos", "Downloads", "Archives", "Disk Images", "Project Backups"], id: \.self) { Text($0) } }.cairnFilterSurface().frame(width: 210)
                            Spacer()
                            Picker("Sort", selection: $fileSort) { ForEach(["Size", "Name", "Modified"], id: \.self) { Text($0) } }.cairnFilterSurface().frame(width: 145)
                        }.font(.system(size: 12)).padding(.horizontal, 16).padding(.bottom, 12)
                    }
                    if section != .smartScan && !visibleBuckets.isEmpty {
                        if store.isScanning { CairnStateView(kind: .scanning, title: "Scan in progress", message: store.progressText.isEmpty ? "Reading files. Nothing is being removed." : store.progressText, compact: true) }
                        else if store.phase == .cancelled { CairnStateView(kind: .interrupted, title: "Scan stopped", message: "Results may be incomplete. Rescan to finish measuring before cleanup.", compact: true) }
                    }
                    tableHeader
                    if visibleBuckets.isEmpty {
                        emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                if section == .largeFiles {
                                    ForEach(visibleFiles) { item in itemRow(item, bucketID: item.categoryID) }
                                } else {
                                    ForEach(visibleBuckets) { group in
                                        bucketRow(group)
                                        if expandedBuckets.contains(group.id) {
                                            ForEach(group.items) { item in itemRow(item, bucketID: group.id) }
                                        }
                                    }
                                }
                                protectedRow
                            }
                        }
                    }
                }
                .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
                if inspectorVisible {
                    inspector.frame(width: 300).frame(maxHeight: .infinity)
                }
            }
            actionBar.fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Brand.background)
        .quickLookPreview($quickLookURL)
        .onAppear { if previewMode && section != .developer { previewBuckets = PreviewLibrary.buckets(section) } }
        .sheet(isPresented: $showMap) {
            CairnDialog(title: "Storage map", subtitle: "Measured categories", wide: true, height: 540) {
                DiskMapView(store: store) { id in inspectedBucketID = id; showMap = false }
            } actions: { Button("Done") { showMap = false }.buttonStyle(ControlPanelButtonStyle()).keyboardShortcut(.cancelAction) }
        }
        .onChange(of: section) { _, value in
            quickLookURL = nil
            inspectedItemID = nil; inspectedBucketID = value == .developer ? "xcode" : nil; expandedBuckets = value == .developer ? ["xcode"] : []
            if previewMode { previewBuckets = value == .developer ? Self.makePreviewBuckets() : PreviewLibrary.buckets(value) }
        }
    }

    private var listToolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(section.title).font(.system(size: 28, weight: .semibold)).foregroundStyle(Brand.textPrimary)
                    Text(headerSubtitle).font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(Brand.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .frame(minHeight: 92)
            .padding(.trailing, 150)
            if section != .largeFiles {
                HStack(spacing: 10) {
                    if section == .smartScan {
                        Menu("Select…") {
                            ForEach(Mission.all.filter { $0.id != "ai" }) { mission in
                                Button(mission.title) { mission.apply(store) }
                            }
                        }.frame(width: 90).disabled(previewMode || !store.hasScanned)
                        Button { showMap = true } label: { Image(systemName: "square.split.2x2") }
                            .buttonStyle(.plain).help("Storage map").disabled(previewMode || !store.hasScanned)
                    }
                    Spacer()
                    Menu {
                        Button("Sort by Size") { sortBySize = true }
                        Button("Sort by Name") { sortBySize = false }
                    } label: {
                        HStack(spacing: 6) {
                            Text(sortBySize ? "Sort by Size" : "Sort by Name")
                            Image(systemName: "chevron.down").font(.system(size: 9))
                        }
                        .foregroundStyle(Brand.textSecondary)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 135)
                }
                .frame(height: 28)
            }
        }
        .font(.system(size: 15, weight: .medium))
        .padding(.horizontal, 26)
        .padding(.bottom, section == .largeFiles ? 10 : 4)
    }

    private var headerSubtitle: String {
        switch section {
        case .smartScan: return "A focused check for measured items worth your review."
        case .developer: return "Review build output, package caches and tool-owned data before acting."
        case .browsers: return "Browser caches and site data have different consequences. Inspect each item."
        case .ai: return "Review local models and generated media; some may need to be downloaded again."
        case .creative: return "Inspect render and creative-tool data before choosing an action."
        case .general: return "Every category has its own requirement and recovery limits."
        case .largeFiles: return "Review the files worth a closer look. Some may be the only copy."
        default: return "Choose what to review. Your work stays protected."
        }
    }

    private var categorySummary: some View {
        let items = sourceBuckets.flatMap(\.items)
        let measuredBytes = items.reduce(Int64(0)) { $0 + $1.allocatedSize }
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MEASURED IN THIS CATEGORY")
                        .font(.system(size: 10.5, weight: .medium)).tracking(0.7)
                        .foregroundStyle(Brand.textMuted)
                    Text(items.isEmpty ? "No items measured" : Fmt.size(measuredBytes))
                        .font(.system(size: 22, weight: .regular)).monospacedDigit()
                        .foregroundStyle(Brand.textPrimary)
                }
                Spacer()
                Text("\(items.count) item\(items.count == 1 ? "" : "s") · \(sourceBuckets.count) categor\(sourceBuckets.count == 1 ? "y" : "ies")")
                    .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
            }
            Text(previewMode ? "Sample data for interface preview. No files have been inspected or changed." :
                    "These are scanned file-size estimates, not available space or promised savings. Review each requirement below.")
                .font(.system(size: 10.5)).foregroundStyle(Brand.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 26).padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().fill(Brand.separator).frame(height: 0.5), alignment: .bottom)
    }

    private var smartScanSummary: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: scanSummaryIcon)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(store.phase == .cancelled ? Brand.amber : Brand.safeCyan)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(scanSummaryTitle).font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Brand.textPrimary)
                    Text(scanSummaryDetail).font(.system(size: 11.5))
                        .foregroundStyle(Brand.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !previewMode, let date = store.lastScanDate, store.phase == .finished {
                        Text("Started \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 10.5)).foregroundStyle(Brand.textMuted)
                    }
                }
                Spacer(minLength: 0)
            }
            Text(previewMode ? "Sample suggestions · no scan or file action." :
                    "The results below come from the current scan. No files have been changed; selected items still need review.")
                .font(.system(size: 10.5)).foregroundStyle(Brand.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 26).padding(.top, 10).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().fill(Brand.separator).frame(height: 0.5), alignment: .bottom)
    }

    private var scanSummaryTitle: String {
        if previewMode { return "Sample scan results" }
        switch store.phase {
        case .scanning: return "Scan in progress"
        case .finished: return "Scan complete"
        case .cancelled: return "Scan interrupted"
        case .idle: return "Ready to scan"
        }
    }

    private var scanSummaryDetail: String {
        if previewMode { return "Example categories illustrate the review flow." }
        if store.isScanning { return "\(store.completedCount) of \(store.totalCount) categories completed. Nothing is being removed." }
        if store.phase == .cancelled { return "Results may be incomplete. Rescan before choosing items." }
        if store.phase == .finished {
            return "\(store.completedCount) of \(store.totalCount) categories completed · \(sourceBuckets.flatMap(\.items).count) items measured."
        }
        return "Run a scan to see measured categories and review suggestions."
    }

    private var scanSummaryIcon: String {
        switch store.phase {
        case .scanning: return "circle.dotted"
        case .cancelled: return "exclamationmark.circle.fill"
        case .finished: return "checkmark.circle.fill"
        case .idle: return "scope"
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.square")
                .font(.system(size: 13)).foregroundStyle(Brand.textMuted)
                .frame(width: 23)
            Text("Item").frame(maxWidth: .infinity, alignment: .leading)
            if !inspectorVisible { Text("Location").frame(width: 140, alignment: .leading) }
            Text("Size").frame(width: 62, alignment: .trailing)
            Text("Requirement").frame(width: 140, alignment: .leading)
        }
        .font(.system(size: 11, weight: .medium)).foregroundStyle(Brand.textSecondary)
        .padding(.horizontal, 14).frame(height: 40)
        .background(Brand.background)
        .overlay(Rectangle().fill(Brand.separator).frame(height: 0.5), alignment: .bottom)
    }

    private func bucketRow(_ group: VisibleBucket) -> some View {
        let selected = group.bucket.selectedCount > 0
        let canSelectSafeItems = group.items.contains {
            $0.severity == .safe && $0.isRegenerable && $0.isActionable
        }
        let focused = inspectorVisible && inspectedItemID == nil && (inspectedBucketID ?? visibleBuckets.first?.id) == group.id
        return HStack(spacing: 10) {
            if selected || canSelectSafeItems {
                Button {
                    toggleBucketSelection(group.id, clear: selected)
                    inspectorVisible = true
                    inspectedBucketID = group.id
                    inspectedItemID = nil
                } label: {
                    Image(systemName: selected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 17)).foregroundStyle(selected ? Brand.blue : Brand.textMuted)
                        .frame(width: 23)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(selected ? "Clear \(group.bucket.info.title) selection" :
                                        "Select rebuildable \(group.bucket.info.title) items")
            } else {
                Image(systemName: "minus.square")
                    .font(.system(size: 17)).foregroundStyle(Brand.textMuted)
                    .frame(width: 23)
                    .accessibilityHidden(true)
            }
            Button {
                inspectorVisible = true
                inspectedBucketID = group.id
                inspectedItemID = nil
                expandedBuckets.formSymmetricDifference([group.id])
            } label: {
                HStack(spacing: 9) {
                    ToolIcon.forCategory(group.id, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.bucket.info.title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Brand.textPrimary).lineLimit(1)
                        Text("\(group.items.count) item\(group.items.count == 1 ? "" : "s")")
                            .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Brand.textMuted)
                        .rotationEffect(.degrees(expandedBuckets.contains(group.id) ? 90 : 0))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
            if !inspectorVisible {
            Text(shortPath(group.items.first?.resolvedURL.path ?? ""))
                .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                .lineLimit(1).truncationMode(.middle)
                .frame(width: 140, alignment: .leading)
            }
            Text(Fmt.size(group.bytes)).font(.system(size: 13, weight: .medium))
                .monospacedDigit().foregroundStyle(Brand.textPrimary)
                .frame(width: 62, alignment: .trailing)
            requirement(for: group.items).frame(width: 140, alignment: .leading)
        }
        .padding(.horizontal, 14).frame(height: 68)
        .background(focused ? Color.white.opacity(0.045) : Brand.background)
    }

    private func itemRow(_ item: ScanItem, bucketID: String) -> some View {
        let canSelect = item.severity != .risky && item.isActionable
        let focused = inspectorVisible && inspectedItemID == item.id
        return HStack(spacing: 10) {
            Button {
                if canSelect { toggleItemSelection(item.id) }
                inspectorVisible = true
                inspectedItemID = item.id
                inspectedBucketID = bucketID
            } label: {
                Image(systemName: item.selected ? "checkmark.square.fill" :
                    (canSelect ? "square" : "minus.square"))
                    .font(.system(size: 15))
                    .foregroundStyle(item.selected ? Brand.blue : Brand.textMuted)
                    .frame(width: 23)
            }
            .buttonStyle(.plain).disabled(!canSelect)
            .accessibilityLabel(item.selected ? "Deselect \(item.url.lastPathComponent)" :
                                    "Select \(item.url.lastPathComponent)")
            Button {
                inspectorVisible = true
                inspectedItemID = item.id
                inspectedBucketID = bucketID
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill").font(.system(size: 15))
                        .foregroundStyle(Brand.textSecondary).frame(width: 23)
                    Text(item.url.lastPathComponent)
                        .font(.system(size: 13)).foregroundStyle(Brand.textPrimary)
                        .lineLimit(1).truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
            if !inspectorVisible {
            Text(shortPath(item.resolvedURL.path))
                .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                .lineLimit(1).truncationMode(.middle)
                .frame(width: 140, alignment: .leading)
            }
            Text(Fmt.size(item.allocatedSize)).font(.system(size: 11))
                .monospacedDigit().foregroundStyle(Brand.textSecondary)
                .frame(width: 62, alignment: .trailing)
            requirement(for: [item]).frame(width: 140, alignment: .leading)
        }
        .padding(.horizontal, 14).frame(height: 40)
        .background(focused ? Color.white.opacity(0.045) : Brand.surfaceSubtle.opacity(0.17))
        .contextMenu {
            if section == .largeFiles {
                Button("Quick Look") { quickLook(item) }
                    .disabled(previewMode)
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([item.resolvedURL])
                }.disabled(previewMode)
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.resolvedURL.path, forType: .string)
                }.disabled(previewMode)
            }
        }
    }

    private var protectedRow: some View {
        VStack(spacing: 0) {
            Button { showProtected.toggle() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right").rotationEffect(.degrees(showProtected ? 90 : 0))
                        .font(.system(size: 10)).frame(width: 18)
                    Image(systemName: "lock.shield").frame(width: 23)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Protected locations").font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Brand.textPrimary)
                    Text("Sessions, source code, Git metadata and recovery data")
                            .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 18).frame(height: 57)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
            if showProtected {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Codex and ChatGPT sessions, credentials, source files, Git metadata and worktree roots stay out of cleanup selections.")
                    Text("Generated artifacts inside a repository may still appear for individual review. The cleaner checks protected paths again before moving a file.")
                }
                .font(.system(size: 11)).foregroundStyle(Brand.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 70).padding(.trailing, 18).padding(.bottom, 13)
            }
        }
        .overlay(Rectangle().fill(Brand.separator).frame(height: 0.5), alignment: .top)
    }

    @ViewBuilder private var emptyState: some View {
        if store.isScanning {
            CairnStateView(kind: .scanning, title: "Reading your files", message: "Results appear as the scan progresses. Nothing is being removed.")
        } else if store.phase == .cancelled {
            CairnStateView(kind: .interrupted, title: "Ready when you are", message: "The scan was stopped. Use Rescan to start a fresh measurement.")
        } else if !store.hasScanned {
            CairnStateView(kind: .empty, title: "Start with a scan", message: "Measure files on this Mac before choosing anything to clean. Use Rescan above.")
        } else if !searchText.isEmpty {
            CairnStateView(kind: .empty, title: "No matching results", message: "Try another tool, file name or path. Escape clears your search.")
        } else {
            CairnStateView(kind: .completed, title: "Nothing to review here", message: "The last scan found no items in this section. This does not guarantee all locations were accessible.")
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(developerSelected.count) item\(developerSelected.count == 1 ? "" : "s") selected · \(Fmt.size(developerSelectedBytes))")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(Brand.textPrimary)
                if outsideSelectedCount > 0 {
                    Text("Review also includes \(outsideSelectedCount) selection\(outsideSelectedCount == 1 ? "" : "s") from other sections.")
                        .font(.system(size: 12)).foregroundStyle(Brand.amber)
                }
            }
            Spacer()
            Button("Clear selection") {
                clearDeveloperSelection()
            }
            .buttonStyle(ControlPanelButtonStyle()).disabled(developerSelected.isEmpty)
            Button("Review cleanup…") { onReview() }
                .buttonStyle(ControlPanelButtonStyle(primary: true))
                .disabled(previewMode || store.selectedCount == 0)
        }
        .padding(.horizontal, 22).frame(height: 72)
        .background(Brand.deepPanel.opacity(0.35))
        .overlay(alignment: .top) { Rectangle().fill(Brand.separator).frame(height: 0.5) }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Details").font(.system(size: 11, weight: .medium)).foregroundStyle(Brand.textMuted)
                Spacer()
                Button { inspectorVisible = false } label: {
                    Image(systemName: "xmark").font(.system(size: 11))
                        .foregroundStyle(Brand.textMuted)
                }
                .buttonStyle(.plain).accessibilityLabel("Hide details")
            }.padding(.top, 18)
            ScrollView {
                if let item = inspectedItem {
                    itemInspector(item).id(item.id)
                } else if let bucket = inspectedBucket {
                    bucketInspector(bucket).id(bucket.id)
                } else {
                    EmptyState(icon: "info.circle", title: "Select an item",
                               caption: "Details and requirements appear here.")
                }
            }
        }
        .padding(.horizontal, 20)
        .background(Brand.deepPanel)
    }

    private func bucketInspector(_ bucket: ScanStore.Bucket) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ToolIcon.forCategory(bucket.id, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(bucket.info.title).font(.system(size: 15, weight: .semibold))
                    Text("\(bucket.items.count) measured items").font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                }
            }
            inspectorSize(bucket.items.reduce(0) { $0 + $1.allocatedSize }, label: "Measured size")
            requirement(for: bucket.items)
            Text(bucket.info.subtitle).font(.system(size: 12)).foregroundStyle(Brand.textSecondary).fixedSize(horizontal: false, vertical: true)
            detailDivider
            inspectorSection("Before cleanup", "Expand this category to inspect individual files. Requirements can differ between items.")
            HStack {
                Text("Selected").foregroundStyle(Brand.textMuted)
                Spacer()
                Text("\(bucket.selectedCount) · \(Fmt.size(bucket.selectedSize))").monospacedDigit()
            }.font(.system(size: 12))
            if bucket.items.contains(where: { $0.cleanMethod.isPaid }) {
                inspectorSection("Tool-managed finding", "Broad tool commands are review-only until Cairn can verify their exact scope and active writers.")
            }
            detailDivider
            DisclosureGroup("Protected data") {
                Text("Known session history, credentials, source code and recovery locations are excluded by the safety guard. Paths are checked again before removal.")
                    .font(.system(size: 12)).foregroundStyle(Brand.textSecondary).padding(.top, 8)
            }.font(.system(size: 12)).tint(Brand.textMuted)
        }.foregroundStyle(Brand.textPrimary).padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func itemInspector(_ item: ScanItem) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                FileIcon(url: item.url, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.url.lastPathComponent).font(.system(size: 15, weight: .semibold)).lineLimit(3)
                    Text(sourceBuckets.first(where: { $0.id == item.categoryID })?.info.title ?? item.categoryID)
                        .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                }
            }
            inspectorSize(item.allocatedSize, label: "Measured size · not guaranteed savings")
            requirement(for: [item])
            if !item.note.isEmpty {
                Text(item.note).font(.system(size: 12)).foregroundStyle(Brand.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            detailDivider
            if section == .largeFiles {
                Button {
                    quickLook(item)
                } label: { Label("Quick Look", systemImage: "eye") }
                    .buttonStyle(ControlPanelButtonStyle())
                    .disabled(previewMode)
                    .keyboardShortcut(.space, modifiers: [])
                Text("Preview the file before deciding what to do. Space opens Quick Look when this page is active.")
                    .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            inspectorSection("What happens", consequence(for: item))
            if !item.requiresQuitBundleIDs.isEmpty {
                inspectorSection("Close before cleanup", item.requiresQuitBundleIDs.joined(separator: "\n"))
            }
            inspectorSection("Action", methodText(for: item))
            if item.cleanMethod.isPaid {
                inspectorSection("Review only", "Cairn will not execute this tool command. Inspect the owning tool and its active work before manual maintenance.")
            }
            detailDivider
            DisclosureGroup("Location & file details") {
                VStack(alignment: .leading, spacing: 14) {
                    Text(item.resolvedURL.path).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Brand.textSecondary).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if item.latestModified > .distantPast {
                        inspectorSection("Modified", item.latestModified.formatted(date: .abbreviated, time: .shortened))
                    }
                    Button("Exclude this location") {
                        AppSettings.shared.add(item.resolvedURL)
                        if item.selected { store.toggle(item.id) }
                    }.buttonStyle(ControlPanelButtonStyle()).disabled(previewMode)
                }.padding(.top, 10)
            }.font(.system(size: 12)).tint(Brand.textMuted)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.resolvedURL])
            } label: { Label("Show in Finder", systemImage: "folder") }
                .buttonStyle(ControlPanelButtonStyle()).disabled(previewMode)
        }.foregroundStyle(Brand.textPrimary).padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quickLook(_ item: ScanItem) {
        guard !previewMode, section == .largeFiles,
              FileManager.default.fileExists(atPath: item.resolvedURL.path) else { return }
        quickLookURL = item.resolvedURL
    }

    private func inspectorSize(_ bytes: Int64, label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(Fmt.size(bytes)).font(.system(size: 29, weight: .medium)).monospacedDigit()
            Text(label).font(.system(size: 11)).foregroundStyle(Brand.textMuted)
        }
    }

    private var detailDivider: some View {
        Rectangle().fill(Brand.separator).frame(height: 0.5)
    }
    private func inspectorSection(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12, weight: .medium))
                .foregroundStyle(Brand.textPrimary)
            Text(detail).font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func requirement(for items: [ScanItem]) -> some View {
        let mixed = items.count > 1 && items.contains(where: { !$0.isActionable || $0.severity == .risky })
            && items.contains(where: { $0.isActionable && $0.severity != .risky })
        let item = items.first(where: { !$0.isActionable || $0.severity == .risky })
            ?? items.first(where: { $0.cleanMethod.isPaid })
            ?? items.first(where: { $0.severity == .review })
            ?? items.first(where: { !$0.requiresQuitBundleIDs.isEmpty })
            ?? items.first
        let text = mixed ? "Mixed · review" : item.map(requirementText(for:)) ?? "Review"
        let color: Color = mixed ? Brand.amber : item?.isActionable == false ? Brand.textMuted :
            item?.cleanMethod.isPaid == true ? Brand.blue :
            item?.severity == .safe && item?.isRegenerable == true && item?.requiresQuitBundleIDs.isEmpty == true ? Brand.safeCyan : Brand.amber
        let icon: String
        if mixed { icon = "exclamationmark.triangle.fill" }
        else if item?.isActionable == false { icon = "info.circle.fill" }
        else if item?.cleanMethod.isPaid == true { icon = "info.circle.fill" }
        else if item?.severity == .safe && item?.isRegenerable == true && item?.requiresQuitBundleIDs.isEmpty == true { icon = "checkmark.circle.fill" }
        else { icon = "exclamationmark.triangle.fill" }
        return HStack(spacing: 5) {
            Image(systemName: icon)
            Text(text).lineLimit(1)
        }
        .font(.system(size: 12)).foregroundStyle(color)
    }

    private func requirementText(for item: ScanItem) -> String {
        if !item.isActionable { return "Advice only" }
        if item.severity == .risky { return "Protected" }
        if case .tool(let command) = item.cleanMethod { return "Use \(command.tool)" }
        if case .emptyTrash = item.cleanMethod { return "Permanent" }
        if item.severity == .review { return "Review required" }
        if !item.requiresQuitBundleIDs.isEmpty { return "Close app first" }
        return item.isRegenerable ? "Rebuildable" : "Review required"
    }

    private func consequence(for item: ScanItem) -> String {
        if !item.isActionable { return "Cairn provides guidance only and does not remove this path." }
        if case .emptyTrash = item.cleanMethod { return "Items already in Trash are permanently removed." }
        if item.isRegenerable { return "The owning tool may download or rebuild these files when next used." }
        return "This may be the only local copy. Check the path and make a backup before proceeding."
    }
    private func methodText(for item: ScanItem) -> String {
        switch item.cleanMethod {
        case .trash: return "Move to Trash, with recovery available while the Trash entry remains."
        case .emptyTrash: return "Empty Trash; this action cannot be put back by Cairn."
        case .tool(let command): return "Run \(command.display) through the tool's own interface."
        case .adviceOnly: return "No removal action."
        }
    }
    private func matchesFileFilter(_ item: ScanItem) -> Bool {
        let ext = item.url.pathExtension.lowercased()
        switch fileFilter {
        case "Videos": return ["mov", "mp4", "m4v", "mkv", "avi"].contains(ext)
        case "Downloads": return item.url.path.contains("/Downloads/")
        case "Archives": return ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "tgz"].contains(ext)
        case "Disk Images": return ["dmg", "iso", "sparsebundle", "sparseimage", "img"].contains(ext)
        case "Project Backups": return ["sparsebundle", "ipsw"].contains(ext) || item.url.lastPathComponent.localizedCaseInsensitiveContains("backup")
        default: return true
        }
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

    private func clearDeveloperSelection() {
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
        return [
            group("xcode", "Xcode build output", "DerivedData for two projects", "hammer.fill", [
                example("Library/Developer/Xcode/DerivedData/MyApp", 4 * gib + gib / 10,
                        "xcode", "Rebuilds during the next Xcode build", selected: true,
                        quit: ["com.apple.dt.Xcode"]),
                example("Library/Developer/Xcode/DerivedData/DataTools", 2 * gib + 3 * gib / 10,
                        "xcode", "Rebuilds during the next Xcode build", selected: true,
                        quit: ["com.apple.dt.Xcode"]),
            ]),
            group("npm", "npm cache", "Downloaded packages and metadata", "shippingbox.fill", [
                example(".npm/_cacache", 2 * gib + gib / 10, "npm",
                        "Verify npm's configured cache and active installs before maintenance", severity: .review, method: .adviceOnly),
            ]),
            group("dev-projects", "Project build artifacts", "Dependencies and generated output", "folder.fill", [
                example("Projects/MyApp/node_modules", 8 * gib + 6 * gib / 10,
                        "dev-projects", "Dependencies may need to be installed again",
                        severity: .review),
            ]),
            group("docker", "Docker build cache", "Managed by Docker", "shippingbox.fill", [
                example("Library/Containers/com.docker.docker/Data", 3 * gib + 2 * gib / 10,
                        "docker", "Use Docker's own prune command; never delete Docker.raw",
                        severity: .review, method: .adviceOnly),
            ]),
            group("android", "Android system images", "Review before removing", "candybarphone", [
                example("Library/Android/sdk/system-images", 4 * gib + 8 * gib / 10,
                        "android", "SDK Manager owns installed system images",
                        severity: .review, method: .adviceOnly),
            ]),
            group("ide-caches", "Editor caches", "Close the editor first", "chevron.left.forwardslash.chevron.right", [
                example("Library/Application Support/Code/Cache", gib + 3 * gib / 10,
                        "ide-caches", "Editor cache; close the app first",
                        quit: ["com.microsoft.VSCode"]),
            ]),
            group("git-bloat", "Git maintenance", "Repository objects", "arrow.triangle.branch", [
                example("Projects/MyApp/.git", gib + 6 * gib / 10,
                        "git-bloat", "Use Git maintenance; do not remove .git",
                        severity: .review,
                        method: .adviceOnly),
            ]),
        ]
    }
}
