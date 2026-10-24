import Foundation

/// Cache folders added by a signed cleaning rules update (see RuleUpdates).
/// Nothing is listed until such an update is installed. Every folder is a
/// cache by the update's own limits, and still goes through review and the Bin.
struct RuleSpotsScanner: CairnScanner {
    let info = CategoryInfo(
        id: "rule-spots",
        title: "More App Caches",
        subtitle: "Cache folders added by a cleaning rules update",
        systemImage: "folder.badge.plus",
        group: .general,
        requiresFDA: false
    )

    func scan(_ ctx: ScanContext) async {
        guard let book = RuleUpdates.installed() else { return }
        for spot in book.spots {
            if ctx.isCancelled() { return }
            let url = FileScan.home.appendingPathComponent(spot.path)
            ctx.progress(spot.title)
            if let item = makeItem(at: url, severity: .review, minSize: ctx.minSizeBytes, isRegenerable: true,
                                   cleanMethod: .trash, note: spot.note) {
                ctx.emit(item)
            }
        }
    }
}
