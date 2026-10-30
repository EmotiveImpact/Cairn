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

    @State private var filter: FileFilter = .all
    @State private var inspectedID: UUID?
    @State private var quickLookURL: URL?
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
        }.sorted { $0.allocatedSize > $1.allocatedSize }
    }

    var body: some View {
        // Resolve the filtered order and inspector once per render. Doing this
        // inside every row made large result sets quadratic on the main actor.
        let source = sourceItems
        let visible = visibleItems(from: source)
        let selected = source.filter { $0.selected && $0.isActionable && $0.severity != .risky }
        let selectedElsewhere = preview ? 0 : max(0, store.selectedCount - selected.count)
        let inspected = visible.first { $0.id == inspectedID } ?? visible.first
        let largest = visible.map(\.allocatedSize).max() ?? 1
        let selectedBytes = selected.reduce(Int64(0)) { $0 + $1.allocatedSize }
        return CairnWorkspace(
            eyebrow: store.isScanning && !preview ? "Files · scanning" : "Files · \(visible.count) large \(visible.count == 1 ? "file" : "files")",
            title: "\(Fmt.size(visible.reduce(0) { $0 + $1.allocatedSize })) in large files",
            subtitle: "Look inside before you decide. These may be your only copies, so nothing is chosen for you.",
            inspectorVisible: inspectorVisible, onCloseInspector: { inspectorVisible = false }) {
            Button(store.isScanning ? "Stop scan" : "Rescan", action: onRescan)
                .buttonStyle(ControlPanelButtonStyle(size: .small))
                .keyboardShortcut("r", modifiers: .command)
                .disabled(preview || store.isCleaning)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                filters
                if store.phase == .cancelled && !preview && !visible.isEmpty {
                    NightEmpty(title: "Scan stopped", message: "These results may be incomplete. Rescan before choosing.")
                }
                if visible.isEmpty {
                    NightEmpty(title: emptyTitle, message: emptyMessage, busy: store.isScanning && !preview)
                    Spacer(minLength: 0)
                } else {
                    NightList {
                        ForEach(visible) { item in
                            fileRow(item, focused: inspectorVisible && inspected?.id == item.id, largest: largest)
                        }
                    }
                }
            }
        } detail: {
            if let inspected { detailContent(inspected) }
            else { NightEmpty(title: "Choose a file", message: "Its preview and where it lives appear here.") }
        } actions: {
            NightTotal(strong: Fmt.size(selectedBytes),
                       rest: selectedElsewhere > 0 ? "selected · \(selectedElsewhere) picked on other screens are not included" : "selected")
            Spacer()
            if !selected.isEmpty {
                Button("Select none") { for item in selected { store.toggle(item.id) } }
                    .buttonStyle(ControlPanelButtonStyle(size: .large))
            }
            // Reviews only the files picked here, so the review shows this same number.
            Button(selected.isEmpty ? "Review cleanup" : "Review cleanup · \(Fmt.size(selectedBytes))") {
                store.beginScopedReview(Set(selected.map(\.id)))
                onReview()
            }
                .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
                .disabled(preview || selected.isEmpty || store.isScanning || store.isCleaning)
        }
        .quickLookPreview($quickLookURL)
        .onAppear {
            if !opened { inspectorVisible = true; opened = true }
        }
    }

    /// Quiet text filters, as on Apps. Sort stays by size, largest first.
    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(FileFilter.allCases) { option in
                    Button(option == .all ? "All" : option.rawValue) { filter = option }
                        .buttonStyle(.plain).font(.system(size: 12)).fixedSize()
                        .foregroundStyle(filter == option ? Brand.textPrimary : Brand.textMuted)
                }
            }
        }
    }

    /// Check | thumbnail, name and folder | share | size | pill, as in the reference rows.
    private func fileRow(_ item: ScanItem, focused: Bool, largest: Int64) -> some View {
        let canSelect = item.isActionable && item.severity != .risky && !preview
        return HStack(spacing: 14) {
            NightCheck(on: item.selected, enabled: canSelect) {
                store.toggle(item.id)
                inspectedID = item.id
            }
            .accessibilityLabel(canSelect ? (item.selected ? "Deselect \(item.url.lastPathComponent)" : "Select \(item.url.lastPathComponent) for review") : "\(item.url.lastPathComponent) is advice only")
            Button {
                inspectedID = item.id
                inspectorVisible = true
            } label: {
                HStack(spacing: 14) {
                    HStack(spacing: 10) {
                        Group {
                            if preview, item.url.lastPathComponent == "Coast-film.mov", let sample = LargeFileSampleArt.image {
                                Image(nsImage: sample).resizable().scaledToFill()
                            } else if preview { FileIcon(url: item.url, size: 22) }
                            else { ThumbnailView(url: item.resolvedURL, size: 22) }
                        }
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.url.lastPathComponent).font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Brand.textPrimary).lineLimit(1).truncationMode(.middle)
                            Text(folderLine(item)).font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Keep filenames readable when the inspector narrows the list.
                    if !inspectorVisible {
                        NightMeter(share: Double(item.allocatedSize) / Double(max(1, largest)))
                    }
                    Text(Fmt.size(item.allocatedSize)).font(.system(size: 13, weight: .medium)).monospacedDigit()
                        .frame(width: inspectorVisible ? 70 : 90, alignment: .trailing)
                    NightPill(text: item.selected ? "Selected" : item.isActionable ? "Needs you" : "Advice only",
                              tone: item.selected ? .ok : .neutral)
                        .frame(width: inspectorVisible ? 90 : 120, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .nightRow()
        .background(focused ? Brand.wash(0.035) : Color.clear)
        .contextMenu {
            Button("Quick Look") { quickLook(item) }
                .disabled(preview || !FileManager.default.fileExists(atPath: item.resolvedURL.path))
            Button("Show in Finder") { reveal(item) }
                .disabled(preview || !FileManager.default.fileExists(atPath: item.resolvedURL.path))
            Button("Copy path") { copyPath(item) }.disabled(preview)
        }
    }

    /// "~/Downloads · 3 Oct 2025": the folder and when it last changed.
    private func folderLine(_ item: ScanItem) -> String {
        let folder = shortPath(item.resolvedURL.deletingLastPathComponent().path)
        guard item.latestModified > .distantPast else { return folder }
        return folder + " · " + item.latestModified.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// The preview first, then the plain facts. Click the picture or press Space to look closer.
    @ViewBuilder private func detailContent(_ item: ScanItem) -> some View {
        LargeFilePreviewArtwork(url: item.resolvedURL, preview: preview)
            .frame(height: 256 * 9 / 16)
            .id(item.id)
            .contentShape(Rectangle())
            .onTapGesture { quickLook(item) }
            .help("Click or press Space to look closer")
        VStack(alignment: .leading, spacing: 2) {
            Text(item.url.lastPathComponent).font(.system(size: 15, weight: .medium))
                .lineLimit(2).textSelection(.enabled)
            Text("\(fileKind(item)) · \(Fmt.size(item.allocatedSize))")
                .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
        }
        VStack(spacing: 0) {
            detailRow("Where", shortPath(item.resolvedURL.deletingLastPathComponent().path))
            if item.latestModified > .distantPast {
                detailRow("Last changed", item.latestModified.formatted(date: .abbreviated, time: .omitted))
            }
        }
        HStack(spacing: 8) {
            Button("Quick Look") { quickLook(item) }
                .buttonStyle(ControlPanelButtonStyle())
                .keyboardShortcut(.space, modifiers: [])
            Button("Show in Finder") { reveal(item) }
                .buttonStyle(ControlPanelButtonStyle())
        }
        .disabled(preview || !FileManager.default.fileExists(atPath: item.resolvedURL.path))
        if item.isActionable && item.severity != .risky {
            Button(item.selected ? "Remove from selection" : "Select for cleanup") {
                store.toggle(item.id)
            }
            .buttonStyle(ControlPanelButtonStyle())
            .disabled(preview || store.isScanning || store.isCleaning)
        }
        Text(item.isActionable && item.severity != .risky
             ? "This may be your only copy. Select it, then review the clean, where you can choose Move to Trash or Delete now."
             : "Cairn can't remove this. \(item.note.isEmpty ? "It holds protected data, or Cairn has no safe way to remove it." : item.note)")
            .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
            .fixedSize(horizontal: false, vertical: true)
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
    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).foregroundStyle(Brand.textSecondary).frame(width: 84, alignment: .leading)
            Text(value).fontWeight(.medium).frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
        }
        .font(.system(size: 12.5)).padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.wash(0.06)).frame(height: 1) }
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
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Brand.deepPanel)
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
                        .transition(.opacity)
                } else {
                    VStack(spacing: 10) {
                        FileIcon(url: url, size: 64)
                        if preview { Text("Sample preview").font(.system(size: 10.5)).foregroundStyle(Brand.textMuted) }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Brand.separator, lineWidth: 0.5))
            .animation(.easeOut(duration: 0.25), value: image != nil)
        }
        .task(id: url.path) {
            image = nil
            let path = url.path
            requestedPath = path
            guard !preview, FileManager.default.fileExists(atPath: url.path) else { return }
            ThumbnailCache.shared.generate(url: url, side: 340, scale: 2) { generated in
                if requestedPath == path { withAnimation(.easeOut(duration: 0.25)) { image = generated } }
            }
        }
    }
}
