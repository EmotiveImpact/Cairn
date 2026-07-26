import Foundation

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
        switch item.cleanMethod {
        case .adviceOnly:
            return Outcome(movedToTrashURL: nil, bytesAffected: 0, usedTool: false,
                           error: "This is an advice item — nothing to delete here.")

        case .trash:
            return trash(item, allowedRoots: allowedRoots)

        case .emptyTrash:
            return permanentlyRemove(item, allowedRoots: allowedRoots)

        case .tool(let cmd):
            guard proEnabled else {
                return Outcome(movedToTrashURL: nil, bytesAffected: 0, usedTool: false,
                               error: "Correct-command cleaning is a Pro feature.")
            }
            return runTool(cmd, item: item)
        }
    }

    // MARK: - Trash (the default, recoverable path)

    private static func trash(_ item: ScanItem, allowedRoots: [URL]) -> Outcome {
        let verdict = SafePaths.evaluate(item.resolvedURL, allowedRoots: allowedRoots)
        guard verdict.isAllowed else {
            return Outcome(movedToTrashURL: nil, bytesAffected: 0, usedTool: false,
                           error: rejectReason(verdict))
        }
        guard FileScan.exists(item.resolvedURL) else {
            return Outcome(movedToTrashURL: nil, bytesAffected: 0, usedTool: false, error: nil) // already gone
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

    // MARK: - Permanent remove (Empty Trash items — already in the Trash)

    private static func permanentlyRemove(_ item: ScanItem, allowedRoots: [URL]) -> Outcome {
        let verdict = SafePaths.evaluate(item.resolvedURL, allowedRoots: allowedRoots)
        guard verdict.isAllowed else {
            return Outcome(movedToTrashURL: nil, bytesAffected: 0, usedTool: false, error: rejectReason(verdict))
        }
        do {
            try FileManager.default.removeItem(at: item.resolvedURL)
            return Outcome(movedToTrashURL: nil, bytesAffected: item.allocatedSize, usedTool: false, error: nil)
        } catch {
            return Outcome(movedToTrashURL: nil, bytesAffected: 0, usedTool: false,
                           error: (error as NSError).localizedDescription)
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
        do { try FileManager.default.moveItem(at: trashURL, to: original); return true }
        catch { return false }
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
