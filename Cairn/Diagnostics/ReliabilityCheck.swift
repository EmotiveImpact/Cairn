import Foundation
import Security
import Darwin

/// Isolated failure injection. No real Keychain, scans, preferences or volumes.
@MainActor enum ReliabilityCheck {
    static func run() async {
        struct FixtureActionArchive: Encodable {
            let version: Int
            let entries: [ActionJournal.Entry]
        }
        var failures = 0
        func check(_ good: Bool, _ label: String) {
            print("\(good ? "PASS" : "FAIL") \(label)"); if !good { failures += 1 }
        }
        func rejects(_ label: String, _ operation: () throws -> Void) {
            do { try operation(); check(false, label) } catch { check(true, label) }
        }
        if !Notify.isAvailable {
            // This check runs from the raw SwiftPM executable. It must not
            // prompt, post, or crash when no application bundle exists.
            Notify.requestAuth()
            Notify.send(title: "Fixture", body: "No notification should be posted")
            Notify.scanComplete(totalBytes: 1, items: 1)
            await StorageControl.shared.refreshNotificationStatus()
            check(StorageControl.shared.notificationStatus.contains("unbundled build"),
                  "Unbundled executable skips UserNotifications without crashing")
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
            let destroyMarker = root.appendingPathComponent("must-not-exist")
            let destructiveTool = ScanItem(
                url: root, resolvedURL: root, allocatedSize: 1024,
                categoryID: "fixture", severity: .safe,
                cleanMethod: .tool(ToolCommand(tool: "touch", arguments: [destroyMarker.path], display: "touch fixture", destroysData: true)),
                selected: true
            )
            var toolBucket = ScanStore.Bucket(info: .init(id: "fixture", title: "Fixture", subtitle: "", systemImage: "folder", group: .general, requiresFDA: false))
            toolBucket.append(destructiveTool)
            check(destructiveTool.isActionable && toolBucket.selectedCount == 1,
                  "Tool findings can enter a reviewed cleanup selection")
            let destructiveResult = Cleaner.clean(destructiveTool, allowedRoots: [root], proEnabled: true)
            check(!destructiveResult.ok && !fm.fileExists(atPath: destroyMarker.path),
                  "Data-destroying tool commands never run")
            let advice = ScanItem(url: root, resolvedURL: root, allocatedSize: 1024, categoryID: "fixture",
                                  severity: .review, cleanMethod: .adviceOnly, selected: true)
            let unsupportedJournal = root.appendingPathComponent("unsupported-clean.actions")
            let unsupportedStore = ScanStore(removalLogURL: root.appendingPathComponent("unsupported-clean"),
                                             actionJournal: ActionJournal(url: unsupportedJournal))
            let unsupportedResult = await unsupportedStore.clean([advice], proEnabled: true)
            check(unsupportedResult.failed == 1 && !fm.fileExists(atPath: unsupportedJournal.path),
                  "Advice-only findings stop before journal or file work")
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
            let replaceable = root.appendingPathComponent("replaceable.bin")
            try Data("old candidate".utf8).write(to: replaceable)
            let scanned = ScanItem(url: replaceable, allocatedSize: 13, categoryID: "fixture", severity: .safe)
            let originalIdentity = scanned.sourceIdentity
            let appOrHealthSnapshot = SourceSnapshot.read(replaceable)
            try fm.moveItem(at: replaceable, to: root.appendingPathComponent("old-candidate.bin"))
            try Data("new important content".utf8).write(to: replaceable)
            let replaced = Cleaner.clean(scanned, allowedRoots: [root], proEnabled: true)
            check(originalIdentity != nil && !replaced.ok && replaced.error?.contains("changed since scanning") == true,
                  "Reviewed Trash action refuses a different inode at the same path")
            check(try Data(contentsOf: replaceable) == Data("new important content".utf8), "Replacement content remains untouched")
            check(appOrHealthSnapshot != nil && appOrHealthSnapshot?.matches(replaceable) == false,
                  "App and health review snapshots refuse a new object at the same path")
            let intentURL = root.appendingPathComponent("fixture-action-journal.json")
            let intentJournal = ActionJournal(url: intentURL)
            check(intentJournal.prepare(), "Fresh action journal permits an isolated fixture")
            let pendingID = intentJournal.begin(path: replaceable.path, category: "fixture")
            check(pendingID != nil, "Intent is durable before a filesystem action")
            let journalDirectoryMode = (try fm.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber)?.intValue
            let journalFileMode = (try fm.attributesOfItem(atPath: intentURL.path)[.posixPermissions] as? NSNumber)?.intValue
            check(journalDirectoryMode == 0o700 && journalFileMode == 0o600,
                  "Action journal directory and file are private after atomic save")
            let interruptedJournal = ActionJournal(url: intentURL)
            check(!interruptedJournal.prepare() && interruptedJournal.recent.first?.state == .pending,
                  "Relaunch sees uncertain intent and blocks replay")
            if let pendingID {
                check(intentJournal.finish(pendingID, succeeded: false, trashPath: nil, detail: "fixture refused"),
                      "Failure outcome is durably recorded")
            }
            check(ActionJournal(url: intentURL).prepare(), "Completed failure no longer blocks unrelated reviewed work")
            let reviewURL = root.appendingPathComponent("review-action-journal.json")
            let reviewJournal = ActionJournal(url: reviewURL)
            let reviewID = reviewJournal.begin(path: replaceable.path, category: "fixture")
            let restartedReview = ActionJournal(url: reviewURL)
            check(reviewID != nil && !restartedReview.prepare(), "Interrupted action remains blocked after relaunch")
            if let reviewID {
                check(restartedReview.acknowledgeManualReview(reviewID), "Explicit manual review persists without replay")
            }
            let afterReview = ActionJournal(url: reviewURL)
            check(afterReview.prepare() && afterReview.recent.first?.state == .reviewed &&
                  afterReview.recent.first?.detail?.contains("unknown") == true,
                  "Reviewed uncertainty remains visible while new reviewed work can proceed")
            if let reviewID {
                check(!reviewJournal.finish(reviewID, succeeded: true, trashPath: nil) &&
                      ActionJournal(url: reviewURL).recent.first?.state == .reviewed,
                      "Stale process cannot overwrite a manually reviewed uncertain action")
            }
            let fullReviewURL = root.appendingPathComponent("full-reviewed-journal.json")
            let uncertainEntries = (0..<512).map { _ in
                ActionJournal.Entry(id: UUID(), date: Date(), path: replaceable.path,
                                    category: "fixture", state: .reviewed, trashPath: nil,
                                    detail: "Outcome unknown")
            }
            let fullReviewData = try JSONEncoder().encode(FixtureActionArchive(version: 1, entries: uncertainEntries))
            try fullReviewData.write(to: fullReviewURL)
            let fullReviewJournal = ActionJournal(url: fullReviewURL)
            let initiallyReviewable = fullReviewJournal.prepare()
            let refusedNewAction = fullReviewJournal.begin(path: replaceable.path, category: "fixture") == nil
            let preservedReviewData = try Data(contentsOf: fullReviewURL)
            check(initiallyReviewable && refusedNewAction && preservedReviewData == fullReviewData,
                  "Full journal blocks cleanup rather than discarding reviewed uncertain actions")
            let corruptIntent = root.appendingPathComponent("corrupt-action-journal.json")
            let keepIntent = Data("preserve corrupt intent".utf8)
            try keepIntent.write(to: corruptIntent)
            let corruptActionBlocked = !ActionJournal(url: corruptIntent).prepare()
            let corruptIntentPreserved = try Data(contentsOf: corruptIntent) == keepIntent
            check(corruptActionBlocked && corruptIntentPreserved,
                  "Corrupt action journal is retained and blocks mutation")
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
            check(!(await history.prepareRemovalLog()), "Corrupt recovery history blocks new removal")
            check(try Data(contentsOf: corrupt) == corruptBytes, "Corrupt recovery history is not overwritten")
            let transferHistory = StorageTransferStore(journal: corrupt)
            transferHistory.load()
            check(transferHistory.message.contains("not be overwritten"), "Corrupt transfer journal is surfaced")
            let fakeDrive = StorageDrive(url: root, name: "Fixture", uuid: "fixture", capacity: 1_000_000_000, available: 500_000_000, external: true, writable: true, encrypted: true, format: "apfs")
            transferHistory.start(source: source, drive: fakeDrive)
            check(try !transferHistory.busy && Data(contentsOf: corrupt) == corruptBytes, "Transfer does not overwrite corrupt journal or begin copying")
            let oversized = root.appendingPathComponent("oversized-transfer-history.json")
            let oversizedBytes = Data(repeating: 0x58, count: 4 * 1024 * 1024 + 1)
            try oversizedBytes.write(to: oversized)
            let oversizedHistory = StorageTransferStore(journal: oversized)
            oversizedHistory.load()
            check(oversizedHistory.message.contains("too large") && oversizedHistory.records.isEmpty,
                  "Oversized transfer history reports its limit without loading records")
            let exportsBefore = try fm.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix("Cairn Export ") }
            oversizedHistory.start(source: source, drive: fakeDrive)
            let exportsAfter = try fm.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix("Cairn Export ") }
            check(try !oversizedHistory.busy && exportsAfter == exportsBefore &&
                  Data(contentsOf: oversized) == oversizedBytes && Data(contentsOf: source) == content,
                  "Oversized transfer history blocks export and preserves journal and source bytes")
            let danglingJournal = root.appendingPathComponent("dangling-transfer-history.json")
            let absentTarget = root.appendingPathComponent("absent-transfer-history.json")
            try fm.createSymbolicLink(at: danglingJournal, withDestinationURL: absentTarget)
            let linkedHistory = StorageTransferStore(journal: danglingJournal)
            linkedHistory.load()
            linkedHistory.start(source: source, drive: fakeDrive)
            check(try !linkedHistory.busy && linkedHistory.message.contains("ordinary file") &&
                  fm.destinationOfSymbolicLink(atPath: danglingJournal.path) == absentTarget.path &&
                  !fm.fileExists(atPath: absentTarget.path),
                  "Dangling transfer-history link blocks export and leaves its target untouched")

            let journal = root.appendingPathComponent("recovery.json"), trash = root.appendingPathComponent(".Trash")
            try fm.createDirectory(at: trash, withIntermediateDirectories: false)
            let trashed = trash.appendingPathComponent("restore-me.zip"), original = root.appendingPathComponent("restored.zip")
            try Data("restore fixture".utf8).write(to: trashed)
            let record = ScanStore.RemovalLogEntry(name: "Fixture", originalPath: original.path, trashPath: trashed.path, bytes: 15, date: Date(), category: "fixture")
            let recovery = ScanStore(removalLogURL: journal, restoreFile: { from, to in
                guard Cleaner.canRestore(from: from, to: to, trashRoots: [trash]) else { return false }
                return renamex_np(from.path, to.path, UInt32(RENAME_EXCL)) == 0
            }, recordRestoredBytes: { _ in })
            check(await recovery.appendRemovals([record]), "Fixture recovery entry saved")
            try Data("existing original".utf8).write(to: original)
            check(!(await recovery.restoreFromLog(record)), "Restore refuses to overwrite existing original")
            check(try Data(contentsOf: original) == Data("existing original".utf8), "Failed restore preserves existing original")
            try fm.removeItem(at: original)
            check(await recovery.restoreFromLog(record), "Fixture can be restored without overwriting")
            check(recovery.removalLog.count == 1 && recovery.removalLog[0].restoredAt != nil && !recovery.removalLog[0].recoverable, "Successful restore keeps a non-actionable history record")
            let reloaded = ScanStore(removalLogURL: journal, recordRestoredBytes: { _ in })
            await reloaded.loadRemovalLog()
            check(reloaded.removalLog.first?.restoredAt != nil, "Restored status survives relaunch")
            // Concurrent callers must merge against the actor's current history,
            // not overwrite one another with stale UI snapshots.
            let bulk = RecoveryHistory(url: root.appendingPathComponent("bulk-recovery.json"))
            let makeRecords: (Int) -> [ScanStore.RemovalLogEntry] = { offset in
                (offset..<(offset + 6_000)).map { index in
                    .init(name: "Fixture \(index)", originalPath: "/fixture/\(index)", trashPath: nil,
                          bytes: 1, date: Date(), category: "fixture")
                }
            }
            let batchA = makeRecords(0), batchB = makeRecords(6_000)
            var recoveryHeartbeats = 0
            var recoveryMaxGap: TimeInterval = 0
            let heartbeat = Task { @MainActor in
                var last = ProcessInfo.processInfo.systemUptime
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(10))
                    let now = ProcessInfo.processInfo.systemUptime
                    recoveryMaxGap = max(recoveryMaxGap, now - last)
                    last = now; recoveryHeartbeats += 1
                }
            }
            async let appendedA = bulk.append(batchA)
            async let appendedB = bulk.append(batchB)
            let pair = await (appendedA, appendedB)
            let bulkResult = await bulk.load()
            check(pair.0.error == nil && pair.1.error == nil && bulkResult.entries.count == 12_000,
                  "Concurrent background history appends preserve both batches")
            let bulkReload = await RecoveryHistory(url: root.appendingPathComponent("bulk-recovery.json")).load()
            check(bulkReload.entries.count == 12_000 && bulkReload.error == nil,
                  "Large background recovery history round-trips without lost records")
            heartbeat.cancel(); await heartbeat.value
            check(recoveryHeartbeats > 0 && recoveryMaxGap < 1,
                  "Main actor remains responsive during large recovery history writes")
            print("RECOVERY HISTORY: 12,000 records; \(recoveryHeartbeats) heartbeats; largest gap \(recoveryMaxGap)s")
            var conflicting = batchA[0]
            conflicting = .init(id: conflicting.id, name: "Replacement", originalPath: "/wrong-source", trashPath: nil,
                                bytes: 1, date: Date(), category: "fixture")
            let conflict = await bulk.append([conflicting])
            check(conflict.error != nil && conflict.entries.count == 12_000,
                  "Conflicting recovery identity is refused without losing history")
            // Simulate a crash after the per-action outcome persisted, before
            // the separate Put Back history callback could run. No Trash API runs.
            let gapJournal = ActionJournal(url: root.appendingPathComponent("gap-actions.json"))
            let gapTrash = trash.appendingPathComponent("gap.zip")
            let gapOriginal = root.appendingPathComponent("gap-original.zip")
            try Data("gap fixture".utf8).write(to: gapTrash)
            let gapID = gapJournal.begin(path: gapOriginal.path, category: "fixture", affectedBytes: 11)!
            check(gapJournal.finish(gapID, succeeded: true, trashPath: gapTrash.path), "Outcome persists its Trash identity before Put Back callback")
            let gapLogURL = root.appendingPathComponent("gap-recovery.json")
            let gapStore = ScanStore(removalLogURL: gapLogURL, actionJournal: gapJournal, recordRestoredBytes: { _ in })
            check(await gapStore.reconcileActionJournal(), "Successful journal outcome rebuilds missing Put Back metadata")
            check(gapStore.removalLog.count == 1 && gapStore.removalLog[0].id == gapID && gapStore.removalLog[0].trashIdentity != nil,
                  "Recovered receipt retains exact action and Trash identities")
            check(await gapStore.reconcileActionJournal(), "Reconciliation is idempotent")
            check(gapStore.removalLog.count == 1 && gapJournal.recent.first?.recoveryRecorded == true,
                  "Journal is linked only after recovery metadata is saved")
            try fm.moveItem(at: gapTrash, to: trash.appendingPathComponent("old-gap.zip"))
            try Data("different important content".utf8).write(to: gapTrash)
            check(!(await gapStore.restoreFromLog(gapStore.removalLog[0])), "Put Back rejects a replaced Trash inode")
            check(try Data(contentsOf: gapTrash) == Data("different important content".utf8), "Replacement Trash contents remain untouched")
            let gapRestoreID = gapJournal.begin(path: gapTrash.path, category: "restore", affectedBytes: 11, actionKind: "restore", relatedRecoveryID: gapID, destinationPath: gapOriginal.path)!
            check(gapJournal.finish(gapRestoreID, succeeded: true, trashPath: nil), "Synthetic completed-restore receipt persists")
            check(await gapStore.reconcileActionJournal(), "Completed restore reconciles after a lost history update")
            check(gapStore.removalLog.first?.restoredAt != nil, "A reconciled restore cannot be offered again")
            check(!fm.fileExists(atPath: gapOriginal.path), "Reconciliation never replays filesystem operations")
            try corruptBytes.write(to: journal)
            check(try !(await reloaded.prepareRemovalLog()) && Data(contentsOf: journal) == corruptBytes, "External history change is not overwritten")
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
