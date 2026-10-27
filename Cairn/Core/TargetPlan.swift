import Foundation

/// "I need 24 GB": the safest set of findings that reaches a size. Caches and
/// files that are made again come first, then installers for apps already
/// installed, then things that are downloaded again after a look, then other
/// installers and the Bin. Your own files are never in the plan. It stops as
/// soon as the goal is reached.
enum TargetPlan {
    /// How safe a finding is for a goal. Lower goes first; nil is never planned.
    enum Tier: Int, Comparable {
        case madeAgain = 0, alreadyInstalled, downloadedAgain, youChoose
        static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }
    }

    /// One bucket's findings at one tier: the rows on the page.
    struct Group: Identifiable {
        let bucketID: String
        let title: String
        let tier: Tier
        let order: Int
        let items: [ScanItem]
        var id: String { "\(bucketID)#\(tier.rawValue)" }
        var bytes: Int64 { items.reduce(0) { $0 + $1.allocatedSize } }
    }

    struct Row: Identifiable {
        let group: Group
        /// The findings the plan takes from this group; empty when not needed.
        let chosen: [ScanItem]
        /// Running total once this row is freed, for the "→ 16.9 GB" column.
        let runningTotal: Int64
        var id: String { group.id }
        var bytes: Int64 { chosen.reduce(0) { $0 + $1.allocatedSize } }
        var included: Bool { !chosen.isEmpty }
    }

    struct Result {
        let goal: Int64
        let rows: [Row]
        var chosen: [ScanItem] { rows.flatMap(\.chosen) }
        var total: Int64 { rows.reduce(0) { $0 + $1.bytes } }
        var reached: Bool { goal > 0 && total >= goal }
        /// Bytes the person checks before they go (anything past "made again").
        var toCheck: Int64 { rows.filter { $0.group.tier != .madeAgain }.reduce(0) { $0 + $1.bytes } }
    }

    /// Findings that belong to a page of their own or to the person.
    static let neverPlanned: Set<String> = ["games", "chat-apps", "large-old", "orphaned"]

    static func tier(_ item: ScanItem) -> Tier? {
        guard item.isActionable, item.severity != .risky, !item.permissionDenied,
              !neverPlanned.contains(item.categoryID) else { return nil }
        // An installer is your own download and the Bin empties for good: the
        // person's call. An installer for an app that is already installed is
        // the safer of the two, so it comes before things downloaded again.
        if item.categoryID == "installers" { return item.severity == .safe && item.isRegenerable ? .alreadyInstalled : .youChoose }
        if item.categoryID == "trash" { return .youChoose }
        if item.severity == .safe && item.isRegenerable { return .madeAgain }
        if item.isRegenerable { return .downloadedAgain }
        return nil
    }

    /// Caches first: general caches, then developer, creative and AI.
    private static func groupRank(_ group: CategoryGroup) -> Int {
        switch group {
        case .general: return 0
        case .developer: return 1
        case .creative: return 2
        case .ai: return 3
        }
    }

    /// Every plannable group, in the order the plan takes them.
    static func groups(_ buckets: [(info: CategoryInfo, items: [ScanItem])]) -> [Group] {
        var found: [Group] = []
        for (index, bucket) in buckets.enumerated() {
            var byTier: [Tier: [ScanItem]] = [:]
            for item in bucket.items {
                if let tier = tier(item) { byTier[tier, default: []].append(item) }
            }
            for (tier, items) in byTier {
                found.append(Group(bucketID: bucket.info.id, title: bucket.info.title, tier: tier,
                                   order: groupRank(bucket.info.group) * 1000 + index,
                                   items: items.sorted { $0.allocatedSize > $1.allocatedSize }))
            }
        }
        return found.sorted { a, b in
            if a.tier != b.tier { return a.tier < b.tier }
            if a.order / 1000 != b.order / 1000 { return a.order < b.order }
            return a.bytes > b.bytes
        }
    }

    /// Takes groups in order, biggest finding first inside each, until the goal
    /// is met. `forced` groups are taken whole first; `left` groups are skipped.
    static func plan(_ groups: [Group], goal: Int64, forced: Set<String> = [], left: Set<String> = []) -> Result {
        var acc: Int64 = 0
        var picks: [String: [ScanItem]] = [:]
        for group in groups where forced.contains(group.id) && !left.contains(group.id) {
            picks[group.id] = group.items
            acc += group.bytes
        }
        for group in groups where !forced.contains(group.id) && !left.contains(group.id) {
            if acc >= goal { break }
            var taken: [ScanItem] = []
            for item in group.items {
                if acc >= goal { break }
                taken.append(item)
                acc += item.allocatedSize
            }
            if !taken.isEmpty { picks[group.id] = taken }
        }
        var running: Int64 = 0
        let rows = groups.map { group -> Row in
            let chosen = picks[group.id] ?? []
            running += chosen.reduce(0) { $0 + $1.allocatedSize }
            return Row(group: group, chosen: chosen, runningTotal: running)
        }
        return Result(goal: goal, rows: rows)
    }
}
