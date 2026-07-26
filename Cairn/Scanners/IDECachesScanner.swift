import Foundation

/// IDE & Electron-app caches — the GPU/HTTP/service-worker/code caches that
/// editors (VS Code, Cursor, JetBrains) and Electron desktop apps (Slack,
/// Discord, Notion) recreate on next launch (SPEC §3.x). Every target here is a
/// genuinely regenerable cache subpath: we ONLY touch cache directories and
/// NEVER the app's "User"/settings/IndexedDB/Local Storage trees, which hold the
/// only local copy of state. These live in plain user dirs (0700) → no Full Disk
/// Access needed. Owning apps are listed in `requiresQuitBundleIDs` so the cache
/// is only cleaned while the app is quit (Electron/Chromium lock these files).
struct IDECachesScanner: CairnScanner {
    let info = CategoryInfo(
        id: "ide-caches",
        title: "IDE & App Caches",
        subtitle: "VS Code, Cursor, JetBrains, Slack, Discord, Notion caches",
        systemImage: "curlybraces.square.fill",
        group: .developer,
        requiresFDA: false
    )

    // Owning-app bundle ids (must quit before their cache is cleaned).
    private static let vscodeID  = "com.microsoft.VSCode"
    private static let cursorID  = "com.todesktop.230313mzl4w4u92"
    private static let slackID   = "com.tinyspeck.slackmacgap"
    private static let discordID = "com.hnc.Discord"
    private static let notionID  = "notion.id"

    /// A fixed cache target: (label, home-relative path, owning bundle id).
    private struct Target {
        let label: String
        let rel: String
        let bundleID: String
    }

    /// Cache-ONLY subpaths. Deliberately excludes every settings/state path
    /// (User/, IndexedDB/, Local Storage/, databases, etc.).
    private var targets: [Target] {
        let vs = Self.vscodeID, cu = Self.cursorID
        let sl = Self.slackID, di = Self.discordID, no = Self.notionID
        return [
            // VS Code (com.microsoft.VSCode)
            .init(label: "VS Code", rel: "Library/Application Support/Code/Cache", bundleID: vs),
            .init(label: "VS Code", rel: "Library/Application Support/Code/CachedData", bundleID: vs),
            .init(label: "VS Code", rel: "Library/Application Support/Code/Service Worker/CacheStorage", bundleID: vs),
            .init(label: "VS Code", rel: "Library/Application Support/Code/GPUCache", bundleID: vs),
            .init(label: "VS Code", rel: "Library/Caches/com.microsoft.VSCode", bundleID: vs),

            // Cursor (com.todesktop.230313mzl4w4u92)
            .init(label: "Cursor", rel: "Library/Application Support/Cursor/Cache", bundleID: cu),
            .init(label: "Cursor", rel: "Library/Application Support/Cursor/CachedData", bundleID: cu),
            .init(label: "Cursor", rel: "Library/Application Support/Cursor/GPUCache", bundleID: cu),

            // Slack (com.tinyspeck.slackmacgap) — Electron
            .init(label: "Slack", rel: "Library/Application Support/Slack/Cache", bundleID: sl),
            .init(label: "Slack", rel: "Library/Application Support/Slack/Code Cache", bundleID: sl),
            .init(label: "Slack", rel: "Library/Application Support/Slack/GPUCache", bundleID: sl),
            .init(label: "Slack", rel: "Library/Application Support/Slack/Service Worker/CacheStorage", bundleID: sl),

            // Discord (com.hnc.Discord) — Electron
            .init(label: "Discord", rel: "Library/Application Support/discord/Cache", bundleID: di),
            .init(label: "Discord", rel: "Library/Application Support/discord/Code Cache", bundleID: di),
            .init(label: "Discord", rel: "Library/Application Support/discord/GPUCache", bundleID: di),

            // Notion (notion.id) — Electron
            .init(label: "Notion", rel: "Library/Application Support/Notion/Cache", bundleID: no),
        ]
    }

    func scan(_ ctx: ScanContext) async {
        // 1) Fixed cache subpaths for VS Code / Cursor / Slack / Discord / Notion.
        for t in targets {
            if ctx.isCancelled() { return }
            let url = FileScan.home.appendingPathComponent(t.rel)
            ctx.progress(t.label)
            if let item = makeItem(
                at: url,
                severity: .safe,
                minSize: ctx.minSizeBytes,
                isRegenerable: true,
                requiresQuitBundleIDs: [t.bundleID],
                cleanMethod: .trash,
                note: "\(t.label) cache — recreated on next launch",
                selectedIfSafe: true
            ) {
                ctx.emit(item)
            }
        }

        if ctx.isCancelled() { return }

        // 2) JetBrains — enumerate each per-product cache child under
        //    ~/Library/Caches/JetBrains, plus the shared logs tree.
        scanJetBrains(ctx)
    }

    /// JetBrains keeps one cache folder per product/version (e.g. "IntelliJIdea2024.1")
    /// under ~/Library/Caches/JetBrains. Enumerate each child so big stale product
    /// caches surface individually, and add ~/Library/Logs/JetBrains.
    private func scanJetBrains(_ ctx: ScanContext) {
        let jbBundleID = "com.jetbrains.intellij"
        let cachesRoot = FileScan.home.appendingPathComponent("Library/Caches/JetBrains")
        if FileScan.exists(cachesRoot), let children = FileScan.children(of: cachesRoot) {
            for child in children {
                if ctx.isCancelled() { return }
                guard (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                let name = child.lastPathComponent
                ctx.progress("JetBrains \(name)")
                if let item = makeItem(
                    at: child,
                    severity: .safe,
                    minSize: ctx.minSizeBytes,
                    isRegenerable: true,
                    requiresQuitBundleIDs: [jbBundleID],
                    cleanMethod: .trash,
                    note: "JetBrains \(name) cache — recreated on next launch",
                    selectedIfSafe: true
                ) {
                    ctx.emit(item)
                }
            }
        }

        if ctx.isCancelled() { return }

        let logsRoot = FileScan.home.appendingPathComponent("Library/Logs/JetBrains")
        ctx.progress("JetBrains logs")
        if let item = makeItem(
            at: logsRoot,
            severity: .safe,
            minSize: ctx.minSizeBytes,
            isRegenerable: true,
            requiresQuitBundleIDs: [jbBundleID],
            cleanMethod: .trash,
            note: "JetBrains logs — recreated on next launch",
            selectedIfSafe: true
        ) {
            ctx.emit(item)
        }
    }
}
