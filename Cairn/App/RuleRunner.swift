import Foundation

/// Runs approved cleaning rules while Cairn is open. It checks every half
/// hour, waits while the person is scanning or cleaning, measures fresh,
/// and cleans through `ScanStore.clean`, so each run is journalled and
/// leaves a receipt in Activity like any other clean.
@MainActor @Observable final class RuleRunner {
    static let shared = RuleRunner()
    private(set) var rules: [CleaningRule] = RuleRunner.previewMode ? RuleRunner.sample : CleaningRule.Kind.allCases.map { CleaningRule(kind: $0) }
    private static let previewMode = CommandLine.arguments.contains("--preview-ui")
    private(set) var pendingStateChanges = 0
    var isUpdating: Bool { pendingStateChanges > 0 }
    var quitState: RuleQuitState {
        .evaluate(pending: pendingStateChanges, failed: unsavedRevocations.count)
    }
    private(set) var consentError: String?
    private(set) var consentErrorKind: CleaningRule.Kind?
    private(set) var running: CleaningRule.Kind?
    @ObservationIgnored private weak var store: ScanStore?
    @ObservationIgnored private var proEnabled: () -> Bool = { false }
    @ObservationIgnored private var unsavedRevocations = Set<CleaningRule.Kind>()
    @ObservationIgnored private var activeRun: CleaningRuleRun?
    @ObservationIgnored private let updateState: @Sendable (CleaningRule) -> RuleStateWorker.Result
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var outcomeRevisions: [CleaningRule.Kind: Int] = [:]
    @ObservationIgnored private var loop: Task<Void, Never>?

    func attach(store: ScanStore, proEnabled: @escaping () -> Bool) {
        guard !Self.previewMode else { return }
        self.store = store
        self.proEnabled = proEnabled
        guard loop == nil else { return }
        loop = Task { [weak self] in
            // Give launch a quiet minute before the first check.
            try? await Task.sleep(for: .seconds(60))
            while !Task.isCancelled {
                await self?.runDue()
                try? await Task.sleep(for: .seconds(30 * 60))
            }
        }
    }

    init(loadState: @escaping @Sendable () -> [CleaningRule] = { CleaningRules.load() },
         updateState: @escaping @Sendable (CleaningRule) -> RuleStateWorker.Result = { RuleStateWorker.update($0) },
         activeRun: CleaningRuleRun? = nil) {
        self.updateState = updateState
        self.activeRun = activeRun
        self.running = activeRun?.rule.kind
        guard !Self.previewMode else { return }
        enqueue { RuleStateWorker.Result(rules: loadState()) }
    }

    func update(_ rule: CleaningRule) {
        guard !Self.previewMode else { return }
        // This lock only protects a Boolean. Never read Keychain before stopping
        // the active run, even if an earlier state operation is still stalled.
        if running == rule.kind { activeRun?.cancel() }
        var display = rule
        if !rule.approved || rules.first(where: { $0.kind == rule.kind })?.scope != rule.scope {
            display.approved = false; display.consentID = nil; display.consentSeal = nil
        }
        rules = rules.map { $0.kind == rule.kind ? display : $0 }
        let update = updateState
        enqueue { update(rule) }
    }

    func approve(_ rule: CleaningRule) {
        guard !Self.previewMode, !isUpdating else { return }
        if running == rule.kind { activeRun?.cancel() }
        enqueue { RuleStateWorker.approve(rule) }
    }

    private func enqueue(_ work: @escaping @Sendable () -> RuleStateWorker.Result) {
        revision += 1
        let requested = revision
        pendingStateChanges += 1
        RuleStateWorker.submit(work) { [weak self] result in
            guard let self else { return }
            self.pendingStateChanges -= 1
            self.apply(result, revision: requested)
        }
    }

    private func apply(_ result: RuleStateWorker.Result, revision requested: Int) {
        if let kind = result.kind, let saved = result.saved,
           requested >= (outcomeRevisions[kind] ?? 0) {
            outcomeRevisions[kind] = requested
            recordConsentPersistence(kind, saved: saved)
        }
        // A queued refresh/receipt cannot replace a newer optimistic pause/off
        // or scope edit. Only the latest requested transaction owns the view.
        guard requested == revision else { return }
        rules = result.rules
        if let error = result.error, consentErrorKind == nil { consentError = error }
    }

    private func recordConsentPersistence(_ kind: CleaningRule.Kind, saved: Bool) {
        if saved { unsavedRevocations.remove(kind) } else { unsavedRevocations.insert(kind) }
        consentErrorKind = CleaningRule.Kind.allCases.first { unsavedRevocations.contains($0) }
        consentError = consentErrorKind == nil ? nil
            : "Cairn stopped the affected rules, but could not save their protected approval state. Keep Cairn open, unlock your login Keychain, then retry saving them off before restarting."
    }

    func retrySavingOff() {
        guard let kind = consentErrorKind, var rule = rules.first(where: { $0.kind == kind }) else { return }
        rule.approved = false
        update(rule)
    }

    /// `--preview-ui`: two approved rules with receipts. Never saved, never run.
    private static var sample: [CleaningRule] {
        CleaningRule.Kind.allCases.map { kind in
            var rule = CleaningRule(kind: kind)
            switch kind {
            case .xcodeBuild:
                rule.approved = true
                rule.approvedAt = Date().addingTimeInterval(-30 * 86_400)
                rule.lastRun = Date().addingTimeInterval(-2 * 86_400)
                rule.lastRunBytes = 6_200_000_000
                rule.lastRunItems = 4
                rule.lastResult = "Cleared 6.2 GB"
            case .packageCaches:
                rule.approved = true
                rule.schedule = .daily
                rule.capGB = 10
                rule.approvedAt = Date().addingTimeInterval(-12 * 86_400)
                rule.lastRun = Date().addingTimeInterval(-5 * 3_600)
                rule.lastRunBytes = 1_400_000_000
                rule.lastRunItems = 3
                rule.lastResult = "Cleared 1.4 GB"
            default: break
            }
            return rule
        }
    }

    /// What the rule would clear now. Measures, changes nothing.
    func preview(_ rule: CleaningRule) async -> [ScanItem]? {
        guard !Self.previewMode else { return [] }
        guard await ScanGate.shared.acquire(.scan) else { return nil }
        defer { ScanGate.shared.release() }
        let found = await AgentBridge.gather(category: rule.kind.category)
        return rule.select(found)
    }

    func runDue(now: Date = Date()) async {
        guard !isUpdating else { return }
        for rule in rules where rule.isDue(now: now) {
            guard let store, !store.isScanning, !store.isCleaning, !store.isRestoring else { return }
            await run(rule.kind)
        }
    }

    /// Runs one approved rule now.
    func run(_ kind: CleaningRule.Kind) async {
        guard !Self.previewMode, !isUpdating, running == nil, let store else { return }
        let startingRevision = revision
        running = kind
        defer { running = nil; activeRun = nil }
        let loaded = await RuleStateWorker.run { CleaningRules.load().first { $0.kind == kind } }
        guard startingRevision == revision, !isUpdating, !Task.isCancelled,
              var rule = loaded, rule.active else { return }
        let authorization = CleaningRuleRun(rule)
        activeRun = authorization
        await withTaskCancellationHandler {
            guard let items = await preview(rule) else { return }
            // Recheck: the person may have paused the rule while it measured.
            guard await authorization.authorized(), !Task.isCancelled else { return }
            rule.lastRun = Date()
            if items.isEmpty {
                rule.lastRunBytes = 0
                rule.lastRunItems = 0
                rule.lastResult = "Nothing to clear"
            } else {
                let summary = await store.clean(items, proEnabled: proEnabled(), removal: .trash, runKind: "Rule · " + kind.title, ruleRun: authorization)
                rule.lastRunBytes = summary.freedBytes
                rule.lastRunItems = summary.accounting.completedCount
                let trashed = summary.accounting.movedToTrashBytes
                let count = summary.accounting.completedCount
                var parts = ["Cleared \(count) \(count == 1 ? "item" : "items")"]
                if summary.freedBytes > 0 { parts.append("\(Fmt.size(summary.freedBytes)) freed") }
                if trashed > 0 { parts.append("\(Fmt.size(trashed)) moved to the Trash") }
                if summary.failed > 0 { parts.append("\(summary.failed) skipped") }
                if summary.interrupted { parts.append("Stopped before remaining items") }
                rule.lastResult = parts.joined(separator: " · ")
            }
            // The queued transaction re-reads current authority after any
            // pause/off already submitted while this run was working.
            let receipt = rule
            enqueue { RuleStateWorker.receipt(receipt) }
        } onCancel: {
            authorization.cancel()
        }
    }
}
