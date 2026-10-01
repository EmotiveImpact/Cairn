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
    /// The caller may still pass a legacy tool item; the executor must reject it.
    static func clean(_ item: ScanItem, allowedRoots: [URL], proEnabled: Bool, reviewedSource: ReviewedSource? = nil,
                      moveToTrash: @Sendable (URL) throws -> URL? = { url in
                          var result: NSURL?
                          try FileManager.default.trashItem(at: url, resultingItemURL: &result)
                          return result as URL?
                      }) -> Outcome {
        // A package/build tool may still write to a cache, and a fixed path
        // does not prove which location its configuration actually uses. Refuse
        // even a stale or manually constructed `.trash` item for observed
        // tool-owned roots, not just current scanner selections.
        if DevCachesScanner.isObservedToolCache(item.url) || DevCachesScanner.isObservedToolCache(item.resolvedURL) {
            return Outcome(movedToTrashURL: nil, bytesAffected: 0, usedTool: false,
                           error: "Tool-owned caches are review-only. Cairn cannot verify the configured cache or active writers; use the tool's own maintenance after checking it is idle.")
        }
        if item.severity == .risky {
            return Outcome(movedToTrashURL: nil, bytesAffected: 0, usedTool: false,
                           error: "Risky data is review-only; Cairn will not remove it.")
        }
        switch item.cleanMethod {
        case .adviceOnly:
            return Outcome(movedToTrashURL: nil, bytesAffected: 0, usedTool: false,
                           error: "This is an advice item — nothing to delete here.")

        case .trash:
            return trash(item, allowedRoots: allowedRoots, reviewedSource: reviewedSource, moveToTrash: moveToTrash)

        case .emptyTrash:
            // Trash can contain the last recoverable copy of a conversation or
            // work session. Its current path cannot reveal its original location.
            return Outcome(movedToTrashURL: nil, bytesAffected: 0, usedTool: false,
                           error: "Permanent Trash removal is disabled. Review and empty Trash in Finder.")

        case .tool:
            // A broad command can act outside `item.url` (for example pnpm's
            // configured store or Docker's whole VM). Neither SafePaths nor a
            // checkbox can constrain the command's real target, exclusions,
            // writers, or effect. Keep tool findings visible but never execute
            // them until each action has its own validated adapter.
            return Outcome(movedToTrashURL: nil, bytesAffected: 0, usedTool: false,
                           error: "Tool cleanup is review-only. Cairn cannot verify the command's configured target, exclusions, active writers, or exact effect.")
        }
    }

    // MARK: - Trash (the default, recoverable path)

    private static func trash(_ item: ScanItem, allowedRoots: [URL], reviewedSource: ReviewedSource?, moveToTrash: @Sendable (URL) throws -> URL?) -> Outcome {
        guard item.url.resolvingSymlinksInPath().standardizedFileURL == item.resolvedURL.standardizedFileURL else {
            return Outcome(bytesAffected: 0, usedTool: false, error: "The location changed since scanning. Run a fresh scan.")
        }
        guard let scanned = item.sourceIdentity,
              let current = SourceIdentity.read(item.resolvedURL), scanned == current else {
            return Outcome(bytesAffected: 0, usedTool: false, error: "The file at this location changed since scanning. Run a fresh scan.")
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
        if let reviewedSource, ReviewedSource.read(item.url) != reviewedSource {
            return Outcome(bytesAffected: 0, usedTool: false, error: "The source changed after goal review. Review a fresh plan.")
        }
        do {
            let resulting = try moveToTrash(item.resolvedURL)
            return Outcome(movedToTrashURL: resulting, bytesAffected: item.allocatedSize,
                           usedTool: false, error: nil)
        } catch {
            // Surface ENOSPC / cross-device honestly; never report a failed trash as reclaimed.
            return Outcome(movedToTrashURL: nil, bytesAffected: 0, usedTool: false,
                           error: trashErrorText(error))
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
