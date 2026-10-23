import Foundation

/// How much an AI coding tool connected through `Cairn mcp` may clean.
/// Off until the person chooses otherwise in Settings › AI tools.
enum AgentCleaningMode: String, CaseIterable, Identifiable, Sendable {
    case off, ask, allow
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "Off"
        case .ask: return "Ask me each time"
        case .allow: return "Let them clean safe junk"
        }
    }
    var detail: String {
        switch self {
        case .off: return "AI tools can measure and plan, but cannot clean."
        case .ask: return "Cairn shows you exactly what an AI tool wants to clean, and nothing happens until you press Free."
        case .allow: return "AI tools can clean rebuildable caches and build files without asking. Each clean leaves a receipt in Activity."
        }
    }
    static let key = "cairn.agentCleaning.v1"
    /// The saved preference, readable off the main actor.
    static var current: AgentCleaningMode {
        UserDefaults.standard.string(forKey: key).flatMap(AgentCleaningMode.init(rawValue:)) ?? .off
    }
}

/// The contract for cleanups an AI tool asks for. An agent plans first, gets
/// back the exact items, and can then run only that plan, once, soon after.
/// Only findings the scanner proved safe and rebuildable are ever offered;
/// emptying the Trash, personal files and anything SafePaths protects stay
/// with the person, in Cairn.
enum AgentCleanup {
    enum Scope: String, CaseIterable, Sendable { case recommended, projects, category }

    struct Request: Sendable {
        var scope: Scope = .recommended
        var category: String?
        var minIdleDays = 0
        var projectPaths: [String] = []
        var targetBytes: Int64?
    }

    struct Plan {
        let id: String
        let client: String
        let created: Date
        let items: [ScanItem]
        /// Found but left out because they need a person's review.
        let heldBack: [ScanItem]
        var totalBytes: Int64 { items.reduce(0) { $0 + $1.allocatedSize } }
    }

    static let planLifetime: TimeInterval = 15 * 60
    static let maxItems = 500

    /// What an agent may ever clean.
    static func eligible(_ item: ScanItem) -> Bool {
        guard item.isActionable, item.severity == .safe, item.isRegenerable else { return false }
        switch item.cleanMethod {
        case .emptyTrash, .adviceOnly: return false
        case .tool(let command): return !command.destroysData
        case .trash: return true
        }
    }

    /// Picks the plan's items from fresh findings. Largest first; with a
    /// target, stops once the target is covered.
    static func select(_ found: [ScanItem], request: Request, now: Date = Date(),
                       home: URL = FileScan.home) -> (items: [ScanItem], heldBack: [ScanItem]) {
        var candidates = found
        switch request.scope {
        case .recommended: break
        case .category:
            candidates = found.filter { $0.categoryID == request.category }
        case .projects:
            var projects = ProjectIndex.build(from: found, stopAt: home)
            if request.minIdleDays > 0 {
                projects = projects.filter { ($0.idleDays(now: now) ?? 0) >= request.minIdleDays }
            }
            if !request.projectPaths.isEmpty {
                let wanted = Set(request.projectPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
                projects = projects.filter { wanted.contains($0.url.standardizedFileURL.path) }
            }
            candidates = projects.flatMap(\.items)
        }
        let heldBack = candidates.filter { !eligible($0) && $0.allocatedSize > 0 }
        var chosen: [ScanItem] = []
        var total: Int64 = 0
        for item in candidates.filter(eligible).sorted(by: { $0.allocatedSize > $1.allocatedSize }) {
            if let target = request.targetBytes, total >= target { break }
            if chosen.count >= maxItems { break }
            chosen.append(item)
            total += item.allocatedSize
        }
        return (chosen, heldBack)
    }

    /// "claude-code" becomes "Claude Code" for receipts and prompts.
    static func displayName(_ client: String?) -> String {
        let raw = (client ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let known = ["claude-code": "Claude Code", "claude-ai": "Claude Desktop", "cursor-vscode": "Cursor",
                     "codex-mcp-client": "Codex", "gemini-cli-mcp-client": "Gemini CLI", "visual-studio-code": "VS Code"]
        if let name = known[raw.lowercased()] { return name }
        guard !raw.isEmpty else { return "An AI tool" }
        let words = raw.prefix(40).replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return words.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// Why a plan cannot run, or nil when it can.
    static func refusal(plan: Plan?, mode: AgentCleaningMode, now: Date = Date()) -> String? {
        guard mode != .off else {
            return "AI tools are not allowed to clean on this Mac. Ask the user to choose \"Ask me each time\" or \"Let them clean safe junk\" in Cairn › Settings › AI tools, or call open_cairn so they can review it themselves."
        }
        guard let plan else { return "That plan was not found. Plans can be run once; make a new one with plan_cleanup." }
        guard now.timeIntervalSince(plan.created) <= planLifetime else { return "That plan is more than 15 minutes old. Make a new one with plan_cleanup." }
        guard !plan.items.isEmpty else { return "That plan has nothing to clean." }
        guard plan.items.allSatisfy(eligible) else { return "That plan contains items an AI tool may not clean." }
        return nil
    }

    static func describe(_ item: ScanItem) -> [String: Any] {
        let action: String
        switch item.cleanMethod {
        case .tool(let command): action = "runs \(command.display)"
        default: action = RemovalMode.current.deletesImmediately(item) ? "deleted" : "moved to Trash"
        }
        return ["path": item.resolvedURL.path, "bytes": item.allocatedSize, "size": Fmt.size(item.allocatedSize),
                "category": item.categoryID, "action": action, "note": item.note]
    }
}
