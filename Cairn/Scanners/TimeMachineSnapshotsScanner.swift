import Foundation

/// Local APFS Time Machine snapshots (SPEC §3.3, hidden general clutter). macOS
/// keeps on-disk "local snapshots" so Time Machine can offer rollbacks even when
/// the backup disk is detached. They are purgeable, so the Finder reports them as
/// free space, yet they routinely dominate the opaque "System Data" bucket and can
/// hold many gigabytes. They are NOT directly sizeable per-snapshot (the kernel
/// reports them only as aggregate purgeable space), so every item here carries an
/// unknown (0) allocatedSize and is surfaced for explicit REVIEW — never pre-selected.
///
/// Discovery: `tmutil listlocalsnapshots /`. Snapshots are recovery points, so
/// Cairn lists them for context but never deletes them.
struct TimeMachineSnapshotsScanner: CairnScanner {
    let info = CategoryInfo(
        id: "tm-snapshots",
        title: "Time Machine Snapshots",
        subtitle: "Local APFS snapshots hiding inside opaque \u{201C}System Data\u{201D}",
        systemImage: "clock.arrow.circlepath",
        group: .general,
        requiresFDA: false
    )

    func scan(_ ctx: ScanContext) async {
        // tmutil unavailable (non-APFS / locked-down env) → nothing to surface.
        guard ToolRunner.isAvailable("tmutil") else { return }

        ctx.progress("Local snapshots")
        guard let result = try? ToolRunner.run("tmutil", ["listlocalsnapshots", "/"], timeout: 10),
              result.ok else { return }

        let tokens = Self.parseSnapshotTokens(result.stdout)
        if tokens.isEmpty { return }   // no snapshots → emit nothing
        if ctx.isCancelled() { return }

        let snapshotRoot = URL(fileURLWithPath: "/")

        // Leading advice card: explain WHY these matter before any actionable items.
        // Size is unknown (purgeable, not per-snapshot sizeable) → construct directly.
        ctx.emit(ScanItem(
            url: snapshotRoot,
            resolvedURL: snapshotRoot,
            allocatedSize: 0,
            itemCount: tokens.count,
            latestModified: .distantPast,
            categoryID: info.id,
            severity: .review,
            isRegenerable: false,
            requiresQuitBundleIDs: [],
            requiresRunning: false,
            cleanMethod: .adviceOnly,
            note: "\(tokens.count) local Time Machine snapshot\(tokens.count == 1 ? "" : "s") — these are purgeable APFS snapshots that the Finder counts as free space yet often make up the largest hidden part of \u{201C}System Data\u{201D}. Thinning them reduces your local rollback window but never affects networked or external-disk backups.",
            permissionDenied: false,
            volumeURL: FileScan.volumeURL(of: snapshotRoot),
            selected: false
        ))

        // One advice item per snapshot. Size is not directly knowable → 0.
        for token in tokens {
            if ctx.isCancelled() { return }
            ctx.progress(token)

            // Snapshot path is on "/" (the data volume); use it for volume-aware UI.
            let displayURL = URL(fileURLWithPath: "/.snapshots/com.apple.TimeMachine.\(token).local")

            ctx.emit(ScanItem(
                url: displayURL,
                resolvedURL: displayURL,
                allocatedSize: 0,
                itemCount: 1,
                latestModified: Self.date(from: token) ?? .distantPast,
                categoryID: info.id,
                severity: .review,
                isRegenerable: false,
                requiresQuitBundleIDs: [],
                requiresRunning: false,
                cleanMethod: .adviceOnly,
                note: "Local Time Machine recovery point from \(token). Manage snapshots with macOS or Time Machine after checking your backup state.",
                permissionDenied: false,
                volumeURL: FileScan.volumeURL(of: snapshotRoot),
                selected: false
            ))
        }
    }

    // MARK: - tmutil output parsing

    private static let snapshotPrefix = "com.apple.TimeMachine."
    private static let snapshotSuffix = ".local"

    /// Parse `tmutil listlocalsnapshots /` output into bare date tokens
    /// (e.g. "2026-06-30-031500"). Output lines look like:
    ///   "com.apple.TimeMachine.2026-06-30-031500.local"
    /// A header line ("Snapshots for volume '/':") and blank lines are ignored.
    /// Each token is the argument `tmutil deletelocalsnapshots` expects.
    static func parseSnapshotTokens(_ stdout: String) -> [String] {
        var tokens: [String] = []
        var seen = Set<String>()
        for rawLine in stdout.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix(snapshotPrefix), line.hasSuffix(snapshotSuffix) else { continue }
            var token = String(line.dropFirst(snapshotPrefix.count))
            token = String(token.dropLast(snapshotSuffix.count))
            token = token.trimmingCharacters(in: .whitespaces)
            guard !token.isEmpty, !seen.contains(token) else { continue }
            seen.insert(token)
            tokens.append(token)
        }
        return tokens
    }

    /// Best-effort parse of a snapshot token ("2026-06-30-031500") into a Date so
    /// the UI can show its age. Returns nil if the token isn't the expected shape.
    static func date(from token: String) -> Date? {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone.current
        fmt.dateFormat = "yyyy-MM-dd-HHmmss"
        return fmt.date(from: token)
    }
}
