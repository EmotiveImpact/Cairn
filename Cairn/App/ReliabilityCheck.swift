import Foundation
import Security
import Darwin

/// Isolated failure injection. No real Keychain, scans, preferences or volumes.
@MainActor enum ReliabilityCheck {
    static func run() async {
        var failures = 0
        func check(_ good: Bool, _ label: String) {
            print("\(good ? "PASS" : "FAIL") \(label)"); if !good { failures += 1 }
        }
        func rejects(_ label: String, _ operation: () throws -> Void) {
            do { try operation(); check(false, label) } catch { check(true, label) }
        }
        var receipt = CleanupAccounting()
        receipt.record(.init(movedToTrashURL: URL(fileURLWithPath: "/fixture/.Trash/file"), bytesAffected: 800, usedTool: false), recoveryRecorded: true)
        receipt.record(.init(bytesAffected: 200, usedTool: false))
        receipt.record(.init(bytesAffected: 400, usedTool: true))
        receipt.record(.init(bytesAffected: 900, usedTool: false, error: "Fixture failure"))
        check(receipt.trashCount == 2 && receipt.trashBytes == 1_000, "Trash accounting records estimates separately from tool actions")
        check(receipt.recordedRecoveryCount == 1 && receipt.missingRecoveryCount == 1, "Missing recovery path is reported without claiming permanent removal")
        check(receipt.toolCount == 1 && receipt.toolBytes == 400 && receipt.completedCount == 3, "Failed actions do not enter successful cleanup accounting")
        receipt.record(.init(bytesAffected: -10, usedTool: true))
        check(receipt.toolBytes == 400, "Negative size estimates cannot reduce activity totals")
        receipt.record(.init(movedToTrashURL: URL(fileURLWithPath: "/fixture/.Trash/unrecorded"), bytesAffected: 100, usedTool: false))
        check(receipt.recordedRecoveryCount == 1 && receipt.missingRecoveryCount == 2, "A returned Trash path alone does not claim saved recovery history")
        let capacityBefore = CleanupCapacityChange.Reading(volumeID: "original", name: "Fixture", available: 1_000)
        let unchanged = CleanupCapacityChange(id: "/fixture", before: capacityBefore, after: capacityBefore)
        check(unchanged.delta == 0 && unchanged.changeText == "No measured change", "Zero capacity change is not replaced by affected file sizes")
        let decreased = CleanupCapacityChange(id: "/fixture", before: capacityBefore, after: .init(volumeID: "original", name: "Fixture", available: 800))
        check(decreased.delta == -200 && decreased.changeText.contains("less"), "Capacity decreases remain signed and visible")
        check(CleanupCapacityChange(id: "/fixture", before: capacityBefore, after: nil).delta == nil, "Missing capacity readings remain unknown")
        check(CleanupCapacityChange(id: "/fixture", before: capacityBefore, after: .init(volumeID: "replacement", name: "Fixture", available: 2_000)).delta == nil, "Replacement drive readings cannot produce false savings")
        // Simulated Security statuses. Never access this user's Keychain.
        do {
            let missing: Double? = try LicenseKeychain.read("fixture", as: Double.self, fetch: { _, _ in errSecItemNotFound })
            check(missing == nil, "Only a missing Keychain item is treated as absent")
        } catch { check(false, "Missing item decoding") }
        rejects("Locked Keychain is an error, not a new trial") {
            let _: Double? = try LicenseKeychain.read("fixture", as: Double.self, fetch: { query, _ in
                check((query as NSDictionary)[kSecUseAuthenticationUI as String] as? String == kSecUseAuthenticationUIFail as String, "Startup Keychain read forbids interaction")
                return errSecInteractionNotAllowed
            })
        }
        rejects("Malformed credential data is preserved") {
            let _: Double? = try LicenseKeychain.read("fixture", as: Double.self, fetch: { _, result in result?.pointee = Data("invalid".utf8) as CFData; return errSecSuccess })
        }
        var added = false
        rejects("Failed credential update does not delete or replace the record") {
            try LicenseKeychain.write("fixture", value: 1, update: { _, _ in errSecInteractionNotAllowed }, add: { _, _ in added = true; return errSecSuccess })
        }
        check(!added, "No replacement add after access denial")
        do {
            try LicenseKeychain.write("fixture", value: 1, update: { _, _ in errSecSuccess }, add: { _, _ in added = true; return errSecSuccess })
            check(!added, "Existing credentials updated in place")
        } catch { check(false, "Credential update fixture") }

        let lazyRead = CancelBox()
        let deferred = LicenseManager(loadLocal: {
            lazyRead.cancel()
            return LocalLicenseState(trialStart: Date(), license: nil)
        }, checkOnline: false, honorDevUnlock: false)
        try? await Task.sleep(nanoseconds: 100_000_000)
        check(!lazyRead.isCancelled && !deferred.hasRequestedStorage, "Default startup performs no Keychain access")
        await deferred.loadIfNeeded()
        check(lazyRead.isCancelled && deferred.hasRequestedStorage && deferred.isInTrial, "Opening license settings loads entitlement on demand")
        let releaseKeychain = DispatchSemaphore(value: 0)
        let before = Date()
        let slow = LicenseManager(loadLocal: {
            _ = releaseKeychain.wait(timeout: .now() + 8)
            return LocalLicenseState(trialStart: Date(), license: nil)
        }, automatic: false, checkOnline: false, honorDevUnlock: false)
        check(Date().timeIntervalSince(before) < 0.2, "License construction performs no blocking read")
        let loading = Task { await slow.reloadStorage() }
        try? await Task.sleep(nanoseconds: 100_000_000)
        check(slow.isLoading, "Main actor remains responsive during slow credential read")
        let watchdogDeadline = Date().addingTimeInterval(5)
        while slow.storageMessage == nil && Date() < watchdogDeadline { try? await Task.sleep(nanoseconds: 50_000_000) }
        check(slow.storageMessage?.contains("longer") == true, "Slow Keychain check explains the delay")
        releaseKeychain.signal()
        await loading.value
        check(!slow.isLoading && slow.isInTrial, "Delayed result finishes without rebuilding the window")
        let denied = LicenseManager(loadLocal: { throw LicenseStorageError.keychain(errSecInteractionNotAllowed) }, automatic: false, checkOnline: false, honorDevUnlock: false)
        await denied.reloadStorage()
        check(!denied.isLoading && !denied.isUnlocked && denied.storageMessage != nil, "Denied Keychain leaves free UI available and no false trial")

        let gate = ScanGate()
        let first = await gate.acquire()
        check(first, "First operation acquires scan gate")
        let waiting = Task { await gate.acquire() }
        try? await Task.sleep(nanoseconds: 10_000_000)
        waiting.cancel()
        let cancelled = await waiting.value
        check(!cancelled, "Cancelled queued operation never acquires scan gate")
        gate.release()
        let next = await gate.acquire()
        check(next, "Cancelled waiter does not strand the gate")
        gate.release()
        for _ in 0..<50 {
            let task = Task { let granted = await gate.acquire(); if granted { gate.release() }; return granted }
            task.cancel(); _ = await task.value
        }
        let afterStress = await gate.acquire()
        check(afterStress, "Gate remains usable after repeated immediate cancellations")
        gate.release()

        let floodFinished = CancelBox()
        let flood = ScanEventPipeline(scanners: [FixtureScanner(flood: true, started: CancelBox(), finished: floodFinished)], fdaGranted: false, includeExternal: false, minSize: 0, bufferLimit: 32)
        let floodDeadline = Date().addingTimeInterval(2)
        while !floodFinished.isCancelled && Date() < floodDeadline { try? await Task.sleep(nanoseconds: 10_000_000) }
        await flood.stopAndWait()
        var buffered = 0
        for await _ in flood.stream { buffered += 1 }
        check(flood.overflow.isCancelled && buffered <= 32, "Fast scan producer has bounded delivery and reports incomplete results")
        let slowStarted = CancelBox(), slowFinished = CancelBox()
        let slowScan = ScanEventPipeline(scanners: [FixtureScanner(flood: false, started: slowStarted, finished: slowFinished)], fdaGranted: false, includeExternal: false, minSize: 0)
        let startDeadline = Date().addingTimeInterval(2)
        while !slowStarted.isCancelled && Date() < startDeadline { try? await Task.sleep(nanoseconds: 10_000_000) }
        await slowScan.stopAndWait()
        check(slowStarted.isCancelled && slowFinished.isCancelled, "Scan cancellation awaits producer shutdown before releasing its slot")

        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("cairn-reliability-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: false)
            defer { try? fm.removeItem(at: root) }
            let duplicatesRoot = root.appendingPathComponent("duplicate-fixtures")
            try fm.createDirectory(at: duplicatesRoot, withIntermediateDirectories: false)
            let duplicateData = Data(repeating: 0x42, count: 2 * 1_048_576)
            try duplicateData.write(to: duplicatesRoot.appendingPathComponent("one.bin"))
            try duplicateData.write(to: duplicatesRoot.appendingPathComponent("two.bin"))
            var different = duplicateData
            different[different.count / 2] = 0x43
            try different.write(to: duplicatesRoot.appendingPathComponent("different-middle.bin"))
            try fm.createSymbolicLink(at: duplicatesRoot.appendingPathComponent("link.bin"), withDestinationURL: duplicatesRoot.appendingPathComponent("one.bin"))
            let discovery = await Task.detached {
                await DuplicateStore.findDuplicates(roots: [duplicatesRoot], minSize: 1, cap: 10, skipDirNames: [], onProgress: { _, _ in })
            }.value
            check(discovery.groups.count == 1 && discovery.groups.first?.count == 2 && !discovery.limited, "Full duplicate comparison excludes different middles and symbolic links")
            check(discovery.groups.first?.files.filter(\.isKeeper).count == 1 && discovery.groups.first?.files.allSatisfy({ !$0.selected }) == true, "Duplicate comparison preserves one keeper and never preselects copies")
            let limitedDiscovery = await Task.detached {
                await DuplicateStore.findDuplicates(roots: [duplicatesRoot], minSize: 1, cap: 1, skipDirNames: [], onProgress: { _, _ in })
            }.value
            check(limitedDiscovery.limited && limitedDiscovery.groups.isEmpty, "Duplicate candidate limit is explicit and does not invent groups")
            let oldExclusions = SafePaths.userExcluded, oldRoots = SafePaths.protectedSessionRoots
            defer { SafePaths.userExcluded = oldExclusions; SafePaths.protectedSessionRoots = oldRoots }
            SafePaths.userExcluded = []
            SafePaths.protectedSessionRoots = []
            for (index, child) in ["arbitrary/deep/sessions/2026/item.jsonl", "checkout/.git/HEAD", "editor/Backups/unsaved", "db/live.sqlite-wal", "recordings/rollout-fixture.jsonl", "workspace/state.vscdb", "credentials/.env.local"].enumerated() {
                let directory = root.appendingPathComponent("protected-\(index)")
                let file = directory.appendingPathComponent(child)
                try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("keep".utf8).write(to: file)
                check(!SafePaths.evaluateContents(directory).isAllowed, "Nested protected content blocked: \(child)")
                check(try Data(contentsOf: file) == Data("keep".utf8), "Protection inspection preserves fixture \(index)")
            }
            let parent = root.appendingPathComponent("ordinary-cache")
            let excluded = parent.appendingPathComponent("keep")
            try fm.createDirectory(at: excluded, withIntermediateDirectories: true)
            SafePaths.userExcluded = [excluded.path]
            check(!SafePaths.evaluateContents(parent).isAllowed, "Parent cleanup cannot bypass a nested exclusion")
            SafePaths.userExcluded = []
            SafePaths.protectedSessionRoots = [excluded.path]
            check(!SafePaths.evaluateContents(parent).isAllowed, "Generic custom conversation root is protected")
            SafePaths.protectedSessionRoots = []
            check(SafePaths.evaluateContents(parent).isAllowed, "Ordinary empty cache fixture remains inspectable")

            let source = root.appendingPathComponent("export.zip")
            let content = Data(repeating: 0x5a, count: 4 * 1024 * 1024)
            try content.write(to: source)
            let good = try ArchiveCopy.copy(source: source, directory: root.appendingPathComponent("good"), cancel: CancelBox(), destinationValid: { true }, progress: { _ in })
            let verified = try ArchiveCopy.verify(source: source, destination: good.0, bytes: good.1, digest: good.2, cancel: CancelBox(), destinationValid: { true })
            check(verified.1 == good.2, "Existing verified copy can be checked again")
            try Data("changed".utf8).write(to: good.0)
            rejects("Changed copy fails re-verification") { _ = try ArchiveCopy.verify(source: source, destination: good.0, bytes: good.1, digest: good.2, cancel: CancelBox(), destinationValid: { true }) }
            let disconnected = CancelBox()
            rejects("Disconnect interrupts copy before promotion") {
                _ = try ArchiveCopy.copy(source: source, directory: root.appendingPathComponent("disconnect"), cancel: CancelBox(), destinationValid: { !disconnected.isCancelled }, progress: { _ in disconnected.cancel() })
            }
            check(!fm.fileExists(atPath: root.appendingPathComponent("disconnect/export.zip").path), "Disconnected transfer has no finished filename")
            let racing = root.appendingPathComponent("racing")
            let inserted = CancelBox()
            rejects("File appearing at final destination is not overwritten") {
                _ = try ArchiveCopy.copy(source: source, directory: racing, cancel: CancelBox(), destinationValid: { true }, progress: { _ in
                    if !inserted.isCancelled { inserted.cancel(); try? Data("retain existing".utf8).write(to: racing.appendingPathComponent("export.zip")) }
                })
            }
            check(try Data(contentsOf: racing.appendingPathComponent("export.zip")) == Data("retain existing".utf8), "Concurrent destination remains intact")
            let swapped = root.appendingPathComponent("swapped"), displaced = root.appendingPathComponent("displaced"), foreign = root.appendingPathComponent("foreign")
            try fm.createDirectory(at: foreign, withIntermediateDirectories: false)
            let didSwap = CancelBox()
            rejects("Destination directory substitution is rejected") {
                _ = try ArchiveCopy.copy(source: source, directory: swapped, cancel: CancelBox(), destinationValid: { true }, progress: { _ in
                    if !didSwap.isCancelled { didSwap.cancel(); try? FileManager.default.moveItem(at: swapped, to: displaced); try? FileManager.default.createSymbolicLink(at: swapped, withDestinationURL: foreign) }
                })
            }
            check(try fm.contentsOfDirectory(atPath: foreign.path).isEmpty, "Substituted directory received no writes")
            check(try Data(contentsOf: source) == content, "All interrupted transfers preserve original bytes")

            let corrupt = root.appendingPathComponent("corrupt-history.json")
            let corruptBytes = Data("do not replace this record".utf8)
            try corruptBytes.write(to: corrupt)
            let history = ScanStore(removalLogURL: corrupt, recordRestoredBytes: { _ in })
            check(!history.prepareRemovalLog(), "Corrupt recovery history blocks new removal")
            check(try Data(contentsOf: corrupt) == corruptBytes, "Corrupt recovery history is not overwritten")
            let transferHistory = StorageTransferStore(journal: corrupt)
            transferHistory.load()
            check(transferHistory.message.contains("not be overwritten"), "Corrupt transfer journal is surfaced")
            let fakeDrive = StorageDrive(url: root, name: "Fixture", uuid: "fixture", capacity: 1_000_000_000, available: 500_000_000, external: true, writable: true, encrypted: true, format: "apfs")
            transferHistory.start(source: source, drive: fakeDrive)
            check(try !transferHistory.busy && Data(contentsOf: corrupt) == corruptBytes, "Transfer does not overwrite corrupt journal or begin copying")

            let journal = root.appendingPathComponent("recovery.json"), trash = root.appendingPathComponent(".Trash")
            try fm.createDirectory(at: trash, withIntermediateDirectories: false)
            let trashed = trash.appendingPathComponent("restore-me.zip"), original = root.appendingPathComponent("restored.zip")
            try Data("restore fixture".utf8).write(to: trashed)
            let record = ScanStore.RemovalLogEntry(name: "Fixture", originalPath: original.path, trashPath: trashed.path, bytes: 15, date: Date(), category: "fixture")
            let recovery = ScanStore(removalLogURL: journal, restoreFile: { from, to in
                guard Cleaner.canRestore(from: from, to: to, trashRoots: [trash]) else { return false }
                return renamex_np(from.path, to.path, UInt32(RENAME_EXCL)) == 0
            }, recordRestoredBytes: { _ in })
            check(recovery.appendRemovals([record]), "Fixture recovery entry saved")
            try Data("existing original".utf8).write(to: original)
            check(!(await recovery.restoreFromLog(record)), "Restore refuses to overwrite existing original")
            check(try Data(contentsOf: original) == Data("existing original".utf8), "Failed restore preserves existing original")
            try fm.removeItem(at: original)
            check(await recovery.restoreFromLog(record), "Fixture can be restored without overwriting")
            check(recovery.removalLog.count == 1 && recovery.removalLog[0].restoredAt != nil && !recovery.removalLog[0].recoverable, "Successful restore keeps a non-actionable history record")
            let reloaded = ScanStore(removalLogURL: journal, recordRestoredBytes: { _ in })
            reloaded.loadRemovalLog()
            check(reloaded.removalLog.first?.restoredAt != nil, "Restored status survives relaunch")
            try corruptBytes.write(to: journal)
            check(try !reloaded.prepareRemovalLog() && Data(contentsOf: journal) == corruptBytes, "External history change is not overwritten")
        } catch { check(false, "Fixture failure: \(error.localizedDescription)") }

        do {
            let start = Date()
            let output = try ToolRunner.runExecutable("/usr/bin/python3", ["-c", "import sys,time; sys.stdout.write('o'*400000); sys.stdout.flush(); sys.stderr.write('e'*400000); sys.stderr.flush(); time.sleep(5)"], timeout: 0.7)
            check(output.timedOut && Date().timeIntervalSince(start) < 4, "Chatty tool exits within bounded timeout")
            check(output.stdout.utf8.count <= 256 * 1024 && output.stderr.utf8.count <= 256 * 1024, "Tool diagnostics stay within memory caps")
        } catch { check(false, "Tool fixture: \(error.localizedDescription)") }
        print("Reliability checks: \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}

private struct FixtureScanner: CairnScanner {
    let flood: Bool
    let started: CancelBox
    let finished: CancelBox
    let info = CategoryInfo(id: "fixture", title: "Fixture", subtitle: "", systemImage: "folder", group: .general, requiresFDA: false)
    func scan(_ context: ScanContext) async {
        started.cancel()
        defer { finished.cancel() }
        if flood {
            let url = URL(fileURLWithPath: "/private/tmp/cairn-synthetic-no-file")
            for _ in 0..<10_000 {
                if context.isCancelled() { break }
                context.emit(ScanItem(url: url, resolvedURL: url, allocatedSize: 1, categoryID: "fixture", severity: .safe))
            }
        } else {
            while !context.isCancelled() { try? await Task.sleep(nanoseconds: 10_000_000) }
            // A worker may need time to close its handles after cancellation.
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { continuation.resume() }
            }
        }
    }
}
