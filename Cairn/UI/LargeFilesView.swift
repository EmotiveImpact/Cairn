import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Large Files page — Archetype B: sortable table + right-side file inspector.
/// Uses REAL file icons (NSWorkspace) and the large-old / installers buckets.
struct LargeFilesView: View {
    let store: ScanStore
    var proEnabled: Bool = false
    var onReview: () -> Void

    enum Filter: String, CaseIterable { case all = "All Files", videos = "Videos", downloads = "Downloads", archives = "Archives", diskImages = "Disk Images", backups = "Project Backups" }
    enum SortKey { case name, size, date }

    @State private var filter: Filter = .all
    @State private var sortKey: SortKey = .size
    @State private var ascending = false
    @State private var inspectedID: UUID?
    @State private var pendingTrash: ScanItem?
    @Bindable private var settings = AppSettings.shared   // so ignoring a file refreshes the list now

    private var allItems: [ScanItem] {
        store.buckets.filter { ["large-old", "installers"].contains($0.id) }.flatMap { $0.items }
            .filter { !settings.isExcluded($0.resolvedURL) }
    }

    private var items: [ScanItem] {
        var list = allItems.filter { matches(filter, $0) }
        switch sortKey {
        case .name: list.sort { $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending }
        case .size: list.sort { $0.allocatedSize < $1.allocatedSize }
        case .date: list.sort { $0.latestModified < $1.latestModified }
        }
        return ascending ? list : list.reversed()
    }

    private var inspected: ScanItem? { items.first { $0.id == inspectedID } ?? allItems.first { $0.id == inspectedID } }

    var body: some View {
        VStack(spacing: 0) {
            PageHero(title: "Large Files",
                     subtitle: "Heavy files taking real space — reviewed one at a time, never bulk-selected.",
                     progress: totalBytes > 0 ? 1 : 0.02,
                     value: totalBytes,
                     caption: "Found",
                     footnote: "\(allItems.count) files") {
                Button {
                    if let target = inspected ?? items.first { reveal(target) }
                } label: { Label("Reveal in Finder", systemImage: "magnifyingglass") }
                    .buttonStyle(WhiteButtonStyle())
                    .disabled(items.isEmpty)
            }
            pageContent.heroPageContent()
        }
    }

    private var totalBytes: Int64 { allItems.reduce(0) { $0 + $1.allocatedSize } }

    private var pageContent: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                statCards
                filterChips
                table
            }
            .frame(maxWidth: .infinity)
            if let inspected {
                LargeFileDetailPanel(item: inspected,
                                     onReveal: { reveal(inspected) },
                                     onIgnore: { AppSettings.shared.add(inspected.resolvedURL); inspectedID = nil },
                                     onTrash: {
                                        if settings.askBeforeDeleting { pendingTrash = inspected }
                                        else { Task { _ = await store.clean([inspected], proEnabled: proEnabled); inspectedID = nil } }
                                     })
                    .frame(width: 320)
            }
        }
        .confirmationDialog("Move “\(pendingTrash?.url.lastPathComponent ?? "")” to the Trash?",
                            isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } }),
                            titleVisibility: .visible) {
            if let item = pendingTrash {
                Button("Move \(Fmt.size(item.allocatedSize)) to Trash", role: .destructive) {
                    Task { _ = await store.clean([item], proEnabled: proEnabled); inspectedID = nil; pendingTrash = nil }
                }
            }
            Button("Cancel", role: .cancel) { pendingTrash = nil }
        } message: {
            Text("Large files are often irreplaceable. This moves it to the Trash — recoverable until you empty it.")
        }
    }

    private var statCards: some View {
        HStack(spacing: 14) {
            stat("internaldrive.fill", "Total Space Used", Fmt.size(DeviceInfo.used))
            stat("doc.fill", "Large Files Found", "\(allItems.count) files")
        }
    }

    private func stat(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Brand.blue)
                .frame(width: 40, height: 40).background(RoundedRectangle(cornerRadius: 10).fill(Brand.blue.opacity(0.1)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                Text(value).font(.system(size: 18, weight: .bold)).foregroundStyle(Brand.textPrimary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity).cairnCard(14)
    }

    private var filterChips: some View {
        HStack(spacing: 8) {
            ForEach(Filter.allCases, id: \.self) { f in
                Button { filter = f } label: {
                    Text(f.rawValue).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(filter == f ? Brand.blue : Brand.textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(filter == f ? Brand.blue.opacity(0.12) : .clear)
                            .overlay(Capsule().stroke(filter == f ? Brand.blue.opacity(0.3) : Brand.border, lineWidth: 1)))
                }.buttonStyle(.plain).pointerCursor()
            }
            Spacer()
        }
    }

    private var table: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("").frame(width: 28)
                colHeader("File Name", .name).frame(maxWidth: .infinity, alignment: .leading)
                Text("Location").font(colFont).foregroundStyle(Brand.textMuted).frame(width: 170, alignment: .leading)
                colHeader("Size", .size).frame(width: Brand.colSize, alignment: .trailing)
                colHeader("Last Opened", .date).frame(width: Brand.colDate, alignment: .trailing)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider().overlay(Brand.border)
            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            row(item)
                            Divider().overlay(Brand.border).padding(.leading, 14)
                        }
                    }
                }
            }
            Divider().overlay(Brand.border)
            HStack {
                Text("\(items.filter { $0.selected }.count) of \(items.count) files selected")
                    .font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
                Spacer()
                let sel = items.filter { $0.selected }.reduce(Int64(0)) { $0 + $1.allocatedSize }
                if sel > 0 {
                    Text("\(Fmt.size(sel)) selected").font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.blue)
                    Button("Review & Clean") { onReview() }.buttonStyle(BrandButtonStyle())
                }
            }
            .padding(14)
        }
        .background(CardBackground())
    }

    private func row(_ item: ScanItem) -> some View {
        let isInspected = inspectedID == item.id
        return HStack(spacing: 0) {
            Image(systemName: item.selected ? "checkmark.square.fill" : "square")
                .font(.system(size: 15)).foregroundStyle(item.selected ? Brand.blue : Brand.textMuted)
                .frame(width: 28).contentShape(Rectangle())
                .onTapGesture { store.toggle(item.id) }.pointerCursor()
            HStack(spacing: 9) {
                FileIcon(url: item.url, size: 22)
                Text(item.url.lastPathComponent).font(.system(size: 13)).foregroundStyle(Brand.textPrimary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(prettyDir(item.url)).font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                .lineLimit(1).truncationMode(.middle).frame(width: 170, alignment: .leading)
            Text(Fmt.size(item.allocatedSize)).font(.system(size: 12, weight: .medium)).foregroundStyle(Brand.textSecondary).frame(width: Brand.colSize, alignment: .trailing)
            Text(item.latestModified > .distantPast ? shortDate(item.latestModified) : "—")
                .font(.system(size: 12)).foregroundStyle(Brand.textMuted).frame(width: Brand.colDate, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(isInspected ? Brand.blue.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { inspectedID = item.id }.pointerCursor()
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 28)).foregroundStyle(Brand.textMuted)
            Text(store.isScanning ? "Scanning for large files…" : "No large files match this filter.")
                .font(.system(size: 13)).foregroundStyle(Brand.textMuted)
        }.frame(maxWidth: .infinity).padding(.vertical, 50)
    }

    private let colFont = Font.system(size: 11, weight: .semibold)
    private func colHeader(_ title: String, _ key: SortKey) -> some View {
        Button { if sortKey == key { ascending.toggle() } else { sortKey = key; ascending = false } } label: {
            HStack(spacing: 3) {
                Text(title).font(colFont).foregroundStyle(sortKey == key ? Brand.blue : Brand.textMuted)
                if sortKey == key { Image(systemName: ascending ? "chevron.up" : "chevron.down").font(.system(size: 8)).foregroundStyle(Brand.blue) }
            }
        }.buttonStyle(.plain).pointerCursor()
    }

    // MARK: helpers
    private func matches(_ f: Filter, _ item: ScanItem) -> Bool {
        let ext = item.url.pathExtension.lowercased()
        switch f {
        case .all: return true
        case .videos: return ["mov", "mp4", "m4v", "mkv", "avi"].contains(ext)
        case .downloads: return item.url.path.contains("/Downloads/")
        case .archives: return ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "tgz"].contains(ext)
        case .diskImages: return ["dmg", "iso", "sparsebundle", "sparseimage", "img"].contains(ext)
        case .backups: return ["sparsebundle", "ipsw"].contains(ext) || item.url.lastPathComponent.localizedCaseInsensitiveContains("backup")
        }
    }
    private func prettyDir(_ url: URL) -> String {
        let dir = url.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return dir.hasPrefix(home) ? "~" + dir.dropFirst(home.count) : dir
    }
    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f.string(from: d)
    }
    private func reveal(_ item: ScanItem) { NSWorkspace.shared.activateFileViewerSelecting([item.resolvedURL]) }
}

/// Right-side inspector for the selected large file.
struct LargeFileDetailPanel: View {
    let item: ScanItem
    var onReveal: () -> Void
    var onIgnore: () -> Void
    var onTrash: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 10) {
                FileIcon(url: item.url, size: 72)
                Text(item.url.lastPathComponent).font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Brand.textPrimary).multilineTextAlignment(.center).lineLimit(2)
                Text("\(kind) – \(Fmt.size(item.allocatedSize))").font(.system(size: 12)).foregroundStyle(Brand.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)

            Divider().overlay(Brand.border)
            metaRow("Location", prettyDir)
            metaRow("Size", Fmt.size(item.allocatedSize))
            metaRow("Kind", kind)
            if let c = created { metaRow("Created", longDate(c)) }
            if item.latestModified > .distantPast { metaRow("Modified", longDate(item.latestModified)) }
            Divider().overlay(Brand.border)
            Text("QUICK ACTIONS").font(.system(size: 10, weight: .black)).tracking(1).foregroundStyle(Brand.textMuted)
            Button { onReveal() } label: { Label("Reveal in Finder", systemImage: "magnifyingglass").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(GhostButtonStyle())
            Button { onIgnore() } label: { Label("Ignore This File", systemImage: "eye.slash").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(GhostButtonStyle())
            Button { onTrash() } label: { Label("Move to Bin", systemImage: "trash").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(GhostButtonStyle())
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(CardBackground())
    }

    private var prettyDir: String {
        let dir = item.url.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return dir.hasPrefix(home) ? "~" + dir.dropFirst(home.count) : dir
    }
    private var kind: String {
        (try? item.url.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription
            ?? item.url.pathExtension.uppercased()
    }
    private var created: Date? {
        (try? item.url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
    }
    private func longDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f.string(from: d)
    }
    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.system(size: 11)).foregroundStyle(Brand.textMuted).frame(width: 70, alignment: .leading)
            Text(value).font(.system(size: 11)).foregroundStyle(Brand.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing).multilineTextAlignment(.trailing).lineLimit(2)
        }
    }
}
