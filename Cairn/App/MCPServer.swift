import Foundation

/// `cairn mcp`: a Model Context Protocol server on stdio, so coding agents
/// such as Claude Code can ask Cairn what is using space.
///
/// Measuring tools run here. Cleaning goes to the running app through
/// `AgentBridge`: an agent plans first and gets the exact items back, then may
/// run that plan once. The app re-checks the person's AI tools setting, asks
/// them when it is set to ask, and cleans through the same executor, journal
/// and receipts as a reviewed clean. Only safe, rebuildable findings qualify.
///
///     claude mcp add cairn -- /usr/local/bin/cairn mcp
enum MCPServer {
    static let protocolVersion = "2025-06-18"
    /// The connecting tool's name from `initialize`, used to label receipts.
    static var clientName: String?

    private static let instructions = """
    Cairn measures disk usage on this Mac and knows which developer output can be rebuilt. \
    Use storage_status for available space, list_projects for repositories and their rebuildable \
    build output, and find_reclaimable for caches by category. To free space, call plan_cleanup \
    (optionally with targetGB, a project scope or a category), show the user the plan, then call \
    run_cleanup with its planId. Only caches and build files that rebuild themselves are ever \
    included; personal files, AI conversations and the Trash are never touched. The user decides \
    in Cairn whether AI tools may clean and whether Cairn asks them first. If cleaning is off, \
    call open_cairn so they can review it themselves. A whole-machine scan can take a minute.
    """

    static func run() {
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            guard let data = line.data(using: .utf8),
                  let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                send(["jsonrpc": "2.0", "id": NSNull(), "error": obj(["code": -32700, "message": "Parse error"])])
                continue
            }
            if let reply = handle(message) { send(reply) }
        }
    }

    /// Returns nil for notifications, which take no response.
    static func handle(_ message: [String: Any]) -> [String: Any]? {
        let method = message["method"] as? String ?? ""
        guard let id = message["id"] else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]
        func result(_ value: [String: Any]) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "result": value] }
        func failure(_ code: Int, _ text: String) -> [String: Any] {
            ["jsonrpc": "2.0", "id": id, "error": obj(["code": code, "message": text])]
        }

        switch method {
        case "initialize":
            clientName = (params["clientInfo"] as? [String: Any])?["name"] as? String
            let requested = params["protocolVersion"] as? String
            return result([
                "protocolVersion": requested ?? protocolVersion,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "cairn", "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"],
                "instructions": instructions,
            ])
        case "ping":
            return result([:])
        case "tools/list":
            return result(["tools": tools])
        case "tools/call":
            guard let name = params["name"] as? String else { return failure(-32602, "Missing tool name") }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            switch call(name, arguments) {
            case .success(let payload): return result(["content": [["type": "text", "text": encode(payload)]], "isError": false])
            case .failure(let error): return result(["content": [["type": "text", "text": error.message]], "isError": true])
            }
        default:
            return failure(-32601, "Method not found: \(method)")
        }
    }

    // MARK: - Tools

    struct ToolError: Error { let message: String }

    private static let sections = ["dashboard", "projects", "developer", "makeRoom", "largeFiles", "activity", "settings"]

    static let tools: [[String: Any]] = [
        [
            "name": "storage_status",
            "description": "Available and total space on the startup disk, with the recent trend.",
            "inputSchema": obj(["type": "object", "properties": [String: Any]()]),
            "annotations": ["readOnlyHint": true],
        ],
        [
            "name": "list_projects",
            "description": "Repositories with build output that tools can rebuild (node_modules, target, .build, Pods, venvs, web build folders), how many bytes each holds, and days since the last git or manifest change.",
            "inputSchema": obj([
                "type": "object",
                "properties": obj([
                    "minIdleDays": obj(["type": "integer", "minimum": 0, "description": "Only projects idle at least this many days."]),
                    "limit": obj(["type": "integer", "minimum": 1, "maximum": 200, "description": "Maximum projects to return (default 25)."]),
                ]),
            ]),
            "annotations": ["readOnlyHint": true],
        ],
        [
            "name": "find_reclaimable",
            "description": "Measure cleanup candidates. Returns totals per category and the largest items with whether each is rebuildable and actionable in Cairn. Use list_categories for ids.",
            "inputSchema": obj([
                "type": "object",
                "properties": obj([
                    "category": obj(["type": "string", "description": "One scanner id, for example xcode, docker, dev-caches or browser-caches."]),
                    "limit": obj(["type": "integer", "minimum": 1, "maximum": 200, "description": "Maximum items to return (default 25)."]),
                ]),
            ]),
            "annotations": ["readOnlyHint": true],
        ],
        [
            "name": "list_categories",
            "description": "Scanner category ids and titles for find_reclaimable.",
            "inputSchema": obj(["type": "object", "properties": [String: Any]()]),
            "annotations": ["readOnlyHint": true],
        ],
        [
            "name": "plan_cleanup",
            "description": "Make a cleanup plan: the exact caches and build files Cairn would remove, largest first. Only items Cairn has proved are safe and rebuild themselves are included. Nothing is removed. Returns a planId for run_cleanup, valid for 15 minutes, and whether the user lets AI tools clean.",
            "inputSchema": obj([
                "type": "object",
                "properties": obj([
                    "scope": obj(["type": "string", "enum": ["recommended", "projects", "category"], "description": "recommended (default): every safe rebuildable finding. projects: build output in repositories. category: one scanner id."]),
                    "targetGB": obj(["type": "number", "minimum": 0.1, "description": "Stop once this many gigabytes are covered."]),
                    "minIdleDays": obj(["type": "integer", "minimum": 0, "description": "With scope projects: only projects idle at least this long."]),
                    "projects": obj(["type": "array", "items": obj(["type": "string"]), "description": "With scope projects: only these repository paths."]),
                    "category": obj(["type": "string", "description": "With scope category: the scanner id from list_categories."]),
                ]),
            ]),
            "annotations": ["readOnlyHint": true],
        ],
        [
            "name": "run_cleanup",
            "description": "Run a plan from plan_cleanup, once. Cairn re-checks every item, asks the user first if they chose that, and records a receipt in Activity. Returns the space freed and the change macOS measured.",
            "inputSchema": obj([
                "type": "object",
                "properties": obj(["planId": obj(["type": "string", "description": "The planId from plan_cleanup."])]),
                "required": ["planId"],
            ]),
            "annotations": obj(["readOnlyHint": false, "destructiveHint": true, "idempotentHint": false]),
        ],
        [
            "name": "recent_cleanups",
            "description": "The latest cleanup receipts, including ones run by AI tools: who ran them, items removed and the measured change in free space.",
            "inputSchema": obj(["type": "object", "properties": obj(["limit": obj(["type": "integer", "minimum": 1, "maximum": 20])])]),
            "annotations": ["readOnlyHint": true],
        ],
        [
            "name": "open_cairn",
            "description": "Open the Cairn app so the user can review and free space. Opens on the given page when Cairn is not already running.",
            "inputSchema": obj([
                "type": "object",
                "properties": obj(["section": obj(["type": "string", "enum": sections, "description": "Page to open (default projects)."])]),
            ]),
            "annotations": obj(["readOnlyHint": false, "destructiveHint": false]),
        ],
    ]

    static func call(_ name: String, _ arguments: [String: Any]) -> Result<[String: Any], ToolError> {
        switch name {
        case "storage_status":
            let free = Volumes.homeFree()
            let total = DeviceInfo.totalCapacity
            return .success([
                "availableBytes": free, "available": Fmt.size(free),
                "totalBytes": total, "total": Fmt.size(total),
                "trend": StorageHistory.summary(currentFree: free).text,
            ])

        case "list_projects":
            let limit = boundedLimit(arguments["limit"])
            let minimumIdle = max(0, arguments["minIdleDays"] as? Int ?? 0)
            let projects = ProjectIndex.build(from: CLI.collect(category: ProjectIndex.categoryID))
                .filter { minimumIdle == 0 || ($0.idleDays() ?? 0) >= minimumIdle }
                .sorted { $0.rebuildableBytes > $1.rebuildableBytes }
            return .success([
                "projectCount": projects.count,
                "rebuildableBytes": projects.reduce(Int64(0)) { $0 + $1.rebuildableBytes },
                "projects": projects.prefix(limit).map(describeProject),
                "nextStep": "To free this space, call open_cairn with section projects and ask the user to review the selection.",
            ])

        case "find_reclaimable":
            let limit = boundedLimit(arguments["limit"])
            let category = arguments["category"] as? String
            if let category, !ScannerRegistry.all().contains(where: { $0.info.id == category }) {
                return .failure(ToolError(message: "Unknown category '\(category)'. Call list_categories for valid ids."))
            }
            let items = CLI.collect(category: category).sorted { $0.allocatedSize > $1.allocatedSize }
            let byCategory = Dictionary(grouping: items, by: \.categoryID)
                .map { ["category": $0.key, "bytes": $0.value.reduce(Int64(0)) { $0 + $1.allocatedSize }, "items": $0.value.count] as [String: Any] }
                .sorted { ($0["bytes"] as? Int64 ?? 0) > ($1["bytes"] as? Int64 ?? 0) }
            return .success([
                "totalBytes": items.reduce(Int64(0)) { $0 + $1.allocatedSize },
                "itemCount": items.count,
                "categories": byCategory,
                "items": items.prefix(limit).map(describeItem),
                "note": "Sizes are measured file sizes, not space already freed. Removal happens in Cairn after the user reviews it.",
            ])

        case "list_categories":
            return .success(["categories": ScannerRegistry.all().map { ["id": $0.info.id, "title": $0.info.title] }])

        case "plan_cleanup":
            var request: [String: Any] = ["op": "plan", "client": clientName ?? ""]
            for key in ["scope", "category", "minIdleDays", "projects"] { if let value = arguments[key] { request[key] = value } }
            if let target = (arguments["targetGB"] as? NSNumber)?.doubleValue { request["targetGB"] = target }
            return bridge(request, timeout: 600)

        case "run_cleanup":
            guard let plan = arguments["planId"] as? String, !plan.isEmpty else { return .failure(ToolError(message: "Pass the planId from plan_cleanup.")) }
            return bridge(["op": "run", "planId": plan, "client": clientName ?? ""], timeout: 1_800)

        case "recent_cleanups":
            return bridge(["op": "receipts", "limit": boundedLimit(arguments["limit"])], timeout: 30)

        case "open_cairn":
            let section = arguments["section"] as? String ?? "projects"
            guard sections.contains(section) else {
                return .failure(ToolError(message: "Unknown section '\(section)'. Use one of: \(sections.joined(separator: ", "))."))
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-b", "com.emotiveimpact.cairn", "--args", "--section=\(section)"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do { try process.run(); process.waitUntilExit() }
            catch { return .failure(ToolError(message: "Could not open Cairn: \(error.localizedDescription)")) }
            guard process.terminationStatus == 0 else {
                return .failure(ToolError(message: "Cairn.app was not found. Install it in Applications first."))
            }
            return .success(["opened": true, "section": section,
                             "note": "If Cairn was already open it was brought forward on its current page."])

        default:
            return .failure(ToolError(message: "Unknown tool '\(name)'."))
        }
    }

    // MARK: - App bridge

    /// Sends a request to the running app, starting it in the background when
    /// it is not running yet.
    static var bridgeURL = AgentSocket.defaultURL
    static func bridge(_ request: [String: Any], timeout: TimeInterval) -> Result<[String: Any], ToolError> {
        var launched = false
        let deadline = Date().addingTimeInterval(30)
        while true {
            do {
                var reply = try AgentSocket.request(request, at: bridgeURL, timeout: timeout)
                guard reply["ok"] as? Bool == true else {
                    return .failure(ToolError(message: reply["error"] as? String ?? "Cairn could not do that."))
                }
                reply.removeValue(forKey: "ok")
                return .success(reply)
            } catch let failure as AgentSocket.Failure where failure.notRunning && Date() < deadline {
                if !launched {
                    launched = true
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                    process.arguments = ["-g", "-b", "com.emotiveimpact.cairn"]
                    process.standardOutput = FileHandle.nullDevice
                    process.standardError = FileHandle.nullDevice
                    guard (try? process.run()) != nil else { return .failure(ToolError(message: "Cairn is not running and could not be started.")) }
                    process.waitUntilExit()
                    guard process.terminationStatus == 0 else { return .failure(ToolError(message: "Cairn.app was not found. Install it in Applications first.")) }
                }
                Thread.sleep(forTimeInterval: 1)
            } catch let failure as AgentSocket.Failure {
                return .failure(ToolError(message: failure.message))
            } catch {
                return .failure(ToolError(message: error.localizedDescription))
            }
        }
    }

    // MARK: - Encoding

    /// Gives nested heterogeneous literals a contextual type.
    private static func obj(_ value: [String: Any]) -> [String: Any] { value }

    private static func boundedLimit(_ value: Any?) -> Int { min(200, max(1, value as? Int ?? 25)) }

    private static func describeProject(_ project: ProjectSummary) -> [String: Any] {
        var entry: [String: Any] = [
            "name": project.name,
            "path": project.url.path,
            "repository": project.isRepository,
            "rebuildableBytes": project.rebuildableBytes,
            "rebuildable": Fmt.size(project.rebuildableBytes),
            "artifacts": project.items.map { ["path": $0.url.path, "bytes": $0.allocatedSize, "rebuildable": $0.isRegenerable] as [String: Any] },
        ]
        if let days = project.idleDays() { entry["idleDays"] = days }
        return entry
    }

    private static func describeItem(_ item: ScanItem) -> [String: Any] {
        [
            "path": item.resolvedURL.path,
            "bytes": item.allocatedSize,
            "size": Fmt.size(item.allocatedSize),
            "category": item.categoryID,
            "safety": item.severity.label,
            "rebuildable": item.isRegenerable,
            "actionableInCairn": item.isActionable && item.severity != .risky,
            "note": item.note,
        ]
    }

    static func encode(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    private static func send(_ object: [String: Any]) {
        print(encode(object))
        fflush(stdout)
    }
}
