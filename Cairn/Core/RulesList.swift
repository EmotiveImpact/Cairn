import Foundation

/// Everything Cairn looks for, written from the scanners themselves so the
/// published list can never drift from what the app does. Shown in Settings
/// and printed by `cairn rules` as Markdown for the website.
enum RulesList {
    struct Entry: Identifiable, Sendable {
        let id: String
        let title: String
        let detail: String
        let needsFullDiskAccess: Bool
    }

    struct Section: Identifiable, Sendable {
        let id: String
        let title: String
        let entries: [Entry]
    }

    static let promises = [
        "Nothing is removed until you have reviewed it.",
        "Your own files go to the Bin, so you can put them back.",
        "Caches and build files that rebuild on their own are deleted, so the space comes back straight away. Settings can send them to the Bin instead.",
        "Every item is checked again against Cairn's protected list just before it moves: system files, credentials, your emails, Messages, Photos, iCloud, source code and AI conversation history are never touched.",
        "Apps that are still open keep their caches until you close them.",
    ]

    private static let order: [(CategoryGroup, String)] = [
        (.developer, "Developer tools"), (.ai, "AI tools"), (.creative, "Creative apps"), (.general, "Everyday Mac"),
    ]

    static func sections(_ scanners: [CairnScanner] = ScannerRegistry.all()) -> [Section] {
        order.compactMap { group, title in
            let entries = scanners.filter { $0.info.group == group }.map {
                Entry(id: $0.info.id, title: $0.info.title, detail: $0.info.subtitle, needsFullDiskAccess: $0.info.requiresFDA)
            }
            return entries.isEmpty ? nil : Section(id: group.rawValue, title: title, entries: entries)
        }
    }

    static func markdown(version: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) -> String {
        var lines = ["# What Cairn looks for", ""]
        if let version { lines += ["Written from Cairn \(version).", ""] }
        lines += promises.map { "- \($0)" } + [""]
        for section in sections() {
            lines += ["## \(section.title)", ""]
            for entry in section.entries {
                lines.append("- **\(entry.title)**: \(entry.detail)\(entry.needsFullDiskAccess ? " (needs Full Disk Access)" : "")")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
