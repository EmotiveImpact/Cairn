import Foundation

/// The single destructive-op chokepoint (SPEC §5.1). EVERY trash/delete passes
/// `evaluate` first. Replaces the prototype's over-permissive `safe_under_home`
/// (which allowlisted system `/Library/Caches`, BUG-008) with:
///   resolve symlinks → scanner allowlist-of-roots → global denylist (always
///   wins) → must be a strict descendant (never a root itself).
enum SafePaths {
    private static let rulesLock = NSLock()
    private static var exclusions: [String] = []
    private static var sessionRoots: [String] = ["CODEX_HOME", "CLAUDE_CONFIG_DIR"].compactMap {
        ProcessInfo.processInfo.environment[$0].flatMap { $0.hasPrefix("/") ? $0 : nil }
    }
    /// Additional custom session locations use the same absolute path guard as
    /// built-in locations. Kept synchronized with background cleanup checks.
    static var protectedSessionRoots: [String] {
        get { rulesLock.lock(); defer { rulesLock.unlock() }; return sessionRoots }
        set { rulesLock.lock(); defer { rulesLock.unlock() }; sessionRoots = newValue }
    }
    /// Result of a safety evaluation.
    enum Verdict: Equatable {
        case allow
        case reject(String)   // human-readable reason
        var isAllowed: Bool { if case .allow = self { return true } else { return false } }
    }

    static let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()

    /// Absolute roots that are NEVER deletable, whatever a scanner declares.
    static let denyAbsolutePrefixes: [String] = [
        "/System", "/Library", "/usr", "/bin", "/sbin", "/private/var/db",
        "/nix",            // Nix store — advice only, never user-rm-safe
        "/Applications",   // never delete app bundles in v1
    ]

    /// Home-relative subtrees that are never deletable (state / secrets / the
    /// only local copy of something). Expanded well beyond the prototype.
    static let denyHomeRelative: [String] = [
        "Library/Keychains",
        ".ssh", ".gnupg",
        "Library/Mail",
        "Library/Messages",
        "Library/Application Support/MobileSync",   // iOS device backups
        "Library/Developer/Xcode/Archives",         // dSYMs to symbolicate shipped crashes
        "Library/Mobile Documents",                 // iCloud Drive local mirror
        "Library/CloudStorage",                     // iCloud/Dropbox/OneDrive mirrors
        "Documents",                                // never a cache target
        // AI coding-agent history + config. These hold irreplaceable conversation
        // transcripts (~/.claude/projects/**.jsonl, Codex sessions) that cannot be
        // re-downloaded or regenerated. Never deletable, at any severity.
        ".claude", ".codex", ".cursor", ".continue", ".aider",
        "Library/Application Support/Claude",
        "Library/Application Support/ChatGPT",
        "Library/Application Support/Codex",
        "Library/Application Support/OpenAI",
        "Library/Application Support/Code/User/History",
    ]

    /// Coding-assistant conversations can also be stored in sandbox containers,
    /// group containers, exports, and moved copies. Scanner root checks alone do
    /// not cover these locations, so every destructive route must use this guard.
    static func protectedSessionReason(_ url: URL) -> String? {
        // Check both the displayed path and the symlink target. A symlink named
        // chatgpt-mac must not become cleanable just because its target has a
        // generic directory name, and a generic alias must not hide agent data.
        let paths = [url.standardizedFileURL,
                     url.resolvingSymlinksInPath().standardizedFileURL]
        for configured in protectedSessionRoots {
            let root = URL(fileURLWithPath: configured).resolvingSymlinksInPath().standardizedFileURL.path
            if paths.contains(where: { isUnder($0.path, root) || isUnder($0.path, configured) }) {
                return "protected custom conversation location"
            }
        }
        for path in paths {
          for part in path.pathComponents.map({ $0.lowercased() }) {
            if [".git", ".hg", ".svn", ".jj", ".ssh", ".gnupg", "worktrees", ".worktrees", "workspacestorage", "session storage", "sessions", "backups", "recovery", "autosave information", "indexeddb", "local storage"].contains(part) {
                return "protected source, session or recovery data (\(part))"
            }
            if part == ".codex" || part == "codex" || part.hasPrefix("codex ")
                || part.hasPrefix("codex-") || part.hasPrefix("codex.")
                || part == "chatgpt" || part.hasPrefix("chatgpt ")
                || part.hasPrefix("chatgpt-") || part.hasPrefix("chatgpt.")
                || part == "openai" || part.hasPrefix("openai-")
                || part == ".claude" || part == "claude" || part.hasPrefix("claude-")
                || part.hasPrefix("com.openai.") || part.hasPrefix("group.com.openai.")
                || part.contains(".com.openai.") {
                return "protected conversation or agent data (\(part))"
            }
          }
          let name = path.lastPathComponent.lowercased()
          if (name.hasPrefix("rollout-") && name.hasSuffix(".jsonl")) || name == "history.jsonl"
              || name == "pg_version" || name == ".env" || name.hasPrefix(".env.")
              || ["sqlite", "sqlite3", "db", "vscdb", "rdb", "pem", "key", "p12", "pfx"].contains(path.pathExtension.lowercased())
              || [".sqlite-wal", ".sqlite-shm", ".db-wal", ".db-shm", ".sqlite3-wal", ".sqlite3-shm"].contains(where: name.hasSuffix) {
              return "protected database, conversation or recovery file"
          }
        }
        return nil
    }

    /// A path containing any of these components is rejected (e.g. Photos library).
    static let denyComponents: [String] = [
        ".photoslibrary", ".photolibrary", ".aplibrary",
    ]

    /// User-defined exclusions (set from AppSettings). Always wins, like the denylist.
    static var userExcluded: [String] {
        get { rulesLock.lock(); defer { rulesLock.unlock() }; return exclusions }
        set { rulesLock.lock(); defer { rulesLock.unlock() }; exclusions = newValue }
    }

    /// Evaluate whether `url` may be moved to the Trash by a scanner whose
    /// declared allowlist-of-roots is `allowedRoots`.
    static func evaluate(_ url: URL, allowedRoots: [URL]) -> Verdict {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let path = resolved.path

        if path == "/" || path.isEmpty { return .reject("refuses to act on the filesystem root") }
        if resolved == home { return .reject("refuses to act on the home folder itself") }

        if let reason = protectedSessionReason(url) { return .reject(reason) }

        // Denylist always wins.
        for prefix in denyAbsolutePrefixes where isUnder(path, prefix) {
            return .reject("protected system location (\(prefix))")
        }
        for comp in denyComponents where resolved.pathComponents.contains(where: { $0.hasSuffix(comp) }) {
            return .reject("protected library bundle (\(comp))")
        }
        for rel in denyHomeRelative {
            let denied = home.appendingPathComponent(rel).path
            if path == denied || isUnder(path, denied) {
                return .reject("protected data location (~/\(rel))")
            }
        }
        for ex in userExcluded {
            let resolvedEx = URL(fileURLWithPath: ex).resolvingSymlinksInPath().standardizedFileURL.path
            if isUnder(path, resolvedEx) || isUnder(url.standardizedFileURL.path, ex) {
                return .reject("excluded by you in Settings")
            }
        }

        // Must be a STRICT descendant of at least one declared root.
        let roots = allowedRoots.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        let underAllowed = roots.contains { root in path != root && isUnder(path, root) }
        guard underAllowed else {
            return .reject("outside this scanner's permitted roots")
        }
        return .allow
    }

    /// A generic parent folder can hide an agent session several levels down.
    /// Verify immediately before moving a directory; fail closed on unreadable
    /// or exceptionally large trees rather than silently skipping descendants.
    static func evaluateContents(_ url: URL) -> Verdict {
        let root = url.resolvingSymlinksInPath().standardizedFileURL
        guard let values = try? root.resourceValues(forKeys: [.isDirectoryKey]) else {
            return .reject("could not inspect the selected path")
        }
        guard values.isDirectory == true else { return .allow }
        var hadError = false
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [], errorHandler: { _, _ in hadError = true; return false }
        ) else { return .reject("could not inspect directory contents") }
        var count = 0
        let excludedRoots = userExcluded.flatMap { [$0, URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL.path] }
        let deadline = ProcessInfo.processInfo.systemUptime + 15
        for case let child as URL in walker {
            if Task.isCancelled { return .reject("inspection cancelled") }
            if ProcessInfo.processInfo.systemUptime >= deadline {
                return .reject("directory inspection timed out")
            }
            count += 1
            if count > 100_000 { return .reject("directory is too large to verify safely") }
            if let reason = protectedSessionReason(child) { return .reject(reason) }
            // Removing a parent must not bypass an exclusion on its child.
            let resolved = child.resolvingSymlinksInPath().standardizedFileURL.path
            for excluded in excludedRoots {
                if isUnder(child.path, excluded) || isUnder(resolved, excluded) { return .reject("contains a location excluded in Settings") }
            }
            if denyComponents.contains(where: { child.lastPathComponent.lowercased().hasSuffix($0) }) {
                return .reject("contains a protected library bundle")
            }
        }
        if hadError { return .reject("could not inspect every directory entry") }
        return .allow
    }

    /// True if `path` is `prefix` or strictly inside it (component-aware, so
    /// "/Library" never matches "/LibraryFoo").
    static func isUnder(_ path: String, _ prefix: String) -> Bool {
        if path == prefix { return true }
        let p = prefix.hasSuffix("/") ? prefix : prefix + "/"
        return path.hasPrefix(p)
    }
}
