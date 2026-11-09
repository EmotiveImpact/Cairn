import Foundation
import Darwin

/// Disposable files and injected service replies only. Never sends an XPC request.
@MainActor enum ModelSafetyCheck {
    static func run() async -> Int {
        var failures = 0
        func check(_ good: Bool, _ label: String) {
            print("\(good ? "PASS" : "FAIL") \(label)"); if !good { failures += 1 }
        }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("cairn-model-safety-\(UUID())").resolvingSymlinksInPath()
        defer { try? fm.removeItem(at: root) }
        do {
            let home = root.appendingPathComponent("home")
            let file = home.appendingPathComponent(".cache/whisper/model.pt")
            let trash = root.appendingPathComponent("trash")
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createDirectory(at: trash, withIntermediateDirectories: true)
            try Data("reviewed model".utf8).write(to: file)
            func model() -> LocalModel { LocalModel(url: file, name: "fixture", tool: "Whisper", bytes: 14, updated: nil, removal: .trash) }
            let reviewed = model()
            try fm.moveItem(at: file, to: root.appendingPathComponent("old-model"))
            try Data("replacement".utf8).write(to: file)
            check((try? LocalModels.reviewedItem(reviewed, home: home)) == nil,
                  "Local model replacement is rejected before mutation")
            let current = model()
            let item = try LocalModels.reviewedItem(current, home: home)
            let nilOutcome = Cleaner.clean(item, allowedRoots: [home], proEnabled: false, moveToTrash: { _ in nil })
            check(!nilOutcome.ok && fm.fileExists(atPath: file.path), "Missing Trash outcome cannot report success")
            let scanner = ModelFixtureScanner(root: home)
            let log = root.appendingPathComponent("recovery.json")
            let store = ScanStore(removalLogURL: log, restoreFile: { from, to in
                renamex_np(from.path, to.path, UInt32(RENAME_EXCL)) == 0
            }, recordRestoredBytes: { _ in }, fixtureScanners: [scanner], cleanFile: { item, roots, pro, reviewed in
                Cleaner.clean(item, allowedRoots: roots, proEnabled: pro, reviewedSource: reviewed, moveToTrash: { from in
                    let to = trash.appendingPathComponent(from.lastPathComponent)
                    try FileManager.default.moveItem(at: from, to: to)
                    return to
                })
            })
            let result = await store.trashLocalModel(current, home: home)
            check(result.recoverableCount == 1 && !result.interrupted && result.freedBytes == 0,
                  "Model Trash has durable recovery and zero immediate reclaim")
            if let entry = store.removalLog.first {
                let restored = await store.restoreFromLog(entry)
                check(restored && fm.fileExists(atPath: file.path), "Model Put Back restores the recorded disposable file")
            } else { check(false, "Model Put Back entry exists") }
            let stale = try LocalModels.reviewedItem(model(), home: home)
            try fm.moveItem(at: file, to: root.appendingPathComponent("second-old-model"))
            try Data("second replacement".utf8).write(to: file)
            let staleResult = await store.clean([stale], proEnabled: false, removal: .trash)
            check(staleResult.failed == 1 && fm.fileExists(atPath: file.path),
                  "Shared executor rejects model replaced after item review")
            let badJournal = root.appendingPathComponent("bad-actions.json")
            try Data("invalid journal".utf8).write(to: badJournal)
            let blocked = ScanStore(removalLogURL: root.appendingPathComponent("blocked.json"),
                                    actionJournal: ActionJournal(url: badJournal), fixtureScanners: [scanner])
            let refused = await blocked.trashLocalModel(model(), home: home)
            check(refused.trashed == 0 && !refused.errors.isEmpty && fm.fileExists(atPath: file.path),
                  "Model journal failure refuses mutation")
        } catch { check(false, "Model fixture failed: \(error)") }

        if let set = AppleIntelligence.sets.first {
            let state = ModelServiceFixture()
            let refused = await AppleIntelligence.AssetService.remove([set.id], consent: { _ in false },
                type: { _ in set.assetType }, request: { _ in state.record(); return .done })
            check(state.count == 0 && !refused.isEmpty, "Asset removal refuses absent consent without a service request")
            _ = await AppleIntelligence.AssetService.remove([set.id], consent: { _ in state.allowed },
                type: { _ in set.assetType }, request: { _ in state.record(); return .locked },
                pause: { _ in state.revoke() })
            check(state.count == 1, "Revoked asset consent prevents retry after a locked reply")
            let cancellation = ModelServiceFixture()
            let task = Task {
                await AppleIntelligence.AssetService.remove([set.id], consent: { _ in true },
                    type: { _ in set.assetType }, request: { _ in cancellation.record(); return .locked },
                    pause: { _ in try await Task.sleep(for: .seconds(60)) })
            }
            let startDeadline = Date().addingTimeInterval(3)
            while cancellation.count == 0 && Date() < startDeadline { await Task.yield() }
            check(cancellation.count == 1, "Asset cancellation fixture starts within its deadline")
            task.cancel()
            let stopped = await task.value
            check(cancellation.count == 1 && !stopped.isEmpty, "Cancellation drains the asset task and prevents retries")
        }
        return failures
    }
}

private struct ModelFixtureScanner: CairnScanner {
    let root: URL
    var info: CategoryInfo { .init(id: LocalModels.categoryID, title: "Fixture", subtitle: "", systemImage: "cpu", group: .ai, requiresFDA: false) }
    var allowedRoots: [URL] { [root] }
    func scan(_ context: ScanContext) async {}
}

private final class ModelServiceFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var consent = true
    var count: Int { lock.withLock { calls } }
    var allowed: Bool { lock.withLock { consent } }
    func record() { lock.withLock { calls += 1 } }
    func revoke() { lock.withLock { consent = false } }
}
