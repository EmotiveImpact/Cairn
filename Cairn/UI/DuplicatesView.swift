import SwiftUI
import AppKit
import QuickLookThumbnailing

// MARK: - Thumbnail (QuickLook content preview, FileIcon fallback)

/// Caches QuickLook thumbnails (images/video/PDF) keyed by path+mtime so the list
/// scrolls smoothly. Falls back to the real Finder icon while loading / for
/// non-previewable types via the existing `IconCache`.
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let store = NSCache<NSString, NSImage>()   // auto-evicting, thread-safe
    init() {
        store.countLimit = 400
        // A selected large file can request a much larger preview than a list
        // row. Bound decoded image memory by cost as well as entry count.
        store.totalCostLimit = 48 * 1024 * 1024
    }

    // QLThumbnailGenerator applies NO concurrency limit of its own. With a few
    // hundred visible rows every one fired a request at once and each completion
    // decoded an image and hopped to the main queue — that storm is what hung the
    // main thread on the Duplicates page. Requests are now queued, at most
    // `maxInFlight` at a time, and duplicate requests for the same key coalesce.
    private let lock = NSLock()
    private var inFlight = 0
    private var pendingKeys = Set<String>()
    private var queue: [(key: String, url: URL, side: CGFloat, scale: CGFloat, done: (NSImage) -> Void)] = []
    private let maxInFlight = 3
    private let maxQueued = 60          // don't hoard work for rows scrolled past

    func cached(_ key: String) -> NSImage? { store.object(forKey: key as NSString) }
    func set(_ image: NSImage, for key: String, cost: Int) {
        store.setObject(image, forKey: key as NSString, cost: cost)
    }

    /// Cancel queued (not yet started) work — call when a view goes away.
    func drainQueue() {
        lock.lock(); queue.removeAll(); pendingKeys.removeAll(); lock.unlock()
    }

    private func enqueue(key: String, url: URL, side: CGFloat, scale: CGFloat,
                         done: @escaping (NSImage) -> Void) {
        lock.lock()
        guard !pendingKeys.contains(key) else { lock.unlock(); return }
        pendingKeys.insert(key)
        queue.append((key, url, side, scale, done))
        if queue.count > maxQueued {
            let dropped = queue.removeFirst()
            pendingKeys.remove(dropped.key)
        }
        lock.unlock()
        pump()
    }

    private func pump() {
        lock.lock()
        guard inFlight < maxInFlight, !queue.isEmpty else { lock.unlock(); return }
        let job = queue.removeLast()          // newest first — that's what's on screen
        pendingKeys.remove(job.key)
        inFlight += 1
        lock.unlock()

        let size = CGSize(width: job.side, height: job.side)
        let req = QLThumbnailGenerator.Request(fileAt: job.url, size: size, scale: job.scale,
                                              representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
            guard let self else { return }
            if let rep {
                // Quick Look can return a wide video frame for a square request.
                // Giving NSImage the requested square size distorts that frame
                // even when the view later uses scaledToFit or scaledToFill.
                let pixels = rep.cgImage
                let imageSize = CGSize(width: CGFloat(pixels.width) / job.scale,
                                       height: CGFloat(pixels.height) / job.scale)
                let img = NSImage(cgImage: pixels, size: imageSize)
                self.set(img, for: job.key,
                         cost: rep.cgImage.bytesPerRow * rep.cgImage.height)
                DispatchQueue.main.async { job.done(img) }
            }
            self.lock.lock(); self.inFlight -= 1; self.lock.unlock()
            self.pump()                        // start the next one
        }
    }

    func generate(url: URL, side: CGFloat, scale: CGFloat, completion: @escaping (NSImage) -> Void) {
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)#\(side)#\(Int(mtime))"   // include mtime so a changed file re-renders
        if let hit = cached(key) { completion(hit); return }
        enqueue(key: key, url: url, side: side, scale: scale, done: completion)
    }
}

/// Real content thumbnail for a file, with a graceful Finder-icon fallback.
struct ThumbnailView: View {
    let url: URL
    var size: CGFloat = 40
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                Image(nsImage: IconCache.shared.icon(for: url)).resizable().interpolation(.high)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous).stroke(Brand.border, lineWidth: 1))
        .task(id: url.path) {
            image = nil
            ThumbnailCache.shared.generate(url: url, side: size, scale: 2) { img in
                self.image = img
            }
        }
    }
}

// MARK: - Duplicates screen (Archetype C: stat cards + grouped list + pinned footer)

struct DuplicatesView: View {
    @Bindable var store: DuplicateStore
    @State private var expanded: Set<UUID> = []
    @State private var didStart = false
    @State private var showResult = false
    @State private var confirmRemove = false
    @State private var lastResult: DuplicateStore.RemovalResult?

    var body: some View {
        VStack(spacing: 0) {
            PageHero(title: "Duplicates",
                     subtitle: "Verified byte-for-byte by hash. One copy of every file always survives.",
                     progress: store.reclaimableBytes > 0 ? 1 : 0.02,
                     value: store.reclaimableBytes,
                     caption: "Reclaimable",
                     footnote: store.isScanning ? "Scanning…" : "\(store.groupCount) groups") {
                if store.isScanning {
                    Button("Stop") { store.cancel() }.buttonStyle(WhiteButtonStyle())
                } else {
                    Button("Auto-select recommended") { store.autoSelectRecommended() }
                        .buttonStyle(WhiteButtonStyle())
                        .disabled(store.groups.isEmpty)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    statCards
                    if store.isScanning && store.groups.isEmpty {
                        scanningState
                    } else if store.hasScanned && store.groups.isEmpty {
                        emptyState
                    } else {
                        toolbar
                        groupList
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
            }
            if store.selectedCopyCount > 0 { footer }
        }
        .background(Brand.background)
        .task {
            guard !didStart else { return }
            didStart = true
            store.startIfNeeded()
        }
        .onDisappear { ThumbnailCache.shared.drainQueue() }   // don't render for a page you left
        .confirmationDialog("Move \(store.selectedCopyCount) duplicate\(store.selectedCopyCount == 1 ? "" : "s") to the Trash?",
                            isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Move \(Fmt.size(store.selectedBytes)) to Trash", role: .destructive) {
                Task {
                    let r = await store.removeSelected()
                    lastResult = r
                    showResult = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The recommended “Keep” copy in each group stays. Everything moved is recoverable from the Trash.")
        }
        .alert("Moved to Trash", isPresented: $showResult, presenting: lastResult) { _ in
            Button("OK", role: .cancel) {}
        } message: { r in
            Text("Moved \(r.trashed) duplicate\(r.trashed == 1 ? "" : "s") to Trash · \(Fmt.size(r.bytes)) recoverable."
                 + (r.failed > 0 ? "\n\(r.failed) could not be removed." : ""))
        }
    }

    // MARK: Header

    // MARK: Stat cards

    private var statCards: some View {
        HStack(spacing: 14) {
            statCard("doc.on.doc.fill", "Duplicate Groups", grouped(store.groupCount))
            statCard("doc.on.doc", "Duplicate Files", grouped(store.duplicateFileCount))
            statCard("doc.on.doc", "Extra-copy file size", Fmt.size(store.reclaimableBytes))
        }
    }

    private func statCard(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Brand.blue)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(Brand.blue.opacity(0.1)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Brand.textPrimary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity).cairnCard(14)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Menu {
                Picker("Sort", selection: $store.sortOrder) {
                    ForEach(DuplicateStore.SortOrder.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.arrow.down").font(.system(size: 11, weight: .semibold))
                    Text("Sort by \(store.sortOrder.rawValue)").font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Brand.textSecondary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).stroke(Brand.inputBorder, lineWidth: 1))
            }
            .menuStyle(.borderlessButton).fixedSize()

            Text("\(grouped(store.visibleGroups.count)) groups found")
                .font(.system(size: 12)).foregroundStyle(Brand.textSecondary)

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                TextField("Search duplicates…", text: $store.searchQuery)
                    .textFieldStyle(.plain).font(.system(size: 13)).frame(width: 180)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Brand.surfaceSubtle)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.inputBorder, lineWidth: 1)))
        }
    }

    // MARK: Group list

    private var groupList: some View {
        LazyVStack(spacing: 10) {
            ForEach(store.visibleGroups) { group in
                groupCard(group)
            }
            if store.hasMoreGroups {
                VStack(spacing: 7) {
                    Text("Showing the \(store.visibleGroups.count) biggest of \(store.matchingGroupCount) groups")
                        .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                    Button("Show 120 more") { store.showMoreGroups() }
                        .buttonStyle(GhostButtonStyle())
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
            }
        }
    }

    private func groupCard(_ group: DupGroup) -> some View {
        let isOpen = expanded.contains(group.id)
        return VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isOpen { expanded.remove(group.id) } else { expanded.insert(group.id) }
                }
            } label: {
                HStack(spacing: 12) {
                    if let rep = group.representativeURL {
                        ThumbnailView(url: rep, size: 40)
                    } else {
                        IconTile(systemImage: "doc.on.doc", size: 40)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.name).font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Brand.textPrimary).lineLimit(1)
                        pill("\(group.count) duplicates", Brand.blue)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Fmt.size(group.totalSize)).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Brand.textSecondary)
                        Text("\(Fmt.size(group.reclaimableSize)) extra-copy file size")
                            .font(.system(size: 10)).foregroundStyle(Brand.textMuted)
                    }
                    Button("Keep Best") { store.keepBest(group.id) }
                        .buttonStyle(GhostButtonStyle())
                    Button("Remove") {
                        store.keepBest(group.id)
                        if !isOpen { withAnimation(.easeInOut(duration: 0.18)) { _ = expanded.insert(group.id) } }
                    }
                    .buttonStyle(BrandButtonStyle())
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Brand.textMuted).rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).pointerCursor()

            if isOpen {
                Divider().overlay(Brand.border)
                LazyVStack(spacing: 2) {   // lazy: a group can hold many copies
                    ForEach(group.files) { file in
                        fileRow(file, in: group)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 8)
            }
        }
        .background(CardBackground())
    }

    private func fileRow(_ file: DupFile, in group: DupGroup) -> some View {
        HStack(spacing: 10) {
            Image(systemName: file.selected ? "checkmark.square.fill" : "square")
                .font(.system(size: 15))
                .foregroundStyle(file.isKeeper ? Brand.textMuted.opacity(0.4) : (file.selected ? Brand.blue : Brand.textMuted))
                .frame(width: 22)
                .contentShape(Rectangle())
                .onTapGesture { store.toggle(file.id) }.pointerCursor()
                .disabled(file.isKeeper)

            ThumbnailView(url: file.url, size: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(file.name).font(.system(size: 13)).foregroundStyle(Brand.textPrimary).lineLimit(1)
                    if file.isKeeper {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill").font(.system(size: 8))
                            Text("KEEP").font(.system(size: 8, weight: .black)).tracking(0.5)
                        }
                        .foregroundStyle(Brand.amber)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Brand.amber.opacity(0.14)))
                    }
                }
                Text(prettyDir(file.url)).font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if !file.isKeeper {
                Button {
                    store.setKeeper(file.id, in: group.id)
                } label: {
                    Image(systemName: "star").font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                }
                .buttonStyle(.plain).help("Keep this copy instead").pointerCursor()
            }
            Text(Fmt.size(file.size)).font(.system(size: 12, weight: .medium))
                .foregroundStyle(Brand.textSecondary).frame(width: 70, alignment: .trailing)
            Text(file.modified > .distantPast ? shortDate(file.modified) : "—")
                .font(.system(size: 11)).foregroundStyle(Brand.textMuted).frame(width: 88, alignment: .trailing)
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(file.selected ? Brand.blue.opacity(0.06) : .clear))
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text("\(grouped(store.selectedCopyCount)) file\(store.selectedCopyCount == 1 ? "" : "s") selected · \(Fmt.size(store.selectedBytes))")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.textSecondary)
            Spacer()
            Button {
                confirmRemove = true
            } label: {
                Text(store.isRemoving ? "Checking copies…" : "Review \(grouped(store.selectedCopyCount)) copies →")
            }
            .buttonStyle(BrandButtonStyle())
            .disabled(store.isRemoving)
        }
        .padding(.horizontal, 28).padding(.vertical, 14)
        .background(Brand.surfaceElevated)
        .overlay(Divider().overlay(Brand.border), alignment: .top)
    }

    // MARK: States

    private var scanningState: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text(store.progressText.isEmpty ? "Scanning for duplicates…" : store.progressText)
                .font(.system(size: 13)).foregroundStyle(Brand.textSecondary)
            Text("Comparing file sizes, then verifying content by hash. This runs in the background — you can cancel anytime.")
                .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                .multilineTextAlignment(.center).frame(maxWidth: 380)
            Button("Cancel scan") { store.cancel() }.buttonStyle(GhostButtonStyle())
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60)
        .cairnCard(20)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle").font(.system(size: 34)).foregroundStyle(Brand.safeCyan)
            Text("No duplicates found").font(.system(size: 15, weight: .semibold)).foregroundStyle(Brand.textPrimary)
            Text("Your Downloads, Documents, Desktop, Pictures and Movies are duplicate-free.")
                .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                .multilineTextAlignment(.center).frame(maxWidth: 380)
            Button("Rescan") { store.rescan() }.buttonStyle(GhostButtonStyle()).padding(.top, 4)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60)
        .cairnCard(20)
    }

    // MARK: Bits

    private func grouped(_ n: Int) -> String {
        return Fmt.grouped(n)
    }
    private func pill(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .black)).tracking(0.5).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.14)))
    }
    private func prettyDir(_ url: URL) -> String {
        let dir = url.deletingLastPathComponent().path
        let home = FileScan.home.path
        return dir.hasPrefix(home) ? "~" + dir.dropFirst(home.count) : dir
    }
    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f.string(from: d)
    }
}
