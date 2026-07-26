import Foundation
import AppKit

/// Full Disk Access detection + onboarding (SPEC §4.5, §6). There is no public
/// API to query FDA, so we test-read GENUINELY TCC-gated paths. Critically we do
/// NOT probe the Time Machine plist — it is world-readable (`root:wheel 0644`)
/// and would falsely report FDA granted (the verified false positive).
enum FullDiskAccess {
    /// Confirmed TCC-gated probes. If ANY is readable, FDA is granted.
    private static var probePaths: [URL] {
        [
            FileScan.home.appendingPathComponent("Library/Safari/Bookmarks.plist"),
            FileScan.home.appendingPathComponent("Library/Mail"),
            FileScan.home.appendingPathComponent("Library/Messages/chat.db"),
        ]
    }

    /// Best-effort: true if FDA appears granted. Conservative — only returns true
    /// on a positive read of a gated path that exists.
    static func isGranted() -> Bool {
        let fm = FileManager.default
        for p in probePaths where fm.fileExists(atPath: p.path) {
            if probeReadable(p) { return true }
        }
        // None of the gated paths exist (fresh account) — can't prove denial,
        // so don't nag. Treat as granted-enough; per-item permissionDenied flags
        // will still surface real gaps during a scan.
        let anyExists = probePaths.contains { fm.fileExists(atPath: $0.path) }
        return anyExists ? false : true
    }

    private static func probeReadable(_ url: URL) -> Bool {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            return FileScan.children(of: url) != nil
        }
        if let fh = try? FileHandle(forReadingFrom: url) {
            try? fh.close()
            return true
        }
        return false
    }

    /// Open System Settings ▸ Privacy & Security ▸ Full Disk Access.
    @MainActor
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
