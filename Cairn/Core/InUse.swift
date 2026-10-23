import Foundation
import Darwin

/// Folders a running program depends on right now: a build folder that holds
/// the binary of a running process, or one a build wrote to in the last few
/// minutes. Clean skips these, so a cleanup never pulls files out from under a
/// running tool or a build in progress.
enum InUse {
    /// Executable paths of every process this user can see.
    static func runningExecutables() -> [String] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return [] }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        var paths: [String] = []
        for pid in pids.prefix(Int(filled)) where pid > 0 {
            let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
            if length > 0 { paths.append(String(cString: buffer)) }
        }
        return paths
    }

    /// Why this item should be left alone now, or nil when it is safe to act on.
    static func reason(_ item: ScanItem, running: [String], now: Date = Date()) -> String? {
        let folder = item.resolvedURL.standardizedFileURL.path + "/"
        if running.contains(where: { $0.hasPrefix(folder) }) {
            return "\(item.resolvedURL.lastPathComponent) in \(item.resolvedURL.deletingLastPathComponent().lastPathComponent): a running program uses it."
        }
        if item.categoryID == "dev-projects", item.latestModified > .distantPast,
           now.timeIntervalSince(item.latestModified) < 15 * 60 {
            return "\(item.resolvedURL.lastPathComponent) in \(item.resolvedURL.deletingLastPathComponent().lastPathComponent): changed in the last 15 minutes, so a build may be running."
        }
        return nil
    }
}
