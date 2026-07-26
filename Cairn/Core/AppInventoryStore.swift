import Foundation
import AppKit
import Observation

/// A tiny thread-safe cancellation flag shared between the @MainActor store and
/// its off-main (`Task.detached`) enumeration — a detached task cannot see the
/// parent's `Task.isCancelled`, so without this the walk runs to completion even
/// after the user navigates away. Flipping it stops the walk between apps.
final class CancelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    func cancel() { lock.lock(); flag = true; lock.unlock() }
}

/// One installed application as a removable entity: the `.app` bundle plus every
/// associated support / cache / preference / container / log file we can key to
/// its bundle id. Selecting an app selects the whole set; uninstalling trashes
/// all of it (recoverable).
struct AppEntry: Identifiable {
    let id = UUID()
    var name: String
    var developer: String
    var bundleID: String
    var version: String
    var url: URL                      // the .app bundle
    var size: Int64                   // bundle on-disk size
    var supportSize: Int64            // Application Support / Containers / Group Containers
    var leftoverSize: Int64           // Caches / Preferences / Logs / Saved State / HTTPStorages / WebKit
    var associated: [URL]             // every associated ~/Library path (support + leftover)
    var lastOpened: Date?
    var isApple: Bool
    var isIntel: Bool
    var isSystem: Bool                // /System/Applications — shown, never removable
    var selected: Bool = false

    /// Total reclaimable bytes for this app (bundle + all associated files).
    var totalSize: Int64 { size + supportSize + leftoverSize }

    /// Combined support + leftover bytes (everything outside the bundle itself).
    var componentsSize: Int64 { supportSize + leftoverSize }

    /// Removable = a real third-party / user app we can safely trash.
    var isRemovable: Bool { !isSystem }

    /// Unused = never opened, or last opened more than 3 months ago.
    var isUnused: Bool {
        guard let last = lastOpened else { return true }
        return Date().timeIntervalSince(last) > 60 * 60 * 24 * 90
    }

    /// Large = bundle bigger than 1 GB.
    var isLarge: Bool { size > 1_000_000_000 }

    /// Has associated leftover/support files we can also remove.
    var hasLeftovers: Bool { !associated.isEmpty }
}

/// On-demand inventory of installed Mac apps + their associated files. Built to
/// stand alone (it is NOT registered in `ScannerRegistry`, so it never pollutes
/// Smart-Scan totals). Enumeration runs off-main and is cancellable; the view
/// kicks it once via `scanIfNeeded()`.
@MainActor
@Observable
final class AppInventoryStore {
    private(set) var apps: [AppEntry] = []
    private(set) var isScanning = false
    private(set) var hasScanned = false
    private(set) var progress: String = ""
    private(set) var lastError: String?

    nonisolated(unsafe) private var scanTask: Task<Void, Never>?
    nonisolated(unsafe) private var cancelBox: CancelBox?

    deinit { cancelBox?.cancel(); scanTask?.cancel() }

    // MARK: - Roots

    /// Directories that hold removable *.app bundles.
    private nonisolated static let userAppRoots: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: "/Applications/Utilities"),
        FileScan.home.appendingPathComponent("Applications"),
    ]
    /// System apps are shown (so the list is complete) but never removable.
    private nonisolated static let systemAppRoots: [URL] = [
        URL(fileURLWithPath: "/System/Applications"),
        URL(fileURLWithPath: "/System/Applications/Utilities"),
    ]

    /// The `~/Library` subtrees we scan for associated files, keyed by bundle id.
    private nonisolated static var librarySubtrees: [URL] {
        let lib = FileScan.home.appendingPathComponent("Library")
        return [
            "Application Support", "Caches", "Preferences", "Containers",
            "Group Containers", "Logs", "Saved Application State",
            "HTTPStorages", "WebKit",
        ].map { lib.appendingPathComponent($0) }
    }

    /// `~/Library` subtrees considered "support" (state / data) vs "leftover"
    /// (caches / prefs / regenerable). Drives the right-panel breakdown.
    private nonisolated static let supportSubtreeNames: Set<String> = [
        "Application Support", "Containers", "Group Containers",
    ]

    // MARK: - Lifecycle

    /// Start the scan once. Safe to call from `.task`/`onAppear` repeatedly.
    func scanIfNeeded() {
        guard !hasScanned, !isScanning else { return }
        rescan()
    }

    func rescan() {
        cancelBox?.cancel()          // stop any in-flight off-main walk
        scanTask?.cancel()
        let box = CancelBox()
        cancelBox = box
        isScanning = true
        lastError = nil
        progress = "Reading installed apps…"
        scanTask = Task { [weak self] in
            await ScanGate.shared.acquire()          // see ScanGate: one heavy scan at a time
            defer { ScanGate.shared.release() }
            await self?.run(box: box)
        }
    }

    func cancel() {
        cancelBox?.cancel()
        scanTask?.cancel()
        scanTask = nil
        if isScanning { isScanning = false }
    }

    // MARK: - Scan

    private func run(box: CancelBox) async {
        let result = await Task.detached(priority: .userInitiated) {
            Self.enumerate(isCancelled: { box.isCancelled })   // observes real cancellation
        }.value
        if box.isCancelled { return }
        apps = result.sorted { $0.size > $1.size }
        isScanning = false
        hasScanned = true
        progress = ""
    }

    /// Heavy filesystem work — runs entirely off-main.
    private nonisolated static func enumerate(isCancelled: () -> Bool) -> [AppEntry] {
        // Map every user-removable bundle id to its support/leftover sizes once,
        // so we walk the ~/Library subtrees a single time.
        var entries: [AppEntry] = []

        // 1) Discover apps.
        struct Raw { let url: URL; let isSystem: Bool }
        var raws: [Raw] = []
        for root in userAppRoots {
            for app in appBundles(in: root) { raws.append(Raw(url: app, isSystem: false)) }
        }
        for root in systemAppRoots {
            for app in appBundles(in: root) { raws.append(Raw(url: app, isSystem: true)) }
        }

        // 2) Pre-index the contents of each ~/Library subtree (one level deep) so
        //    we can match by bundle-id prefix without re-listing per app.
        var indexed: [(name: String, url: URL, isSupport: Bool)] = []
        for subtree in librarySubtrees {
            guard FileScan.exists(subtree), let children = FileScan.children(of: subtree) else { continue }
            let isSupport = supportSubtreeNames.contains(subtree.lastPathComponent)
            for child in children {
                indexed.append((name: child.lastPathComponent, url: child, isSupport: isSupport))
            }
        }

        // 3) Build an entry per app.
        for raw in raws {
            if isCancelled() { break }
            guard let info = readInfo(raw.url) else { continue }
            let bundleID = info.bundleID.lowercased()
            let stats = FileScan.measure(raw.url, maxFiles: 40_000)

            // Associated files: prefix-match the (normalized) folder/file name to
            // the bundle id on a dotted boundary. Skip Apple-owned entries.
            var support: Int64 = 0
            var leftover: Int64 = 0
            var associated: [URL] = []
            if !bundleID.hasPrefix("com.apple"), !bundleID.isEmpty {
                for entry in indexed {
                    let candidate = normalize(entry.name)
                    guard !candidate.isEmpty, dottedPrefixMatch(candidate, bundleID) else { continue }
                    let s = FileScan.measure(entry.url, maxFiles: 20_000).allocatedSize
                    associated.append(entry.url)
                    if entry.isSupport { support += s } else { leftover += s }
                }
            }

            entries.append(AppEntry(
                name: info.name,
                developer: developer(for: info.name, bundleID: bundleID),
                bundleID: info.bundleID,
                version: info.version,
                url: raw.url,
                size: stats.allocatedSize,
                supportSize: support,
                leftoverSize: leftover,
                associated: associated,
                lastOpened: lastOpened(raw.url),
                isApple: bundleID.hasPrefix("com.apple"),
                isIntel: machIsIntelOnly(raw.url),
                isSystem: raw.isSystem
            ))
        }
        return entries
    }

    // MARK: - App discovery helpers

    private nonisolated static func appBundles(in root: URL) -> [URL] {
        guard FileScan.exists(root), let children = FileScan.children(of: root) else { return [] }
        return children.filter { $0.pathExtension == "app" }
    }

    private struct Info { let name: String; let bundleID: String; let version: String }

    private nonisolated static func readInfo(_ app: URL) -> Info? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = obj as? [String: Any] else {
            // No plist (rare) — still list it by file name.
            let fallback = app.deletingPathExtension().lastPathComponent
            return Info(name: fallback, bundleID: "", version: "—")
        }
        let display = (dict["CFBundleDisplayName"] as? String)
            ?? (dict["CFBundleName"] as? String)
            ?? app.deletingPathExtension().lastPathComponent
        let id = (dict["CFBundleIdentifier"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let version = (dict["CFBundleShortVersionString"] as? String)
            ?? (dict["CFBundleVersion"] as? String) ?? "—"
        return Info(name: display, bundleID: id, version: version)
    }

    /// Best-effort developer/vendor name from the bundle id, falling back to the
    /// reverse-DNS organization segment, then "—".
    private nonisolated static func developer(for name: String, bundleID: String) -> String {
        if bundleID.hasPrefix("com.apple") { return "Apple" }
        let parts = bundleID.split(separator: ".")
        // com.<vendor>.<app> → <vendor>; io.<vendor>.<app> → <vendor>.
        if parts.count >= 2 {
            let prefixes: Set<String> = ["com", "io", "org", "net", "co", "app", "dev", "me"]
            let vendor = prefixes.contains(String(parts[0])) && parts.count >= 3
                ? String(parts[1])
                : String(parts.first ?? "")
            if !vendor.isEmpty { return vendor.prefix(1).uppercased() + vendor.dropFirst() }
        }
        return "—"
    }

    /// `kMDItemLastUsedDate` is the most accurate "last opened"; we approximate it
    /// with the content-access date (and fall back to modification date).
    private nonisolated static func lastOpened(_ app: URL) -> Date? {
        let keys: Set<URLResourceKey> = [.contentAccessDateKey, .contentModificationDateKey]
        guard let v = try? app.resourceValues(forKeys: keys) else { return nil }
        return v.contentAccessDate ?? v.contentModificationDate
    }

    /// Best-effort Intel-only detection by reading the Mach-O header of the main
    /// executable. Fat binaries listing an arm64 slice → not Intel-only.
    private nonisolated static func machIsIntelOnly(_ app: URL) -> Bool {
        guard let exe = mainExecutable(app),
              let fh = try? FileHandle(forReadingFrom: exe) else { return false }
        defer { try? fh.close() }
        guard let head = try? fh.read(upToCount: 4096), head.count >= 8 else { return false }

        func be32(_ o: Int) -> UInt32 {
            (UInt32(head[o]) << 24) | (UInt32(head[o+1]) << 16) | (UInt32(head[o+2]) << 8) | UInt32(head[o+3])
        }
        func le32(_ o: Int) -> UInt32 {
            (UInt32(head[o+3]) << 24) | (UInt32(head[o+2]) << 16) | (UInt32(head[o+1]) << 8) | UInt32(head[o])
        }
        let magic = be32(0)
        let FAT = UInt32(0xCAFEBABE), FAT_CIGAM = UInt32(0xBEBAFECA)
        let MH64 = UInt32(0xFEEDFACF), MH64_C = UInt32(0xCFFAEDFE)
        let MH32 = UInt32(0xFEEDFACE), MH32_C = UInt32(0xCEFAEDFE)
        let CPU_ARM64 = UInt32(0x0100000C)   // CPU_TYPE_ARM | ABI64

        if magic == FAT || magic == FAT_CIGAM {
            let count = magic == FAT ? be32(4) : le32(4)
            var off = 8
            var sawIntel = false
            for _ in 0..<min(count, 16) where off + 8 <= head.count {
                let cpuType = magic == FAT ? be32(off) : le32(off)
                if cpuType == CPU_ARM64 { return false }   // has arm64 → not Intel-only
                if cpuType == 0x01000007 || cpuType == 0x00000007 { sawIntel = true } // x86_64 / i386
                off += 20  // fat_arch is 20 bytes
            }
            return sawIntel
        }
        if magic == MH64 || magic == MH64_C || magic == MH32 || magic == MH32_C {
            let cpuType = (magic == MH64 || magic == MH32) ? be32(4) : le32(4)
            return cpuType == 0x01000007 || cpuType == 0x00000007
        }
        return false
    }

    private nonisolated static func mainExecutable(_ app: URL) -> URL? {
        let macOS = app.appendingPathComponent("Contents/MacOS")
        // Prefer the CFBundleExecutable named binary.
        if let dict = (try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")))
            .flatMap({ try? PropertyListSerialization.propertyList(from: $0, options: [], format: nil) }) as? [String: Any],
           let exe = dict["CFBundleExecutable"] as? String {
            let url = macOS.appendingPathComponent(exe)
            if FileScan.exists(url) { return url }
        }
        return FileScan.children(of: macOS)?.first
    }

    // MARK: - Bundle-id matching (mirrors OrphanedAppDataScanner, in reverse)

    private nonisolated static func normalize(_ name: String) -> String {
        var s = name
        // Strip a trailing extension (e.g. "com.acme.App.plist", ".savedState").
        if let dot = s.lastIndex(of: "."), s[s.index(after: dot)...].count <= 12,
           ["plist", "savedstate", "binarycookies"].contains(String(s[s.index(after: dot)...]).lowercased()) {
            s = String(s[s.startIndex..<dot])
        }
        if let stripped = strippingTeamID(s) { s = stripped }
        if s.hasPrefix("group.") { s = String(s.dropFirst("group.".count)) }
        if let stripped = strippingTeamID(s) { s = stripped }
        return s.lowercased()
    }

    private nonisolated static func strippingTeamID(_ name: String) -> String? {
        guard let dot = name.firstIndex(of: ".") else { return nil }
        let head = name[name.startIndex..<dot]
        guard head.count == 10 else { return nil }
        let isTeamID = head.allSatisfy { $0.isLetter || $0.isNumber } &&
            head.contains(where: { $0.isLetter }) && head.contains(where: { $0.isNumber })
        guard isTeamID else { return nil }
        return String(name[name.index(after: dot)...])
    }

    private nonisolated static func dottedPrefixMatch(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        // Require the matched (shorter) id to carry ≥2 dotted segments, so a short
        // or single-token name can't sweep in unrelated ~/Library folders.
        let shorter = a.count <= b.count ? a : b
        guard shorter.contains(".") else { return false }
        if a.hasPrefix(b + ".") { return true }
        if b.hasPrefix(a + ".") { return true }
        return false
    }

    // MARK: - Selection

    func toggle(_ id: UUID) {
        guard let i = apps.firstIndex(where: { $0.id == id }), apps[i].isRemovable else { return }
        apps[i].selected.toggle()
    }

    func setSelected(_ id: UUID, _ value: Bool) {
        guard let i = apps.firstIndex(where: { $0.id == id }), apps[i].isRemovable else { return }
        apps[i].selected = value
    }

    var selectedApps: [AppEntry] { apps.filter { $0.selected && $0.isRemovable } }
    var selectedCount: Int { selectedApps.count }
    var selectedReclaimable: Int64 { selectedApps.reduce(0) { $0 + $1.totalSize } }

    /// Sum of reclaimable space across apps that look unused (the headline metric).
    var unusedReclaimable: Int64 {
        apps.filter { $0.isRemovable && $0.isUnused }.reduce(0) { $0 + $1.totalSize }
    }
    var unusedCount: Int { apps.filter { $0.isRemovable && $0.isUnused }.count }
    var removableCount: Int { apps.filter { $0.isRemovable }.count }

    // MARK: - Uninstall (recoverable — everything goes to the Trash)

    struct UninstallSummary {
        var trashedApps = 0
        var failed = 0
        var bytes: Int64 = 0
        var errors: [String] = []
        var quit: [String] = []
    }

    /// Quit each selected app if running, then trash its bundle and every
    /// associated `~/Library` file. SAFETY: a path is only trashed if it is a
    /// `*.app` under one of the user app roots, or anything under `~/Library`.
    /// Everything else is refused. All moves are recoverable via the Trash.
    @discardableResult
    func uninstall(_ entries: [AppEntry]) async -> UninstallSummary {
        // 1) Quit running apps first.
        let runningIDs = entries.map { $0.bundleID }.filter { !$0.isEmpty }
        let toQuit = RunningApps.runningNow(amongst: runningIDs)
        var summary = UninstallSummary()
        if !toQuit.isEmpty {
            summary.quit = RunningApps.displayNames(for: toQuit)
            RunningApps.requestQuit(toQuit)
            // Give apps a moment to terminate before we move their bundles.
            try? await Task.sleep(nanoseconds: 600_000_000)
        }

        // 2) Trash bundle + associated files off-main; accumulate the result there.
        struct Batch { var done: Set<UUID> = []; var summary: UninstallSummary }
        let batch = await Task.detached(priority: .userInitiated) { () -> Batch in
            var b = Batch(summary: summary)
            for app in entries {
                // All-or-nothing: trash the bundle FIRST. If that fails (busy /
                // perms / relaunched), bail BEFORE touching the app's data so we
                // never orphan ~/Library files for a still-installed app.
                let (bundleOK, bundleBytes) = Self.trash(app.url)
                guard bundleOK else {
                    b.summary.failed += 1
                    b.summary.errors.append("\(app.name): could not move to Trash — left untouched")
                    continue
                }
                var moved = bundleBytes
                for url in app.associated {
                    let (ok, bytes) = Self.trash(url)
                    if ok { moved += bytes }
                }
                b.summary.trashedApps += 1
                b.summary.bytes += moved
                b.done.insert(app.id)
            }
            return b
        }.value

        // 3) Remove uninstalled apps from the list.
        apps.removeAll { batch.done.contains($0.id) }
        return batch.summary
    }

    /// Trash a single path IF it passes the conservative app-uninstall guard.
    /// Returns (success, bytesMoved). Recoverable via Finder's Put Back.
    private nonisolated static func trash(_ url: URL) -> (Bool, Int64) {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        guard isUninstallSafe(resolved), FileScan.exists(resolved) else { return (false, 0) }
        let bytes = FileScan.measure(resolved, maxFiles: 40_000).allocatedSize
        do {
            var out: NSURL?
            try FileManager.default.trashItem(at: resolved, resultingItemURL: &out)
            return (true, bytes)
        } catch {
            return (false, 0)
        }
    }

    /// Conservative guard, independent of `SafePaths`: a path may be trashed by
    /// the uninstaller ONLY if it is (a) a `*.app` directly under `/Applications`,
    /// `/Applications/Utilities`, or `~/Applications`, or (b) anything strictly
    /// under `~/Library`. Never `/System`, never a bare home/library root.
    nonisolated static func isUninstallSafe(_ resolved: URL) -> Bool {
        let path = resolved.standardizedFileURL.path
        if path == "/" || path.isEmpty { return false }
        let home = FileScan.home.path
        if resolved.standardizedFileURL == FileScan.home.standardizedFileURL { return false }

        // (a) *.app under a known user app root.
        if resolved.pathExtension == "app" {
            for root in userAppRoots {
                let parent = resolved.deletingLastPathComponent().standardizedFileURL.path
                if parent == root.standardizedFileURL.path { return true }
            }
        }

        // (b) Strictly inside ~/Library (but not the Library root itself), and NOT
        //     in a protected subtree (mail / messages / keychains / device backups
        //     / contacts & photo data) that an over-eager id match could reach.
        let lib = (home as NSString).appendingPathComponent("Library")
        if path != lib && path.hasPrefix(lib + "/") {
            let protectedSubpaths = [
                "Library/Keychains", "Library/Mail", "Library/Messages",
                "Library/Application Support/MobileSync",
                "Library/Application Support/AddressBook",
                "Library/Application Support/CallHistoryDB",
                "Library/Application Support/com.apple",
                "Library/Calendars", "Library/Photos", "Library/Suggestions",
                // AI agent conversation history — irreplaceable, never removable.
                "Library/Application Support/Claude",
            ]
            for p in protectedSubpaths {
                let full = (home as NSString).appendingPathComponent(p)
                if path == full || path.hasPrefix(full + "/") { return false }
            }
            return true
        }

        return false
    }
}
