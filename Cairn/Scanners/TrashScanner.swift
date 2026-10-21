import Foundation

/// Items already in the Trash — emptying reclaims this space immediately.
/// Volume-aware: surfaces the home Trash AND each external volume's
/// `/Volumes/*/.Trashes/<uid>` so external-SSD reclaim is visible (SPEC §3.2).
struct TrashScanner: CairnScanner {
    let info = CategoryInfo(
        id: "trash",
        title: "Trash",
        subtitle: "Items already in the Trash, across all volumes",
        systemImage: "trash.fill",
        group: .general,
        requiresFDA: false
    )

    var allowedRoots: [URL] {
        var roots = [FileScan.home]
        roots.append(contentsOf: Volumes.mountedExternalVolumes())
        return roots
    }

    func scan(_ ctx: ScanContext) async {
        let uid = getuid()
        var trashes: [URL] = [FileScan.home.appendingPathComponent(".Trash")]
        if ctx.includeExternalVolumes {
            for vol in Volumes.mountedExternalVolumes() {
                trashes.append(vol.appendingPathComponent(".Trashes/\(uid)"))
            }
        }

        for trash in trashes {
            if ctx.isCancelled() { return }
            guard FileScan.exists(trash), let children = FileScan.children(of: trash) else { continue }
            ctx.progress("Reading \(trash.path)")
            for child in children {
                if ctx.isCancelled() { return }
                if let item = makeItem(
                    at: child,
                    severity: .safe,
                    minSize: 1,                       // show everything in Trash
                    cleanMethod: .emptyTrash,
                    note: "In Trash — emptying frees this space now",
                    selectedIfSafe: true
                ) {
                    ctx.emit(item)
                }
            }
        }
    }
}
