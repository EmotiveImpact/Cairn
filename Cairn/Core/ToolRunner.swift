import Foundation
import Darwin

/// Runs CLI tools (docker / brew / pnpm / go / xcrun / simctl …) for the paid
/// "correct command" cleans (SPEC §6). Tools receive an absolute executable and
/// an argument array. Both tool discovery and execution have finite deadlines.
enum ToolRunner {
    struct Result {
        var status: Int32
        var stdout: String
        var stderr: String
        var timedOut: Bool
        var ok: Bool { status == 0 && !timedOut }
    }

    enum RunError: Error { case toolNotFound(String), pipeConfiguration }

    private static var resolvedCache: [String: String] = [:]
    private static let cacheLock = NSLock()
    private static let outputLimit = 256 * 1024 // retain diagnostics without growing with a chatty tool

    private static let fallbackDirs = [
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
        FileScan.home.appendingPathComponent(".asdf/shims").path,
        FileScan.home.appendingPathComponent(".local/share/mise/shims").path,
        FileScan.home.appendingPathComponent(".bun/bin").path,
        FileScan.home.appendingPathComponent(".cargo/bin").path,
    ]

    /// Tools that come with macOS always run from their system location, never
    /// from a look-alike placed earlier on the PATH. A program Cairn starts
    /// shares Cairn's Full Disk Access, so this matters.
    static let systemTools: [String: String] = [
        "tmutil": "/usr/bin/tmutil", "xcrun": "/usr/bin/xcrun",
        "diskutil": "/usr/sbin/diskutil", "pgrep": "/usr/bin/pgrep",
    ]

    /// A bare command name such as `docker` or `pnpm`: no paths, spaces or
    /// shell characters, so it can be looked up safely.
    static func isPlainName(_ tool: String) -> Bool {
        guard !tool.isEmpty, tool.count <= 64, !tool.hasPrefix("-"), !tool.hasPrefix(".") else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return tool.unicodeScalars.allSatisfy { $0.isASCII && allowed.contains($0) }
    }

    /// Refuse a program that anyone else could have replaced: one another user
    /// owns, or one that every account on the Mac may write to.
    static func isTrustworthy(_ path: String) -> Bool {
        let real = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        var info = stat()
        guard stat(real, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return false }
        guard info.st_uid == 0 || info.st_uid == getuid() else { return false }
        return info.st_mode & S_IWOTH == 0
    }

    static func resolve(_ tool: String) -> String? {
        if let fixed = systemTools[tool] {
            return FileManager.default.isExecutableFile(atPath: fixed) ? fixed : nil
        }
        guard isPlainName(tool) else { return nil }
        cacheLock.lock()
        let hit = resolvedCache[tool]
        cacheLock.unlock()
        if let hit { return hit.isEmpty ? nil : hit }

        // Shell startup can run arbitrary user plugins. Never hold the cache lock
        // during that subprocess, and never let it block another scan forever.
        var path = resolveViaLoginShell(tool).flatMap { isTrustworthy($0) ? $0 : nil }
        if path == nil {
            path = fallbackDirs.lazy
                .map { ($0 as NSString).appendingPathComponent(tool) }
                .first { FileManager.default.isExecutableFile(atPath: $0) && isTrustworthy($0) }
        }
        cacheLock.lock()
        resolvedCache[tool] = path ?? ""
        cacheLock.unlock()
        return path
    }

    private static func resolveViaLoginShell(_ tool: String) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shell) else { return nil }
        // Keep interactive startup so nvm/asdf/mise paths can be discovered, but
        // close stdin and give startup only three seconds before falling back.
        guard let result = try? execute(executable: shell,
                                        arguments: ["-l", "-i", "-c", "command -v \(tool)"],
                                        timeout: 3), result.ok else { return nil }
        let path = result.stdout.split(whereSeparator: \.isNewline).last.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    @discardableResult
    static func run(_ tool: String, _ arguments: [String], timeout: TimeInterval = 15) throws -> Result {
        guard let exe = resolve(tool) else { throw RunError.toolNotFound(tool) }
        return try execute(executable: exe, arguments: arguments, timeout: timeout)
    }

    static func runExecutable(_ path: String, _ arguments: [String], timeout: TimeInterval = 15) throws -> Result {
        try execute(executable: path, arguments: arguments, timeout: timeout)
    }

    static func isAvailable(_ tool: String) -> Bool { resolve(tool) != nil }

    /// Drain both pipes WHILE the child runs. Reading only after it exits can
    /// deadlock once a pipe fills; waiting for EOF can also hang if a descendant
    /// inherited a pipe. Output is capped in memory but always fully drained.
    private static func execute(executable: String, arguments: [String], timeout: TimeInterval) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        try? outPipe.fileHandleForWriting.close()
        try? errPipe.fileHandleForWriting.close()

        let outFD = outPipe.fileHandleForReading.fileDescriptor
        let errFD = errPipe.fileHandleForReading.fileDescriptor
        for fd in [outFD, errFD] {
            let flags = fcntl(fd, F_GETFL)
            guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0 else {
                // A blocking read would defeat every timeout below. Fail closed.
                if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
                try? outPipe.fileHandleForReading.close()
                try? errPipe.fileHandleForReading.close()
                throw RunError.pipeConfiguration
            }
        }

        var out = Data(), err = Data()
        var outOpen = true, errOpen = true
        let deadline = ProcessInfo.processInfo.systemUptime + max(0.1, timeout)
        var timedOut = false

        while process.isRunning {
            if outOpen { outOpen = drain(outFD, into: &out) }
            if errOpen { errOpen = drain(errFD, into: &err) }
            if Task.isCancelled || ProcessInfo.processInfo.systemUptime >= deadline {
                timedOut = true
                process.terminate()
                let grace = ProcessInfo.processInfo.systemUptime + 0.5
                while process.isRunning && ProcessInfo.processInfo.systemUptime < grace {
                    if outOpen { outOpen = drain(outFD, into: &out) }
                    if errOpen { errOpen = drain(errFD, into: &err) }
                    Thread.sleep(forTimeInterval: 0.02)
                }
                if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
                // Do not wait indefinitely for a child blocked in kernel I/O.
                let killDeadline = ProcessInfo.processInfo.systemUptime + 1.0
                while process.isRunning && ProcessInfo.processInfo.systemUptime < killDeadline {
                    Thread.sleep(forTimeInterval: 0.02)
                }
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }

        // Drain buffered output after exit, up to the retained-output budget.
        // A descendant can keep a pipe open, so never wait for EOF.
        for _ in 0..<4 {
            if outOpen { outOpen = drain(outFD, into: &out) }
            if errOpen { errOpen = drain(errFD, into: &err) }
            if !outOpen && !errOpen { break }
        }
        try? outPipe.fileHandleForReading.close()
        try? errPipe.fileHandleForReading.close()
        return Result(status: process.isRunning ? -1 : process.terminationStatus,
                      stdout: String(decoding: out, as: UTF8.self),
                      stderr: String(decoding: err, as: UTF8.self),
                      timedOut: timedOut)
    }

    /// Returns false on EOF/error. EAGAIN means the pipe is empty for now.
    private static func drain(_ fd: Int32, into data: inout Data) -> Bool {
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        // A child can produce output continuously. Yield back to the deadline
        // loop after a bounded amount, even when the pipe never goes empty.
        var drained = 0
        while drained < 64 * 1024 {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(fd, bytes.baseAddress!, bytes.count)
            }
            if count > 0 {
                drained += count
                let remaining = max(0, outputLimit - data.count)
                if remaining > 0 { data.append(contentsOf: buffer.prefix(min(count, remaining))) }
            } else if count == 0 {
                return false
            } else {
                return errno == EAGAIN || errno == EWOULDBLOCK
            }
        }
        return true
    }
}
