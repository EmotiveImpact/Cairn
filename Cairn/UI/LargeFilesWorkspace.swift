import SwiftUI
import AppKit
import QuickLook

/// The live file browser for the two large-file scan buckets. It deliberately
/// shares ScanStore selection and the mandatory ReviewSheet with the rest of
/// Cairn; changing the presentation does not create a second deletion path.
struct LargeFilesWorkspace: View {
    let store: ScanStore
    var search: String
    @Binding var inspectorVisible: Bool
    var onRescan: () -> Void
    var onReview: () -> Void

    private enum FileFilter: String, CaseIterable, Identifiable {
        case all = "All types", videos = "Videos", downloads = "Downloads"
        case archives = "Archives", diskImages = "Disk images", backups = "Project backups"
        var id: String { rawValue }
    }
    private enum FileSort: String, CaseIterable, Identifiable {
        case size = "Size", name = "Name", modified = "Last modified"
        var id: String { rawValue }
    }

    @State private var filter: FileFilter = .all
    @State private var sort: FileSort = .size
    @State private var inspectedID: UUID?
    @State private var quickLookURL: URL?
    @State private var protectedExpanded = false
    @State private var opened = false
    @State private var sampleItems = LargeFilesWorkspace.makeSamples()
    private let preview = CommandLine.arguments.contains("--preview-ui")

    private var sourceItems: [ScanItem] {
        preview ? sampleItems : store.buckets
            .filter { ["large-old", "installers"].contains($0.id) }
            .flatMap(\.items)
    }
    private func visibleItems(from source: [ScanItem]) -> [ScanItem] {
        source.filter { item in
            let matchesSearch = search.isEmpty || item.url.lastPathComponent.localizedCaseInsensitiveContains(search)
                || item.resolvedURL.path.localizedCaseInsensitiveContains(search)
            return matchesSearch && matchesFilter(item)
        }.sorted { first, second in
            switch sort {
            case .size: return first.allocatedSize > second.allocatedSize
            case .name: return first.url.lastPathComponent.localizedStandardCompare(second.url.lastPathComponent) == .orderedAscending
            case .modified: return first.latestModified > second.latestModified
            }
        }
    }

    var body: some View {
        // Resolve the filtered order and inspector once per render. Doing this
        // inside every row made large result sets quadratic on the main actor.
        let source = sourceItems
        let visible = visibleItems(from: source)
        let selected = source.filter { $0.selected && $0.isActionable && $0.severity != .risky }
        let selectedElsewhere = preview ? 0 : max(0, store.selectedCount - selected.count)
        let inspected = visible.first { $0.id == inspectedID } ?? visible.first
        return GeometryReader { geometry in
            let showInspector = inspectorVisible && geometry.size.width >= 760
            let inspectorWidth = min(400, max(300, geometry.size.width * 0.34))
            VStack(spacing: 0) {
                header
                filters
                Rectangle().fill(Brand.separator).frame(height: 0.5)
                HStack(spacing: 0) {
                    fileTable(items: visible, focusedID: inspected?.id)
                        .frame(minWidth: 450, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    if showInspector {
                        Rectangle().fill(Brand.separator).frame(width: 0.5)
                        detailPanel(item: inspected, compact: inspectorWidth < 340, width: inspectorWidth)
                            .frame(width: inspectorWidth).frame(maxHeight: .infinity)
                            .background(Brand.background)
                    }
                }
                footer(selected: selected, selectedElsewhere: selectedElsewhere)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Brand.background)
        }
        .foregroundStyle(Brand.textPrimary)
        .quickLookPreview($quickLookURL)
        .onAppear {
            if !opened { inspectorVisible = true; opened = true }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Large files").font(.system(size: 38, weight: .light))
                Text("Look inside before you decide.")
                    .font(.system(size: 13)).foregroundStyle(Brand.textSecondary)
            }
            Spacer(minLength: 12)
            Button(action: onRescan) {
                Label(store.isScanning ? "Stop scan" : "Rescan", systemImage: store.isScanning ? "stop.circle" : "arrow.clockwise")
            }
            .buttonStyle(ControlPanelButtonStyle())
            .keyboardShortcut("r", modifiers: .command)
            .disabled(preview || store.isCleaning)
            Button { inspectorVisible.toggle() } label: { Image(systemName: "sidebar.right") }
                .buttonStyle(ControlPanelButtonStyle())
                .help(inspectorVisible ? "Hide file details" : "Show file details")
                .accessibilityLabel(inspectorVisible ? "Hide file details" : "Show file details")
        }
        .padding(.horizontal, 28).padding(.top, 27).padding(.bottom, 21)
    }

    private var filters: some View {
        HStack(spacing: 11) {
            Text("File type").foregroundStyle(Brand.textSecondary)
            Picker("File type", selection: $filter) {
                ForEach(FileFilter.allCases) { option in Text(option.rawValue).tag(option) }
            }.labelsHidden().cairnFilterSurface().frame(width: 162)
            Spacer(minLength: 12)
            Text("Sort").foregroundStyle(Brand.textSecondary)
            Picker("Sort", selection: $sort) {
                ForEach(FileSort.allCases) { option in Text(option.rawValue).tag(option) }
            }.labelsHidden().cairnFilterSurface().frame(width: 146)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 28).padding(.bottom, 15)
    }

    private func fileTable(items: [ScanItem], focusedID: UUID?) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.square")
                    .font(.system(size: 13)).frame(width: 28)
                    .accessibilityHidden(true)
                Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                Text("Size").frame(width: 71, alignment: .trailing)
                Text("Last modified").frame(width: 91, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Brand.textSecondary)
            .padding(.horizontal, 21).frame(height: 40)
            .background(Brand.background)
            if store.isScanning && !preview {
                CairnStateView(kind: .scanning, title: "Reading files", message: store.progressText.isEmpty ? "Results appear as they are measured." : store.progressText, compact: true)
            } else if store.phase == .cancelled && !preview {
                CairnStateView(kind: .interrupted, title: "Scan stopped", message: "These results may be incomplete. Rescan before cleanup.", compact: true)
            }
            if items.isEmpty {
                WorkspaceEmpty(title: emptyTitle, message: emptyMessage, icon: "doc.text.magnifyingglass")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in fileRow(item, focused: inspectorVisible && focusedID == item.id) }
                        protectedRow
                    }.padding(.horizontal, 10).padding(.top, 6)
                }
            }
        }
    }

    private func fileRow(_ item: ScanItem, focused: Bool) -> some View {
        let canSelect = item.isActionable && item.severity != .risky && !preview
        return HStack(spacing: 10) {
            Button {
                store.toggle(item.id)
                inspectedID = item.id
            } label: {
                Image(systemName: item.selected ? "checkmark.square.fill" : canSelect ? "square" : "minus.square")
                    .font(.system(size: 15)).foregroundStyle(item.selected ? Brand.blue : Brand.textMuted)
                    .frame(width: 28)
            }
            .buttonStyle(.plain).disabled(!canSelect)
            .accessibilityLabel(canSelect ? (item.selected ? "Deselect \(item.url.lastPathComponent)" : "Select \(item.url.lastPathComponent) for review") : "\(item.url.lastPathComponent) is advice only")
            Button {
                inspectedID = item.id
                inspectorVisible = true
            } label: {
                HStack(spacing: 11) {
                    if preview, item.url.lastPathComponent == "Coast-film.mov",
                       let sample = LargeFileSampleArt.image {
                        Image(nsImage: sample).resizable().scaledToFill()
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    } else if preview { FileIcon(url: item.url, size: 36) }
                    else { ThumbnailView(url: item.resolvedURL, size: 36) }
                    Text(item.url.lastPathComponent)
                        .font(.system(size: 12.5, weight: focused ? .medium : .regular))
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(Fmt.size(item.allocatedSize)).frame(width: 71, alignment: .trailing)
                    Text(item.latestModified > .distantPast ? item.latestModified.formatted(.dateTime.day().month(.abbreviated).year()) : "—")
                        .frame(width: 91, alignment: .trailing)
                }
                .font(.system(size: 11.5)).monospacedDigit()
                .foregroundStyle(Brand.textSecondary)
                .frame(height: 67).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 11)
        .background(focused ? Brand.wash(0.045) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .bottom) {
            if !focused { Rectangle().fill(Brand.separator).frame(height: 0.5).padding(.leading, 48) }
        }
        .contextMenu {
            Button("Quick Look") { quickLook(item) }
                .disabled(preview || !FileManager.default.fileExists(atPath: item.resolvedURL.path))
            Button("Show in Finder") { reveal(item) }
                .disabled(preview || !FileManager.default.fileExists(atPath: item.resolvedURL.path))
            Button("Copy path") { copyPath(item) }.disabled(preview)
        }
    }

    private var protectedRow: some View {
        DisclosureGroup(isExpanded: $protectedExpanded) {
            Text("Sessions, source code, Git metadata, credentials and recovery data are excluded. Cairn checks paths again before any reviewed action.")
                .font(.system(size: 11)).foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 29).padding(.bottom, 13)
        } label: {
            Label("Protected locations", systemImage: "lock.shield")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Brand.textSecondary)
        }
        .padding(.horizontal, 18).padding(.vertical, 17)
    }

    @ViewBuilder private func detailPanel(item: ScanItem?, compact: Bool, width: CGFloat) -> some View {
        if let item {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    LargeFilePreviewArtwork(url: item.resolvedURL, preview: preview)
                        .frame(height: (width - 42) * 9 / 16)
                        .padding(.bottom, 17)
                    Text(item.url.lastPathComponent)
                        .font(.system(size: 18, weight: .semibold))
                        .lineLimit(2).textSelection(.enabled)
                    Text("\(fileKind(item)) · \(Fmt.size(item.allocatedSize)) estimated file size")
                        .font(.system(size: 11.5)).foregroundStyle(Brand.textSecondary)
                        .padding(.top, 5)
                    if compact { safetyNote(compact: true).padding(.top, 15) }
                    divider.padding(.vertical, compact ? 13 : 17)
                    detailRow("Location", shortPath(item.resolvedURL.path))
                    if item.latestModified > .distantPast {
                        detailRow("Last modified", item.latestModified.formatted(date: .abbreviated, time: .omitted))
                    }
                    divider.padding(.vertical, compact ? 13 : 17)
                    HStack(spacing: 8) {
                        Button { quickLook(item) } label: { Label("Quick Look", systemImage: "eye") }
                            .buttonStyle(ControlPanelButtonStyle())
                            .keyboardShortcut(.space, modifiers: [])
                        Button { reveal(item) } label: { Label(compact ? "Finder" : "Show in Finder", systemImage: "folder") }
                            .buttonStyle(ControlPanelButtonStyle())
                            .help("Show in Finder")
                            .accessibilityLabel("Show in Finder")
                    }
                    .disabled(preview || !FileManager.default.fileExists(atPath: item.resolvedURL.path))
                    .padding(.bottom, 8)
                    Text("Press Space to preview the selected file.")
                        .font(.system(size: 10.5)).foregroundStyle(Brand.textMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                    if !compact {
                        divider.padding(.vertical, 17)
                        safetyNote(compact: false)
                    }
                    if !item.note.isEmpty {
                        Text(item.note).font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                            .padding(.top, 12)
                    }
                    if !item.isActionable {
                        Text("Advice only · no cleanup action is available for this item.")
                            .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                            .padding(.top, 11)
                    }
                }
                .padding(21).frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            WorkspaceEmpty(title: "Choose a file", message: "Its preview, location and review requirement will appear here.")
        }
    }

    private func footer(selected: [ScanItem], selectedElsewhere: Int) -> some View {
        let selectedBytes = selected.reduce(Int64(0)) { $0 + $1.allocatedSize }
        return HStack(spacing: 13) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(selected.count) item\(selected.count == 1 ? "" : "s") selected")
                    .font(.system(size: 14, weight: .medium))
                Text(selectedElsewhere > 0
                    ? "\(Fmt.size(selectedBytes)) here · \(selectedElsewhere) also selected in other screens"
                    : "Moving to Trash does not immediately free space.")
                    .font(.system(size: 10.5)).foregroundStyle(selectedElsewhere > 0 ? Brand.amber : Brand.textMuted)
            }
            Spacer(minLength: 6)
            if !selected.isEmpty {
                Button("Clear selection") { for item in selected { store.toggle(item.id) } }
                    .buttonStyle(ControlPanelButtonStyle())
            }
            Button("Review cleanup…", action: onReview)
                .buttonStyle(ControlPanelButtonStyle(primary: true))
                .disabled(preview || selected.isEmpty || store.isScanning || store.isCleaning)
        }
        .padding(.horizontal, 22).frame(height: 72)
        .background(Brand.background)
        .overlay(alignment: .top) { divider }
    }

    private var emptyTitle: String {
        if store.isScanning && !preview { return "Reading files" }
        if store.phase == .cancelled && !preview { return "Scan stopped" }
        if !store.hasScanned && !preview { return "Start with a scan" }
        return search.isEmpty && filter == .all ? "No large files found" : "No matching files"
    }
    private var emptyMessage: String {
        if !store.hasScanned && !preview { return "Use Rescan to measure large files in supported folders." }
        if store.phase == .cancelled && !preview { return "Results may be incomplete. Rescan before choosing a file." }
        return "Try another file type or search. Inaccessible locations may be missing from this scan."
    }
    private var divider: some View { Rectangle().fill(Brand.separator).frame(height: 0.5) }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title).foregroundStyle(Brand.textSecondary).frame(width: 88, alignment: .leading)
            Text(value).foregroundStyle(Brand.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
        }.font(.system(size: 11.5)).padding(.vertical, 4)
    }
    private func safetyNote(compact: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(Brand.amber).font(.system(size: 17))
            VStack(alignment: .leading, spacing: 5) {
                Text("Personal file · Review required")
                    .font(.system(size: 12.5, weight: .medium))
                Text(compact ? "This may be your only copy. Check your backup before selecting it."
                             : "This may be your only copy. Check whether you still need it and have a separate backup before selecting it.")
                    .font(.system(size: 11.5)).foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func matchesFilter(_ item: ScanItem) -> Bool {
        if filter == .all { return true }
        let ext = item.url.pathExtension.lowercased()
        switch filter {
        case .all: return true
        case .videos: return ["mov", "mp4", "m4v", "mkv", "avi"].contains(ext)
        case .downloads: return item.url.path.contains("/Downloads/")
        case .archives: return ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "tgz"].contains(ext)
        case .diskImages: return ["dmg", "iso", "sparsebundle", "sparseimage", "img"].contains(ext)
        case .backups: return ["sparsebundle", "ipsw"].contains(ext) || item.url.lastPathComponent.localizedCaseInsensitiveContains("backup")
        }
    }
    private func fileKind(_ item: ScanItem) -> String {
        (try? item.resolvedURL.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription
            ?? (item.url.pathExtension.isEmpty ? "File" : item.url.pathExtension.uppercased() + " file")
    }
    private func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
    private func quickLook(_ item: ScanItem) {
        guard !preview, FileManager.default.fileExists(atPath: item.resolvedURL.path) else { return }
        quickLookURL = item.resolvedURL
    }
    private func reveal(_ item: ScanItem) {
        guard !preview, FileManager.default.fileExists(atPath: item.resolvedURL.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.resolvedURL])
    }
    private func copyPath(_ item: ScanItem) {
        guard !preview else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.resolvedURL.path, forType: .string)
    }

    private static func makeSamples() -> [ScanItem] {
        let examples: [(String, Int64, Int)] = [
            ("Coast-film.mov", 3_800_000_000, 2),
            ("Brand-assets.zip", 2_100_000_000, 8),
            ("Product-demo.mov", 1_400_000_000, 11),
            ("Old-installer.dmg", 940_000_000, 18),
            ("Interview.wav", 620_000_000, 20)
        ]
        return examples.map { name, size, days in
            ScanItem(url: URL(fileURLWithPath: "/Sample/" + name), allocatedSize: size,
                     latestModified: Date().addingTimeInterval(-Double(days) * 86_400),
                     categoryID: "large-old", severity: .review, isRegenerable: false,
                     cleanMethod: .adviceOnly, note: "Sample data for interface preview.")
        }
    }

}

/// Only the focused item asks Quick Look for a larger thumbnail. The existing
/// thumbnail queue bounds concurrent requests and the Finder icon is a safe
/// fallback for unsupported formats or a missing file.
private enum LargeFileSampleArt {
    static let image: NSImage? = {
        let name = "SampleCoastFilm.png"
        let candidates = [Bundle.main.resourceURL?.appendingPathComponent(name),
                          URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                            .appendingPathComponent("Cairn/Resources/" + name)]
        for case let url? in candidates {
            if let image = NSImage(contentsOf: url) { return image }
        }
        return nil
    }()
}

private struct LargeFilePreviewArtwork: View {
    let url: URL
    let preview: Bool
    @State private var image: NSImage?
    @State private var requestedPath = ""

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Brand.surfaceElevated)
                if preview, url.lastPathComponent == "Coast-film.mov",
                   let sample = LargeFileSampleArt.image {
                    Image(nsImage: sample).resizable().scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    Text("SAMPLE")
                        .font(.system(size: 9, weight: .semibold)).tracking(0.7)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(.black.opacity(0.6), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(9)
                } else if let image {
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    VStack(spacing: 10) {
                        FileIcon(url: url, size: 64)
                        if preview { Text("Sample preview").font(.system(size: 10.5)).foregroundStyle(Brand.textMuted) }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .task(id: url.path) {
            image = nil
            let path = url.path
            requestedPath = path
            guard !preview, FileManager.default.fileExists(atPath: url.path) else { return }
            ThumbnailCache.shared.generate(url: url, side: 340, scale: 2) { generated in
                if requestedPath == path { image = generated }
            }
        }
    }
}
