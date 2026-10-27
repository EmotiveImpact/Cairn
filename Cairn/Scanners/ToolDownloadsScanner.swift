import Foundation

/// Downloads developer tools keep outside any one project: browsers for test
/// runners (Playwright, Puppeteer, Cypress), Electron builds, Bazel build output,
/// Unity's package cache, Watchman's log, old Ruby gem versions and old macOS
/// SDKs inside Command Line Tools.
///
/// Older versions of a download are safe to clear because the newest one stays.
/// Anything a project may still be using is review. Command Line Tools belongs
/// to Apple, so its SDKs are sized as advice and never removed.
struct ToolDownloadsScanner: CairnScanner {
    let info = CategoryInfo(
        id: "tool-downloads",
        title: "Test Browsers & Build Tools",
        subtitle: "Playwright, Cypress, Puppeteer, Electron, Bazel, Unity, Ruby gems",
        systemImage: "hammer.circle",
        group: .developer,
        requiresFDA: false
    )

    /// Bazel keeps its build output outside the home folder on macOS, and
    /// Homebrew's Watchman writes its log under Homebrew's var folder.
    var allowedRoots: [URL] { [FileScan.home] + Self.bazelRoots + Self.watchmanRoots }

    static var bazelRoots: [URL] {
        let user = NSUserName()
        return [URL(fileURLWithPath: "/private/var/tmp/_bazel_\(user)"),
                FileScan.home.appendingPathComponent(".cache/bazel/_bazel_\(user)")]
    }

    static var watchmanRoots: [URL] {
        ["/opt/homebrew/var/run/watchman", "/usr/local/var/run/watchman"].map { URL(fileURLWithPath: $0) }
    }

    private static let maxFiles = 60_000
    private static let unityBundleIDs = ["com.unity3d.UnityEditor5.x", "com.unity3d.unityhub"]

    func scan(_ ctx: ScanContext) async {
        let home = FileScan.home
        emitVersioned(in: home.appendingPathComponent("Library/Caches/ms-playwright"),
                      tool: "Playwright", ctx: ctx, key: Self.dashKey)
        if ctx.isCancelled() { return }
        emitVersioned(in: home.appendingPathComponent("Library/Caches/Cypress"),
                      tool: "Cypress", ctx: ctx, key: { name in (group: "Cypress", version: name) })
        if ctx.isCancelled() { return }
        // Puppeteer keeps one folder per browser, then one per platform and build.
        let puppeteer = home.appendingPathComponent(".cache/puppeteer")
        for browser in Self.subdirectories(of: puppeteer) {
            if ctx.isCancelled() { return }
            emitVersioned(in: browser, tool: "Puppeteer \(browser.lastPathComponent)", ctx: ctx, key: Self.dashKey)
        }
        if ctx.isCancelled() { return }
        emitElectron(ctx)
        if ctx.isCancelled() { return }
        emitUnity(ctx)
        if ctx.isCancelled() { return }
        emitBazel(ctx)
        if ctx.isCancelled() { return }
        emitWatchman(ctx)
        if ctx.isCancelled() { return }
        emitOldGems(ctx)
        if ctx.isCancelled() { return }
        emitOldSDKs(ctx)
    }

    // MARK: - Versioned downloads (test browsers)

    /// "chromium-1148" → ("chromium", "1148"). Names without a version are skipped.
    static func dashKey(_ name: String) -> (group: String, version: String)? {
        guard let dash = name.lastIndex(of: "-") else { return nil }
        let version = String(name[name.index(after: dash)...])
        guard let first = version.first, first.isNumber else { return nil }
        return (group: String(name[..<dash]), version: version)
    }

    /// For each kind of download, the newest version stays (review, your tests
    /// may use it) and every older one is safe: the test runner downloads a
    /// version again if an old project still asks for it.
    static func olderVersions(_ names: [String], key: (String) -> (group: String, version: String)?) -> (old: Set<String>, newest: Set<String>) {
        var groups: [String: [(name: String, version: String)]] = [:]
        for name in names where !name.hasPrefix(".") {
            guard let parsed = key(name) else { continue }
            groups[parsed.group, default: []].append((name: name, version: parsed.version))
        }
        var old = Set<String>(), newest = Set<String>()
        for entries in groups.values {
            guard let top = entries.map({ $0.version }).max(by: AndroidSDKScanner.versionLess) else { continue }
            for entry in entries {
                if entry.version == top { newest.insert(entry.name) } else { old.insert(entry.name) }
            }
        }
        return (old, newest)
    }

    private func emitVersioned(in root: URL, tool: String, ctx: ScanContext,
                               key: (String) -> (group: String, version: String)?) {
        let folders = Self.subdirectories(of: root)
        guard !folders.isEmpty else { return }
        ctx.progress(tool)
        let split = Self.olderVersions(folders.map(\.lastPathComponent), key: key)
        for folder in folders {
            if ctx.isCancelled() { return }
            let name = folder.lastPathComponent
            let isOld = split.old.contains(name)
            guard isOld || split.newest.contains(name) else { continue }
            if let item = makeItem(
                at: folder,
                severity: isOld ? .safe : .review,
                minSize: ctx.minSizeBytes,
                isRegenerable: true,
                cleanMethod: .trash,
                note: isOld ? "\(tool) \(name), an older download. The newest one stays, and an old project downloads its version again if it needs it"
                            : "\(tool) \(name), the newest download. Your tests use this one",
                selectedIfSafe: true,
                maxFiles: Self.maxFiles
            ) {
                ctx.emit(item)
            }
        }
    }

    // MARK: - Electron and Unity

    private func emitElectron(_ ctx: ScanContext) {
        let caches = FileScan.home.appendingPathComponent("Library/Caches")
        for (rel, label) in [("electron", "Electron downloads"), ("electron-builder", "electron-builder downloads")] {
            if ctx.isCancelled() { return }
            let url = caches.appendingPathComponent(rel)
            guard FileScan.exists(url) else { continue }
            ctx.progress(label)
            if let item = makeItem(at: url, severity: .safe, minSize: ctx.minSizeBytes, isRegenerable: true,
                                   cleanMethod: .trash,
                                   note: "\(label) kept for app builds. Downloaded again on the next build",
                                   selectedIfSafe: true, maxFiles: Self.maxFiles) {
                ctx.emit(item)
            }
        }
    }

    private func emitUnity(_ ctx: ScanContext) {
        let unity = FileScan.home.appendingPathComponent("Library/Unity")
        guard FileScan.exists(unity) else { return }
        ctx.progress("Unity")
        if let item = makeItem(at: unity.appendingPathComponent("cache"), severity: .safe, minSize: ctx.minSizeBytes,
                               isRegenerable: true, requiresQuitBundleIDs: Self.unityBundleIDs, cleanMethod: .trash,
                               note: "Unity package cache. Downloaded again when a project opens",
                               selectedIfSafe: true, maxFiles: Self.maxFiles) {
            ctx.emit(item)
        }
        for folder in Self.subdirectories(of: unity) where folder.lastPathComponent.hasPrefix("Asset Store") {
            if ctx.isCancelled() { return }
            if let item = makeItem(at: folder, severity: .review, minSize: ctx.minSizeBytes, isRegenerable: false,
                                   requiresQuitBundleIDs: Self.unityBundleIDs, cleanMethod: .trash,
                                   note: "Unity Asset Store downloads. You can download them again from the Asset Store",
                                   maxFiles: Self.maxFiles) {
                ctx.emit(item)
            }
        }
    }

    // MARK: - Bazel

    /// One output base per workspace (a 32-character hex folder). Output for a
    /// workspace that no longer exists is safe; the rest is review because a
    /// running Bazel server uses it.
    private func emitBazel(_ ctx: ScanContext) {
        for root in Self.bazelRoots where FileScan.exists(root) {
            ctx.progress("Bazel")
            for child in Self.subdirectories(of: root) {
                if ctx.isCancelled() { return }
                let name = child.lastPathComponent
                if name == "cache" {
                    if let item = makeItem(at: child, severity: .review, minSize: ctx.minSizeBytes, isRegenerable: true,
                                           cleanMethod: .trash,
                                           note: "Bazel download cache. Fetched again on the next build",
                                           maxFiles: Self.maxFiles) {
                        ctx.emit(item)
                    }
                    continue
                }
                guard name.count == 32, name.allSatisfy(\.isHexDigit) else { continue }
                let marker = child.appendingPathComponent("DO_NOT_BUILD_HERE")
                let workspace = (try? String(contentsOf: marker, encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let label = workspace.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "a workspace"
                let gone = workspace.map { !$0.isEmpty && !FileScan.exists(URL(fileURLWithPath: $0)) } ?? false
                if let item = makeItem(
                    at: child,
                    severity: gone ? .safe : .review,
                    minSize: ctx.minSizeBytes,
                    isRegenerable: true,
                    cleanMethod: .trash,
                    note: gone ? "Bazel build output for \(label), a project that is no longer on this Mac"
                               : "Bazel build output for \(label). Run bazel shutdown first; Bazel builds it again",
                    selectedIfSafe: gone,
                    maxFiles: Self.maxFiles
                ) {
                    ctx.emit(item)
                }
            }
        }
    }

    // MARK: - Watchman

    /// Watchman's log only grows. It is held open while Watchman runs, so the
    /// space comes back once Watchman restarts.
    private func emitWatchman(_ ctx: ScanContext) {
        for root in Self.watchmanRoots {
            let log = root.appendingPathComponent("\(NSUserName())-state/log")
            guard FileScan.exists(log) else { continue }
            ctx.progress("Watchman")
            if let item = makeItem(at: log, severity: .review, minSize: ctx.minSizeBytes, isRegenerable: true,
                                   cleanMethod: .trash,
                                   note: "Watchman's log. Run watchman shutdown-server first so the space comes back") {
                ctx.emit(item)
            }
        }
    }

    // MARK: - Ruby gems

    /// "nokogiri-1.16.2-arm64-darwin" → ("nokogiri", "1.16.2"). The version is
    /// the first part that starts with a digit; a platform suffix is ignored.
    static func gemKey(_ name: String) -> (group: String, version: String)? {
        let parts = name.split(separator: "-").map(String.init)
        guard let index = parts.firstIndex(where: { $0.first?.isNumber == true }), index > 0 else { return nil }
        return (group: parts[..<index].joined(separator: "-"), version: parts[index])
    }

    /// Older versions of gems you also have a newer version of, cleared with
    /// `gem cleanup`. Only for a Ruby you installed (Homebrew, rbenv, asdf…):
    /// the system Ruby's gems belong to macOS.
    private func emitOldGems(_ ctx: ScanContext) {
        guard let gem = ToolRunner.resolve("gem"), !gem.hasPrefix("/usr/bin/"), !gem.hasPrefix("/System/") else { return }
        ctx.progress("Ruby gems")
        guard let result = try? ToolRunner.run("gem", ["env", "gempath"], timeout: 8), result.ok else { return }
        let home = FileScan.home.path
        let paths = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":").map(String.init)
            .filter { $0.hasPrefix(home + "/") || $0.hasPrefix("/opt/homebrew/") || $0.hasPrefix("/usr/local/") }
        var oldFolders: [URL] = []
        var firstRoot: URL?
        for path in paths {
            let gems = URL(fileURLWithPath: path).appendingPathComponent("gems")
            let folders = Self.subdirectories(of: gems)
            let old = Self.olderVersions(folders.map(\.lastPathComponent), key: Self.gemKey).old
            guard !old.isEmpty else { continue }
            if firstRoot == nil { firstRoot = gems }
            oldFolders += folders.filter { old.contains($0.lastPathComponent) }
        }
        guard let root = firstRoot else { return }
        var total: Int64 = 0
        var latest = Date.distantPast
        for folder in oldFolders {
            if ctx.isCancelled() { return }
            let stats = FileScan.measure(folder, maxFiles: 20_000, maxDuration: 1)
            total += stats.allocatedSize
            latest = max(latest, stats.latestModified)
        }
        guard total >= ctx.minSizeBytes else { return }
        let cleanup = ToolCommand(tool: "gem", arguments: ["cleanup"], display: "gem cleanup")
        ctx.emit(ScanItem(
            url: root,
            allocatedSize: total,
            itemCount: oldFolders.count,
            latestModified: latest,
            categoryID: info.id,
            severity: .review,
            isRegenerable: true,
            cleanMethod: .tool(cleanup),
            note: "\(oldFolders.count) older gem versions. gem cleanup keeps the newest of each, and keeps an old one another gem still needs",
            volumeURL: FileScan.volumeURL(of: root),
            selected: false
        ))
    }

    // MARK: - Command Line Tools SDKs

    /// Command Line Tools can keep SDKs for older macOS versions after an update.
    /// Builds use the newest one. The folder is Apple's, so this is advice only.
    private func emitOldSDKs(_ ctx: ScanContext) {
        let sdks = URL(fileURLWithPath: "/Library/Developer/CommandLineTools/SDKs")
        guard FileScan.exists(sdks), let children = FileScan.children(of: sdks) else { return }
        ctx.progress("Command Line Tools")
        let current = sdks.appendingPathComponent("MacOSX.sdk").resolvingSymlinksInPath().lastPathComponent
        var versioned: [(url: URL, version: String)] = []
        for child in children {
            let values = try? child.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values?.isSymbolicLink != true, values?.isDirectory == true else { continue }
            let name = child.lastPathComponent
            guard name.hasPrefix("MacOSX"), name.hasSuffix(".sdk"), name != "MacOSX.sdk" else { continue }
            let version = String(name.dropFirst("MacOSX".count).dropLast(".sdk".count))
            guard version.first?.isNumber == true else { continue }
            versioned.append((url: child, version: version))
        }
        guard let newest = versioned.map({ $0.version }).max(by: AndroidSDKScanner.versionLess) else { return }
        let old = versioned.filter { $0.version != newest && $0.url.lastPathComponent != current }
        guard !old.isEmpty else { return }
        var total: Int64 = 0
        for entry in old { total += FileScan.measure(entry.url, maxFiles: 60_000, maxDuration: 2).allocatedSize }
        guard total >= ctx.minSizeBytes else { return }
        let names = old.map { "macOS \($0.version)" }.joined(separator: ", ")
        ctx.emit(ScanItem(
            url: sdks,
            allocatedSize: total,
            itemCount: old.count,
            categoryID: info.id,
            severity: .review,
            isRegenerable: false,
            cleanMethod: .adviceOnly,
            note: "Command Line Tools still keeps SDKs for \(names). Builds use the newest one. The folder is Apple's, so Cairn leaves it; remove an old SDK in Terminal with admin rights only if no project asks for it",
            volumeURL: FileScan.volumeURL(of: sdks),
            selected: false
        ))
    }

    // MARK: - Helpers

    /// Immediate subdirectories, skipping symlinks and hidden folders.
    static func subdirectories(of dir: URL) -> [URL] {
        guard let children = FileScan.children(of: dir) else { return [] }
        return children.filter { child in
            guard !child.lastPathComponent.hasPrefix(".") else { return false }
            let values = try? child.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            return values?.isSymbolicLink != true && values?.isDirectory == true
        }
    }
}
