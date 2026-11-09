import Foundation

/// A cleanup the person approves once and Cairn then runs on its own.
///
/// Rules cover a short, fixed list of kinds that rebuild themselves. Each
/// run measures fresh, takes only items the scanner proved safe and
/// rebuildable (the same test AI tools are held to), stops at the rule's
/// size cap, goes through the normal executor and journal, and leaves a
/// receipt in Activity. Pausing or switching a rule off stops further actions; an atomic move
/// already in progress is allowed to settle and is recorded.
struct CleaningRule: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case xcodeBuild, packageCaches, idleProjects, browserCaches, appCaches, logs

        var title: String {
            switch self {
            case .xcodeBuild: return "Old Xcode build files"
            case .packageCaches: return "Package manager caches"
            case .idleProjects: return "Build output in idle projects"
            case .browserCaches: return "Browser caches"
            case .appCaches: return "App caches"
            case .logs: return "Old logs"
            }
        }

        var detail: String {
            switch self {
            case .xcodeBuild: return "DerivedData and other Xcode output Xcode rebuilds on the next build."
            case .packageCaches: return "npm, pip, Homebrew, Cargo and similar download caches. Tools fetch again what they need."
            case .idleProjects: return "node_modules, build folders and virtual environments in projects you have not touched for a while. Your code is never touched."
            case .browserCaches: return "Temporary web caches. Logins, history and bookmarks stay."
            case .appCaches: return "Caches apps rebuild themselves. Skipped while the app is open."
            case .logs: return "Diagnostic logs older than the age you choose."
            }
        }

        /// The scan category the rule draws from.
        var category: String {
            switch self {
            case .xcodeBuild: return "xcode"
            case .packageCaches: return "dev-caches"
            case .idleProjects: return ProjectIndex.categoryID
            case .browserCaches: return "browser-caches"
            case .appCaches: return "app-caches"
            case .logs: return "logs"
            }
        }

        /// The age in days a new rule starts with.
        var defaultAge: Int {
            switch self {
            case .idleProjects: return 60
            case .browserCaches, .appCaches: return 0
            default: return 14
            }
        }

        /// What "age" means for this kind.
        var ageLabel: String { self == .idleProjects ? "Project idle for" : "Older than" }
    }

    enum Schedule: String, Codable, CaseIterable, Sendable {
        case daily, weekly
        var title: String { self == .daily ? "Every day" : "Every week" }
        var interval: TimeInterval { self == .daily ? 86_400 : 7 * 86_400 }
    }

    var kind: Kind
    /// The person's approval. Nothing runs without it.
    var approved = false
    var paused = false
    var schedule: Schedule = .weekly
    var minAgeDays: Int
    /// The most one run may clear.
    var capGB: Int = 20
    var consentID: String?
    var consentSeal: String?
    var approvedAt: Date?
    var lastRun: Date?
    var lastRunBytes: Int64 = 0
    var lastRunItems = 0
    var lastResult = ""

    var id: String { kind.rawValue }
    var validScope: Bool { (1...200).contains(capGB) && (0...365).contains(minAgeDays)
        && (kind != .idleProjects || minAgeDays >= 7) }
    var capBytes: Int64 { validScope ? Int64(capGB) * 1_000_000_000 : 0 }
    // Version the policy as well as the settings: new semantics require new approval.
    var scope: String { "v2|trash-only|\(kind.rawValue)|\(schedule.rawValue)|\(minAgeDays)|\(capGB)" }
    var consentValue: String { "\(scope)|\(approved)|\(paused)|\(consentID ?? "")|\(lastRun.map { String($0.timeIntervalSince1970.rounded(.down)) } ?? "never")" }
    var verified: Bool { isVerified() }
    func isVerified(using verify: ((String, String, String?) -> Bool)? = nil) -> Bool {
        guard validScope, approved, consentID != nil else { return false }
        if let verify { return verify(consentValue, CleaningRules.key, consentSeal) }
        return SettingsSeal.isSealed(consentValue, for: CleaningRules.key, seal: consentSeal)
            && RuleConsentStore.shared.matches(self)
    }
    var active: Bool { approved && !paused }

    init(kind: Kind) {
        self.kind = kind
        self.minAgeDays = kind.defaultAge
    }

    func isDue(now: Date = Date()) -> Bool {
        guard active else { return false }
        guard let lastRun else { return true }
        return now.timeIntervalSince(lastRun) >= schedule.interval
    }

    var nextRun: Date? {
        guard active else { return nil }
        return lastRun.map { $0.addingTimeInterval(schedule.interval) } ?? Date()
    }

    /// The items one run would clear, largest first, up to the cap. Only
    /// findings an AI tool would also be allowed to clean qualify.
    func select(_ found: [ScanItem], now: Date = Date(), home: URL = FileScan.home) -> [ScanItem] {
        guard validScope else { return [] }
        var candidates: [ScanItem]
        if kind == .idleProjects {
            candidates = ProjectIndex.build(from: found, stopAt: home)
                .filter { ($0.idleDays(now: now) ?? 0) >= max(1, minAgeDays) }
                .flatMap(\.items)
        } else {
            candidates = found.filter { $0.categoryID == kind.category }
            if minAgeDays > 0 {
                candidates = candidates.filter { $0.latestModified != .distantPast && now.timeIntervalSince($0.latestModified) >= Double(minAgeDays) * 86_400 }
            }
        }
        var chosen: [ScanItem] = []
        var total: Int64 = 0
        for item in candidates.filter(AgentCleanup.eligible).sorted(by: { $0.allocatedSize > $1.allocatedSize }) {
            guard case .trash = item.cleanMethod, item.allocatedSize >= 0, item.allocatedSize <= capBytes - total else { continue }
            if chosen.count >= AgentCleanup.maxItems { break }
            chosen.append(item)
            total += item.allocatedSize
        }
        return chosen
    }
}

enum CleaningRules {
    static let key = "cairn.cleaningRules.v1"

    /// Every kind, approved or not, in a fixed order.
    static func load(_ defaults: UserDefaults = .standard,
                     verify: ((String, String, String?) -> Bool)? = nil) -> [CleaningRule] {
        let saved = defaults.data(forKey: key).flatMap { try? decoder.decode([CleaningRule].self, from: $0) } ?? []
        return CleaningRule.Kind.allCases.map { kind in
            var rule = saved.first { $0.kind == kind } ?? CleaningRule(kind: kind)
            if saved.filter({ $0.kind == kind }).count > 1 || !rule.isVerified(using: verify) {
                rule.approved = false
                rule.consentSeal = nil
            }
            return rule
        }
    }

    static func save(_ rules: [CleaningRule], _ defaults: UserDefaults = .standard) {
        guard let data = try? encoder.encode(rules) else { return }
        defaults.set(data, forKey: key)
    }

    private static var encoder: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
    private static var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}

/// One run's immutable approval, paired with revocation shared with detached work.
/// Never authorizes tool commands or permanent deletion.
final class CleaningRuleRun: @unchecked Sendable {
    let rule: CleaningRule
    private let cancellation = CancelBox()
    private let current: @Sendable () -> CleaningRule?
    private let verify: (@Sendable (String, String, String?) -> Bool)?
    init(_ rule: CleaningRule,
         current: (@Sendable () -> CleaningRule?)? = nil,
         verify: (@Sendable (String, String, String?) -> Bool)? = nil) {
        self.rule = rule
        self.current = current ?? { CleaningRules.load().first { $0.kind == rule.kind } }
        self.verify = verify
    }
    func cancel() { cancellation.cancel() }
    func isAuthorized(current: CleaningRule?,
                      verify: ((String, String, String?) -> Bool)? = nil) -> Bool {
        guard !cancellation.isCancelled, let current, current.active, current.isVerified(using: verify) else { return false }
        return current.consentValue == rule.consentValue && current.consentSeal == rule.consentSeal
            && !cancellation.isCancelled // Revocation may race a slow protected-state read.
    }
    var isAuthorized: Bool {
        guard !cancellation.isCancelled else { return false }
        return isAuthorized(current: current(), verify: verify)
    }
    func authorized() async -> Bool { await RuleStateWorker.run { self.isAuthorized } }
    func permitsAsync(_ items: [ScanItem]) async -> Bool { await RuleStateWorker.run { self.permits(items) } }
    func permits(_ items: [ScanItem]) -> Bool {
        guard isAuthorized, !items.isEmpty, items.count <= AgentCleanup.maxItems else { return false }
        let selected = rule.select(items)
        return selected.count == items.count && Set(selected.map(\.id)) == Set(items.map(\.id))
    }
}
