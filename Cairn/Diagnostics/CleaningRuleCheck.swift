import Foundation

/// Disposable preferences/files, no production settings or Keychain writes.
enum CleaningRuleCheck {
    static func run(check: (Bool, String) -> Void) {
        let suite = "cairn-rule-check-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            check(false, "Rule fixture preferences available"); return
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        checkProtectedHeads(defaults: defaults, check: check)
        check(!RuleQuitState.saving.permitsTermination(operationBusy: false), "Pending rule persistence blocks ordinary quit")
        check(!RuleQuitState.unsaved.permitsTermination(operationBusy: false), "Failed revocation blocks ordinary quit")
        check(RuleQuitState.unsaved.permitsTermination(operationBusy: false, acceptingUnsavedRisk: true),
              "Explicit unsaved-rule risk decision permits quitting")
        check(!RuleQuitState.unsaved.permitsTermination(operationBusy: true, acceptingUnsavedRisk: true),
              "Unsaved-rule risk acceptance cannot bypass active file-operation protection")
        var approved = CleaningRule(kind: .xcodeBuild)
        approved.approved = true
        approved.consentID = UUID().uuidString
        approved.consentSeal = "fixture-seal"
        let payload = approved.consentValue
        // Inject only cryptographic verification: exercise the real persistence,
        // scope, version, paused/off, and run-snapshot policy without a Keychain.
        let verify: (String, String, String?) -> Bool = { value, key, seal in
            value == payload && key == CleaningRules.key && seal == "fixture-seal"
        }
        func loaded(_ rule: CleaningRule) -> CleaningRule {
            CleaningRules.save([rule], defaults)
            return CleaningRules.load(defaults, verify: verify).first { $0.kind == rule.kind }!
        }
        check(loaded(approved).approved, "Exact sealed rule survives persistence")
        let run = CleaningRuleRun(approved)
        check(run.isAuthorized(current: approved, verify: verify), "Exact approval authorizes its run snapshot")
        var variants: [(String, CleaningRule)] = []
        var changed = approved; changed.consentSeal = nil; variants.append(("legacy unsealed approval", changed))
        changed = approved; changed.consentSeal = "forged"; variants.append(("forged seal", changed))
        changed = approved; changed.capGB += 1; variants.append(("changed cap during preview", changed))
        changed = approved; changed.minAgeDays = 0; variants.append(("changed age during preview", changed))
        changed = approved; changed.kind = .logs; variants.append(("changed category", changed))
        changed = approved; changed.schedule = .daily; variants.append(("changed schedule", changed))
        changed = approved; changed.paused = true; variants.append(("paused run", changed))
        changed = approved; changed.approved = false; variants.append(("switched-off run", changed))
        changed = approved; changed.consentID = UUID().uuidString; variants.append(("replaced approval", changed))
        changed = approved; changed.lastRun = Date(); variants.append(("tampered scheduling receipt", changed))
        for (label, rule) in variants {
            check(!loaded(rule).approved && !run.isAuthorized(current: rule, verify: verify), "Rule rejects \(label)")
        }
        CleaningRules.save([approved, approved], defaults)
        check(!CleaningRules.load(defaults, verify: verify).contains(where: \.approved), "Duplicate persisted rule fails closed")
        let exact: (String, String, String?) -> Bool = { value, _, seal in seal == value }
        var original = approved
        original.consentSeal = original.consentValue
        let inPreview = CleaningRuleRun(original)
        for changeCap in [true, false] {
            var newer = original
            if changeCap { newer.capGB += 1 } else { newer.minAgeDays += 1 }
            newer.consentID = UUID().uuidString
            newer.consentSeal = newer.consentValue
            check(newer.isVerified(using: exact) && !inPreview.isAuthorized(current: newer, verify: exact),
                  "Fresh valid approval cannot authorize old preview items")
        }
        var paused = original
        paused.paused = true
        paused.consentSeal = paused.consentValue
        check(paused.isVerified(using: exact) && !inPreview.isAuthorized(current: paused, verify: exact),
              "Valid paused approval still stops execution")
        var receipt = original
        receipt.lastRun = Date()
        receipt.consentSeal = receipt.consentValue
        CleaningRules.save([receipt], defaults)
        check(CleaningRules.load(defaults, verify: exact).first(where: { $0.kind == receipt.kind })?.approved == true,
              "Sealed scheduling timestamp survives date serialization")
        run.cancel()
        check(!run.isAuthorized(current: approved, verify: verify), "Cancellation stays revoked even if original approval is restored")
        for cap in [Int.min, -1, 0, 201, Int.max] {
            changed = approved; changed.capGB = cap
            check(changed.capBytes == 0 && changed.select([]).isEmpty, "Invalid cap \(cap) fails closed without overflow")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cairn-rule-files-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let source = root.appendingPathComponent("cache")
            try Data([1, 2, 3]).write(to: source)
            let item = ScanItem(url: source, allocatedSize: 3, categoryID: "xcode", severity: .safe)
            let cancelled = Cleaner.clean(item, allowedRoots: [root], proEnabled: true, mutationAllowed: { false },
                                         moveToTrash: { _ in throw CocoaError(.featureUnsupported) })
            check(!cancelled.ok && FileManager.default.fileExists(atPath: source.path), "Revoked rule reaches no mutation")
            // Revoke after initial admission: the final check after contents and
            // identity validation must prevent even calling the move adapter.
            let probe = RevocationProbe()
            let stopped = Cleaner.clean(item, allowedRoots: [root], proEnabled: true,
                                        mutationAllowed: { probe.admitFirstCheckOnly() },
                                        moveToTrash: { _ in probe.markMoved(); throw CocoaError(.featureUnsupported) })
            check(!stopped.ok && probe.checks >= 2 && !probe.moved && FileManager.default.fileExists(atPath: source.path),
                  "Pause/off during executor validation prevents the move")
        } catch { check(false, "Rule disposable fixture: \(error)") }
    }

    private static func checkProtectedHeads(defaults: UserDefaults, check: (Bool, String) -> Void) {
        var heads: [String: String] = [:]
        var failRead = false, failWrite = false, dropWrite = false
        func reopen() -> RuleConsentStore {
            RuleConsentStore(read: { key in
                if failRead { throw CocoaError(.fileReadNoPermission) }
                return heads[key]
            }, write: { key, value in
                if failWrite { throw CocoaError(.fileWriteNoPermission) }
                if !dropWrite { heads[key] = value }
            })
        }
        var rule = CleaningRule(kind: .logs)
        rule.approved = true; rule.consentID = "first"; rule.consentSeal = "signed-first"
        let store = reopen()
        check(!store.matches(rule), "Missing protected head rejects an otherwise signed rule")
        check(store.install(rule) && reopen().matches(rule), "Latest protected approval survives simulated restart")
        let snapshot = rule
        CleaningRules.save([snapshot], defaults)
        let oldPreferences = defaults.data(forKey: CleaningRules.key)
        check(store.revoke(rule.kind) && !reopen().matches(snapshot), "Off tombstone prevents whole-preferences replay after restart")
        defaults.set(oldPreferences, forKey: CleaningRules.key)
        let afterRestart = reopen()
        let replayed = CleaningRules.load(defaults, verify: { value, _, seal in
            value == snapshot.consentValue && seal == snapshot.consentSeal && afterRestart.matches(snapshot)
        })
        check(!replayed.contains(where: \.approved), "Restored complete preferences blob stays off with protected tombstone")
        rule.consentID = "second"; rule.consentSeal = "signed-second"
        check(store.install(rule) && !reopen().matches(snapshot), "Reapproval rejects an older signed preferences snapshot")
        let beforePause = rule
        rule.paused = true; rule.consentSeal = "signed-paused"
        check(store.install(rule) && !reopen().matches(beforePause), "Pause invalidates the older active snapshot across restart")
        let beforeReceipt = rule
        rule.lastRun = Date(); rule.consentSeal = "signed-receipt"
        check(store.install(rule) && !reopen().matches(beforeReceipt), "Protected receipt rejects replayed scheduling metadata")
        failRead = true
        check(!store.matches(rule), "Protected state read failure fails closed")
        failRead = false; failWrite = true
        check(!store.revoke(rule.kind) && !store.matches(rule), "Failed revocation is reported and latched off for this process")
        failWrite = false
        check(store.revoke(rule.kind) && !reopen().matches(rule), "Retried durable revocation blocks replay after restart")
        dropWrite = true
        check(!store.install(rule) && !store.matches(rule), "Read-back rejects a lost protected-state write")
        dropWrite = false
        check(store.install(rule), "Protected-state retry can recover")
        var unsigned = rule; unsigned.consentSeal = nil
        check(!store.install(unsigned) && !store.matches(rule), "Seal creation failure also latches execution off")
    }

    /// Called from the async lifecycle suite. Any fixture delays are bounded;
    /// no production preferences, Keychain access or real Trash adapters are used.
    @MainActor static func runCancellation(check: (Bool, String) -> Void) async {
        await checkSlowProtectedState(check: check)
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("cairn-rule-cancel-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            let source = root.appendingPathComponent("cache")
            try Data([1, 2, 3]).write(to: source)
            var draft = CleaningRule(kind: .xcodeBuild)
            draft.approved = true; draft.consentID = "fixture"; draft.consentSeal = "fixture"
            let rule = draft
            let ticket = CleaningRuleRun(rule, current: { rule }, verify: { _, _, seal in seal == "fixture" })
            let item = ScanItem(url: source, allocatedSize: 3, latestModified: Date(timeIntervalSinceNow: -40 * 86_400),
                                categoryID: "xcode", severity: .safe)
            let store = ScanStore(removalLogURL: root.appendingPathComponent("recovery.json"),
                                  recordRestoredBytes: { _ in }, fixtureScanners: [],
                                  lifecycleCheckpoint: { point in
                                      if point == "intent" { withUnsafeCurrentTask { $0?.cancel() } }
                                  })
            let task = Task { await store.clean([item], proEnabled: true, ruleRun: ticket) }
            let summary = await task.value
            check(!ticket.isAuthorized && summary.interrupted && summary.errors.contains(where: { $0.contains("revoked") })
                    && fm.fileExists(atPath: source.path), "Task cancellation after journal intent reaches no mutation")

            let duringValidation = CleaningRuleRun(rule, current: { rule }, verify: { _, _, seal in seal == "fixture" })
            let probe = RevocationProbe()
            let validation = Task.detached {
                await withTaskCancellationHandler {
                    Cleaner.clean(item, allowedRoots: [root], proEnabled: true, mutationAllowed: {
                        if probe.admitFirstCheckOnly() {
                            withUnsafeCurrentTask { $0?.cancel() }
                            return true // Already-admitted validation can finish, but not mutate.
                        }
                        return duringValidation.isAuthorized
                    }, moveToTrash: { _ in probe.markMoved(); throw CocoaError(.featureUnsupported) })
                } onCancel: { duringValidation.cancel() }
            }
            let result = await validation.value
            check(!result.ok && !duringValidation.isAuthorized && probe.checks >= 2 && !probe.moved
                    && fm.fileExists(atPath: source.path), "Task cancellation during validation revokes detached final mutation")
        } catch { check(false, "Rule cancellation fixture: \(error)") }
    }

    /// A bounded fake protected-store read holds its I/O lock for at most two
    /// seconds. The main actor must still create the runner and pause it before
    /// that read is released. No real Keychain or preferences writes occur.
    @MainActor private static func checkSlowProtectedState(check: (Bool, String) -> Void) async {
        let gate = DispatchSemaphore(value: 0)
        let (events, signal) = AsyncStream<Void>.makeStream()
        var draft = CleaningRule(kind: .logs)
        draft.approved = true; draft.consentID = "latency"; draft.consentSeal = "latency-seal"
        let rule = draft
        let protected = RuleConsentStore(read: { _ in
            signal.yield(())
            _ = gate.wait(timeout: .now() + 2)
            return rule.consentSeal
        }, write: { _, _ in })
        let ticket = CleaningRuleRun(rule, current: { rule }, verify: { _, _, _ in protected.matches(rule) })
        let validation = Task { await ticket.authorized() }
        // The fake read signals before waiting. Also bound the event wait in
        // case a regression prevents the queued validation from starting.
        let watchdog = Task.detached {
            try? await Task.sleep(for: .seconds(3))
            signal.finish()
            gate.signal()
        }
        var began = false
        for await _ in events { began = true; break }
        let clock = ContinuousClock()
        let start = clock.now
        let runner = RuleRunner(loadState: { [rule] }, updateState: { next in
            RuleStateWorker.Result(rules: [next], kind: next.kind, saved: true)
        }, activeRun: ticket)
        var paused = rule; paused.paused = true
        runner.update(paused)
        let elapsed = start.duration(to: clock.now)
        check(began && elapsed < .milliseconds(500) && !ticket.isAuthorized,
              "Runner init and Pause revoke immediately while protected I/O is stalled")
        check(runner.quitState == .saving && !runner.quitState.permitsTermination(operationBusy: false),
              "Pause followed by quit is guarded while protected-state saving is stalled")
        gate.signal(); signal.finish(); watchdog.cancel()
        await watchdog.value
        check(!(await validation.value), "Slow protected read cannot reauthorize a cancelled run")
        // Bounded callback drain also proves the older launch snapshot cannot
        // overwrite the later pause result when queued I/O catches up.
        for _ in 0..<200 where runner.isUpdating { try? await Task.sleep(for: .milliseconds(5)) }
        check(!runner.isUpdating && runner.rules.first?.paused == true,
              "Revision checks preserve pause after delayed launch-state loading")
        check(runner.quitState == .ready, "Successful protected save clears the pending quit guard")
        let failingRunner = RuleRunner(loadState: { [rule] }, updateState: { next in
            RuleStateWorker.Result(rules: [next], kind: next.kind, saved: false)
        })
        var off = rule; off.approved = false
        failingRunner.update(off)
        for _ in 0..<200 where failingRunner.isUpdating { try? await Task.sleep(for: .milliseconds(5)) }
        check(!failingRunner.isUpdating && failingRunner.quitState == .unsaved
                && !failingRunner.quitState.permitsTermination(operationBusy: false),
              "Failed off persistence keeps ordinary quit guarded after the queue drains")
    }

    private final class RevocationProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private var didMove = false
        var checks: Int { lock.lock(); defer { lock.unlock() }; return count }
        var moved: Bool { lock.lock(); defer { lock.unlock() }; return didMove }
        func admitFirstCheckOnly() -> Bool { lock.lock(); defer { lock.unlock() }; count += 1; return count == 1 }
        func markMoved() { lock.lock(); defer { lock.unlock() }; didMove = true }
    }
}
