import Foundation
import Darwin

/// Every filesystem write is contained in this disposable fixture directory.
/// The volume provider and clocks are injected; no personal roots are observed.
enum EvidenceCheck {
    private final class EventResult: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var received: Bool { lock.withLock { value } }
        func mark(_ received: Bool) { lock.withLock { value = value || received } }
    }
    static func run() async {
        var failures = 0
        func check(_ good: Bool, _ name: String) {
            print("\(good ? "PASS" : "FAIL") \(name)"); if !good { failures += 1 }
        }
        let fm = FileManager.default
        let base = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("cairn-evidence-check-\(UUID().uuidString)")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        struct Injected: Error {}
        var schedule = DirtyLocationSchedule(rootIDs: ["a", "b"])
        for index in 0..<10_000 { schedule.mark(["a", "unknown"], at: now.addingTimeInterval(Double(index))) }
        check(schedule.pending.count == 1 && schedule.ready(at: now.addingTimeInterval(10_000), suspended: false).isEmpty, "Event storm stays bounded and waits for a quiet window")
        let quiet = now.addingTimeInterval(10_060)
        check(schedule.ready(at: quiet, suspended: false) == ["a"], "Quiet folder becomes eligible")
        check(schedule.ready(at: quiet, suspended: true).isEmpty, "Pressure or pause prevents background work")
        let revision = schedule.begin("a", at: quiet)!
        schedule.mark(["a"], at: quiet.addingTimeInterval(1))
        schedule.finish("a", revision: revision, complete: true)
        check(schedule.pending.count == 1, "Event arriving during traversal survives completion")
        check(schedule.ready(at: quiet.addingTimeInterval(899), suspended: false).isEmpty, "Repeated writes cannot bypass fifteen-minute interval")
        let next = quiet.addingTimeInterval(901)
        let revision2 = schedule.begin("a", at: next)!
        schedule.finish("a", revision: revision2, complete: false)
        check(schedule.ready(at: next.addingTimeInterval(899), suspended: false).isEmpty, "Incomplete traversal backs off")
        schedule.reconcile(at: next)
        check(schedule.pending.count == 2, "Dropped events and restart mark every covered root pending")
        let urgent = CapacityReading(date: now, volumeID: "a", available: 1_000_000_000, total: 500_000_000_000)
        check(ReserveAlertPolicy.decide(current: urgent, previous: nil, target: 30_000_000_000, alreadyAlerted: true, urgentAlreadyAlerted: false) == .alert, "Urgent low-space crossing can escalate once without a second sample")
        check(ReserveAlertPolicy.decide(current: urgent, previous: nil, target: 30_000_000_000, alreadyAlerted: true, urgentAlreadyAlerted: true) == .unchanged, "Urgent alert remains suppressed after delivery attempt")
        let low = CapacityReading(date: now, volumeID: "a", available: 12_000_000_000, total: 500_000_000_000)
        let staleLow = CapacityReading(date: now.addingTimeInterval(-86_400), volumeID: "a", available: 12_000_000_000, total: 500_000_000_000)
        check(ReserveAlertPolicy.decide(current: low, previous: staleLow, target: 30_000_000_000, alreadyAlerted: false) == .unchanged, "A long offline gap cannot serve as a confirming low-space sample")
        fastDropChecks(check)
        let gate = ScanGate()
        check(gate.tryAcquireForMonitoring(), "Idle gate admits one background traversal")
        check(!gate.tryAcquireForMonitoring(), "Busy gate never queues repeated background jobs")
        gate.release()

        do {
            try fm.createDirectory(at: base, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: base) }
            let folder = base.appendingPathComponent("measured")
            try fm.createDirectory(at: folder, withIntermediateDirectories: false)
            let file = folder.appendingPathComponent("data")
            try Data(repeating: 7, count: 8_192).write(to: file)
            let root = ObservedRoot(id: "fixture", title: "Fixture", path: folder.path, icon: "folder", observationOnly: true)
            var probe = LocationProbe(now: { now }, volume: { _ in .init(id: "fixture-volume", internalVolume: true) })
            let first = probe.measure(root, exclusions: [], source: "fixture", cancelled: { false })
            check(first.coverage == .complete && first.logical == 8_192 && first.valid, "Metadata-only baseline is complete and typed")
            let planCapacity = CapacityReading(date: now, volumeID: "fixture-volume", available: 12_000_000_000, total: 500_000_000_000)
            let planItem = ScanItem(url: file, allocatedSize: first.allocated ?? 0, categoryID: "fixture", severity: .safe)
            var plan = ReviewedSpacePlan.capture(items: [planItem], capacity: planCapacity, target: 30_000_000_000,
                scanStarted: now.addingTimeInterval(-60), exclusions: [], fullDiskAccess: false, developerCaches: true, simulators: true,
                now: now, volume: { _ in "fixture-volume" })
            check(plan != nil && plan?.expectedImmediateReclaim == (RemovalMode.current.deletesImmediately(planItem) ? planItem.allocatedSize : 0) && plan?.matchesSource(planItem) == true, "Reviewed plan binds source metadata and credits reclaim only for deletions")
            check(plan?.invalidReason(itemIDs: [planItem.id], scanStarted: now.addingTimeInterval(-60), exclusions: ["/new-exclusion"], fullDiskAccess: false, developerCaches: true, simulators: true, capacity: planCapacity, now: now) != nil, "Changed exclusions invalidate reviewed plan")
            check(plan?.invalidReason(itemIDs: [UUID()], scanStarted: now.addingTimeInterval(-60), exclusions: [], fullDiskAccess: false, developerCaches: true, simulators: true, capacity: planCapacity, now: now) != nil, "Reviewed plan cannot substitute another selection")
            check(plan?.invalidReason(itemIDs: [planItem.id], scanStarted: now.addingTimeInterval(-60), exclusions: [], fullDiskAccess: false, developerCaches: true, simulators: true, capacity: planCapacity, now: now.addingTimeInterval(901)) != nil, "Consent scope expires after fifteen minutes")
            check(SpaceGoalState.evaluate(current: planCapacity, target: 600_000_000_000, now: now) == .impossible, "Target beyond capacity is impossible without a cleanup recommendation")
            check(SpaceGoalState.evaluate(current: planCapacity, target: 10_000_000_000, now: now) == .met, "Already-met goal offers no unnecessary action")
            check(SpaceGoalState.evaluate(current: planCapacity, target: 30_000_000_000, now: now.addingTimeInterval(601)) == .unavailable, "Old capacity cannot claim current goal progress")
            try fm.linkItem(at: file, to: folder.appendingPathComponent("hard-link"))
            let hardLinkItem = ScanItem(url: folder.appendingPathComponent("hard-link"), allocatedSize: first.allocated ?? 0, categoryID: "fixture", severity: .safe)
            check(MakeRoomCandidates.select([planItem, hardLinkItem], isExcluded: { _ in false }).count == 1, "Planner never counts hard-linked findings twice")
            let linked = probe.measure(root, exclusions: [], source: "fixture", cancelled: { false })
            check(linked.logical == first.logical && linked.allocated == first.allocated && linked.hardLinksSkipped == 1, "Hard links count once within a root")
            try fm.createSymbolicLink(at: folder.appendingPathComponent("outside-link"), withDestinationURL: base)
            let symlink = probe.measure(root, exclusions: [], source: "fixture", cancelled: { false })
            check(symlink.coverage == .complete && symlink.logical == first.logical, "Symlinks never expand metadata scope")
            let parentAlias = base.appendingPathComponent("alias")
            try fm.createSymbolicLink(at: parentAlias, withDestinationURL: base)
            let aliasRoot = ObservedRoot(id: "alias", title: "Alias", path: parentAlias.appendingPathComponent("measured").path, icon: "folder", observationOnly: true)
            check(probe.measure(aliasRoot, exclusions: [], source: "fixture", cancelled: { false }).coverage == .unavailable, "Symlink ancestors cannot redirect a measurement")
            let childRoot = ObservedRoot(id: "child", title: "Child", path: folder.appendingPathComponent("nested").path, icon: "folder", observationOnly: true)
            check(ObservedRoot.nonOverlapping([childRoot, root, root]).count == 1, "Overlapping roots are observed only once")
            probe.now = { now.addingTimeInterval(10) }
            plan = ReviewedSpacePlan.capture(items: [planItem], capacity: planCapacity, target: 30_000_000_000,
                scanStarted: now.addingTimeInterval(-60), exclusions: [], fullDiskAccess: false, developerCaches: true, simulators: true,
                now: now, volume: { _ in "fixture-volume" })
            check(plan?.matchesSource(planItem) == true, "Reviewed source is valid immediately before content-change fixture")
            try Data(repeating: 8, count: 16_384).write(to: file, options: [])
            check(plan?.matchesSource(planItem) == false, "Same-inode contents changed after review are rejected")
            let later = probe.measure(root, exclusions: [], source: "fixture", cancelled: { false })
            let changes = LocationComparison.changes([first, later])
            check(changes.count == 1 && changes[0].delta == (later.allocated! - first.allocated!), "Compatible root delta uses exact interval and allocated metric")
            probe.maxEntries = 1
            let limited = probe.measure(root, exclusions: [], source: "fixture", cancelled: { false })
            check(limited.coverage == .limited && LocationComparison.changes([first, limited]).isEmpty, "Entry budget reports partial evidence instead of false decline")
            probe.maxEntries = 100_000; probe.seconds = 0
            check(probe.measure(root, exclusions: [], source: "fixture", cancelled: { false }).coverage == .limited, "Time budget stops before traversal")
            probe.seconds = 30
            let cancelled = probe.measure(root, exclusions: [], source: "fixture", cancelled: { true })
            check(cancelled.coverage == .cancelled && cancelled.allocated == nil, "Cancelled observation is not zero")
            let excluded = probe.measure(root, exclusions: [folder.path], source: "fixture", cancelled: { false })
            check(excluded.coverage == .excluded && excluded.allocated == nil, "Excluded root is never traversed")
            let partiallyExcluded = probe.measure(root, exclusions: [file.path], source: "fixture", cancelled: { false })
            check(partiallyExcluded.coverage == .partial && LocationComparison.changes([first, partiallyExcluded]).isEmpty, "Changed exclusions cannot fabricate a compatible comparison")
            probe.volume = { _ in .init(id: "different-volume", internalVolume: true) }
            let otherVolume = probe.measure(root, exclusions: [], source: "fixture", cancelled: { false })
            check(LocationComparison.changes([first, otherVolume]).isEmpty, "Another volume cannot inherit root history")
            probe.volume = { _ in .init(id: "external", internalVolume: false) }
            check(probe.measure(root, exclusions: [], source: "fixture", cancelled: { false }).coverage == .unavailable, "Unapproved external volume is not measured")
            probe.volume = { _ in .init(id: "fixture-volume", internalVolume: true) }
            try fm.moveItem(at: folder, to: base.appendingPathComponent("retained-original"))
            let absent = probe.measure(root, exclusions: [], source: "fixture", cancelled: { false })
            check(absent.coverage == .absent && absent.allocated == 0 && LocationComparison.changes([first, absent]).count == 1, "Verified parent and absent entry can prove zero")
            try fm.createDirectory(at: folder, withIntermediateDirectories: false)
            let replaced = probe.measure(root, exclusions: [], source: "fixture", cancelled: { false })
            check(LocationComparison.changes([first, replaced]).isEmpty, "Recreated directory identity starts a new baseline")
            let missingParentRoot = ObservedRoot(id: "missing", title: "Missing", path: base.appendingPathComponent("missing-parent/child").path, icon: "folder", observationOnly: true)
            let missing = probe.measure(missingParentRoot, exclusions: [], source: "fixture", cancelled: { false })
            check(missing.coverage == .unavailable && missing.allocated == nil, "Missing parent cannot prove zero for its child")
            check(LocationComparison.changes([first, later, missing]).count == 1, "Unavailable root preserves independent compatible subset")

            let eventResult = EventResult()
            if let watcher = LocationEventWatcher(roots: [root], deliver: { ids, _ in eventResult.mark(ids.contains("fixture")) }) {
                try Data("event fixture".utf8).write(to: folder.appendingPathComponent("event"))
                for _ in 0..<12 {
                    if eventResult.received { break }
                    try await Task.sleep(for: .seconds(1))
                }
                watcher.stop()
                check(eventResult.received, "Live FSEvents delivers bounded dirty-root hint for a disposable write")
            } else { check(false, "Disposable event watcher starts") }

            let legacy = base.appendingPathComponent("history.json")
            let capacity = CapacityReading(date: now, volumeID: "fixture-volume", available: 12_000_000_000, total: 500_000_000_000)
            let legacyBytes = try JSONEncoder().encode(StorageEvidenceStore.LegacyArchive(version: 1, capacity: [capacity], candidates: []))
            try legacyBytes.write(to: legacy)
            let dbURL = base.appendingPathComponent("store/history.sqlite")
            let interrupted = StorageEvidenceStore(url: dbURL, legacyURL: legacy, now: { now }, failure: { phase in if phase == "after-import" { throw Injected() } })
            do { _ = try await interrupted.load(); check(false, "Interrupted import refuses completion") }
            catch { check(true, "Interrupted import refuses completion") }
            check(try Data(contentsOf: legacy) == legacyBytes, "Import never modifies original history")
            let store = StorageEvidenceStore(url: dbURL, legacyURL: legacy, now: { now })
            let loaded = try await store.load()
            check(loaded.capacity.map(\.id) == [capacity.id], "Interrupted import retries transaction without missing or duplicate records")
            let saved = try await store.append(locations: [first, later, missing])
            check(saved.locations.count == 3 && LocationComparison.changes(saved.locations).count == 1, "SQLite round-trip preserves coverage and root evidence")
            let reloaded = try await store.load()
            check(reloaded.capacity.count == 1 && reloaded.sequence > loaded.sequence, "Repeated load does not repeat legacy import")
            let failedWrite = StorageEvidenceStore(url: dbURL, legacyURL: legacy, now: { now }, failure: { phase in if phase == "before-append" { throw Injected() } })
            do { _ = try await failedWrite.append(capacity: .init(date: now.addingTimeInterval(60), volumeID: "fixture-volume", available: 20, total: 100)); check(false, "Full-disk style write failure is surfaced") }
            catch { check(true, "Full-disk style write failure is surfaced") }
            let afterFailure = try await store.load()
            check(afterFailure.capacity.count == 1 && afterFailure.locations.count == 3, "Failed write preserves prior history")
            let permission = try fm.attributesOfItem(atPath: dbURL.path)[.posixPermissions] as? NSNumber
            check(permission?.intValue == 0o600, "Evidence database remains private")
            let old = CapacityReading(date: now.addingTimeInterval(-91 * 86_400), volumeID: "fixture-volume", available: 5, total: 100)
            let trimmed = try await store.append(capacity: old)
            check(trimmed.capacity.count == 1, "Expired observations prune without changing legacy file")
            // A place that rarely changes keeps its last size while a busy one is
            // measured over and over: the fast-drop check compares with it.
            let perRoot = StorageEvidenceStore(url: base.appendingPathComponent("per-root/history.sqlite"), legacyURL: legacy, now: { now })
            _ = try await perRoot.append(locations: [fixtureReading("quiet", 4_000_000_000, at: now.addingTimeInterval(-3_600))])
            for batch in 0..<2 {
                var busy: [LocationReading] = []
                for index in 0..<30 {
                    let step: Int = batch * 30 + index
                    let size: Int64 = Int64(1_000 + step)
                    let when: Date = now.addingTimeInterval(TimeInterval(step - 60))
                    busy.append(fixtureReading("busy", size, at: when))
                }
                _ = try await perRoot.append(locations: busy)
            }
            let perRootLoaded = try await perRoot.load()
            check(perRootLoaded.locations.filter { $0.root.id == "quiet" }.count == 1 &&
                  perRootLoaded.locations.filter { $0.root.id == "busy" }.count == StorageEvidenceStore.readingsPerLocation,
                  "Each place keeps its own recent readings; a busy place cannot push out a quiet one")
            let invalidLegacy = base.appendingPathComponent("invalid.json")
            try Data("invalid-history".utf8).write(to: invalidLegacy)
            let badStore = StorageEvidenceStore(url: base.appendingPathComponent("bad/history.sqlite"), legacyURL: invalidLegacy, now: { now })
            do { _ = try await badStore.load(); check(false, "Corrupt legacy history blocks migration") }
            catch { check(try Data(contentsOf: invalidLegacy) == Data("invalid-history".utf8), "Corrupt legacy history is preserved and blocks migration") }
        } catch { check(false, "Fixture error: \(error.localizedDescription)") }
        print("Evidence checks: \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }

    static func fixtureReading(_ id: String, _ bytes: Int64, at date: Date, volume: String = "fixture-volume",
                               coverage: LocationCoverage = .complete) -> LocationReading {
        let root = ObservedRoot(id: id, title: id == "docker-disk" ? "Docker disk" : id, path: "/fixture/" + id, icon: "folder", observationOnly: true)
        return LocationReading(id: UUID(), root: root, started: date.addingTimeInterval(-1), ended: date, volumeID: volume,
            identity: .init(device: 1, inode: 2), parentIdentity: .init(device: 1, inode: 1), scope: "fixture-scope",
            coverage: coverage, allocated: bytes, logical: bytes, entries: 3, hardLinksSkipped: 0, source: "fixture",
            metric: "allocated-and-logical-v1", adapterVersion: 1)
    }

    /// Pure checks of the fast-drop alert and the wider watch list. No disk access.
    static func fastDropChecks(_ check: (Bool, String) -> Void) {
        let t0 = Date(timeIntervalSince1970: 1_900_000_000)
        let gb: Int64 = 1_000_000_000
        func reading(_ minutes: Double, _ available: Double, volume: String = "a") -> CapacityReading {
            CapacityReading(date: t0.addingTimeInterval(minutes * 60), volumeID: volume, available: Int64(available * 1e9), total: 500 * gb)
        }
        let steady = [reading(0, 60), reading(5, 58), reading(10, 56)]
        let fast = FastDropPolicy.detect(current: reading(25, 54.5), recent: steady, reserve: nil, lastAlert: nil)
        check(fast?.bytes == Int64(5.5e9) && fast?.interval == 25 * 60, "5 GB or more gone within half an hour is a fast drop")
        check(FastDropPolicy.detect(current: reading(25, 56.5), recent: steady, reserve: nil, lastAlert: nil) == nil,
              "A smaller drop with no reserve close is not an alert")
        check(FastDropPolicy.detect(current: reading(45, 50), recent: [reading(0, 60), reading(20, 51)], reserve: nil, lastAlert: nil) == nil,
              "Space lost before the half-hour window does not count")
        check(FastDropPolicy.detect(current: reading(25, 50), recent: steady.map { reading($0.date.timeIntervalSince(t0) / 60, Double($0.available) / 1e9, volume: "b") }, reserve: nil, lastAlert: nil) == nil,
              "Readings from another disk are never compared")
        check(FastDropPolicy.detect(current: reading(25, 50), recent: steady, reserve: nil, lastAlert: t0.addingTimeInterval(-5 * 60)) == nil,
              "At most one fast-drop alert an hour")
        check(FastDropPolicy.detect(current: reading(25, 50), recent: steady, reserve: nil, lastAlert: t0.addingTimeInterval(-2 * 3_600)) != nil,
              "Alerts again once the hour has passed")
        check(FastDropPolicy.detect(current: reading(0.5, 50), recent: [reading(0, 60)], reserve: nil, lastAlert: nil) == nil,
              "Readings under a minute apart are not compared")
        let close = FastDropPolicy.detect(current: reading(20, 32.5), recent: [reading(0, 35)], reserve: 30 * gb, lastAlert: nil)
        check(close != nil && abs((close?.secondsToReserve ?? 0) - 20 * 60) < 1, "A smaller drop counts when the reserve is near at that rate")
        check(FastDropPolicy.detect(current: reading(20, 29), recent: [reading(0, 31.5)], reserve: 30 * gb, lastAlert: nil) == nil,
              "Below the reserve, the reserve alert speaks instead")
        check(FastDropPolicy.detect(current: reading(5, 32), recent: [reading(0, 34.5)], reserve: 30 * gb, lastAlert: nil) == nil,
              "No forecast from less than ten minutes of readings")

        let drop = fast!
        let before = SystemSignals(date: t0, swapBytes: 2 * gb, snapshotCount: 1)
        let after = SystemSignals(date: t0.addingTimeInterval(25 * 60), swapBytes: 8 * gb, snapshotCount: 3)
        func change(_ id: String, _ from: Int64, _ to: Int64) -> LocationChange {
            LocationChange(before: fixtureReading(id, from, at: t0.addingTimeInterval(-600)), after: fixtureReading(id, to, at: t0.addingTimeInterval(1_500)))
        }
        let report = FastDropReport.make(drop: drop, before: before, after: after,
            changes: [change("docker-disk", 10 * gb, 14 * gb), change("npm-cache", gb, gb + 200_000_000), change("xcode-build", 9 * gb, 8 * gb)],
            reserve: nil, note: nil, now: t0.addingTimeInterval(25 * 60))
        check(report.growers.map(\.id) == ["swap", "docker-disk", "snapshots"],
              "Report names what grew, biggest first, and leaves out small or shrinking places")
        let opening: String = Fmt.size(Int64(5.5e9)) + " less free space in 25 minutes."
        let swapPhrase: String = FastDropReport.swapTitle + " grew by " + Fmt.size(6 * gb)
        let dockerPhrase: String = "Docker disk grew by " + Fmt.size(4 * gb)
        let body: String = report.body
        check(body.hasPrefix(opening) && body.contains(swapPhrase) && body.contains(dockerPhrase) &&
              body.contains("2 new local Time Machine snapshots appeared"),
              "Notification says how much went, how fast, and what grew")
        let quiet = FastDropReport.make(drop: drop, before: before, after: before, changes: [], reserve: nil, note: nil)
        check(quiet.growers.isEmpty && quiet.body.contains("somewhere Cairn doesn't watch"),
              "When nothing watched grew, the notification says so instead of guessing")
        let busy = FastDropReport.make(drop: drop, before: before, after: before, changes: [], reserve: nil, note: "Cairn was busy.")
        check(!busy.body.contains("somewhere Cairn doesn't watch") && busy.body.hasSuffix("Cairn was busy."),
              "A skipped folder check is not reported as nothing having grown")
        let near = FastDropReport.make(drop: close!, before: nil, after: nil, changes: [], reserve: 30 * gb, note: nil)
        let reservePhrase: String = "reach your " + Fmt.size(30 * gb) + " reserve in about 20 minutes"
        check(near.body.contains(reservePhrase), "Report says when the reserve is close")
        let decoded = try? JSONDecoder().decode(FastDropReport.self, from: (try? JSONEncoder().encode(report)) ?? Data())
        check(decoded == report, "The last report survives a restart")
        let oneMinute: String = FastDropReport.spoken(60)
        let twoHours: String = FastDropReport.spoken(95 * 60)
        let joined: String = FastDropReport.list(["a", "b", "c"])
        check(oneMinute == "1 minute" && twoHours == "2 hours" && joined == "a, b and c", "Durations and lists read naturally")

        let catalogue = ObservedRoot.catalogue(home: URL(fileURLWithPath: "/Users/fixture"))
        let ids = catalogue.map(\.id)
        let added = ["simulators", "ollama-models", "huggingface", "lmstudio-models", "docker-disk", "orbstack-disk",
                     "colima-disk", "claude-data", "cursor-worktrees", "conductor-workspaces"]
        check(Set(ids).count == ids.count && Set(added).isSubset(of: Set(ids)) && ids.count <= 32,
              "Watch list covers the fast growers, once each, within the watcher's limit")
        check(ObservedRoot.nonOverlapping(catalogue).count == catalogue.count, "No watched place sits inside another")
        let withoutAccess = Set(ObservedRoot.measurable(fullDiskAccess: false, home: URL(fileURLWithPath: "/Users/fixture")).map(\.id))
        check(!withoutAccess.contains("docker-disk") && !withoutAccess.contains("orbstack-disk") && withoutAccess.contains("claude-data") &&
              ObservedRoot.measurable(fullDiskAccess: true, home: URL(fileURLWithPath: "/Users/fixture")).count == catalogue.count,
              "Other apps' containers are only measured with Full Disk Access")
        let protectedIDs = ["docker-disk", "orbstack-disk", "colima-disk", "claude-data", "cursor-worktrees", "conductor-workspaces"]
        check(catalogue.filter { protectedIDs.contains($0.id) }.allSatisfy(\.observationOnly) &&
              Set(protectedIDs).isDisjoint(with: GrowthSuggestions.selectableIDs),
              "Protected places are watch-only and never become suggestions")
        check(catalogue.filter { ["claude-data", "cursor-worktrees"].contains($0.id) }.allSatisfy { SafePaths.protectedSessionReason($0.url) != nil },
              "Watching Claude Code data and worktrees leaves their protection in place")
        check(FastDropPolicy.ordered(catalogue).first?.id == "docker-disk" && FastDropPolicy.ordered(catalogue).count == catalogue.count,
              "Quick places are measured first and every place is included")
        check(SystemSignals.swapTotal() != nil, "macOS reports the size of swap")
    }
}
