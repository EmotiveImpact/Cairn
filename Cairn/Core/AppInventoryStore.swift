import Foundation
import AppKit
import Security
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

/// One installed application, with associated data shown for context. Selecting
/// an app moves only its `.app` bundle to Trash; support, cache, preferences,
/// containers and logs remain where they are.
struct AppEntry: Identifiable {
    let id = UUID()
    var name: String
    var developer: String
    var bundleID: String
    var version: String
    var url: URL                      // the .app bundle
    var sourceSnapshot: SourceSnapshot? // bundle seen during inventory
    var size: Int64                   // bundle on-disk size
    var supportSize: Int64            // Application Support / Containers / Group Containers
    var leftoverSize: Int64           // Caches / Preferences / Logs / Saved State / HTTPStorages / WebKit
    var associated: [URL]             // every associated ~/Library path (support + leftover)
    var lastOpened: Date?
    /// Where it came from: "App Store", "Homebrew", "Downloaded",
    /// "Came with macOS", or empty when the Mac doesn't record it.
    var source: String = ""
    var isApple: Bool
    var isIntel: Bool
    var isSystem: Bool                // /System/Applications — shown, never removable
    var selected: Bool = false

    /// Reclaimable under the conservative default: the app bundle only.
    /// Associated data can contain projects, settings or conversations.
    var totalSize: Int64 { size }

    /// Combined support + leftover bytes (everything outside the bundle itself).
    var componentsSize: Int64 { supportSize + leftoverSize }

    /// Removable = a real third-party / user app we can safely trash.
    var isRemovable: Bool {
        let id = bundleID.lowercased()
        return !isSystem && !id.contains("openai")
            && !["codex", "chatgpt"].contains(name.lowercased())
    }

    /// Unused = never opened, or last opened more than 3 months ago.
    var isUnused: Bool {
        guard let last = lastOpened else { return true }
        return Date().timeIntervalSince(last) > 60 * 60 * 24 * 90
    }

    /// Large = bundle bigger than 1 GB.
    var isLarge: Bool { size > 1_000_000_000 }

}

/// On-demand inventory of installed Mac apps + their associated files. Built to
/// stand alone (it is NOT registered in `ScannerRegistry`, so it never pollutes
/// Smart-Scan totals). Enumeration runs off-main and is cancellable; the view
/// kicks it once via `scanIfNeeded()`.
@MainActor
@Observable
final class AppInventoryStore {
    private(set) var isUninstalling = false
    var beginReceipt: (() async -> CleanupRun?)?
    var finishReceipt: ((CleanupRun, ScanStore.CleanSummary) async -> Bool)?
    var onRemovals: (([ScanStore.RemovalLogEntry]) async -> Bool)?
    var prepareRemoval: () async -> Bool = { false }

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
    private(set) var wasCancelled = false

    func scanIfNeeded() {
        guard !wasCancelled else { return }
        guard !hasScanned, !isScanning else { return }
        rescan()
    }

    func rescan() {
        guard !isUninstalling else { return }
        cancelBox?.cancel()          // stop any in-flight off-main walk
        scanTask?.cancel()
        let box = CancelBox()
        cancelBox = box
        wasCancelled = false
        isScanning = true
        lastError = nil
        progress = "Reading installed apps…"
        scanTask = Task { [weak self] in
            guard await ScanGate.shared.acquire(.apps) else { return }
            defer { ScanGate.shared.release() }
            guard !Task.isCancelled else { return }
            await self?.run(box: box)
        }
    }

    func cancel() {
        cancelBox?.cancel()
        scanTask?.cancel()
        scanTask = nil
        if isScanning { wasCancelled = true; isScanning = false }
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
        let casks = homebrewApps()
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
                    guard SafePaths.protectedSessionReason(entry.url) == nil else { continue }
                    let s = FileScan.measure(entry.url, maxFiles: 20_000).allocatedSize
                    associated.append(entry.url)
                    if entry.isSupport { support += s } else { leftover += s }
                }
            }

            entries.append(AppEntry(
                name: info.name,
                developer: signer(raw.url) ?? developer(for: info.name, bundleID: bundleID),
                bundleID: info.bundleID,
                version: info.version,
                url: raw.url,
                sourceSnapshot: SourceSnapshot.read(raw.url),
                size: stats.allocatedSize,
                supportSize: support,
                leftoverSize: leftover,
                associated: associated,
                lastOpened: lastOpened(raw.url),
                source: source(raw.url, isSystem: raw.isSystem, casks: casks),
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

    /// The name on the app's signing certificate: "Developer ID Application:
    /// Google LLC (EQHXZ8M8AV)" gives "Google LLC". App Store and Apple
    /// signatures carry no maker's name, so those fall back to the bundle id.
    private nonisolated static func signer(_ app: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let certificates = dict[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first,
              let summary = SecCertificateCopySubjectSummary(leaf) as String? else { return nil }
        return signerName(summary)
    }

    nonisolated static func signerName(_ summary: String) -> String? {
        let prefixes = ["Developer ID Application: ", "Apple Distribution: ", "Apple Development: ",
                        "3rd Party Mac Developer Application: ", "Mac Developer: "]
        guard let prefix = prefixes.first(where: { summary.hasPrefix($0) }) else { return nil }
        var name = String(summary.dropFirst(prefix.count))
        if let team = name.range(of: " (", options: .backwards) { name = String(name[..<team.lowerBound]) }
        name = name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// App Store apps carry a receipt, Homebrew keeps each cask's recipe, and a
    /// download keeps the quarantine mark macOS adds. Anything else: unknown.
    private nonisolated static func source(_ app: URL, isSystem: Bool, casks: Set<String>) -> String {
        if isSystem { return "Came with macOS" }
        if FileScan.exists(app.appendingPathComponent("Contents/_MASReceipt/receipt")) { return "App Store" }
        if casks.contains(app.lastPathComponent) { return "Homebrew" }
        if getxattr(app.path, "com.apple.quarantine", nil, 0, 0, 0) > 0 { return "Downloaded" }
        return ""
    }

    /// App names Homebrew installed, read from each cask's saved recipe in
    /// Caskroom/<cask>/.metadata/<version>/<time>/Casks/<cask>.json or .rb.
    private nonisolated static func homebrewApps() -> Set<String> {
        var names = Set<String>()
        for room in ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"] {
            for cask in FileScan.children(of: URL(fileURLWithPath: room)) ?? [] {
                for version in FileScan.children(of: cask.appendingPathComponent(".metadata")) ?? [] {
                    for stamp in FileScan.children(of: version) ?? [] {
                        for recipe in FileScan.children(of: stamp.appendingPathComponent("Casks")) ?? [] {
                            guard let text = try? String(contentsOf: recipe, encoding: .utf8) else { continue }
                            names.formUnion(caskAppNames(text))
                        }
                    }
                }
            }
        }
        return names
    }

    /// Quoted names ending in .app with no folder in them: `app "Firefox.app"`
    /// in a recipe, `"app":["Google Chrome.app"]` in its JSON.
    nonisolated static func caskAppNames(_ text: String) -> Set<String> {
        var names = Set<String>()
        for part in text.components(separatedBy: "\"").dropFirst() where part.hasSuffix(".app") && !part.contains("/") && part.count > 4 {
            names.insert(part)
        }
        return names
    }

    /// Spotlight's `kMDItemLastUsedDate` is the real "last opened". Without it,
    /// the content-access date stands in (then the modification date).
    private nonisolated static func lastOpened(_ app: URL) -> Date? {
        if let used = NSMetadataItem(url: app)?.value(forAttribute: "kMDItemLastUsedDate") as? Date { return used }
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

    /// Every `~/Library` folder or file that belongs to one app: named by its
    /// bundle id (as the Apps page matches them), or by the app's own name in
    /// Application Support and Caches. Protected agent and session data is left out.
    nonisolated static func associatedFiles(bundleID: String, appName: String) -> [(url: URL, isSupport: Bool)] {
        let id = bundleID.lowercased()
        let name = appName.lowercased()
        guard !id.isEmpty, !id.hasPrefix("com.apple") else { return [] }
        var found: [(url: URL, isSupport: Bool)] = []
        for subtree in librarySubtrees {
            guard let children = FileScan.children(of: subtree) else { continue }
            let isSupport = supportSubtreeNames.contains(subtree.lastPathComponent)
            let byName = ["Application Support", "Caches"].contains(subtree.lastPathComponent)
            for child in children {
                let candidate = normalize(child.lastPathComponent)
                // The app's own id or a sub-id of it, never a vendor-wide folder
                // that other apps from the same maker share.
                let matches = candidate == id || candidate.hasPrefix(id + ".")
                    || (byName && name.count >= 3 && child.lastPathComponent.lowercased() == name)
                guard matches, SafePaths.protectedSessionReason(child) == nil else { continue }
                found.append((url: child, isSupport: isSupport))
            }
        }
        return found
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


    // MARK: - Uninstall (only app bundles move to Trash)

    struct UninstallSummary {
        var trashedApps = 0
        var failed = 0
        var bytes: Int64 = 0
        var errors: [String] = []
        var quit: [String] = []
        var history: [ScanStore.RemovalLogEntry] = []
        var capacityChanges: [CleanupCapacityChange] = []
        var recordedRecoveries = 0
    }

    /// Require selected apps to be closed, then trash only bundles that have
    /// actually exited. Associated `~/Library` files stay untouched, but are
    /// recorded so the next scan lists them for review. The path guard permits
    /// only known app-bundle locations.
    @discardableResult
    func uninstall(_ entries: [AppEntry]) async -> UninstallSummary {
        guard await prepareRemoval() else { return UninstallSummary(failed: entries.count, errors: ["Recovery history is unavailable. No application was removed."]) }
        guard await Task.detached(priority: .utility, operation: { ActionJournal.shared.prepare() }).value else {
            return UninstallSummary(failed: entries.count, errors: [ActionJournal.shared.error ?? "Action journal unavailable. No application was removed."])
        }
        guard !isUninstalling, !isScanning else { return UninstallSummary(failed: entries.count, errors: ["Finish the current application operation first."]) }
        isUninstalling = true
        defer { isUninstalling = false }
        guard await ScanGate.shared.acquire(.removeApps) else { return UninstallSummary(failed: entries.count, errors: ["Removal cancelled before starting."]) }
        defer { ScanGate.shared.release() }

        guard let run = await beginReceipt?() else { return UninstallSummary(failed: entries.count, errors: ["Cleanup receipt could not be prepared. No application was removed."]) }
        let capacityWindow = await CleanupCapacityWindow.begin(urls: entries.map(\.url))
        // The user closes applications themselves to preserve unsaved work.
        let summary = UninstallSummary()

        // 2) Trash bundles off-main. Support data is never included implicitly.
        struct Batch { var done: Set<UUID> = []; var summary: UninstallSummary }
        let batch = await Task.detached(priority: .userInitiated) { () -> Batch in
            var b = Batch(summary: summary)
            for app in entries {
                if await Self.isRunning(app.url, bundleID: app.bundleID) {
                    b.summary.failed += 1
                    b.summary.errors.append("\(app.name): still running; close it before uninstalling")
                    continue
                }
                // Refuse agent/conversation hosts even if a stale UI selection
                // or an internal caller supplied an AppEntry directly.
                guard app.isRemovable else {
                    b.summary.failed += 1
                    b.summary.errors.append("\(app.name): protected application")
                    continue
                }
                guard let snapshot = app.sourceSnapshot, snapshot.matches(app.url) else {
                    b.summary.failed += 1
                    b.summary.errors.append("\(app.name): bundle changed since inventory; rescan before removal")
                    continue
                }
                // All-or-nothing: trash the bundle FIRST. If that fails (busy /
                // perms / relaunched), bail BEFORE touching the app's data so we
                // never orphan ~/Library files for a still-installed app.
                guard let actionID = ActionJournal.shared.begin(path: app.url.path, category: "apps", affectedBytes: app.size) else {
                    b.summary.failed += 1
                    b.summary.errors.append(ActionJournal.shared.error ?? "Action intent could not be recorded; uninstall stopped")
                    break
                }
                let (bundleOK, bundleBytes, trashURL, failure) = await Self.trash(app.url, bundleID: app.bundleID, snapshot: snapshot)
                let journalSaved = ActionJournal.shared.finish(actionID, succeeded: bundleOK,
                                                               trashPath: trashURL?.path,
                                                               detail: bundleOK ? nil : failure ?? "App bundle was not moved")
                guard bundleOK else {
                    b.summary.failed += 1
                    b.summary.errors.append("\(app.name): \(failure ?? "could not move to Trash") — left untouched")
                    if !journalSaved { b.summary.errors.append(ActionJournal.shared.error ?? "Action outcome could not be recorded"); break }
                    continue
                }
                b.summary.history.append(ScanStore.RemovalLogEntry(id: actionID, name: app.name, originalPath: app.url.path, trashPath: trashURL?.path, bytes: bundleBytes, date: Date(), category: "apps"))
                b.summary.trashedApps += 1
                b.summary.bytes += bundleBytes
                b.done.insert(app.id)
                // Support data stays put; the next scan lists it for review.
                RemovedAppLeftovers.record(app.associated, app: app.name)
                AppLeftovers.noteRemovedByCairn(app.bundleID)
                if !journalSaved {
                    b.summary.failed += 1
                    b.summary.errors.append(ActionJournal.shared.error ?? "Action outcome could not be recorded; uninstall stopped")
                    break
                }
            }
            return b
        }.value

        // 3) Remove uninstalled apps from the list.
        apps.removeAll { batch.done.contains($0.id) }
        var result = batch.summary
        let logged = await onRemovals?(batch.summary.history) ?? batch.summary.history.isEmpty
        result.recordedRecoveries = logged ? batch.summary.history.filter { $0.trashPath != nil }.count : 0
        result.capacityChanges = await capacityWindow.finish()
        if !logged {
            result.failed += 1
            result.errors.append("Recovery history could not be saved. The action journal retains the paths; further cleanup is blocked.")
        }
        let receipt = ScanStore.CleanSummary.specialist(history: result.history, failed: result.failed, errors: result.errors,
            capacity: result.capacityChanges, logged: logged, interrupted: Task.isCancelled || !logged)
        if await finishReceipt?(run, receipt) != true {
            result.failed += 1; result.errors.append("The complete receipt could not be saved. Recovery records remain available.")
        }
        return result
    }

    /// Re-read the live app list on the main actor. A bundle URL match also
    /// covers applications whose bundle identifier was missing from inventory.
    private nonisolated static func isRunning(_ url: URL, bundleID: String) async -> Bool {
        await MainActor.run {
            let bundle = url.resolvingSymlinksInPath().standardizedFileURL
            return NSWorkspace.shared.runningApplications.contains { running in
                (!bundleID.isEmpty && running.bundleIdentifier?.caseInsensitiveCompare(bundleID) == .orderedSame)
                    || running.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == bundle
            }
        }
    }

    /// Trash a single path IF it passes the conservative app-uninstall guard.
    /// Returns (success, bytesMoved, Trash URL, failure). Recoverable via Finder's Put Back.
    private nonisolated static func trash(_ url: URL, bundleID: String, snapshot: SourceSnapshot) async -> (Bool, Int64, URL?, String?) {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        guard snapshot.matches(url), isUninstallSafe(resolved), FileScan.exists(resolved) else { return (false, 0, nil, nil) }
        let bytes = FileScan.measure(resolved, maxFiles: 40_000).allocatedSize
        guard snapshot.matches(url), isUninstallSafe(resolved) else { return (false, 0, nil, nil) }
        // Sizing may take time and the app can relaunch after the batch preflight.
        // Check again at the last possible point before the filesystem move.
        guard !(await isRunning(resolved, bundleID: bundleID)) else {
            return (false, 0, nil, "relaunched; close it before uninstalling")
        }
        do {
            var out: NSURL?
            try FileManager.default.trashItem(at: resolved, resultingItemURL: &out)
            return (true, bytes, out as URL?, nil)
        } catch {
            return (false, 0, nil, nil)
        }
    }

    /// Conservative guard, independent of `SafePaths`: a path may be trashed by
    /// the uninstaller ONLY if it is (a) a `*.app` directly under `/Applications`,
    /// `/Applications/Utilities`, or `~/Applications`, or (b) anything strictly
    /// under `~/Library`. Never `/System`, never a bare home/library root.
    nonisolated static func isUninstallSafe(_ resolved: URL) -> Bool {
        let path = resolved.standardizedFileURL.path
        if path == "/" || path.isEmpty { return false }
        if ["codex", "chatgpt"].contains(resolved.deletingPathExtension().lastPathComponent.lowercased()) { return false }
        if SafePaths.protectedSessionReason(resolved) != nil { return false }
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
            guard SafePaths.evaluate(resolved, allowedRoots: [URL(fileURLWithPath: lib)]).isAllowed else { return false }
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
