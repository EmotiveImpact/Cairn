import Foundation

/// One serial queue for rule-state transactions. Never hold up the main actor
/// waiting for Keychain I/O; executor reads remain fresh, never authority caches.
enum RuleStateWorker {
    private static let queue = DispatchQueue(label: "dev.cairn.rule-state", qos: .utility)

    static func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    static func submit<T: Sendable>(_ work: @escaping @Sendable () -> T,
                                    completion: @escaping @MainActor @Sendable (T) -> Void) {
        queue.async {
            let result = work()
            Task { @MainActor in completion(result) }
        }
    }

    struct Result: Sendable {
        var rules: [CleaningRule]
        var kind: CleaningRule.Kind?
        var saved: Bool?
        var error: String?
    }

    static func update(_ rule: CleaningRule) -> Result {
        let base = CleaningRules.load()
        guard let current = base.first(where: { $0.kind == rule.kind }) else { return Result(rules: base) }
        let fresh = rule.consentSeal == current.consentSeal && rule.consentID == current.consentID
        guard !rule.approved || fresh else {
            return Result(rules: base, error: "This rule changed. Review its current settings again.")
        }
        var next = current
        if fresh {
            next.schedule = rule.schedule; next.minAgeDays = rule.minAgeDays; next.capGB = rule.capGB
        }
        let saved: Bool
        if current.scope != next.scope || !rule.approved || !current.verified {
            next.approved = false; next.approvedAt = nil; next.consentID = nil; next.consentSeal = nil
            saved = RuleConsentStore.shared.revoke(next.kind)
        } else {
            next.paused = rule.paused
            next.consentID = UUID().uuidString
            next.consentSeal = SettingsSeal.seal(next.consentValue, for: CleaningRules.key)
            saved = RuleConsentStore.shared.install(next)
        }
        return persist(next, base: base, saved: saved)
    }

    static func approve(_ rule: CleaningRule) -> Result {
        let base = CleaningRules.load()
        guard let current = base.first(where: { $0.kind == rule.kind }), current.scope == rule.scope,
              current.consentSeal == rule.consentSeal, current.consentID == rule.consentID,
              rule.validScope else {
            return Result(rules: base, error: "This rule changed. Measure its current settings again.")
        }
        var next = current
        next.approved = true; next.paused = false; next.approvedAt = Date()
        next.consentID = UUID().uuidString
        next.consentSeal = SettingsSeal.seal(next.consentValue, for: CleaningRules.key)
        return persist(next, base: base, saved: RuleConsentStore.shared.install(next))
    }

    static func receipt(_ rule: CleaningRule) -> Result {
        let base = CleaningRules.load()
        guard let current = base.first(where: { $0.kind == rule.kind }) else { return Result(rules: base) }
        var merged = current
        merged.lastRun = rule.lastRun; merged.lastRunBytes = rule.lastRunBytes
        merged.lastRunItems = rule.lastRunItems; merged.lastResult = rule.lastResult
        if current.verified {
            merged.consentSeal = SettingsSeal.seal(merged.consentValue, for: CleaningRules.key)
            return persist(merged, base: base, saved: RuleConsentStore.shared.install(merged))
        }
        let rules = base.map { $0.kind == merged.kind ? merged : $0 }
        CleaningRules.save(rules)
        return Result(rules: rules)
    }

    private static func persist(_ rule: CleaningRule, base: [CleaningRule], saved: Bool) -> Result {
        var next = rule
        if !saved { next.approved = false; next.consentSeal = nil }
        let rules = base.map { $0.kind == next.kind ? next : $0 }
        CleaningRules.save(rules)
        return Result(rules: rules, kind: next.kind, saved: saved)
    }
}

/// In-memory quit policy. Checking this must never wait for protected storage.
enum RuleQuitState: Equatable {
    case ready, saving, unsaved

    static func evaluate(pending: Int, failed: Int) -> RuleQuitState {
        if pending > 0 { return .saving }
        return failed > 0 ? .unsaved : .ready
    }

    func permitsTermination(operationBusy: Bool, acceptingUnsavedRisk: Bool = false) -> Bool {
        !operationBusy && (self == .ready || acceptingUnsavedRisk)
    }
}
