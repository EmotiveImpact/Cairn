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
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Suspends until this caller owns the gate. Always pair with `release()`.
    func acquire() async {
        lock.lock()
        if !busy {
            busy = true
            lock.unlock()
            return
        }
        // Enqueue BEFORE unlocking, so a release racing us can't be missed.
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            lock.unlock()
        }
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
            next.resume()
        }
    }
}
