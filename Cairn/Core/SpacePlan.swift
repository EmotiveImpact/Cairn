import Foundation
import Darwin

enum SpaceActionKind: String { case observe, guide, trash, supportedTool, exportCopy, configuredRelocation }
enum SpaceRecovery: String { case notApplicable, trashWhilePresent, sourceRetained, noUndo }

/// Capabilities describe what this build can actually do. Severity alone never
/// creates an executor or turns a size estimate into promised reclaimed bytes.
struct SpaceActionCapability {
    let kind: SpaceActionKind
    let adapter: String
    let version: Int
    let recovery: SpaceRecovery
    let immediateReclaim: Int64
    let consequence: String
    let requirements: String
    let executableAfterReview: Bool

    static func forItem(_ item: ScanItem) -> SpaceActionCapability {
        guard item.severity != .risky, item.sourceIdentity != nil, !item.permissionDenied,
              SafePaths.protectedSessionReason(item.resolvedURL) == nil else {
            return .init(kind: .observe, adapter: "protected-observation", version: 1, recovery: .notApplicable,
                immediateReclaim: 0, consequence: "Protected or incomplete evidence; observation only.", requirements: "No cleanup is offered", executableAfterReview: false)
        }
        switch item.cleanMethod {
        case .trash:
            let deletes = RemovalMode.current.deletesImmediately(item)
            return .init(kind: .trash, adapter: deletes ? "reviewed-delete" : "reviewed-trash", version: 1, recovery: deletes ? .noUndo : .trashWhilePresent,
                immediateReclaim: deletes ? item.allocatedSize : 0,
                consequence: deletes ? (item.isRegenerable ? "Deleted now; rebuilt or downloaded again when needed." : "Deleted now; cannot be put back.")
                                     : "Moved to Trash; space is freed when you delete it from Trash.",
                requirements: "Unchanged source and scan scope; exclusions, contents and running owners checked again", executableAfterReview: true)
        case .tool:
            return .init(kind: .guide, adapter: "tool-guidance", version: 1, recovery: .noUndo,
                immediateReclaim: 0, consequence: "This planner has no certified immediate-reclaim adapter.", requirements: "Review the tool's supported workflow separately", executableAfterReview: false)
        default:
            return .init(kind: .guide, adapter: "manual-review", version: 1, recovery: .notApplicable,
                immediateReclaim: 0, consequence: "No automatic action is offered.", requirements: "Manual review", executableAfterReview: false)
        }
    }
}

enum SpaceGoalState: Equatable {
    case unavailable, met, shortfall(Int64), impossible
    static func evaluate(current: CapacityReading?, target: Int64, now: Date = Date()) -> SpaceGoalState {
        guard let current, target > 0, current.date <= now, now.timeIntervalSince(current.date) <= 10 * 60 else { return .unavailable }
        guard target <= current.total else { return .impossible }
        return current.available >= target ? .met : .shortfall(target - current.available)
    }
}

struct ReviewedSource: Equatable, Sendable {
    let path: String
    let identity: SourceIdentity
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanos: Int64
    let changedSeconds: Int64
    let changedNanos: Int64
    static func read(_ url: URL) -> ReviewedSource? {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        var info = stat()
        guard lstat(resolved.path, &info) == 0, (info.st_mode & S_IFMT) != S_IFLNK else { return nil }
        return .init(path: resolved.path, identity: .init(device: UInt64(info.st_dev), inode: UInt64(info.st_ino)), size: Int64(info.st_size),
            modifiedSeconds: Int64(info.st_mtimespec.tv_sec), modifiedNanos: Int64(info.st_mtimespec.tv_nsec),
            changedSeconds: Int64(info.st_ctimespec.tv_sec), changedNanos: Int64(info.st_ctimespec.tv_nsec))
    }
}

/// Immutable consent scope from the planner. General cleanup retains its own
/// review path; a goal review cannot substitute items or a new scan underneath it.
struct ReviewedSpacePlan {
    let id: UUID
    let created: Date
    let schemaVersion: Int
    let target: Int64
    let capacityEvidenceID: UUID
    let volumeID: String
    let scanStarted: Date
    let exclusions: [String]
    let fullDiskAccess: Bool
    let developerCaches: Bool
    let simulators: Bool
    let items: [ScanItem]
    let sources: [UUID: ReviewedSource]
    var itemIDs: Set<UUID> { Set(items.map(\.id)) }
    var expectedImmediateReclaim: Int64 { items.reduce(0) { $0 + SpaceActionCapability.forItem($1).immediateReclaim } }

    static func internalVolumeID(_ url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.volumeUUIDStringKey, .volumeIsInternalKey]), values.volumeIsInternal == true else { return nil }
        return values.volumeUUIDString
    }
    static func capture(items: [ScanItem], capacity: CapacityReading, target: Int64, scanStarted: Date,
                        exclusions: [String], fullDiskAccess: Bool, developerCaches: Bool, simulators: Bool,
                        now: Date = Date(), volume: (URL) -> String? = internalVolumeID) -> ReviewedSpacePlan? {
        guard !items.isEmpty, items.count <= 60, Set(items.map(\.id)).count == items.count,
              now >= scanStarted, now.timeIntervalSince(scanStarted) <= 86_400,
              now >= capacity.date, now.timeIntervalSince(capacity.date) <= 10 * 60,
              target > 0, target <= capacity.total else { return nil }
        var sources: [UUID: ReviewedSource] = [:]
        var identities = Set<String>()
        var paths: [String] = []
        for item in items {
            guard SpaceActionCapability.forItem(item).executableAfterReview, volume(item.url) == capacity.volumeID,
                  let source = ReviewedSource.read(item.url), source.identity == item.sourceIdentity,
                  source.path == item.resolvedURL.standardizedFileURL.path,
                  !paths.contains(where: { source.path == $0 || source.path.hasPrefix($0 + "/") || $0.hasPrefix(source.path + "/") }),
                  !exclusions.contains(where: { source.path == $0 || source.path.hasPrefix($0 + "/") || $0.hasPrefix(source.path + "/") }),
                  identities.insert("\(source.identity.device):\(source.identity.inode)").inserted else { return nil }
            sources[item.id] = source; paths.append(source.path)
        }
        return .init(id: UUID(), created: now, schemaVersion: 1, target: target,
            capacityEvidenceID: capacity.id, volumeID: capacity.volumeID, scanStarted: scanStarted,
            exclusions: exclusions.sorted(), fullDiskAccess: fullDiskAccess, developerCaches: developerCaches,
            simulators: simulators, items: items, sources: sources)
    }
    func invalidReason(itemIDs: Set<UUID>, scanStarted: Date?, exclusions: [String], fullDiskAccess: Bool,
                       developerCaches: Bool, simulators: Bool, capacity: CapacityReading?, now: Date = Date()) -> String? {
        guard schemaVersion == 1, now >= created, now.timeIntervalSince(created) <= 15 * 60 else { return "This review expired. Build a fresh plan." }
        guard self.itemIDs == itemIDs, self.scanStarted == scanStarted else { return "The scan or selection changed. Review a fresh plan." }
        guard self.exclusions == exclusions.sorted(), self.fullDiskAccess == fullDiskAccess,
              self.developerCaches == developerCaches, self.simulators == simulators else { return "Permissions or scan settings changed. Review a fresh plan." }
        guard let capacity, capacity.volumeID == volumeID, now >= capacity.date,
              now.timeIntervalSince(capacity.date) <= 10 * 60 else { return "Internal volume evidence is unavailable or stale. Check space and review again." }
        return nil
    }
    func matchesSource(_ item: ScanItem) -> Bool { sources[item.id] == ReviewedSource.read(item.url) && sources[item.id] != nil }
}
