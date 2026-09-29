import Foundation

/// Isolated fixtures only; no real user data, drives or settings are changed.
enum WorkspaceCheck {
    static func run() {
        var failures = 0
        func check(_ good: Bool, _ label: String) { print("\(good ? "PASS" : "FAIL") \(label)"); if !good { failures += 1 } }
        let today = Calendar.current.startOfDay(for: Date())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let oldDay = Calendar.current.date(byAdding: .day, value: -8, to: today)!
        let history = [StorageHistory.Sample(date: yesterday, freeBytes: 20_000_000_000)]
        check(MenuStorageSummary.change(current: nil, samples: history).contains("still building"), "Missing capacity does not become zero space")
        check(MenuStorageSummary.change(current: 10_000_000_000, samples: history).contains("less since yesterday"), "Menu growth uses a prior calendar day")
        check(MenuStorageSummary.change(current: 30_000_000_000, samples: history).contains("more since yesterday"), "Menu free-space increase keeps its direction")
        check(!MenuStorageSummary.change(current: 10_000_000_000, samples: [.init(date: oldDay, freeBytes: 20_000_000_000)]).contains("yesterday"), "Older history is not labelled yesterday")
        check(MenuStorageSummary.change(current: 10_000_000_000, samples: [.init(date: today, freeBytes: 20_000_000_000)]).contains("still building"), "Same-day history does not invent a daily change")
        check(MenuScanStatus().canStart, "Idle menu allows an explicit scan")
        check(!MenuScanStatus(scanning: true).canStart && !MenuScanStatus(operationBusy: true).canStart && !MenuScanStatus(otherScanBusy: true).canStart, "Menu blocks overlapping operations")
        // Scan comparison must never turn missing or incompatible data into savings.
        let scope = ScanComparison.Scope(categories: ["a"], exclusions: [], developerCaches: true,
                                         simulators: true, fullDiskAccess: true, externalVolumes: false)
        let baseline = ScanComparison.Reading(date: Date(timeIntervalSince1970: 100), scope: scope, complete: true,
            buckets: [.init(id: "a", title: "Build output", icon: "hammer", group: .developer, bytes: 100)])
        var later = baseline; later.date = Date(timeIntervalSince1970: 200); later.buckets[0].bytes = 175
        check(ScanComparison.compare([baseline, later]).changes.first?.delta == 75, "Compatible scan growth is measured")
        later.buckets[0].bytes = 60
        check(ScanComparison.compare([baseline, later]).changes.first?.delta == -40, "Category decreases retain their sign")
        later.buckets[0].bytes = 100
        check(ScanComparison.compare([baseline, later]).comparable && ScanComparison.compare([baseline, later]).changes.isEmpty, "Unchanged categories are not invented changes")
        check(!ScanComparison.compare([baseline]).comparable, "First scan waits for a baseline pair")
        later.complete = false
        check(!ScanComparison.compare([baseline, later]).comparable, "Incomplete scans cannot be compared")
        later.complete = true; later.scope.exclusions = ["/example"]
        check(!ScanComparison.compare([baseline, later]).comparable, "Different exclusions block comparison")
        later.scope = scope; later.buckets = []
        check(!ScanComparison.compare([baseline, later]).comparable, "Missing category is not zero bytes")
        later = baseline; later.date = Date(timeIntervalSince1970: 200); later.buckets.append(later.buckets[0])
        check(!ScanComparison.compare([baseline, later]).comparable, "Duplicate saved category IDs are rejected without a crash")
        var limited = baseline; limited.scope.fullDiskAccess = false
        later = limited; later.date = Date(timeIntervalSince1970: 200)
        check(!ScanComparison.compare([limited, later]).comparable, "Limited-access scans do not imply complete coverage")
        var external = baseline; external.scope.externalVolumes = true
        later = external; later.date = Date(timeIntervalSince1970: 200)
        check(!ScanComparison.compare([external, later]).comparable, "External-drive comparisons withheld until drive scope is tracked")
        check(!ScanComparison.compare([baseline, baseline]).comparable, "Equal measurement times cannot be compared")
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("cairn-workspace-check-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: false)
            defer { try? fm.removeItem(at: root) }
            let source = root.appendingPathComponent("export.zip")
            let original = Data((0..<(3 * 1024 * 1024)).map { UInt8($0 % 251) })
            try original.write(to: source)
            let cancel = CancelBox()
            let result = try ArchiveCopy.copy(source: source, directory: root.appendingPathComponent("complete"), cancel: cancel, destinationValid: { true }, progress: { _ in })
            check(try Data(contentsOf: result.0) == original, "Full copy content matches")
            check(try Data(contentsOf: source) == original, "Original retained unchanged")
            check(result.1 == original.count && result.2.count == 64, "Byte count and SHA-256 recorded")
            let permissions = try fm.attributesOfItem(atPath: result.0.path)[.posixPermissions] as? NSNumber
            check(permissions?.intValue == 0o600, "Export has private file permissions")
            let stopped = CancelBox(); stopped.cancel()
            do { _ = try ArchiveCopy.copy(source: source, directory: root.appendingPathComponent("cancelled"), cancel: stopped, destinationValid: { true }, progress: { _ in }); check(false, "Cancelled copy rejected") }
            catch { check(!fm.fileExists(atPath: root.appendingPathComponent("cancelled").path), "Cancelled copy creates no destination") }
            do { _ = try ArchiveCopy.copy(source: source, directory: root.appendingPathComponent("missing-drive"), cancel: cancel, destinationValid: { false }, progress: { _ in }); check(false, "Missing drive rejected") }
            catch { check(true, "Missing or different drive rejected") }
            let link = root.appendingPathComponent("link.zip")
            try fm.createSymbolicLink(at: link, withDestinationURL: source)
            do { try ArchiveCopy.validateSource(link); check(false, "Symbolic link rejected") } catch { check(true, "Symbolic link rejected") }
            let database = root.appendingPathComponent("live.sqlite")
            try Data("database".utf8).write(to: database)
            do { try ArchiveCopy.validateSource(database); check(false, "Database rejected") } catch { check(true, "Database rejected") }
            do { try ArchiveCopy.validateSource(root); check(false, "Directory rejected") } catch { check(true, "Directory rejected") }
            let interrupted = CancelBox()
            let partialDir = root.appendingPathComponent("interrupted")
            do { _ = try ArchiveCopy.copy(source: source, directory: partialDir, cancel: interrupted, destinationValid: { true }, progress: { _ in interrupted.cancel() }); check(false, "Mid-copy cancellation rejected") }
            catch { check(!fm.fileExists(atPath: partialDir.appendingPathComponent("export.zip").path), "Interrupted copy is never marked complete") }
            check(try Data(contentsOf: source) == original, "Cancellation preserves original")
            do { _ = try ArchiveCopy.copy(source: source, directory: root.appendingPathComponent("complete"), cancel: cancel, destinationValid: { true }, progress: { _ in }); check(false, "Existing destination protected") }
            catch { check(try Data(contentsOf: result.0) == original, "Existing destination is never overwritten") }
        } catch { check(false, "Fixture error: \(error.localizedDescription)") }
        print("Workspace checks: \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
