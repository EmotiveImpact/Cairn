import Foundation
import Darwin

/// Executes a clean for one item. Every file removal passes the SafePaths
/// chokepoint first. Files are moved with `FileManager.trashItem` to their OWN
/// volume's Trash (no AppleScript), then deleted when the reviewed removal mode
/// asks for space to be freed now. Tool items run the tool's own clean command.
enum Cleaner {
    struct Outcome {
        var movedToTrashURL: URL?    // for "Restore from Trash"
        var bytesAffected: Int64
        var usedTool: Bool
        var error: String?
        /// True when the space was released now (deleted or pruned), not parked in Trash.
        var deleted = false
        var ok: Bool { error == nil }
    }

    /// Perform the clean appropriate to the item's `cleanMethod`.
    static func clean(_ item: ScanItem, allowedRoots: [URL], proEnabled: Bool, reviewedSource: ReviewedSource? = nil,
                      moveToTrash: @Sendable (URL) throws -> URL? = { url in
                          var result: NSURL?
                          try FileManager.default.trashItem(at: url, resultingItemURL: &result)
                          return result as URL?
                      }) -> Outcome {
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
            return deleteFromTrash(item)

        case .tool(let command):
            return runTool(command, for: item)
        }
    }

    // MARK: - Trash (and optional immediate deletion)

    private static func trash(_ item: ScanItem, allowedRoots: [URL], reviewedSource: ReviewedSource?, moveToTrash: @Sendable (URL) throws -> URL?) -> Outcome {
        guard item.url.resolvingSymlinksInPath().standardizedFileURL == item.resolvedURL.standardizedFileURL else {
            return Outcome(bytesAffected: 0, usedTool: false, error: "The location changed since scanning. Run a fresh scan.")
        }
        guard let scanned = item.sourceIdentity,
              let current = SourceIdentity.read(item.resolvedURL), scanned == current else {
            return Outcome(bytesAffected: 0, usedTool: false, error: "The file at this location changed since scanning. Run a fresh scan.")
        }
        let verdict = SafePaths.evaluate(item.url, allowedRoots: allowedRoots, rebuildable: item.isRebuildable)
        guard verdict.isAllowed else {
            return Outcome(movedToTrashURL: nil, bytesAffected: 0, usedTool: false,
                           error: rejectReason(verdict))
        }
        let contentsVerdict = SafePaths.evaluateContents(item.resolvedURL, rebuildable: item.isRebuildable,
                                                         reinstallable: item.isReinstallable)
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
        let resulting: URL?
        do {
            // Moving first is an atomic rename: the original path disappears at
            // once, and a failed deletion below still leaves the item in Trash.
            resulting = try moveToTrash(item.resolvedURL)
        } catch {
            // Surface ENOSPC / cross-device honestly; never report a failed trash as reclaimed.
            return Outcome(movedToTrashURL: nil, bytesAffected: 0, usedTool: false,
                           error: trashErrorText(error))
        }
        guard item.deleteImmediately, let trashed = resulting else {
            return Outcome(movedToTrashURL: resulting, bytesAffected: item.allocatedSize, usedTool: false, error: nil)
        }
        if removeTree(trashed) {
            return Outcome(movedToTrashURL: nil, bytesAffected: item.allocatedSize, usedTool: false, error: nil, deleted: true)
        }
        // Partly deleted: what remains is still in Trash and can be put back or emptied.
        return Outcome(movedToTrashURL: trashed, bytesAffected: item.allocatedSize, usedTool: false, error: nil)
    }

    /// Permanently delete an item that already sits directly inside a Trash folder.
    private static func deleteFromTrash(_ item: ScanItem) -> Outcome {
        let url = item.url.standardizedFileURL
        guard isDirectTrashChild(url) else {
            return Outcome(bytesAffected: 0, usedTool: false, error: "Only items directly inside a Trash folder can be emptied.")
        }
        if let scanned = item.sourceIdentity, SourceIdentity.read(url) != scanned {
            return Outcome(bytesAffected: 0, usedTool: false, error: "This Trash item changed since scanning. Run a fresh scan.")
        }
        guard FileScan.exists(url) else {
            return Outcome(bytesAffected: 0, usedTool: false, error: "This item is no longer in the Trash.")
        }
        guard removeTree(url) else {
            return Outcome(bytesAffected: 0, usedTool: false, error: "macOS refused to delete part of this item. Try emptying it in Finder.")
        }
        return Outcome(movedToTrashURL: nil, bytesAffected: item.allocatedSize, usedTool: false, error: nil, deleted: true)
    }

    /// Permanently delete a recorded Trash item (Activity's "Delete now").
    static func deleteTrashedCopy(at trashURL: URL, identity: SourceIdentity?) -> Bool {
        let url = trashURL.standardizedFileURL
        guard isDirectTrashChild(url) else { return false }
        if let identity, SourceIdentity.read(url) != identity { return false }
        return removeTree(url)
    }

    static func isDirectTrashChild(_ url: URL) -> Bool {
        let parent = url.deletingLastPathComponent().standardizedFileURL
        guard parent.resolvingSymlinksInPath() == parent else { return false }
        let homeTrash = FileScan.home.appendingPathComponent(".Trash").standardizedFileURL
        if parent == homeTrash { return true }
        if let volume = FileScan.volumeURL(of: url),
           parent == volume.appendingPathComponent(".Trashes/\(getuid())").standardizedFileURL { return true }
        return false
    }

    /// Delete a file or tree. Read-only directories (Go's module cache, some
    /// package stores) are made writable first so the removal does not stop halfway.
    @discardableResult
    static func removeTree(_ url: URL) -> Bool {
        let fm = FileManager.default
        do { try fm.removeItem(at: url); return true } catch {}
        if let walker = fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []) {
            _ = chmod(url.path, 0o700)
            for case let child as URL in walker {
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values?.isDirectory == true && values?.isSymbolicLink != true { _ = chmod(child.path, 0o700) }
            }
        }
        do { try fm.removeItem(at: url); return true } catch { return !FileScan.exists(url) }
    }

    // MARK: - Tool commands

    private static func runTool(_ command: ToolCommand, for item: ScanItem) -> Outcome {
        if command.destroysData {
            return Outcome(bytesAffected: 0, usedTool: true, error: "This command destroys data and is review-only.")
        }
        guard ToolRunner.isAvailable(command.tool) else {
            return Outcome(bytesAffected: 0, usedTool: true, error: "\(command.tool) was not found on this Mac.")
        }
        do {
            let result = try ToolRunner.run(command.tool, command.arguments, timeout: 900)
            if result.timedOut {
                return Outcome(bytesAffected: 0, usedTool: true, error: "\(command.display) took too long and was stopped.")
            }
            guard result.ok else {
                let detail = (result.stderr.isEmpty ? result.stdout : result.stderr)
                    .trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").last.map(String.init) ?? ""
                return Outcome(bytesAffected: 0, usedTool: true,
                               error: "\(command.display) failed (exit \(result.status))" + (detail.isEmpty ? "." : ": \(detail)"))
            }
            return Outcome(movedToTrashURL: nil, bytesAffected: item.allocatedSize, usedTool: true, error: nil, deleted: true)
        } catch {
            return Outcome(bytesAffected: 0, usedTool: true, error: "\(command.display) could not start: \(error.localizedDescription)")
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
