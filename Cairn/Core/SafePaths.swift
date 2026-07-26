import Foundation

/// The single destructive-op chokepoint (SPEC §5.1). EVERY trash/delete passes
/// `evaluate` first. Replaces the prototype's over-permissive `safe_under_home`
/// (which allowlisted system `/Library/Caches`, BUG-008) with:
///   resolve symlinks → scanner allowlist-of-roots → global denylist (always
///   wins) → must be a strict descendant (never a root itself).
enum SafePaths {
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
        "Library/Application Support/Code/User/History",
    ]

    /// A path containing any of these components is rejected (e.g. Photos library).
    static let denyComponents: [String] = [
        ".photoslibrary", ".photolibrary", ".aplibrary",
    ]

    /// User-defined exclusions (set from AppSettings). Always wins, like the denylist.
    static var userExcluded: [String] = []

    /// Evaluate whether `url` may be moved to the Trash by a scanner whose
    /// declared allowlist-of-roots is `allowedRoots`.
    static func evaluate(_ url: URL, allowedRoots: [URL]) -> Verdict {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let path = resolved.path

        if path == "/" || path.isEmpty { return .reject("refuses to act on the filesystem root") }
        if resolved == home { return .reject("refuses to act on the home folder itself") }

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
        for ex in userExcluded where path == ex || isUnder(path, ex) {
            return .reject("excluded by you in Settings")
        }

        // Must be a STRICT descendant of at least one declared root.
        let roots = allowedRoots.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        let underAllowed = roots.contains { root in path != root && isUnder(path, root) }
        guard underAllowed else {
            return .reject("outside this scanner's permitted roots")
        }
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
