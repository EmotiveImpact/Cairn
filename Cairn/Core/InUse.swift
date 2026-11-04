import Foundation
import Darwin

/// Folders a running program depends on right now: a build folder that holds
/// the binary of a running process, a Gradle folder while Gradle runs, or one a
/// build wrote to in the last few minutes. Clean skips these, so a cleanup never pulls files out from under a
/// running tool or a build in progress.
enum InUse {
    /// Every process id this user can see.
    private static func allPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return [] }
        return pids.prefix(Int(filled)).filter { $0 > 0 }
    }

    /// Executable paths of every process this user can see.
    static func runningExecutables() -> [String] {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        var paths: [String] = []
        for pid in allPIDs() {
            let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
            if length > 0 { paths.append(String(cString: buffer)) }
        }
        return paths
    }

    /// The command line of every process this user owns. macOS keeps other
    /// users' command lines private, so those are left out.
    static func runningCommandLines() -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var argMax: Int32 = 0
        var argMaxSize = MemoryLayout<Int32>.size
        if sysctl(&mib, 2, &argMax, &argMaxSize, nil, 0) != 0 || argMax <= 0 { argMax = 1 << 20 }
        var buffer = [UInt8](repeating: 0, count: Int(argMax))
        var lines: [String] = []
        for pid in allPIDs() {
            var request: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
            var size = buffer.count
            guard sysctl(&request, 3, &buffer, &size, nil, 0) == 0 else { continue }
            if let line = commandLine(fromProcArgs: buffer, size: size) { lines.append(line) }
        }
        return lines
    }

    /// Reads the arguments out of a KERN_PROCARGS2 reply: the argument count,
    /// the executable path and its padding, then each argument ending in a zero.
    static func commandLine(fromProcArgs bytes: [UInt8], size: Int) -> String? {
        let header = MemoryLayout<Int32>.size
        let end = min(size, bytes.count)
        guard end > header else { return nil }
        let argc = bytes.withUnsafeBytes { $0.load(as: Int32.self) }
        guard argc > 0 else { return nil }
        var index = header
        while index < end && bytes[index] != 0 { index += 1 }
        while index < end && bytes[index] == 0 { index += 1 }
        var arguments: [String] = []
        var start = index
        while index < end && arguments.count < Int(argc) {
            if bytes[index] == 0 {
                arguments.append(String(decoding: bytes[start..<index], as: UTF8.self))
                start = index + 1
            }
            index += 1
        }
        return arguments.isEmpty ? nil : arguments.joined(separator: " ")
    }

    /// True for a Gradle build, a Gradle background process (daemon) or one of
    /// its workers. Each runs a Java class in Gradle's own `org.gradle` package.
    static func isGradleProcess(_ commandLine: String) -> Bool {
        commandLine.contains("org.gradle.")
    }

    /// True when any Gradle build or Gradle background process is running now.
    static func gradleRunning() -> Bool {
        runningCommandLines().contains(where: isGradleProcess)
    }

    /// Folders that Gradle reads while it builds: everything under `~/.gradle`.
    static func isGradleFolder(_ item: ScanItem) -> Bool {
        item.resolvedURL.standardizedFileURL.path.contains("/.gradle/")
    }

    /// True when the item holds this running copy of Cairn (its app or the
    /// build folder it runs from) or sits inside it. Never offered, never removed.
    static func holdsCairn(_ item: ScanItem) -> Bool {
        let path = item.resolvedURL.standardizedFileURL.path
        let own = [Bundle.main.bundleURL.standardizedFileURL.path,
                   Bundle.main.executableURL?.standardizedFileURL.path].compactMap { $0 }
        return own.contains { $0 == path || $0.hasPrefix(path + "/") || path.hasPrefix($0 + "/") }
    }

    /// Why this item should be left alone now, or nil when it is safe to act on.
    /// `commandLines` only matters for Gradle folders, so callers read it only
    /// when one is being cleaned.
    static func reason(_ item: ScanItem, running: [String], commandLines: [String] = [],
                       now: Date = Date()) -> String? {
        let folder = item.resolvedURL.standardizedFileURL.path + "/"
        if holdsCairn(item) { return "\(item.resolvedURL.lastPathComponent): Cairn itself runs from here." }
        if running.contains(where: { $0.hasPrefix(folder) }) {
            return "\(item.resolvedURL.lastPathComponent) in \(item.resolvedURL.deletingLastPathComponent().lastPathComponent): a running program uses it."
        }
        // A Gradle build can read its caches without changing them, so a quiet
        // cache is not proof that nothing is using it.
        if isGradleFolder(item), commandLines.contains(where: isGradleProcess) {
            return "\(item.resolvedURL.lastPathComponent) in \(item.resolvedURL.deletingLastPathComponent().lastPathComponent): Gradle is still running. Run gradle --stop, or wait for it to stop by itself (up to 3 hours), then clean again."
        }
        if item.categoryID == "dev-projects", item.latestModified > .distantPast,
           now.timeIntervalSince(item.latestModified) < 15 * 60 {
            return "\(item.resolvedURL.lastPathComponent) in \(item.resolvedURL.deletingLastPathComponent().lastPathComponent): changed in the last 15 minutes, so a build may be running."
        }
        return nil
    }
}
