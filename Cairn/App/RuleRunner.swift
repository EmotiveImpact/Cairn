import Foundation

/// Runs approved cleaning rules while Cairn is open. It checks every half
/// hour, waits while the person is scanning or cleaning, measures fresh,
/// and cleans through `ScanStore.clean`, so each run is journalled and
/// leaves a receipt in Activity like any other clean.
@MainActor @Observable final class RuleRunner {
    static let shared = RuleRunner()
    private(set) var rules: [CleaningRule] = CleaningRules.load()
    private(set) var running: CleaningRule.Kind?
    @ObservationIgnored private weak var store: ScanStore?
    @ObservationIgnored private var proEnabled: () -> Bool = { false }
    @ObservationIgnored private var loop: Task<Void, Never>?

    func attach(store: ScanStore, proEnabled: @escaping () -> Bool) {
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

    func update(_ rule: CleaningRule) {
        var next = rule
        if next.approved && next.approvedAt == nil { next.approvedAt = Date() }
        if !next.approved { next.approvedAt = nil }
        rules = rules.map { $0.kind == next.kind ? next : $0 }
        CleaningRules.save(rules)
    }

    /// What the rule would clear now. Measures, changes nothing.
    func preview(_ rule: CleaningRule) async -> [ScanItem]? {
        guard await ScanGate.shared.acquire(.scan) else { return nil }
        defer { ScanGate.shared.release() }
        let found = await AgentBridge.gather(category: rule.kind.category)
        return rule.select(found)
    }

    func runDue(now: Date = Date()) async {
        for rule in rules where rule.isDue(now: now) {
            guard let store, !store.isScanning, !store.isCleaning, !store.isRestoring else { return }
            await run(rule.kind)
        }
    }

    /// Runs one approved rule now.
    func run(_ kind: CleaningRule.Kind) async {
        guard running == nil, let store, var rule = rules.first(where: { $0.kind == kind }), rule.active else { return }
        running = kind
        defer { running = nil }
        guard let items = await preview(rule) else { return }
        // Recheck: the person may have paused the rule while it measured.
        guard rules.first(where: { $0.kind == kind })?.active == true else { return }
        rule.lastRun = Date()
        if items.isEmpty {
            rule.lastRunBytes = 0
            rule.lastRunItems = 0
            rule.lastResult = "Nothing to clear"
        } else {
            let summary = await store.clean(items, proEnabled: proEnabled(), runKind: "Rule · " + kind.title)
            rule.lastRunBytes = summary.accounting.freedBytes
            rule.lastRunItems = summary.accounting.completedCount
            let trashed = max(0, summary.accounting.trashBytes - summary.accounting.freedBytes)
            var parts = ["Cleared \(Fmt.size(summary.accounting.freedBytes))"]
            if trashed > 0 { parts.append("\(Fmt.size(trashed)) moved to the Trash") }
            if summary.failed > 0 { parts.append("\(summary.failed) skipped") }
            rule.lastResult = parts.joined(separator: " · ")
        }
        // Keep any change the person made to the rule while it ran.
        if let current = rules.first(where: { $0.kind == kind }) {
            var merged = current
            merged.lastRun = rule.lastRun
            merged.lastRunBytes = rule.lastRunBytes
            merged.lastRunItems = rule.lastRunItems
            merged.lastResult = rule.lastResult
            rules = rules.map { $0.kind == kind ? merged : $0 }
            CleaningRules.save(rules)
        }
    }
}
