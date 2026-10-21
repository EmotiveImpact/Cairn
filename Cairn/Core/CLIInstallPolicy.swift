import Foundation
import Darwin

/// Never replace an unrelated command at /usr/local/bin/cairn. lstat also sees
/// dangling symlinks, which FileManager.fileExists(atPath:) would miss.
enum CLIInstallPolicy {
    enum TargetState: Equatable { case absent, ownedLink, conflict }

    static let target = URL(fileURLWithPath: "/usr/local/bin/cairn")

    static func state(at target: URL, for binary: URL) -> TargetState {
        var metadata = stat()
        guard lstat(target.path, &metadata) == 0 else {
            return errno == ENOENT ? .absent : .conflict
        }
        guard (metadata.st_mode & 0o170000) == 0o120000,
              let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: target.path) else {
            return .conflict
        }
        let linked = URL(fileURLWithPath: destination, relativeTo: target.deletingLastPathComponent())
            .resolvingSymlinksInPath().standardizedFileURL
        return linked == binary.resolvingSymlinksInPath().standardizedFileURL ? .ownedLink : .conflict
    }

    static func quoteForShell(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
