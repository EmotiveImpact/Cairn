import Foundation
import Observation

// MARK: - Health models

/// A single detected health problem. `url` is the on-disk artifact (a plist, a
/// folder) when one exists; advice-only issues may still carry a url to Reveal.
struct HealthIssue: Identifiable {
    let id = UUID()
    var title: String
    var url: URL?
    var detail: String
    /// True only for issues we can SAFELY remediate by moving the artifact to the
    /// Trash (recoverable). Advice-only issues are always false.
    var fixable: Bool
    let sourceSnapshot: SourceSnapshot?

    init(title: String, url: URL?, detail: String, fixable: Bool) {
        self.title = title; self.url = url; self.detail = detail; self.fixable = fixable
        self.sourceSnapshot = fixable ? url.flatMap(SourceSnapshot.read) : nil
    }
}

/// A category of health issues. `actionable` drives the row button: actionable
/// groups show "Fix" (Trash the fixable items), advice groups show "Review".
struct HealthGroup: Identifiable {
    let id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var items: [HealthIssue]
    /// Whether this whole group can be auto-fixed (Trash). False = advice-only.
    var actionable: Bool

    /// Items we may safely Trash (actionable group AND the item is fixable).
    var fixableItems: [HealthIssue] { actionable ? items.filter { $0.fixable && $0.url != nil } : [] }
    var count: Int { items.count }
}

// MARK: - HealthStore

/// Self-contained, on-demand system-health scanner + fixer for the Bugs & Fixes
/// screen. Deliberately NOT registered in the shared ScannerRegistry — running
/// here would pollute Smart Scan totals. Runs lazily (once) from the view's
/// `.task`, is cancellable, and routes every deletion through the recoverable
/// Trash (FileManager.trashItem). Conservative by design: only Old Launch Agents
/// and Orphaned App Data are ever auto-fixable; everything else is advice-only.
@MainActor
@Observable
final class HealthStore {
    private(set) var isFixing = false
    var onRemovals: (([ScanStore.RemovalLogEntry]) -> Bool)?
    var prepareRemoval: () -> Bool = { false }

    /// Number of distinct system-health checks Cairn runs (launch agents, orphaned
    /// app data, broken login items, corrupted preferences, permission issues).
    static let checkCount = 5

    enum Phase: Equatable { case idle, scanning, finished }

    private(set) var phase: Phase = .idle
    private(set) var groups: [HealthGroup] = []
    private(set) var progressText: String = ""
    private(set) var lastScanAt: Date?
    /// Result banner after a Fix / Fix All action (nil = nothing to show).
    var lastResult: FixResult?

    nonisolated(unsafe) private var scanTask: Task<Void, Never>?
    private var scanGeneration = UUID()

    deinit { scanTask?.cancel() }

    struct FixResult: Identifiable {
        let id = UUID()
        var trashed: Int
        var failed: Int
        var bytes: Int64
        var errors: [String]
        var ok: Bool { failed == 0 }
    }

    /// Stable display order for the issue list.
    private static let order = ["launch-agents", "orphaned", "login-items", "prefs-corrupt", "permissions"]

    // MARK: Derived

    var isScanning: Bool { phase == .scanning }
    var hasScanned: Bool { phase == .finished }
    /// Groups that actually have something to show (non-empty), in display order.
    var visibleGroups: [HealthGroup] {
        groups.filter { !$0.items.isEmpty }
            .sorted { (Self.order.firstIndex(of: $0.id) ?? 99) < (Self.order.firstIndex(of: $1.id) ?? 99) }
    }
    var totalIssues: Int { groups.reduce(0) { $0 + $1.count } }
    var isHealthy: Bool { hasScanned && totalIssues == 0 }
    /// Every safely-fixable issue across all actionable groups (drives "Fix All").
    var allFixable: [HealthIssue] { groups.flatMap { $0.fixableItems } }

    // MARK: - Scan lifecycle

    /// Run the health scan once. Guard at the call site (view) so it only fires
    /// on first appearance.
    private(set) var wasCancelled = false

    func scanIfNeeded() {
        guard !wasCancelled else { return }
        guard phase == .idle else { return }
        rescan()
    }

    func rescan() {
        guard !isFixing else { return }
        scanTask?.cancel()
        let generation = UUID()
        scanGeneration = generation
        wasCancelled = false
        phase = .scanning
        progressText = "Checking your Mac's health…"
        lastResult = nil
        let scanner = HealthScanner()
        scanTask = Task { [weak self] in
            guard await ScanGate.shared.acquire() else { return }
            defer { ScanGate.shared.release() }
            guard let self, !Task.isCancelled else { return }
            let progressStore = self
            let result = await scanner.run { msg in
                Task { @MainActor in
                    guard progressStore.scanGeneration == generation, !Task.isCancelled else { return }
                    progressStore.progressText = msg
                }
            }
            await MainActor.run {
                guard self.scanGeneration == generation, !Task.isCancelled else { return }
                self.groups = result
                self.phase = .finished
                self.lastScanAt = Date()
                self.progressText = ""
                self.scanTask = nil
            }
        }
    }

    func cancel() {
        scanGeneration = UUID()
        scanTask?.cancel()
        scanTask = nil
        if phase == .scanning { wasCancelled = true; phase = .idle; progressText = "" }
    }

    // MARK: - Fixing (Trash only — recoverable)

    /// Trash every fixable item in one actionable group.
    func fix(group: HealthGroup) async {
        await fix(items: group.fixableItems)
    }

    /// Trash a specific set of fixable issues (used by Fix All after confirm).
    func fix(items: [HealthIssue]) async {
        guard prepareRemoval() else { lastResult = FixResult(trashed: 0, failed: items.count, bytes: 0, errors: ["Recovery history is unavailable. Nothing was removed."]); return }
        guard await Task.detached(priority: .utility, operation: { ActionJournal.shared.prepare() }).value else {
            lastResult = FixResult(trashed: 0, failed: items.count, bytes: 0,
                                   errors: [ActionJournal.shared.error ?? "Action journal unavailable. Nothing was removed."])
            return
        }
        guard !isFixing, !isScanning else { return }
        isFixing = true
        defer { isFixing = false }
        guard await ScanGate.shared.acquire() else { return }
        defer { ScanGate.shared.release() }

        let targets = items.compactMap { issue -> HealthTrash.Target? in
            guard issue.fixable, let url = issue.url else { return nil }
            return HealthTrash.Target(url: url, snapshot: issue.sourceSnapshot)
        }
        guard !targets.isEmpty else { return }

        let outcome = await Task.detached(priority: .userInitiated) {
            HealthTrash.trashAll(targets)
        }.value

        // Drop successfully-trashed issues from their groups. Compare resolved +
        // standardized paths on both sides so a trailing slash / symlink can't
        // leave a fixed issue stuck in the list.
        let cleaned = Set(outcome.cleanedURLs.map { $0.resolvingSymlinksInPath().standardizedFileURL.path })
        for g in groups.indices {
            groups[g].items.removeAll { issue in
                guard let u = issue.url else { return false }
                return cleaned.contains(u.resolvingSymlinksInPath().standardizedFileURL.path)
            }
        }
        let logged = onRemovals?(outcome.history) ?? outcome.history.isEmpty
        lastResult = FixResult(trashed: outcome.trashed, failed: outcome.failed + (logged ? 0 : 1),
                               bytes: outcome.bytes, errors: outcome.errors + (logged ? [] : ["Recovery history could not be saved. The action journal retains the paths; further cleanup is blocked."]))
    }
}

// MARK: - Trash helper (recoverable, SafePaths-guarded)

/// Moves health artifacts to the Trash via FileManager.trashItem. Every path is
/// checked against the shared SafePaths chokepoint first, scoped to HOME — so a
/// LaunchAgents plist under ~/Library is allowed, but anything escaping HOME (or
/// the global denylist: Keychains, .ssh, /System…) is rejected. Recoverable.
enum HealthTrash {
    struct Target: Sendable {
        let url: URL
        let snapshot: SourceSnapshot?
    }
    struct Outcome {
        var trashed = 0
        var failed = 0
        var bytes: Int64 = 0
        var errors: [String] = []
        var cleanedURLs: [URL] = []
        var history: [ScanStore.RemovalLogEntry] = []
    }

    static func trashAll(_ targets: [Target]) -> Outcome {
        var out = Outcome()
        for target in targets {
            let url = target.url
            let resolved = url.resolvingSymlinksInPath()
            guard let snapshot = target.snapshot, snapshot.matches(url) else {
                out.failed += 1
                out.errors.append("\(url.lastPathComponent): changed since the health scan; rescan before removal")
                continue
            }
            // Recoverable, but still gate on the global safety chokepoint.
            let verdict = SafePaths.evaluate(url, allowedRoots: [FileScan.home])
            guard verdict.isAllowed else {
                out.failed += 1
                if case .reject(let why) = verdict {
                    out.errors.append("\(url.lastPathComponent): blocked by safety guard (\(why))")
                }
                continue
            }
            guard SafePaths.evaluateContents(resolved).isAllowed else {
                out.failed += 1; out.errors.append("Protected or unreadable contents: \(url.lastPathComponent)"); continue
            }
            guard FileScan.exists(resolved) else { out.cleanedURLs.append(url); continue } // already gone
            let size = FileScan.measure(resolved).allocatedSize
            guard snapshot.matches(url), SafePaths.evaluate(url, allowedRoots: [FileScan.home]).isAllowed,
                  SafePaths.evaluateContents(resolved).isAllowed else {
                out.failed += 1
                out.errors.append("\(url.lastPathComponent): changed or became protected; rescan before removal")
                continue
            }
            guard let actionID = ActionJournal.shared.begin(path: resolved.path, category: "health") else {
                out.failed += 1
                out.errors.append(ActionJournal.shared.error ?? "Action intent could not be recorded; health cleanup stopped")
                return out
            }
            var resulting: NSURL?
            do {
                try FileManager.default.trashItem(at: resolved, resultingItemURL: &resulting)
                out.history.append(ScanStore.RemovalLogEntry(name: url.lastPathComponent, originalPath: url.path, trashPath: (resulting as URL?)?.path, bytes: size, date: Date(), category: "health"))
                out.trashed += 1
                out.bytes += size
                out.cleanedURLs.append(url)
                guard ActionJournal.shared.finish(actionID, succeeded: true, trashPath: (resulting as URL?)?.path) else {
                    out.failed += 1
                    out.errors.append(ActionJournal.shared.error ?? "Action outcome could not be recorded; health cleanup stopped")
                    return out
                }
            } catch {
                out.failed += 1
                out.errors.append("\(url.lastPathComponent): \((error as NSError).localizedDescription)")
                guard ActionJournal.shared.finish(actionID, succeeded: false, trashPath: nil, detail: error.localizedDescription) else {
                    out.errors.append(ActionJournal.shared.error ?? "Action outcome could not be recorded; health cleanup stopped")
                    return out
                }
            }
        }
        return out
    }
}

// MARK: - HealthScanner (off-main work)

/// Performs the actual filesystem inspection off the main actor and returns the
/// fully-built group list. Conservative throughout — never deletes, never chmods.
private struct HealthScanner: Sendable {
    private let lib = FileScan.home.appendingPathComponent("Library")
    /// ~6 months — the staleness floor before orphaned data may be flagged.
    private let staleAge: TimeInterval = 60 * 60 * 24 * 182

    func run(progress: @escaping @Sendable (String) -> Void) async -> [HealthGroup] {
        if Task.isCancelled { return [] }
        progress("Checking launch agents…")
        let launchAgents = scanLaunchAgents()

        if Task.isCancelled { return [] }
        progress("Checking app data…")
        let orphaned = scanOrphanedAppData()

        if Task.isCancelled { return [] }
        progress("Checking login items…")
        let loginItems = scanBrokenLoginItems()

        if Task.isCancelled { return [] }
        progress("Checking preferences…")
        let prefs = scanCorruptedPreferences()

        if Task.isCancelled { return [] }
        progress("Checking permissions…")
        let permissions = scanPermissionIssues()

        if Task.isCancelled { return [] }
        return [
            HealthGroup(id: "launch-agents",
                        title: "Old Launch Agents",
                        subtitle: "Background tasks pointing at programs that no longer exist",
                        systemImage: "clock.badge",
                        items: launchAgents, actionable: true),
            HealthGroup(id: "orphaned",
                        title: "Orphaned App Data",
                        subtitle: "Leftover support files from apps you've since removed",
                        systemImage: "folder.badge.questionmark",
                        items: orphaned, actionable: false),
            HealthGroup(id: "login-items",
                        title: "Broken Login Items",
                        subtitle: "Startup items that reference a missing app — review only",
                        systemImage: "person.badge.minus",
                        items: loginItems, actionable: false),
            HealthGroup(id: "prefs-corrupt",
                        title: "Corrupted Preferences",
                        subtitle: "Preference files that failed to parse — inspect before removing",
                        systemImage: "doc.badge.gearshape",
                        items: prefs, actionable: false),
            HealthGroup(id: "permissions",
                        title: "Permission Issues",
                        subtitle: "Config files with overly-broad permissions — advice only",
                        systemImage: "lock.shield",
                        items: permissions, actionable: false),
        ]
    }

    // MARK: Old Launch Agents (ACTIONABLE → Trash)

    /// Enumerate ~/Library/LaunchAgents/*.plist; parse each; if its Program /
    /// ProgramArguments[0] path does not exist on disk, it's orphaned. Skip any
    /// label starting com.apple. Fixable via Trash (the plist lives under HOME).
    private func scanLaunchAgents() -> [HealthIssue] {
        let dir = lib.appendingPathComponent("LaunchAgents")
        guard FileScan.exists(dir), let children = FileScan.children(of: dir) else { return [] }
        var issues: [HealthIssue] = []
        for plistURL in children where plistURL.pathExtension == "plist" {
            if Task.isCancelled { return issues }
            guard let data = try? Data(contentsOf: plistURL),
                  let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                  let dict = obj as? [String: Any] else { continue }

            // Skip Apple-managed agents entirely.
            if let label = dict["Label"] as? String, label.hasPrefix("com.apple.") { continue }
            if plistURL.lastPathComponent.hasPrefix("com.apple.") { continue }

            guard let program = programPath(in: dict) else { continue }
            // Resolve $PATH-less absolute program paths only; relative/bare tool
            // names are ambiguous, so we leave them alone (conservative).
            guard program.hasPrefix("/") else { continue }
            if FileScan.exists(URL(fileURLWithPath: program)) { continue }

            let label = (dict["Label"] as? String) ?? plistURL.deletingPathExtension().lastPathComponent
            issues.append(HealthIssue(
                title: label,
                url: plistURL,
                detail: "Points to a missing program: \(program)",
                fixable: true
            ))
        }
        return issues
    }

    /// Extract the launch program from a LaunchAgent plist: prefer Program, else
    /// the first element of ProgramArguments.
    private func programPath(in dict: [String: Any]) -> String? {
        if let p = dict["Program"] as? String, !p.isEmpty { return p }
        if let args = dict["ProgramArguments"] as? [String], let first = args.first, !first.isEmpty { return first }
        return nil
    }

    // MARK: Orphaned App Data (ACTIONABLE → Trash)

    /// Folders in ~/Library/Application Support whose bundle-id-ish name doesn't
    /// match any installed app and that are stale (>6mo). Lightweight replica of
    /// OrphanedAppDataScanner's claim logic. Fixable via Trash.
    private func scanOrphanedAppData() -> [HealthIssue] {
        let root = lib.appendingPathComponent("Application Support")
        guard FileScan.exists(root), let children = FileScan.children(of: root) else { return [] }
        let installed = installedBundleIDs()
        let vendorAllowlist: Set<String> = ["MobileSync", "CrashReporter", "Caches", "iCloud",
                                            "CloudDocs", "AddressBook", "Knowledge", "com.apple.TCC"]
        var issues: [HealthIssue] = []
        for child in children {
            if Task.isCancelled { return issues }
            if SafePaths.protectedSessionReason(child) != nil { continue }
            let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { continue }
            let name = child.lastPathComponent
            if name.hasPrefix("com.apple.") { continue }
            if vendorAllowlist.contains(name) { continue }
            if isClaimed(name, by: installed) { continue }

            // Cheap staleness pre-filter on the folder's OWN mtime — skip
            // recently-touched folders before the expensive full-tree measure.
            let folderMtime = (try? child.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if Date().timeIntervalSince(folderMtime) < staleAge { continue }

            let stats = FileScan.measure(child, maxFiles: 8_000)
            // Require a meaningful size AND staleness — avoid flagging tiny or
            // recently-touched folders that may belong to an app we didn't see.
            if stats.allocatedSize < 1 * 1024 * 1024 { continue }
            let age = Date().timeIntervalSince(stats.latestModified)
            if age < staleAge { continue }

            issues.append(HealthIssue(
                title: name,
                url: child,
                detail: "No installed app matches this folder · \(Fmt.size(stats.allocatedSize)). This can contain irreplaceable app data; inspect only.",
                fixable: false
            ))
        }
        return issues
    }

    private func installedBundleIDs() -> Set<String> {
        var ids = Set<String>()
        let roots = [URL(fileURLWithPath: "/Applications"),
                     FileScan.home.appendingPathComponent("Applications"),
                     URL(fileURLWithPath: "/System/Applications")]
        for root in roots {
            if Task.isCancelled { return ids }
            guard FileScan.exists(root), let children = FileScan.children(of: root) else { continue }
            for app in children where app.pathExtension == "app" {
                if Task.isCancelled { return ids }
                let plist = app.appendingPathComponent("Contents/Info.plist")
                guard let data = try? Data(contentsOf: plist),
                      let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                      let dict = obj as? [String: Any],
                      let id = (dict["CFBundleIdentifier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !id.isEmpty else { continue }
                ids.insert(id.lowercased())
            }
        }
        return ids
    }

    private func isClaimed(_ folderName: String, by installed: Set<String>) -> Bool {
        let candidate = normalize(folderName)
        if candidate.isEmpty { return false }
        for id in installed where dottedPrefixMatch(candidate, id) { return true }
        return false
    }

    private func normalize(_ name: String) -> String {
        var s = name
        if let stripped = strippingTeamID(s) { s = stripped }
        if s.hasPrefix("group.") { s = String(s.dropFirst("group.".count)) }
        if let stripped = strippingTeamID(s) { s = stripped }
        return s.lowercased()
    }

    private func strippingTeamID(_ name: String) -> String? {
        guard let dot = name.firstIndex(of: ".") else { return nil }
        let head = name[name.startIndex..<dot]
        guard head.count == 10 else { return nil }
        let isTeamID = head.allSatisfy { $0.isLetter || $0.isNumber } &&
            head.contains(where: { $0.isLetter }) && head.contains(where: { $0.isNumber })
        guard isTeamID else { return nil }
        return String(name[name.index(after: dot)...])
    }

    private func dottedPrefixMatch(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        if a.hasPrefix(b + ".") { return true }
        if b.hasPrefix(a + ".") { return true }
        return false
    }

    // MARK: Broken Login Items (ADVICE-ONLY)

    /// Best-effort only. The modern login-item store (backgrounditems.btm) is
    /// opaque, so we look at the legacy ~/Library/Preferences/com.apple.loginitems.plist
    /// where present and surface entries whose target is gone — as advice with a
    /// Reveal action. Never auto-edited.
    private func scanBrokenLoginItems() -> [HealthIssue] {
        let legacy = lib.appendingPathComponent("Preferences/com.apple.loginitems.plist")
        guard FileScan.exists(legacy),
              let data = try? Data(contentsOf: legacy),
              let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = obj as? [String: Any] else { return [] }

        var issues: [HealthIssue] = []
        // The legacy structure nests session items; walk any "Name"+"Alias"/path-ish
        // leaves defensively without assuming a rigid schema.
        func walk(_ any: Any) {
            if Task.isCancelled { return }
            if let d = any as? [String: Any] {
                if let name = d["Name"] as? String,
                   let path = (d["Path"] as? String) ?? (d["URL"] as? String) {
                    let url = URL(fileURLWithPath: path)
                    if !FileScan.exists(url) {
                        issues.append(HealthIssue(title: name, url: legacy,
                                                  detail: "Login item refers to a missing item: \(path)",
                                                  fixable: false))
                    }
                }
                for v in d.values { walk(v) }
            } else if let arr = any as? [Any] {
                for v in arr { walk(v) }
            }
        }
        walk(dict)
        return issues
    }

    // MARK: Corrupted Preferences (ADVICE-ONLY)

    /// ~/Library/Preferences/*.plist that FAIL to parse. Listed as advice — never
    /// auto-deleted (removing a live prefs file resets app state).
    private func scanCorruptedPreferences() -> [HealthIssue] {
        let dir = lib.appendingPathComponent("Preferences")
        guard FileScan.exists(dir), let children = FileScan.children(of: dir) else { return [] }
        var issues: [HealthIssue] = []
        for url in children where url.pathExtension == "plist" {
            if Task.isCancelled { return issues }
            // Skip zero-byte placeholders (cfprefsd writes these transiently).
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            if size == 0 { continue }
            guard let data = try? Data(contentsOf: url) else { continue }
            let parsed = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) != nil
            if parsed { continue }
            issues.append(HealthIssue(
                title: url.lastPathComponent,
                url: url,
                detail: "This preference file failed to parse — inspect before removing",
                fixable: false
            ))
        }
        return issues
    }

    // MARK: Permission Issues (ADVICE-ONLY)

    /// Light heuristic: world-WRITABLE files in a tight allowlist of HOME config
    /// dirs. Advice only — never chmod, never touch system files. Conservative to
    /// avoid crying wolf.
    private func scanPermissionIssues() -> [HealthIssue] {
        let configDirs = [
            FileScan.home.appendingPathComponent(".ssh"),
            FileScan.home.appendingPathComponent(".config"),
            FileScan.home.appendingPathComponent(".aws"),
        ]
        var issues: [HealthIssue] = []
        for dir in configDirs {
            if Task.isCancelled { return issues }
            guard FileScan.exists(dir), let children = FileScan.children(of: dir) else { continue }
            for url in children {
                if Task.isCancelled { return issues }
                guard let perms = (try? url.resourceValues(forKeys: [.fileSecurityKey]))?.fileSecurity,
                      let mode = posixPermissions(of: url) else { continue }
                _ = perms
                // world-writable bit (0o002).
                if mode & 0o002 != 0 {
                    issues.append(HealthIssue(
                        title: url.lastPathComponent,
                        url: url,
                        detail: "World-writable in ~/\(dir.lastPathComponent) — suggested: chmod 600/700 (do it yourself)",
                        fixable: false
                    ))
                }
            }
        }
        return issues
    }

    private func posixPermissions(of url: URL) -> Int? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let n = attrs[.posixPermissions] as? NSNumber else { return nil }
        return n.intValue
    }
}
