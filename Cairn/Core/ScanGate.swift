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
/// Nothing here leaked — each scan freed its memory when it finished. The
/// failure was purely concurrency, so the fix is a ceiling rather than a cure:
/// one heavy scan at a time, the rest queue in arrival order. Peak memory is now
/// bounded by the single largest scan instead of the sum of all of them.
///
/// Deliberately a lock-backed class, not an actor: `release()` has to be callable
/// from a synchronous `defer`, so a scan releases the gate on every exit path
/// including cancellation and thrown errors.
final class ScanGate: @unchecked Sendable {
    static let shared = ScanGate()

    private let lock = NSLock()
    private var busy = false
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }
    private var waiters: [Waiter] = []
    // A cancellation may arrive before withCheckedContinuation registers its
    // waiter. Track that narrow interval so no cancelled request is stranded.
    private var starting = Set<UUID>()
    private var cancelledWhileStarting = Set<UUID>()

    /// Returns true only when this caller owns the gate. Pair a true result with
    /// `release()` in defer; a false result has no lease and must return at once.
    func acquire() async -> Bool {
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
                    busy = true
                    lock.unlock()
                    continuation.resume(returning: true)
                } else {
                    // Register before unlocking so release cannot miss us.
                    waiters.append(Waiter(id: id, continuation: continuation))
                    lock.unlock()
                }
            }
        } onCancel: {
            lock.lock()
            if starting.contains(id) {
                cancelledWhileStarting.insert(id)
                lock.unlock()
            } else if let index = waiters.firstIndex(where: { $0.id == id }) {
                let waiter = waiters.remove(at: index)
                lock.unlock()
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

    /// Hands the gate to the next waiter, or marks it free.
    func release() {
        lock.lock()
        if waiters.isEmpty {
            busy = false
            lock.unlock()
        } else {
            let next = waiters.removeFirst()
            lock.unlock()
            next.continuation.resume(returning: true)
        }
    }
}
