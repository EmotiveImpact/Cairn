import Foundation

/// A cleanup the person approves once and Cairn then runs on its own.
///
/// Rules cover a short, fixed list of kinds that rebuild themselves. Each
/// run measures fresh, takes only items the scanner proved safe and
/// rebuildable (the same test AI tools are held to), stops at the rule's
/// size cap, goes through the normal executor and journal, and leaves a
/// receipt in Activity. Pausing or switching a rule off stops it at once.
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
    var approvedAt: Date?
    var lastRun: Date?
    var lastRunBytes: Int64 = 0
    var lastRunItems = 0
    var lastResult = ""

    var id: String { kind.rawValue }
    var capBytes: Int64 { Int64(capGB) * 1_000_000_000 }
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
            guard total + item.allocatedSize <= capBytes else { continue }
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
    static func load(_ defaults: UserDefaults = .standard) -> [CleaningRule] {
        let saved = defaults.data(forKey: key).flatMap { try? decoder.decode([CleaningRule].self, from: $0) } ?? []
        return CleaningRule.Kind.allCases.map { kind in saved.first { $0.kind == kind } ?? CleaningRule(kind: kind) }
    }

    static func save(_ rules: [CleaningRule], _ defaults: UserDefaults = .standard) {
        guard let data = try? encoder.encode(rules) else { return }
        defaults.set(data, forKey: key)
    }

    private static var encoder: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
    private static var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}
