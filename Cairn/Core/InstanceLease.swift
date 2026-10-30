import Foundation
import AppKit
import Darwin

/// Kernel-owned lifetime lock: process exit (including a crash) releases it.
/// The lock file stays in place so a competing process cannot lock a new inode.
final class InstanceLease {
    private let descriptor: Int32
    private init(_ descriptor: Int32) { self.descriptor = descriptor }
    deinit { close(descriptor) }
    static func acquire(at url: URL) throws -> InstanceLease? {
        let fd = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_nlink == 1,
              info.st_mode & S_IFMT == S_IFREG else { close(fd); throw CocoaError(.fileReadNoPermission) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno; close(fd)
            if code == EWOULDBLOCK { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        return InstanceLease(fd)
    }
    private static var held: InstanceLease?
    static func claimApplication() -> Bool {
        // Older builds don't know about this lock. Detect them before opening
        // shared state; never terminate an existing app or take over its files.
        if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: "com.emotiveimpact.cairn")
            .first(where: { $0.processIdentifier != getpid() && !$0.isTerminated }) {
            existing.activate(options: [])
            fputs("Cairn is already running. Use the existing app or quit it normally before opening this copy.\n", stderr)
            return false
        }
        do {
            let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Cairn", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            held = try acquire(at: base.appendingPathComponent("instance.lock"))
            guard held != nil else {
                fputs("Another Cairn process owns the data store. No second instance was started.\n", stderr)
                return false
            }
            return true
        } catch {
            fputs("Cairn could not secure exclusive access to its data. Startup stopped: \(error.localizedDescription)\n", stderr)
            return false
        }
    }
}
