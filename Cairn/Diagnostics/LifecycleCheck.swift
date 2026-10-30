import Foundation
import Darwin
import SwiftUI
import AppKit

/// Real child-process exits and file moves, confined to a marked temporary tree.
/// Uses ScanStore, Cleaner policy, journals, receipts and no-overwrite recovery.
@MainActor enum LifecycleCheck {
    static func fixtureRoot() -> URL? {
        guard let index = CommandLine.arguments.firstIndex(of: "--fixture-root"), index + 1 < CommandLine.arguments.count else { return nil }
        let url = URL(fileURLWithPath: CommandLine.arguments[index + 1]).standardizedFileURL
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        guard url.deletingLastPathComponent() == parent, url.lastPathComponent.hasPrefix("cairn-lifecycle-"),
              url.resolvingSymlinksInPath() == url,
              (try? String(contentsOf: url.appendingPathComponent("fixture-marker"), encoding: .utf8)) == "Cairn disposable lifecycle fixture" else { return nil }
        return url
    }
    static func leaseProbe() {
        guard let root = fixtureRoot() else { exit(2) }
        do {
            guard let lease = try InstanceLease.acquire(at: root.appendingPathComponent("instance.lock")) else { exit(23) }
            withExtendedLifetime(lease) { exit(0) }
        } catch { exit(24) }
    }
    static func store(_ root: URL, count: Int = 2, crash: Bool = false, checkpoint: String? = nil) -> ScanStore {
        let trash = root.appendingPathComponent("trash")
        return ScanStore(removalLogURL: root.appendingPathComponent("recovery.json"),
            restoreFile: { from, to in
                guard Cleaner.canRestore(from: from, to: to, trashRoots: [trash]) else { return false }
                return renamex_np(from.path, to.path, UInt32(RENAME_EXCL)) == 0
            }, recordRestoredBytes: { _ in }, fixtureScanners: [LifecycleScanner(root: root, count: count)],
            lifecycleCheckpoint: { point in if point == checkpoint { _exit(78) } },
            cleanFile: { item, roots, pro, reviewed in
                Cleaner.clean(item, allowedRoots: roots, proEnabled: pro, reviewedSource: reviewed, moveToTrash: { source in
                    let target = trash.appendingPathComponent(source.lastPathComponent)
                    guard renamex_np(source.path, target.path, UInt32(RENAME_EXCL)) == 0 else { throw POSIXError(.EIO) }
                    if crash { _exit(77) } // After the move, before the journal outcome.
                    return target
                })
            })
    }
    static func recoveryChild() async {
        guard let root = fixtureRoot() else { exit(2) }
        let checkpoint = ["intent", "outcome", "recovery", "receipt"].first { CommandLine.arguments.contains("--exit-at-" + $0) }
        let instance = store(root, crash: CommandLine.arguments.contains("--crash-after-move"), checkpoint: checkpoint)
        if CommandLine.arguments.contains("--reload-only") {
            await instance.loadRemovalLog(); await instance.loadCleanupRuns()
            guard instance.cleanupRuns.count == 1, instance.lastCleanSummary?.accounting.trashCount == 1,
                  instance.lastCleanSummary?.failed == 1, instance.lastCleanRunID == instance.cleanupRuns.first?.id,
                  instance.lastCleanSummary?.capacityChanges.isEmpty == false else { exit(31) }
            exit(0)
        }
        instance.startScan()
        while instance.isScanning { try? await Task.sleep(nanoseconds: 10_000_000) }
        let items = instance.buckets.flatMap(\.items)
        guard items.count == 2 else { exit(32) }
        // Change one reviewed source after the scan; executor must skip it.
        try? FileManager.default.removeItem(at: root.appendingPathComponent("source/item-1.bin"))
        let result = await instance.clean(items, proEnabled: true)
        guard result.accounting.trashCount == 1, result.failed == 1 else { exit(33) }
        exit(0)
    }
    static func child(_ root: URL, flags: [String]) async -> Int32 {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        return await Task.detached {
            await withCheckedContinuation { continuation in
                let process = Process()
                process.executableURL = executable
                process.arguments = flags + ["--fixture-root", root.path]
                process.terminationHandler = { finished in
                    continuation.resume(returning: finished.terminationStatus)
                }
                do {
                    try process.run()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                    }
                } catch { print("Child failed: \(error)"); continuation.resume(returning: -1) }
            }
        }.value
    }
    static func nativeCheck() async {
        setbuf(stdout, nil)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("cairn-native-reliability-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: root.appendingPathComponent("source"), withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: root) }
            for n in 0..<12_000 { try Data("Native fixture".utf8).write(to: root.appendingPathComponent("source/item-\(n).bin")) }
            let scanning = store(root, count: 12_000)
            let host = NSHostingView(rootView: AnyView(EmptyView()))
            host.sizingOptions = []
            host.frame = NSRect(x: 0, y: 0, width: 1024, height: 680)
            host.autoresizingMask = [.width, .height]
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1024, height: 680), styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            let baseline = MemoryWatch.footprintBytes()
            var peak = baseline, gap: TimeInterval = 0
            let monitor = Task { @MainActor in
                var previous = Date()
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 25_000_000)
                    let now = Date(); gap = max(gap, now.timeIntervalSince(previous)); previous = now
                    peak = max(peak, MemoryWatch.footprintBytes())
                }
            }
            var retained: [UInt64] = []
            for round in 0..<8 {
                // Fill the retained-result store first; the separate lifecycle
                // check stresses streaming and cancellation. Here every native
                // render must see all 12,000 results, not a partial buffer stop.
                host.rootView = AnyView(EmptyView())
                scanning.startScan()
                while scanning.isScanning { try? await Task.sleep(nanoseconds: 50_000_000) }
                guard scanning.buckets.reduce(0, { $0 + $1.items.count }) == 12_000 else { print("FAIL incomplete native fixture"); exit(1) }
                host.rootView = AnyView(LargeFilesWorkspace(store: scanning, search: "", inspectorVisible: .constant(true), onRescan: {}, onReview: {})
                    .environment(\.colorScheme, .dark).frame(width: 1024, height: 680))
                host.layoutSubtreeIfNeeded()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                host.rootView = AnyView(DeveloperCleanupView(store: scanning, section: .smartScan, inspectorVisible: .constant(false), onReview: {})
                    .environment(\.colorScheme, .dark).frame(width: 1024, height: 680))
                host.layoutSubtreeIfNeeded()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                retained.append(MemoryWatch.footprintBytes())
                print("NATIVE ROUND \(round + 1): \(retained.last! / 1_048_576) MiB, \(scanning.buckets.reduce(0) { $0 + $1.items.count }) retained results")
            }
            monitor.cancel(); await monitor.value
            window.contentView = nil
            let plateau = (retained.last ?? 0) < (retained.dropFirst(2).first ?? 0) + 48 * 1_048_576
            let passed = plateau && peak < baseline + 200 * 1_048_576 && gap < 2
            print("NATIVE WORKSPACES: baseline \(baseline/1_048_576) MiB; peak \(peak/1_048_576) MiB; heartbeat \(gap)s; plateau \(plateau)")
            print(passed ? "NATIVE RELIABILITY PASSED" : "NATIVE RELIABILITY FAILED")
            exit(passed ? 0 : 1)
        } catch { print("Native fixture failed: \(error)"); exit(1) }
    }
    static func run() async {
        setbuf(stdout, nil)
        var failures = 0
        func check(_ result: Bool, _ label: String) { print("\(result ? "PASS" : "FAIL") \(label)"); if !result { failures += 1 } }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("cairn-lifecycle-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: false)
            defer { try? fm.removeItem(at: root) }
            try Data("Cairn disposable lifecycle fixture".utf8).write(to: root.appendingPathComponent("fixture-marker"))
            try fm.createDirectory(at: root.appendingPathComponent("source"), withIntermediateDirectories: false)
            try fm.createDirectory(at: root.appendingPathComponent("trash"), withIntermediateDirectories: false)
            for n in 0..<2 { try Data("Original fixture \(n)".utf8).write(to: root.appendingPathComponent("source/item-\(n).bin")) }
            var lease = try InstanceLease.acquire(at: root.appendingPathComponent("instance.lock"))
            check(lease != nil, "First process owns data-store lease")
            let blocked = await child(root, flags: ["--lease-probe"])
            check(blocked == 23, "Second process is refused by kernel lock")
            withExtendedLifetime(lease) {}
            lease = nil
            check(await child(root, flags: ["--lease-probe"]) == 0, "Lease is available after owner closes")
            check(await child(root, flags: ["--lease-probe"]) == 0, "Process exit releases lease without deleting lock file")
            let link = root.appendingPathComponent("link.lock")
            try fm.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("instance.lock"))
            do { _ = try InstanceLease.acquire(at: link); check(false, "Symlink lock refused") }
            catch { check(true, "Symlink lock refused") }

            check(await child(root, flags: ["--recovery-child"]) == 0, "Scan, select exact results and guarded cleanup complete in child")
            check(await child(root, flags: ["--recovery-child", "--reload-only"]) == 0, "Complete receipt and skipped count survive actual process restart")
            let restored = store(root)
            await restored.loadRemovalLog(); await restored.loadCleanupRuns()
            check(restored.removalLog.count == 1, "Recovery metadata survives process restart")
            if let entry = restored.removalLog.first {
                let original = URL(fileURLWithPath: entry.originalPath)
                try Data("Do not overwrite".utf8).write(to: original)
                check(!(await restored.restoreFromLog(entry)), "Restore refuses a destination collision")
                check(try Data(contentsOf: original) == Data("Do not overwrite".utf8), "Collision contents preserved")
                try fm.removeItem(at: original)
                check(await restored.restoreFromLog(entry), "Journaled recovery restores fixture after restart")
                check(try Data(contentsOf: original) == Data("Original fixture 0".utf8), "Restored bytes match original exactly")
                let reopened = store(root)
                await reopened.loadRemovalLog(); await reopened.loadCleanupRuns()
                check(reopened.removalLog.first?.restoredAt != nil && reopened.cleanupRuns.count == 1,
                      "Restored status and complete receipt remain after another reload")
            }
            // A corrupt receipt must stop new mutation without deleting history.
            let brokenURL = root.appendingPathComponent("broken-runs")
            let brokenBytes = Data("not valid JSON".utf8)
            try brokenBytes.write(to: brokenURL)
            let broken = CleanupRunHistory(url: brokenURL)
            let problem = await broken.save(CleanupRun(id: UUID(), started: Date(), finished: nil, summary: .init()))
            let preserved = try Data(contentsOf: brokenURL)
            check(problem != nil && preserved == brokenBytes, "Corrupt receipts fail closed and stay intact")
            let writerURL = root.appendingPathComponent("conflict-runs")
            let writer = CleanupRunHistory(url: writerURL)
            let run = CleanupRun(id: UUID(), started: Date(), finished: nil, summary: .init())
            check(await writer.save(run) == nil, "Run intent persists before actions")
            try brokenBytes.write(to: writerURL)
            check(await writer.save(run) != nil, "External receipt modification refuses overwrite")

            let linkedURL = root.appendingPathComponent("dangling-receipts")
            let absentTarget = root.appendingPathComponent("absent-receipts")
            try fm.createSymbolicLink(at: linkedURL, withDestinationURL: absentTarget)
            let linked = CleanupRunHistory(url: linkedURL)
            check(await linked.save(run) != nil, "Dangling receipt symlink blocks cleanup")
            check(try fm.destinationOfSymbolicLink(atPath: linkedURL.path) == absentTarget.path,
                  "Rejected dangling receipt link is preserved")
            let lateURL = root.appendingPathComponent("late-receipt-link")
            let late = CleanupRunHistory(url: lateURL)
            _ = await late.load()
            try fm.createSymbolicLink(at: lateURL, withDestinationURL: absentTarget)
            check(await late.save(run) != nil, "Receipt symlink introduced after load blocks save")

            // Retain production ScanStore results across repeated scans and stops.
            for index in 0..<12_000 {
                let file = root.appendingPathComponent("source/item-\(index).bin")
                if !fm.fileExists(atPath: file.path) { try Data("Scan fixture".utf8).write(to: file) }
            }
            let scanning = store(root, count: 12_000)
            let baseline = MemoryWatch.footprintBytes()
            var peak = baseline, gaps: TimeInterval = 0, beats = 0
            let monitor = Task { @MainActor in
                var last = Date()
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 25_000_000)
                    let now = Date(); gaps = max(gaps, now.timeIntervalSince(last)); last = now
                    peak = max(peak, MemoryWatch.footprintBytes()); beats += 1
                }
            }
            var retained: [UInt64] = []
            for round in 0..<12 {
                scanning.startScan()
                while scanning.isScanning { try? await Task.sleep(nanoseconds: 20_000_000) }
                check(scanning.buckets.reduce(0) { $0 + $1.items.count } == 12_000, "Round \(round + 1): production store retains bounded results (count=\(scanning.buckets.reduce(0) { $0 + $1.items.count }), phase=\(scanning.phase), status=\(scanning.progressText))")
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                retained.append(MemoryWatch.footprintBytes())
                scanning.startScan()
                try? await Task.sleep(nanoseconds: 20_000_000)
                await scanning.cancelAndWait()
                check(scanning.phase == .cancelled, "Round \(round + 1): cancellation settles")
            }
            monitor.cancel(); await monitor.value
            check(peak < baseline + 160 * 1_048_576, "Retained-result workload stays within 160 MiB growth budget")
            check((retained.last ?? 0) < (retained.dropFirst(2).first ?? 0) + 32 * 1_048_576, "Retained-result memory plateaus after warm-up")
            check(beats > 20 && gaps < 1, "Main actor heartbeat stays below one second")
            print("STORE SOAK: baseline \(baseline/1_048_576) MiB; peak \(peak/1_048_576) MiB; retained \(retained.map { $0/1_048_576 }); heartbeat \(gaps)s")

            // Reset only this fixture's journals to test an abrupt child exit.
            for name in ["recovery.json", "recovery.json.actions", "recovery.json.runs"] {
                try? fm.removeItem(at: root.appendingPathComponent(name))
            }
            try Data("Original fixture 1".utf8).write(to: root.appendingPathComponent("source/item-1.bin"))
            check(await child(root, flags: ["--recovery-child", "--crash-after-move"]) == 77, "Child exits after file move before outcome save")
            let interrupted = store(root)
            await interrupted.loadRemovalLog(); await interrupted.loadCleanupRuns()
            let journal = ActionJournal(url: root.appendingPathComponent("recovery.json.actions"))
            check(!journal.prepare() && journal.recent.first?.state == .pending, "Uncertain mutation blocks new cleanup; no replay")
            check(interrupted.lastCleanSummary?.interrupted == true, "Unfinished receipt is labelled interrupted after process death")
            check(fm.fileExists(atPath: root.appendingPathComponent("trash/item-0.bin").path), "Uncertain moved fixture is preserved for manual review")
            for boundary in ["intent", "outcome", "recovery", "receipt"] {
                for name in ["recovery.json", "recovery.json.actions", "recovery.json.runs", "trash/item-0.bin", "source/item-0.bin"] {
                    try? fm.removeItem(at: root.appendingPathComponent(name))
                }
                for n in 0..<2 { try Data("Original fixture \(n)".utf8).write(to: root.appendingPathComponent("source/item-\(n).bin")) }
                check(await child(root, flags: ["--recovery-child", "--exit-at-" + boundary]) == 78, "Process terminates at \(boundary) boundary")
                let reopened = store(root)
                _ = await reopened.reconcileActionJournal()
                await reopened.loadCleanupRuns()
                let actions = ActionJournal(url: root.appendingPathComponent("recovery.json.actions"))
                if boundary == "intent" {
                    check(!actions.prepare() && fm.fileExists(atPath: root.appendingPathComponent("source/item-0.bin").path), "Intent-only crash preserves source and requires review")
                } else {
                    check(actions.prepare() && reopened.removalLog.count == 1, "\(boundary): recovery metadata survives or reconciles without replay")
                }
                check(reopened.lastCleanSummary?.interrupted == (boundary != "receipt"), "\(boundary): receipt distinguishes interrupted from completed")
            }
            let specialist = store(root)
            await specialist.loadCleanupRuns()
            if let run = await specialist.beginSpecialistRun("Fixture specialist") {
                await specialist.loadCleanupRuns()
                check(specialist.isRunActive(run.id) && specialist.cleanupRuns.first?.summary.interrupted == false, "Active specialist receipt is not labelled a crashed run")
                check(await specialist.finishSpecialistRun(run, summary: .init(failed: 1, errors: ["Fixture skip"])), "Specialist outcome persists through shared receipt store")
                let restarted = store(root)
                await restarted.loadCleanupRuns()
                check(restarted.cleanupRuns.first?.kind == "Fixture specialist" && restarted.lastCleanSummary?.failed == 1, "Specialist receipt survives reload")
            } else { check(false, "Specialist receipt begins") }

        } catch { check(false, "Lifecycle fixture: \(error)") }
        print("Lifecycle checks: \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}

private struct LifecycleScanner: CairnScanner {
    let root: URL
    let count: Int
    let info = CategoryInfo(id: "large-old", title: "Fixture", subtitle: "", systemImage: "folder", group: .general, requiresFDA: false)
    var allowedRoots: [URL] { [root.appendingPathComponent("source")] }
    func scan(_ context: ScanContext) async {
        for index in 0..<count {
            if context.isCancelled() { return }
            let url = root.appendingPathComponent("source/item-\(index).bin")
            context.emit(ScanItem(url: url, resolvedURL: url, allocatedSize: 18, categoryID: info.id, severity: .review, note: "Disposable \(index)"))
            // This suite tests retained results, not buffer overflow (covered by
            // ReliabilityCheck's deliberate flood). Pace real-file findings.
            if index.isMultiple(of: 100) { try? await Task.sleep(nanoseconds: 100_000_000) }
        }
    }
}
