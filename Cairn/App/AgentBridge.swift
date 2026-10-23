import Foundation
import AppKit
import Darwin

/// Lets `Cairn mcp`, which an AI tool starts as its own process, ask the
/// running app to plan and run cleanups. The app owns the recovery journal,
/// receipts and executor, so cleaning always happens here, through
/// `ScanStore.clean`, never in the MCP process.
///
/// Transport: one JSON request and one JSON reply per connection, each a single
/// line, over a Unix socket in Cairn's private support folder. Only processes
/// of the same user can connect.
enum AgentSocket {
    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cairn/agent.sock")
    }

    struct Failure: Error { let message: String; let notRunning: Bool }

    static func request(_ object: [String: Any], at url: URL = defaultURL, timeout: TimeInterval) throws -> [String: Any] {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure(message: "Could not open a socket.", notRunning: false) }
        defer { close(fd) }
        noSigPipe(fd)
        guard var address = address(url.path) else { throw Failure(message: "Socket path is too long.", notRunning: false) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw Failure(message: "Cairn is not running.", notRunning: true) }
        let body = try JSONSerialization.data(withJSONObject: object) + Data([0x0A])
        guard writeAll(fd, body) else { throw Failure(message: "Could not send the request to Cairn.", notRunning: false) }
        setTimeout(fd, timeout)
        guard let line = readLine(fd, limit: 8 * 1_024 * 1_024),
              let reply = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
            throw Failure(message: "Cairn did not answer in time.", notRunning: false)
        }
        return reply
    }

    static func address(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return address
    }

    static func readLine(_ fd: Int32, limit: Int) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while data.count <= limit {
            let count = read(fd, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { return nil }
            if let newline = buffer[0..<count].firstIndex(of: 0x0A) {
                data.append(contentsOf: buffer[0..<newline])
                return data
            }
            data.append(contentsOf: buffer[0..<count])
        }
        return nil
    }

    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            guard var pointer = raw.baseAddress else { return true }
            var remaining = raw.count
            while remaining > 0 {
                let written = write(fd, pointer, remaining)
                if written < 0 && errno == EINTR { continue }
                guard written > 0 else { return false }
                pointer = pointer.advanced(by: written)
                remaining -= written
            }
            return true
        }
    }

    static func setTimeout(_ fd: Int32, _ seconds: TimeInterval) {
        var value = timeval(tv_sec: Int(seconds), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
    }

    static func noSigPipe(_ fd: Int32) {
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    }
}

/// Accepts connections on the agent socket and hands each request to `handler`.
final class AgentBridgeServer: @unchecked Sendable {
    typealias Handler = @Sendable ([String: Any]) async -> [String: Any]
    let url: URL
    private let handler: Handler
    private let lock = NSLock()
    private var listener: Int32 = -1

    init(url: URL = AgentSocket.defaultURL, handler: @escaping Handler) {
        self.url = url
        self.handler = handler
    }

    func start() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Only one Cairn holds the instance lease, so a socket left here is stale.
        // Never remove anything that is not a socket.
        var info = stat()
        if lstat(url.path, &info) == 0 {
            guard info.st_mode & S_IFMT == S_IFSOCK, unlink(url.path) == 0 else {
                throw AgentSocket.Failure(message: "Something other than Cairn's socket is at \(url.path).", notRunning: false)
            }
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, var address = AgentSocket.address(url.path) else {
            if fd >= 0 { close(fd) }
            throw AgentSocket.Failure(message: "Could not create the agent socket.", notRunning: false)
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(url.path, 0o600) == 0, listen(fd, 8) == 0 else {
            close(fd)
            throw AgentSocket.Failure(message: "Could not listen on the agent socket.", notRunning: false)
        }
        lock.withLock { listener = fd }
        let thread = Thread { [weak self] in self?.acceptLoop(fd) }
        thread.name = "Cairn agent bridge"
        thread.start()
    }

    func stop() {
        let fd = lock.withLock { () -> Int32 in let fd = listener; listener = -1; return fd }
        guard fd >= 0 else { return }
        shutdown(fd, SHUT_RDWR)
        close(fd)
        unlink(url.path)
    }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            var uid: uid_t = 0
            var gid: gid_t = 0
            guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { close(client); continue }
            AgentSocket.noSigPipe(client)
            let handler = handler
            Task.detached(priority: .userInitiated) {
                defer { close(client) }
                AgentSocket.setTimeout(client, 10)
                guard let line = AgentSocket.readLine(client, limit: 256 * 1_024),
                      let request = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
                    _ = AgentSocket.writeAll(client, Data(#"{"ok":false,"error":"Unreadable request."}"#.utf8) + Data([0x0A]))
                    return
                }
                let reply = await handler(request)
                let data = (try? JSONSerialization.data(withJSONObject: reply)) ?? Data(#"{"ok":false,"error":"Unencodable reply."}"#.utf8)
                _ = AgentSocket.writeAll(client, data + Data([0x0A]))
            }
        }
    }
}

/// The app side: plans and runs agent cleanups through the window's ScanStore.
@MainActor
final class AgentBridge {
    static let shared = AgentBridge()
    private weak var store: ScanStore?
    private var proEnabled: () -> Bool = { false }
    private var plans: [String: AgentCleanup.Plan] = [:]
    private var server: AgentBridgeServer?
    /// Replaced by the diagnostics to answer the approval prompt.
    var approve: (AgentCleanup.Plan) async -> Bool = { await AgentBridge.askPerson($0) }

    func attach(store: ScanStore, proEnabled: @escaping () -> Bool) {
        self.store = store
        self.proEnabled = proEnabled
        guard server == nil else { return }
        let server = AgentBridgeServer { request in await AgentBridge.shared.handle(request) }
        do { try server.start(); self.server = server }
        catch { NSLog("Cairn agent bridge did not start: \((error as? AgentSocket.Failure)?.message ?? error.localizedDescription)") }
    }

    func handle(_ request: [String: Any]) async -> [String: Any] {
        let client = AgentCleanup.displayName(request["client"] as? String)
        switch request["op"] as? String {
        case "ping":
            return ["ok": true, "mode": AgentCleaningMode.current.rawValue]
        case "plan":
            return await plan(request, client: client)
        case "run":
            return await run(planID: request["planId"] as? String ?? "", client: client)
        case "receipts":
            return receipts(limit: request["limit"] as? Int ?? 5)
        default:
            return ["ok": false, "error": "Unknown request."]
        }
    }

    // MARK: - Plan

    func plan(_ request: [String: Any], client: String, found: [ScanItem]? = nil) async -> [String: Any] {
        var spec = AgentCleanup.Request()
        if let raw = request["scope"] as? String {
            guard let scope = AgentCleanup.Scope(rawValue: raw) else { return ["ok": false, "error": "Unknown scope '\(raw)'. Use recommended, projects or category."] }
            spec.scope = scope
        }
        spec.category = request["category"] as? String
        spec.minIdleDays = max(0, request["minIdleDays"] as? Int ?? 0)
        spec.projectPaths = request["projects"] as? [String] ?? []
        if let gb = request["targetGB"] as? Double, gb > 0 { spec.targetBytes = Int64(gb * 1_000_000_000) }
        if spec.scope == .category {
            guard let category = spec.category, ScannerRegistry.all().contains(where: { $0.info.id == category }) else {
                return ["ok": false, "error": "Unknown or missing category. Call list_categories for valid ids."]
            }
        }
        let items: [ScanItem]
        if let found { items = found }
        else {
            guard await ScanGate.shared.acquire(.scan) else { return ["ok": false, "error": "Cairn is busy. Try again shortly."] }
            defer { ScanGate.shared.release() }
            let only: String? = spec.scope == .category ? spec.category : spec.scope == .projects ? ProjectIndex.categoryID : nil
            items = await Self.gather(category: only)
        }
        let selection = AgentCleanup.select(items, request: spec)
        let plan = AgentCleanup.Plan(id: UUID().uuidString, client: client, created: Date(), items: selection.items, heldBack: selection.heldBack)
        plans = plans.filter { Date().timeIntervalSince($0.value.created) <= AgentCleanup.planLifetime }
        plans[plan.id] = plan
        let mode = AgentCleaningMode.current
        let next: String
        switch mode {
        case .off: next = "Cleaning by AI tools is off. Show the user this plan and call open_cairn so they can review it in Cairn."
        case .ask: next = "Show the user this plan. run_cleanup will ask them to confirm in Cairn before anything is removed."
        case .allow: next = "Show the user this plan, then call run_cleanup with planId within 15 minutes."
        }
        return [
            "ok": true, "planId": plan.id, "cleaningMode": mode.rawValue,
            "totalBytes": plan.totalBytes, "total": Fmt.size(plan.totalBytes), "itemCount": plan.items.count,
            "items": plan.items.prefix(100).map(AgentCleanup.describe),
            "heldBackForReview": plan.heldBack.prefix(20).map { ["path": $0.resolvedURL.path, "bytes": $0.allocatedSize, "why": $0.note] as [String: Any] },
            "nextStep": next,
        ]
    }

    /// Runs the scanners off the main actor without touching the window's results.
    nonisolated static func gather(category: String?) async -> [ScanItem] {
        final class Sink: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var items: [ScanItem] = []
            func add(_ item: ScanItem) { lock.withLock { items.append(item) } }
        }
        let sink = Sink()
        let granted = FullDiskAccess.isGranted()
        for scanner in ScannerRegistry.all() where category == nil || scanner.info.id == category {
            let context = ScanContext(fdaGranted: granted, includeExternalVolumes: false, minSizeBytes: 5 * 1024 * 1024,
                                      emit: { sink.add($0) }, progress: { _ in }, isCancelled: { false })
            await scanner.scan(context)
        }
        return PathDedupe.apply(sink.items)
    }

    // MARK: - Run

    func run(planID: String, client: String) async -> [String: Any] {
        let plan = plans[planID]
        if let reason = AgentCleanup.refusal(plan: plan, mode: AgentCleaningMode.current) {
            return ["ok": false, "error": reason]
        }
        guard let plan, let store else {
            return ["ok": false, "error": "Cairn's window is closed. Call open_cairn, then try again."]
        }
        plans.removeValue(forKey: planID)
        if AgentCleaningMode.current == .ask {
            guard await approve(plan) else { return ["ok": false, "error": "The user chose not to free this space now."] }
        }
        let summary = await store.clean(plan.items, proEnabled: proEnabled(), runKind: plan.client)
        let measured = summary.capacityChanges.compactMap(\.delta).reduce(0, +)
        return [
            "ok": summary.accounting.completedCount > 0,
            "completed": summary.accounting.completedCount,
            "freedNowBytes": summary.accounting.freedBytes, "freedNow": Fmt.size(summary.accounting.freedBytes),
            "movedToTrashBytes": max(0, summary.accounting.trashBytes - summary.accounting.freedBytes),
            "measuredChangeBytes": measured,
            "measuredChange": summary.capacityChanges.map(\.changeText).joined(separator: "; "),
            "failed": summary.failed,
            "errors": Array(summary.errors.prefix(10)),
            "receipt": "Saved in Cairn › Activity as \(plan.client).",
        ]
    }

    // MARK: - Receipts

    private func receipts(limit: Int) -> [String: Any] {
        guard let store else { return ["ok": false, "error": "Cairn's window is closed. Call open_cairn, then try again."] }
        let runs = store.cleanupRuns.prefix(max(1, min(20, limit))).map { run -> [String: Any] in
            ["by": run.kind ?? "Cairn", "started": ISO8601DateFormatter().string(from: run.started),
             "completed": run.summary.accounting.completedCount, "freedNowBytes": run.summary.accounting.freedBytes,
             "measuredChange": run.summary.capacityChanges.map(\.changeText).joined(separator: "; "),
             "failed": run.summary.failed]
        }
        return ["ok": true, "cleanups": runs]
    }

    // MARK: - Approval

    static func askPerson(_ plan: AgentCleanup.Plan) async -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "\(plan.client) wants to free \(Fmt.size(plan.totalBytes))"
        let shown = plan.items.prefix(8).map { "• \($0.resolvedURL.lastPathComponent) (\(Fmt.size($0.allocatedSize)))  \($0.resolvedURL.deletingLastPathComponent().path)" }
        let more = plan.items.count > 8 ? "\n…and \(plan.items.count - 8) more." : ""
        alert.informativeText = shown.joined(separator: "\n") + more
            + "\n\nOnly caches and build files that rebuild themselves. Your files, AI chats and the Trash are not touched."
        alert.addButton(withTitle: "Free \(Fmt.size(plan.totalBytes))")
        alert.addButton(withTitle: "Not now")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
