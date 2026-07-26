import Foundation

/// Runs CLI tools (docker / brew / pnpm / go / xcrun / simctl …) for the paid
/// "correct command" cleans (SPEC §6). Never `/bin/sh -c "string"` — always an
/// absolute executable + explicit argument array. Resolves tool paths through a
/// reconstructed login-shell PATH so corepack/nvm/asdf/mise shims (invisible to
/// a Finder-launched GUI app) are found.
enum ToolRunner {
    struct Result {
        var status: Int32
        var stdout: String
        var stderr: String
        var timedOut: Bool
        var ok: Bool { status == 0 && !timedOut }
    }

    enum RunError: Error { case toolNotFound(String) }

    // Cache resolved absolute tool paths for this session.
    private static var resolvedCache: [String: String] = [:]
    private static let cacheLock = NSLock()

    /// Common absolute fallbacks if shell-PATH resolution fails.
    private static let fallbackDirs = [
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
        FileScan.home.appendingPathComponent(".asdf/shims").path,
        FileScan.home.appendingPathComponent(".local/share/mise/shims").path,
        FileScan.home.appendingPathComponent(".bun/bin").path,
        FileScan.home.appendingPathComponent(".cargo/bin").path,
    ]

    /// Resolve a tool name to an absolute path, or nil if unavailable.
    static func resolve(_ tool: String) -> String? {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let hit = resolvedCache[tool] { return hit.isEmpty ? nil : hit }

        // 1) login-shell `command -v`
        if let viaShell = resolveViaLoginShell(tool) {
            resolvedCache[tool] = viaShell
            return viaShell
        }
        // 2) known absolute fallbacks
        for dir in fallbackDirs {
            let candidate = (dir as NSString).appendingPathComponent(tool)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                resolvedCache[tool] = candidate
                return candidate
            }
        }
        resolvedCache[tool] = ""   // remember the miss
        return nil
    }

    private static func resolveViaLoginShell(_ tool: String) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shell) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-l", "-i", "-c", "command -v \(tool)"]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n").last ?? ""
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    /// Run a resolved tool with a timeout. Read-only sizing calls should pass a
    /// short timeout; mutating calls a longer, cancellable one.
    @discardableResult
    static func run(_ tool: String, _ arguments: [String], timeout: TimeInterval = 15) throws -> Result {
        guard let exe = resolve(tool) else { throw RunError.toolNotFound(tool) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = arguments
        let outPipe = Pipe(); let errPipe = Pipe()
        p.standardOutput = outPipe; p.standardError = errPipe
        try p.run()

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        while p.isRunning {
            if Date() > deadline {
                p.terminate()                      // SIGTERM
                Thread.sleep(forTimeInterval: 0.5)
                if p.isRunning { kill(p.processIdentifier, SIGKILL) }
                timedOut = true
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return Result(
            status: p.isRunning ? -1 : p.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? "",
            timedOut: timedOut
        )
    }

    static func isAvailable(_ tool: String) -> Bool { resolve(tool) != nil }
}
