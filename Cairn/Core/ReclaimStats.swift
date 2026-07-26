import Foundation

/// Two numbers that live longer than a single scan:
///
/// - `lifetimeBytes` — everything Cairn has ever reclaimed on this Mac. This is
///   the number that re-earns a one-time purchase every time the app is opened;
///   a cleaner with no running total asks the user to take its value on faith.
/// - `reclaimableBytes` — what the last scan found, published so the menu bar can
///   show it without the whole scan engine being reachable from the App scene.
///
/// Local only, stored in UserDefaults. Undo subtracts again, so the total always
/// reflects space the user actually kept.
@MainActor
final class ReclaimStats: ObservableObject {
    static let shared = ReclaimStats()

    private static let lifetimeKey = "cairn.lifetimeReclaimedBytes"

    /// Everything ever reclaimed on this Mac.
    @Published private(set) var lifetimeBytes: Int64
    /// What the most recent scan found — drives the menu bar readout.
    @Published var reclaimableBytes: Int64 = 0

    private init() {
        // `integer(forKey:)` is Int, which is 64-bit on every Mac Cairn runs on.
        lifetimeBytes = Int64(UserDefaults.standard.integer(forKey: Self.lifetimeKey))
    }

    /// Called when a clean succeeds.
    func recordClean(bytes: Int64) {
        guard bytes > 0 else { return }
        lifetimeBytes += bytes
        persist()
    }

    /// Called when the user puts files back, so the total stays honest.
    func recordRestore(bytes: Int64) {
        guard bytes > 0 else { return }
        lifetimeBytes = max(0, lifetimeBytes - bytes)
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(Int(lifetimeBytes), forKey: Self.lifetimeKey)
    }
}
