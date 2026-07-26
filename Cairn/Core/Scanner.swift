import Foundation

/// Context handed to each scanner during a run. `emit` is safe to call from any
/// task (it funnels through an AsyncStream continuation in ScanStore).
struct ScanContext {
    var fdaGranted: Bool
    var includeExternalVolumes: Bool
    var minSizeBytes: Int64
    var emit: @Sendable (ScanItem) -> Void
    var progress: @Sendable (String) -> Void
    var isCancelled: @Sendable () -> Bool
}

/// A pluggable scanner. Each declares its category, its allowlist-of-roots (the
/// only places its items may be trashed from — SPEC §5.1), and whether it needs
/// Full Disk Access. Ported in spirit from the prototype's `base.py`/`registry.py`.
protocol CairnScanner: Sendable {
    var info: CategoryInfo { get }
    /// Roots this scanner's items must live under to be trashable. Default: HOME.
    var allowedRoots: [URL] { get }
    func scan(_ context: ScanContext) async
}

extension CairnScanner {
    var allowedRoots: [URL] { [FileScan.home] }

    /// Helper: measure a dir and build a ScanItem, or nil if below threshold / missing.
    func makeItem(
        at url: URL,
        categoryID: String? = nil,
        severity: Severity,
        minSize: Int64,
        isRegenerable: Bool = true,
        requiresQuitBundleIDs: [String] = [],
        requiresRunning: Bool = false,
        cleanMethod: CleanMethod = .trash,
        note: String,
        selectedIfSafe: Bool = false,
        maxFiles: Int = .max
    ) -> ScanItem? {
        guard FileScan.exists(url) else { return nil }
        let stats = FileScan.measure(url, maxFiles: maxFiles)
        if stats.allocatedSize < minSize && !cleanMethod.isPaid { return nil }
        let selected = selectedIfSafe && severity == .safe && isRegenerable && cleanMethod.isActionable
        let finalNote = stats.truncated ? note + " · large (partial size)" : note
        return ScanItem(
            url: url,
            allocatedSize: stats.allocatedSize,
            itemCount: stats.fileCount,
            latestModified: stats.latestModified,
            categoryID: categoryID ?? info.id,
            severity: severity,
            isRegenerable: isRegenerable,
            requiresQuitBundleIDs: requiresQuitBundleIDs,
            requiresRunning: requiresRunning,
            cleanMethod: cleanMethod,
            note: finalNote,
            permissionDenied: stats.permissionDenied,
            volumeURL: FileScan.volumeURL(of: url),
            selected: selected
        )
    }
}

/// Events streamed from the engine to the @MainActor store.
enum ScanEvent {
    case started(String)                 // categoryID
    case item(ScanItem)
    case progress(String, String)        // categoryID, message
    case finishedCategory(String)
    case done
}
