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
        // Never inspect or advertise conversation stores as cleanup candidates,
        // even when a broad cache scanner enumerates their parent directory.
        guard SafePaths.protectedSessionReason(url) == nil else { return nil }
        // Apple's own caches and parts of a shared model store are never listed.
        guard SafePaths.appleCacheReason(url) == nil, SafePaths.sharedModelStoreReason(url) == nil else { return nil }
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


/// Bounded delivery and an explicit producer lifetime. Cancelling a consumer
/// alone does not await a detached task, so the gate owner must call stopAndWait.
struct ScanEventPipeline {
    let stream: AsyncStream<ScanEvent>
    let overflow = CancelBox()
    private let worker: Task<Void, Never>

    init(scanners: [CairnScanner], fdaGranted: Bool, includeExternal: Bool,
         minSize: Int64, bufferLimit: Int = 2048) {
        let (stream, continuation) = AsyncStream.makeStream(of: ScanEvent.self,
            bufferingPolicy: .bufferingOldest(max(1, bufferLimit)))
        self.stream = stream
        let overflow = self.overflow
        let emit: @Sendable (ScanEvent) -> Void = { event in
            guard !overflow.isCancelled else { return }
            if case .dropped = continuation.yield(event) { overflow.cancel() }
        }
        worker = Task.detached(priority: .userInitiated) {
            await withTaskGroup(of: Void.self) { group in
                let limit = max(2, min(4, ProcessInfo.processInfo.activeProcessorCount - 2))
                var iterator = scanners.makeIterator()
                func schedule() {
                    guard !Task.isCancelled, !overflow.isCancelled, let scanner = iterator.next() else { return }
                    group.addTask {
                        guard !Task.isCancelled, !overflow.isCancelled else { return }
                        emit(.started(scanner.info.id))
                        let throttle = ProgressThrottle()
                        let context = ScanContext(fdaGranted: fdaGranted,
                            includeExternalVolumes: includeExternal, minSizeBytes: minSize,
                            emit: { emit(.item($0)) },
                            progress: { if throttle.shouldPublish() { emit(.progress(scanner.info.id, $0)) } },
                            isCancelled: { Task.isCancelled || overflow.isCancelled })
                        await scanner.scan(context)
                        emit(.finishedCategory(scanner.info.id))
                    }
                }
                for _ in 0..<limit { schedule() }
                while await group.next() != nil {
                    if overflow.isCancelled { group.cancelAll() }
                    schedule()
                }
            }
            emit(.done)
            continuation.finish()
        }
        let worker = self.worker
        continuation.onTermination = { _ in worker.cancel() }
    }

    func stopAndWait() async {
        worker.cancel()
        await worker.value
    }
}
