import Foundation
import Darwin

/// Executes a clean for one item. Every destructive op passes the SafePaths
/// chokepoint first. Uses `FileManager.trashItem` to the file's OWN volume —
/// no AppleScript (kills prototype BUG-002 injection), preserves Put Back/undo.
enum Cleaner {
    struct Outcome {
        var movedToTrashURL: URL?    // for "Restore from Trash"
        var bytesAffected: Int64
        var usedTool: Bool
        var error: String?
        var ok: Bool { error == nil }
    }

    /// Perform the clean appropriate to the item's `cleanMethod`.
    /// `proEnabled` gates tool-mediated cleans (the paid "correct command" feature).
    static func clean(_ item: ScanItem, allowedRoots: [URL], proEnabled: Bool) -> Outcome {
        if item.severity == .risky {
            return Outcome(movedToTrashURL: nil, bytesAffected: 0, usedTool: false,
                           error: "Risky data is review-only; Cairn will not remove it.")
        }
        switch item.cleanMethod {
        case .adviceOnly:
            return Outcome(movedToTrashURL: nil, bytesAffected: 0, usedTool: false,
                           error: "This is an advice item — nothing to delete here.")

        case .trash:
            return trash(item, allowedRoots: allowedRoots)

        case .emptyTrash:
            // Trash can contain the last recoverable copy of a conversation or
            // work session. Its current path cannot reveal its original location.
            return Outcome(movedToTrashURL: nil, bytesAffected: 0, usedTool: false,
                           error: "Permanent Trash removal is disabled. Review and empty Trash in Finder.")

        case .tool(let cmd):
            if cmd.destroysData {
                return Outcome(movedToTrashURL: nil, bytesAffected: 0, usedTool: true,
                               error: "This tool action can destroy retained data and is disabled.")
            }
            if let reason = SafePaths.protectedSessionReason(item.url)
                ?? SafePaths.protectedSessionReason(item.resolvedURL) {
                return Outcome(movedToTrashURL: nil, bytesAffected: 0, usedTool: false,
                               error: "Blocked by safety guard: \(reason).")
            }
            guard proEnabled else {
                return Outcome(movedToTrashURL: nil, bytesAffected: 0, usedTool: false,
                               error: "Correct-command cleaning is a Pro feature.")
            }
            return runTool(cmd, item: item)
        }
    }

    // MARK: - Trash (the default, recoverable path)

    private static func trash(_ item: ScanItem, allowedRoots: [URL]) -> Outcome {
        guard item.url.resolvingSymlinksInPath().standardizedFileURL == item.resolvedURL.standardizedFileURL else {
            return Outcome(bytesAffected: 0, usedTool: false, error: "The location changed since scanning. Run a fresh scan.")
        }
        let verdict = SafePaths.evaluate(item.url, allowedRoots: allowedRoots)
        guard verdict.isAllowed else {
            return Outcome(movedToTrashURL: nil, bytesAffected: 0, usedTool: false,
                           error: rejectReason(verdict))
        }
        let contentsVerdict = SafePaths.evaluateContents(item.resolvedURL)
        guard contentsVerdict.isAllowed else {
            return Outcome(movedToTrashURL: nil, bytesAffected: 0, usedTool: false,
                           error: rejectReason(contentsVerdict))
        }
        guard FileScan.exists(item.resolvedURL) else {
            return Outcome(movedToTrashURL: nil, bytesAffected: 0, usedTool: false, error: "This item is no longer at its scanned location. Run a fresh scan.")
        }
        var resulting: NSURL?
        do {
            try FileManager.default.trashItem(at: item.resolvedURL, resultingItemURL: &resulting)
            return Outcome(movedToTrashURL: resulting as URL?, bytesAffected: item.allocatedSize,
                           usedTool: false, error: nil)
        } catch {
            // Surface ENOSPC / cross-device honestly; never report a failed trash as reclaimed.
            return Outcome(movedToTrashURL: nil, bytesAffected: 0, usedTool: false,
                           error: trashErrorText(error))
        }
    }

    // MARK: - Tool-mediated (paid)

    private static func runTool(_ cmd: ToolCommand, item: ScanItem) -> Outcome {
        guard ToolRunner.isAvailable(cmd.tool) else {
            return Outcome(movedToTrashURL: nil, bytesAffected: 0, usedTool: true,
                           error: "`\(cmd.tool)` not found on PATH — run it yourself: \(cmd.display)")
        }
        do {
            let r = try ToolRunner.run(cmd.tool, cmd.arguments, timeout: 180)
            if r.timedOut {
                return Outcome(movedToTrashURL: nil, bytesAffected: 0, usedTool: true,
                               error: "\(cmd.display) timed out and was stopped.")
            }
            if !r.ok {
                let msg = r.stderr.isEmpty ? r.stdout : r.stderr
                return Outcome(movedToTrashURL: nil, bytesAffected: 0, usedTool: true,
                               error: "\(cmd.display) failed: \(msg.prefix(200))")
            }
            return Outcome(movedToTrashURL: nil, bytesAffected: item.allocatedSize, usedTool: true, error: nil)
        } catch {
            return Outcome(movedToTrashURL: nil, bytesAffected: 0, usedTool: true,
                           error: "Could not run \(cmd.tool): \(error.localizedDescription)")
        }
    }

    /// Restore a previously-trashed item to its original location.
    static func restore(from trashURL: URL, to original: URL) -> Bool {
        let homeTrash = FileScan.home.appendingPathComponent(".Trash")
        let volumeTrash = FileScan.volumeURL(of: trashURL)?.appendingPathComponent(".Trashes/\(getuid())")
        guard canRestore(from: trashURL, to: original, trashRoots: [homeTrash] + [volumeTrash].compactMap { $0 }) else { return false }
        // Atomic no-replace rename. A file or dangling link at the original
        // path must not be overwritten after a stale UI existence check.
        return renamex_np(trashURL.path, original.path, UInt32(RENAME_EXCL)) == 0
    }

    static func canRestore(from trashURL: URL, to original: URL, trashRoots: [URL]) -> Bool {
        let trash = trashURL.standardizedFileURL
        let destination = original.standardizedFileURL
        guard trashRoots.contains(where: { trash.deletingLastPathComponent() == $0.standardizedFileURL }),
              trash.deletingLastPathComponent().resolvingSymlinksInPath() == trash.deletingLastPathComponent(),
              destination.deletingLastPathComponent().resolvingSymlinksInPath() == destination.deletingLastPathComponent(),
              trash != destination else { return false }
        var present = stat(), existing = stat()
        return lstat(trash.path, &present) == 0 && lstat(destination.path, &existing) != 0 && errno == ENOENT
    }

    // MARK: - error text

    private static func rejectReason(_ v: SafePaths.Verdict) -> String {
        if case .reject(let why) = v { return "Blocked by safety guard: \(why)." }
        return "Blocked by safety guard."
    }

    private static func trashErrorText(_ error: Error) -> String {
        let ns = error as NSError
        if ns.code == NSFileWriteOutOfSpaceError { return "Not enough free space to move this to the Trash." }
        return ns.localizedDescription
    }
}
