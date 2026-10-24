import Foundation

/// "Send a report": a plain text note about this Mac and Cairn's last scan and
/// clean, shown in full and editable before anything leaves the Mac. It never
/// includes file names, folder names or the account name, and nothing is sent
/// unless the person sends the email themselves.
enum ProblemReport {
    /// Where reports go. Nil until the support address is set up; the sheet
    /// then offers Copy only.
    static let address: String? = nil
    static let subject = "Cairn report"

    @MainActor static func text(store: ScanStore) -> String {
        let info = Bundle.main.infoDictionary
        var lines = [
            "What happened:",
            "",
            "",
            "----",
            "Cairn \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Mac \(model()) · \(chip) · \(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB memory",
            "Full Disk Access: \(FullDiskAccess.isGranted() ? "on" : "off")",
            "Removal: \(AppSettings.shared.removalMode.title) · AI tools may clean: \(AppSettings.shared.agentCleaning.rawValue)",
        ]
        if let capacity = StorageControl.shared.current {
            lines.append("Free space: \(Fmt.size(capacity.available)) of \(Fmt.size(capacity.total))")
        }
        if let scanned = store.lastScanDate {
            let found = store.buckets.reduce(Int64(0)) { $0 + $1.totalSize }
            lines.append("Last scan: \(scanned.formatted(date: .abbreviated, time: .shortened)) · \(store.buckets.count) categories · \(Fmt.size(found)) found")
        }
        if let clean = store.lastCleanSummary {
            lines.append("Last clean: \(clean.trashed) items · \(Fmt.size(clean.freedBytes)) freed · \(clean.failed) skipped\(clean.interrupted ? " · stopped early" : "")")
            for error in clean.errors.prefix(8) { lines.append("  · \(reason(error))") }
        }
        if let crash = latestCrash() { lines += ["", crash] }
        return lines.joined(separator: "\n")
    }

    /// Clean errors read "name: reason". Keep the reason only.
    static func reason(_ error: String) -> String {
        let reason = error.range(of: ": ").map { String(error[$0.upperBound...]) } ?? error
        return scrub(reason)
    }

    /// The home folder and account name are replaced wherever they appear.
    static func scrub(_ text: String) -> String {
        var text = text.replacingOccurrences(of: FileScan.home.path, with: "~")
        let user = NSUserName()
        if user.count >= 3 { text = text.replacingOccurrences(of: user, with: "(you)") }
        return text
    }

    private static var chip: String {
        #if arch(arm64)
        return "Apple silicon"
        #else
        return "Intel"
        #endif
    }

    private static func model() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "unknown" }
        var bytes = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        return String(cString: bytes)
    }

    /// The newest Cairn crash from the last 30 days: when, what kind, and the
    /// top of the crashed thread. Crash files hold no file names of yours.
    static func latestCrash() -> String? {
        let folder = FileScan.home.appendingPathComponent("Library/Logs/DiagnosticReports")
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return nil }
        let crashes = files.filter { $0.lastPathComponent.hasPrefix("Cairn") && $0.pathExtension == "ips" }
            .compactMap { url -> (URL, Date)? in
                guard let date = try? url.resourceValues(forKeys: Set(keys)).contentModificationDate,
                      Date().timeIntervalSince(date) < 30 * 86_400 else { return nil }
                return (url, date)
            }
            .sorted { $0.1 > $1.1 }
        guard let newest = crashes.first, let text = try? String(contentsOf: newest.0, encoding: .utf8) else { return nil }
        var lines = ["Crash: \(newest.1.formatted(date: .abbreviated, time: .shortened)) (\(crashes.count) in the last 30 days)"]
        // An .ips file is a one-line JSON header, then the JSON report.
        if let newline = text.firstIndex(of: "\n"),
           let body = try? JSONSerialization.jsonObject(with: Data(text[text.index(after: newline)...].utf8)) as? [String: Any] {
            if let exception = body["exception"] as? [String: Any] {
                lines.append("  \([exception["type"], exception["signal"]].compactMap { $0 as? String }.joined(separator: " · "))")
            }
            if let threads = body["threads"] as? [[String: Any]], let index = body["faultingThread"] as? Int,
               threads.indices.contains(index), let frames = threads[index]["frames"] as? [[String: Any]] {
                for symbol in frames.compactMap({ $0["symbol"] as? String }).prefix(8) { lines.append("  \(scrub(symbol))") }
            }
        }
        return lines.joined(separator: "\n")
    }
}
