import Foundation

/// Serializes heavy scans across the whole app.
///
/// Every page owns its store at the `AppShell` level so results survive
/// navigation — which also means navigating away never cancels that page's scan.
/// Walking the sidebar therefore used to start the duplicate scan, the app
/// inventory, the health check and a Smart Scan all at once, each walking the
/// filesystem and buffering its own results. Measured peak RSS while navigating
/// was 2.8 GB, and alongside a real Smart Scan it climbed into the double-digit
/// gigabytes until macOS reported "your system has run out of application
/// memory".
///
/// This gate bounds concurrency. Separate hash/copy buffer-lifetime fixes are
/// required too; see artifacts/duplicate-memory/ROOT-CAUSE.md.
///
/// Deliberately a lock-backed class, not an actor: `release()` has to be callable
/// from a synchronous `defer`, so a scan releases the gate on every exit path
/// including cancellation and thrown errors.
final class ScanGate: @unchecked Sendable {
    static let shared = ScanGate()
    static let changed = Notification.Name("Cairn.heavyOperationChanged")
    enum Operation: String, Sendable {
        case scan = "Scanning files"
        case duplicates = "Comparing duplicates"
        case apps = "Measuring applications"
        case health = "Checking health"
        case locations = "Measuring known locations"
        case cleanup = "Cleaning reviewed items"
        case removeDuplicates = "Removing reviewed duplicates"
        case removeApps = "Removing reviewed applications"
        case fixHealth = "Applying reviewed health changes"
        case restore = "Restoring a recorded item"
        case copy = "Copying to external storage"
        case verify = "Verifying external copy"
    }
    struct Snapshot: Sendable { let operation: Operation?; let queued: Int }
    private var activeOperation: Operation?
    var snapshot: Snapshot { lock.withLock { Snapshot(operation: activeOperation, queued: waiters.count) } }
    private func announce() {
        guard self === Self.shared else { return }
        DispatchQueue.main.async { NotificationCenter.default.post(name: Self.changed, object: nil) }
    }

    private let lock = NSLock()
    private var busy = false
    private struct Waiter {
        let id: UUID
        let operation: Operation
        let continuation: CheckedContinuation<Bool, Never>
    }
    private var waiters: [Waiter] = []
    // A cancellation may arrive before withCheckedContinuation registers its
    // waiter. Track that narrow interval so no cancelled request is stranded.
    private var starting = Set<UUID>()
    private var cancelledWhileStarting = Set<UUID>()

    /// Returns true only when this caller owns the gate. Pair a true result with
    /// `release()` in defer; a false result has no lease and must return at once.
    func acquire(_ operation: Operation = .scan) async -> Bool {
        let id = UUID()
        begin(id)

        let granted = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                starting.remove(id)
                if cancelledWhileStarting.remove(id) != nil || Task.isCancelled {
                    lock.unlock()
                    continuation.resume(returning: false)
                } else if !busy {
                    busy = true; activeOperation = operation
                    lock.unlock(); announce()
                    continuation.resume(returning: true)
                } else {
                    // Register before unlocking so release cannot miss us.
                    waiters.append(Waiter(id: id, operation: operation, continuation: continuation))
                    lock.unlock(); announce()
                }
            }
        } onCancel: {
            lock.lock()
            if starting.contains(id) {
                cancelledWhileStarting.insert(id)
                lock.unlock()
            } else if let index = waiters.firstIndex(where: { $0.id == id }) {
                let waiter = waiters.remove(at: index)
                lock.unlock(); announce()
                waiter.continuation.resume(returning: false)
            } else {
                // Already granted or rejected; acquire() resolves the race.
                lock.unlock()
            }
        }
        // Cancellation can race a release after the waiter has been popped.
        // Hand the lease onward here instead of starting cancelled disk work.
        if granted && Task.isCancelled { release(); return false }
        return granted
    }

    private func begin(_ id: UUID) {
        lock.lock()
        starting.insert(id)
        lock.unlock()
    }

    /// Background observers never queue ahead of user work. They retry on a
    /// later tick when the current worker and all queued requests have settled.
    func tryAcquireForMonitoring() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !busy, waiters.isEmpty, starting.isEmpty else { return false }
        busy = true; activeOperation = .locations
        announce()
        return true
    }

    /// Hands the gate to the next waiter, or marks it free.
    func release() {
        lock.lock()
        if waiters.isEmpty {
            busy = false; activeOperation = nil
            lock.unlock(); announce()
        } else {
            let next = waiters.removeFirst()
            activeOperation = next.operation
            lock.unlock(); announce()
            next.continuation.resume(returning: true)
        }
    }
}
