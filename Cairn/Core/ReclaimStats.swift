import Foundation

/// Legacy activity estimates retained without resetting the user's history.
/// These values include files moved to Trash and tool input sizes; they are
/// never measured free capacity. Restore subtracts the recorded file estimate.
@MainActor
final class ReclaimStats: ObservableObject {
    static let shared = ReclaimStats()

    private static let lifetimeKey = "cairn.lifetimeReclaimedBytes"

    /// Estimated affected file sizes, including legacy records. Not space freed.
    @Published private(set) var lifetimeAffectedBytes: Int64
    /// What the most recent scan found; this is not available disk capacity.
    @Published var reclaimableBytes: Int64 = 0

    private init() {
        // `integer(forKey:)` is Int, which is 64-bit on every Mac Cairn runs on.
        lifetimeAffectedBytes = Int64(UserDefaults.standard.integer(forKey: Self.lifetimeKey))
    }

    /// Called when a clean succeeds.
    func recordClean(bytes: Int64) {
        guard bytes > 0 else { return }
        lifetimeAffectedBytes += bytes
        persist()
    }

    /// Called when the user puts files back, so the total stays honest.
    func recordRestore(bytes: Int64) {
        guard bytes > 0 else { return }
        lifetimeAffectedBytes = max(0, lifetimeAffectedBytes - bytes)
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(Int(lifetimeAffectedBytes), forKey: Self.lifetimeKey)
    }
}
