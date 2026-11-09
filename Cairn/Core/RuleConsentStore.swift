import Foundation

/// The latest approved seal is kept outside UserDefaults. Replaying an old,
/// correctly signed preferences snapshot cannot restore a revoked approval.
final class RuleConsentStore: @unchecked Sendable {
    static let shared = RuleConsentStore(
        read: { try LicenseKeychain.read($0, as: String.self) },
        write: { try LicenseKeychain.write($0, value: $1) })
    private let lock = NSLock()
    private let read: (String) throws -> String?
    private let write: (String, String) throws -> Void
    private var blocked = Set<CleaningRule.Kind>()

    init(read: @escaping (String) throws -> String?, write: @escaping (String, String) throws -> Void) {
        self.read = read
        self.write = write
    }
    private func account(_ kind: CleaningRule.Kind) -> String { "cleaning-rule-head-v2-" + kind.rawValue }

    func matches(_ rule: CleaningRule) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !blocked.contains(rule.kind), let seal = rule.consentSeal else { return false }
        do { return try read(account(rule.kind)) == seal }
        catch { return false }
    }

    /// Write and read back before any ordinary preferences are updated.
    /// A failed write is never acknowledged as durable revocation or consent.
    func install(_ rule: CleaningRule) -> Bool {
        guard let seal = rule.consentSeal else {
            lock.lock(); blocked.insert(rule.kind); lock.unlock()
            return false
        }
        return replace(rule.kind, with: seal)
    }
    func revoke(_ kind: CleaningRule.Kind) -> Bool {
        replace(kind, with: "revoked-" + UUID().uuidString)
    }
    private func replace(_ kind: CleaningRule.Kind, with value: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        blocked.insert(kind)
        do {
            try write(account(kind), value)
            guard try read(account(kind)) == value else { return false }
            blocked.remove(kind)
            return true
        } catch { return false }
    }
}
