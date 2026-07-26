import Foundation

/// Old application logs under `~/Library/Logs`. Logs are diagnostic output that
/// apps regenerate as they run, so stale ones (untouched for 14+ days) are SAFE
/// to trash — the app simply writes fresh logs on its next launch. We only flag
/// entries that have gone cold to avoid removing a log an app is actively
/// appending to. These are plain 0700 user dirs → no Full Disk Access needed.
struct LogsScanner: CairnScanner {
    let info = CategoryInfo(
        id: "logs",
        title: "Logs",
        subtitle: "Stale application logs in ~/Library/Logs",
        systemImage: "doc.text.magnifyingglass",
        group: .general,
        requiresFDA: false
    )

    /// Logs untouched for at least this many days are considered safe to clear.
    private let maxAgeDays: Double = 14

    func scan(_ ctx: ScanContext) async {
        // A 1MB floor: tiny log entries aren't worth surfacing as their own row.
        let minSize = max(1_048_576, ctx.minSizeBytes)

        let logsRoot = FileScan.home.appendingPathComponent("Library/Logs")

        // 1) Direct children of ~/Library/Logs.
        if FileScan.exists(logsRoot), let entries = FileScan.children(of: logsRoot) {
            for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                if ctx.isCancelled() { return }
                let name = url.lastPathComponent
                ctx.progress(name)
                emitIfStale(at: url, name: name, minSize: minSize, ctx: ctx)
            }
        }

        // 2) Notable nested log dirs worth flagging individually if present. These
        //    may also appear as direct children above; emitting both is harmless
        //    (deduped downstream by path) and ensures we cover them explicitly.
        let nested = [
            ("JetBrains", "Library/Logs/JetBrains"),
            ("DiagnosticReports", "Library/Logs/DiagnosticReports"),
        ]
        for (name, rel) in nested {
            if ctx.isCancelled() { return }
            let url = FileScan.home.appendingPathComponent(rel)
            guard FileScan.exists(url) else { continue }
            ctx.progress(name)
            emitIfStale(at: url, name: name, minSize: minSize, ctx: ctx)
        }
    }

    /// Measure an entry and, if it has been untouched for `maxAgeDays`, emit it as
    /// a SAFE, pre-selected, trashable item.
    private func emitIfStale(at url: URL, name: String, minSize: Int64, ctx: ScanContext) {
        guard let item = makeItem(
            at: url,
            severity: .safe,
            minSize: minSize,
            isRegenerable: true,
            cleanMethod: .trash,
            note: "Old logs for \(name)",
            selectedIfSafe: true
        ) else { return }

        // Only old logs qualify — recently written logs may be in active use.
        guard item.ageDays >= maxAgeDays else { return }

        ctx.emit(item)
    }
}
