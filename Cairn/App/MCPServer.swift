import Foundation

/// `cairn mcp`: a Model Context Protocol server on stdio, so coding agents
/// such as Claude Code can ask Cairn what is using space.
///
/// Every tool is read-only. Agents can measure, list projects and open Cairn
/// on a page, but removal stays in the app, where a person reviews the exact
/// items. That keeps the executor's review-before-removal contract intact.
///
///     claude mcp add cairn -- /usr/local/bin/cairn mcp
enum MCPServer {
    static let protocolVersion = "2025-06-18"

    private static let instructions = """
    Cairn measures disk usage on this Mac and knows which developer output can be rebuilt. \
    Use storage_status for available space, list_projects for repositories and their rebuildable \
    build output, and find_reclaimable for caches by category. Cairn never deletes from here: \
    to free space, call open_cairn and tell the user what to review. Scans read file sizes only. \
    find_reclaimable with no category answers at once from Cairn's last scan when it is under a day old; \
    a fresh whole-machine scan can take several minutes, and results are kept for ten minutes, \
    so pass a category when you can.
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

    private static let sections = ["dashboard", "projects", "developer", "makeRoom", "largeFiles", "activity"]

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
                    "fresh": obj(["type": "boolean", "description": "Rescan now instead of using Cairn's last scan from today. A full rescan can take several minutes."]),
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
            let cleans = CLI.recordedTotals()
            return .success([
                "availableBytes": free, "available": Fmt.size(free),
                "totalBytes": total, "total": Fmt.size(total),
                "trend": StorageHistory.summary(currentFree: free).text,
                "freedByCairnBytes": cleans?.freedBytes ?? 0,
                "movedToTrashByCairnBytes": cleans?.movedToTrashBytes ?? 0,
                "cleans": cleans?.cleans ?? 0,
                "cleanHistory": cleans.map(CLI.describe) ?? "No cleans recorded yet",
            ])

        case "list_projects":
            let limit = boundedLimit(arguments["limit"])
            let minimumIdle = max(0, arguments["minIdleDays"] as? Int ?? 0)
            let measured = measure(ProjectIndex.categoryID)
            let projects = ProjectIndex.build(from: measured.items)
                .filter { minimumIdle == 0 || ($0.idleDays() ?? 0) >= minimumIdle }
                .sorted { $0.rebuildableBytes > $1.rebuildableBytes }
            return .success([
                "projectCount": projects.count,
                "rebuildableBytes": projects.reduce(Int64(0)) { $0 + $1.rebuildableBytes },
                "projects": projects.prefix(limit).map(describeProject),
                "nextStep": "To free this space, call open_cairn with section projects and ask the user to review the selection.",
                "measuredSecondsAgo": measured.age,
            ])

        case "find_reclaimable":
            let limit = boundedLimit(arguments["limit"])
            let category = arguments["category"] as? String
            if let category, !ScannerRegistry.all().contains(where: { $0.info.id == category }) {
                return .failure(ToolError(message: "Unknown category '\(category)'. Call list_categories for valid ids."))
            }
            if category == nil, arguments["fresh"] as? Bool != true, cache.isEmpty,
               let snapshot = ScanStore.savedSnapshot(), Date().timeIntervalSince(snapshot.date) < 86_400 {
                return .success(summarise(snapshot))
            }
            let measured = measure(category)
            let items = measured.items.sorted { $0.allocatedSize > $1.allocatedSize }
            func bytes(_ list: [ScanItem]) -> Int64 { list.reduce(Int64(0)) { $0 + $1.allocatedSize } }
            let byCategory = Dictionary(grouping: items, by: \.categoryID)
                .map { ["category": $0.key, "bytes": bytes($0.value), "readyBytes": bytes($0.value.filter(CLI.isReady)),
                        "items": $0.value.count] as [String: Any] }
                .sorted { ($0["bytes"] as? Int64 ?? 0) > ($1["bytes"] as? Int64 ?? 0) }
            let ready = bytes(items.filter(CLI.isReady))
            return .success([
                "readyBytes": ready, "ready": Fmt.size(ready),
                "needsUserBytes": bytes(items) - ready,
                "totalBytes": bytes(items),
                "itemCount": items.count,
                "categories": byCategory,
                "items": items.prefix(limit).map(describeItem),
                "measuredSecondsAgo": measured.age,
                "note": "readyBytes is what Cairn can free once the user reviews it: safe items their tools rebuild. The rest are personal files or advice the user must decide on, so never present them as free space. Sizes are measured file sizes, not space already freed.",
            ])

        case "list_categories":
            return .success(["categories": ScannerRegistry.all().map { ["id": $0.info.id, "title": $0.info.title] }])

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

    // MARK: - Measuring

    /// Totals from the app's last scan, returned instantly. Item lists need a
    /// category or `fresh`, which scan now.
    private static func summarise(_ snapshot: ScanStore.Snapshot) -> [String: Any] {
        let buckets = snapshot.buckets.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
        let total = buckets.reduce(Int64(0)) { $0 + $1.bytes }
        let known = buckets.allSatisfy { $0.readyBytes != nil }
        let ready = buckets.reduce(Int64(0)) { $0 + ($1.readyBytes ?? 0) }
        var result: [String: Any] = [
            "source": "Cairn's last scan",
            "measuredSecondsAgo": Int(Date().timeIntervalSince(snapshot.date)),
            "totalBytes": total,
            "itemCount": buckets.reduce(0) { $0 + $1.count },
            "categories": buckets.map { bucket -> [String: Any] in
                var entry: [String: Any] = ["category": bucket.id, "title": bucket.title, "bytes": bucket.bytes, "items": bucket.count]
                if let ready = bucket.readyBytes { entry["readyBytes"] = ready }
                return entry
            },
            "note": "Totals from Cairn's last scan, without rescanning. Call again with a category for its items, or with fresh: true to rescan everything. readyBytes is what Cairn can free once the user reviews it; never present the rest as free space.",
        ]
        if known { result["readyBytes"] = ready; result["ready"] = Fmt.size(ready); result["needsUserBytes"] = total - ready }
        return result
    }

    /// Scans are slow (a full project sweep can take minutes), so results are
    /// kept per scanner for ten minutes within one agent session. A later call
    /// rescans only the scanners whose results have gone stale.
    private static var cache: [String: (date: Date, items: [ScanItem])] = [:]
    private static let cacheLifetime: TimeInterval = 600

    private static func measure(_ category: String?) -> (items: [ScanItem], age: Int) {
        let ids = category.map { [$0] } ?? ScannerRegistry.all().map(\.info.id)
        var items: [ScanItem] = []
        var oldest: Date?
        for id in ids {
            let entry: (date: Date, items: [ScanItem])
            if let hit = cache[id], Date().timeIntervalSince(hit.date) < cacheLifetime {
                entry = hit
            } else {
                entry = (date: Date(), items: CLI.collect(category: id))
                cache[id] = entry
            }
            items += entry.items
            oldest = min(oldest ?? entry.date, entry.date)
        }
        return (PathDedupe.apply(items), oldest.map { Int(Date().timeIntervalSince($0)) } ?? 0)
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
