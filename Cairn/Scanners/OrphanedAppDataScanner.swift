import Foundation

/// Orphaned application data — per-app folders under Application Support,
/// Containers and Group Containers whose owning app is no longer installed
/// (SPEC §3.x). Fixes prototype BUG-009: the prototype matched folder name to
/// bundle id with a naive equality test, so it (a) missed sub-domains like
/// `com.google.Chrome.helper`, and (b) wrongly flagged sandbox/group folders
/// that carry a 10-char team-id prefix (`<TEAMID>.com.acme.App`) or a
/// `group.` prefix (`group.com.acme.App`). We now strip those affixes and do a
/// bundle-id PREFIX match so a folder is claimed by any installed app whose
/// bundle id it is a prefix of (or vice-versa, on a dotted boundary).
///
/// Reading another app's data folders to size them needs Full Disk Access.
struct OrphanedAppDataScanner: CairnScanner {
    let info = CategoryInfo(
        id: "orphaned",
        title: "Orphaned App Data",
        subtitle: "Leftover data from apps that are no longer installed",
        systemImage: "questionmark.folder.fill",
        group: .general,
        requiresFDA: true
    )

    /// Six months in seconds — the staleness floor before a folder may be
    /// flagged (a recently-touched folder may belong to an app installed
    /// somewhere we didn't enumerate, or one about to be reinstalled).
    private static let staleAge: TimeInterval = 60 * 60 * 24 * 182  // ~6 months

    /// Directories that hold *.app bundles. We read CFBundleIdentifier from each.
    private var appRoots: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            FileScan.home.appendingPathComponent("Applications"),
            URL(fileURLWithPath: "/System/Applications"),
        ]
    }

    /// Per-app data roots to scan, one level deep.
    private var dataRoots: [URL] {
        let lib = FileScan.home.appendingPathComponent("Library")
        return [
            lib.appendingPathComponent("Application Support"),
            lib.appendingPathComponent("Containers"),
            lib.appendingPathComponent("Group Containers"),
        ]
    }

    /// Folder names that are never per-app orphans — Apple/system-managed or
    /// shared stores whose absence-of-app heuristic would mis-fire.
    private let vendorAllowlist: Set<String> = [
        "MobileSync", "CrashReporter", "Caches", "iCloud",
        "CloudDocs", "AddressBook", "Knowledge",
    ]

    func scan(_ ctx: ScanContext) async {
        ctx.progress("Reading installed apps")
        let installed = installedBundleIDs()

        for root in dataRoots {
            if ctx.isCancelled() { return }
            guard FileScan.exists(root), let children = FileScan.children(of: root) else { continue }
            ctx.progress("Scanning \(root.lastPathComponent)")

            for child in children {
                if ctx.isCancelled() { return }

                // Only consider directories (a per-app folder).
                let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if !isDir { continue }

                let name = child.lastPathComponent

                // Apple's own state and the static vendor allowlist are skipped.
                if name.hasPrefix("com.apple.") { continue }
                if isAllowlisted(name) { continue }

                // Claimed by an installed app? Then it is NOT orphaned.
                if isClaimed(name, by: installed) { continue }

                ctx.progress(name)

                // Build the item (this applies the min-size floor). Stale check
                // uses the measured latestModified, so we read it post-build.
                guard let item = makeItem(
                    at: child,
                    severity: .review,
                    minSize: ctx.minSizeBytes,
                    isRegenerable: false,
                    cleanMethod: .trash,
                    note: "No installed app matches '\(name)' (stale >6mo) — review before removing",
                    selectedIfSafe: false
                ) else { continue }

                // Only flag genuinely stale folders. distantPast (unreadable
                // mtime) is treated as stale; a recent touch keeps it.
                let age = Date().timeIntervalSince(item.latestModified)
                if age < Self.staleAge { continue }

                ctx.emit(item)
            }
        }
    }

    // MARK: - Installed bundle ids

    /// Read CFBundleIdentifier from the Info.plist of every *.app under the app
    /// roots (one level deep — we don't recurse into nested bundles).
    private func installedBundleIDs() -> Set<String> {
        var ids = Set<String>()
        for root in appRoots {
            guard FileScan.exists(root), let children = FileScan.children(of: root) else { continue }
            for app in children where app.pathExtension == "app" {
                if let id = bundleID(ofApp: app) { ids.insert(id) }
            }
        }
        return ids
    }

    /// CFBundleIdentifier from `<App>.app/Contents/Info.plist`, lowercased for
    /// case-insensitive matching against folder names.
    private func bundleID(ofApp app: URL) -> String? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = obj as? [String: Any],
              let id = dict["CFBundleIdentifier"] as? String else { return nil }
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    // MARK: - Claim logic (BUG-009 fix)

    private func isAllowlisted(_ name: String) -> Bool {
        if vendorAllowlist.contains(name) { return true }
        return false
    }

    /// A folder is claimed (NOT orphaned) if its normalized name relates to any
    /// installed bundle id on a dotted boundary: equal, the folder is a prefix
    /// of the id (`com.acme` ⊑ `com.acme.App`), or the id is a prefix of the
    /// folder (`com.acme.App` ⊑ `com.acme.App.helper`).
    private func isClaimed(_ folderName: String, by installed: Set<String>) -> Bool {
        let candidate = normalize(folderName)
        if candidate.isEmpty { return false }
        for id in installed {
            if dottedPrefixMatch(candidate, id) { return true }
        }
        return false
    }

    /// Strip a leading 10-char team-id + "." and a leading "group." prefix, then
    /// lowercase. Order: team-id first (it may wrap a group container, e.g.
    /// `<TEAMID>.group.com.acme.App` is seen in the wild), then group.
    private func normalize(_ name: String) -> String {
        var s = name
        if let stripped = strippingTeamID(s) { s = stripped }
        if s.hasPrefix("group.") { s = String(s.dropFirst("group.".count)) }
        // A team id can also sit *inside* a group prefix on some layouts.
        if let stripped = strippingTeamID(s) { s = stripped }
        return s.lowercased()
    }

    /// If `name` begins with a 10-character alphanumeric team identifier
    /// followed by a dot (e.g. `9XYZ123ABC.com.acme.App`), return the remainder
    /// after that dot; otherwise nil.
    private func strippingTeamID(_ name: String) -> String? {
        guard let dot = name.firstIndex(of: ".") else { return nil }
        let head = name[name.startIndex..<dot]
        guard head.count == 10 else { return nil }
        // Team ids are A–Z0–9 (uppercase), but be lenient on case here.
        let isTeamID = head.allSatisfy { $0.isLetter || $0.isNumber } &&
            head.contains(where: { $0.isLetter }) &&
            head.contains(where: { $0.isNumber })
        guard isTeamID else { return nil }
        return String(name[name.index(after: dot)...])
    }

    /// True if `a` and `b` are equal, or one is a prefix of the other on a
    /// dotted component boundary. Both are already lowercased.
    private func dottedPrefixMatch(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        if a.hasPrefix(b + ".") { return true }
        if b.hasPrefix(a + ".") { return true }
        return false
    }
}
