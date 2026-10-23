import Foundation

/// The space only the person can decide on: everything a scan found that is not
/// ready to free in one click, sorted into plain groups ("Videos in Movies",
/// "Zip files in Downloads") so a whole group can be cleared with one tick.
/// Together the groups add up to Home's "more to look through" number.
struct LookGroup: Identifiable {
    let id: String
    let title: String
    let line: String
    let items: [ScanItem]

    var bytes: Int64 { items.reduce(0) { $0 + $1.allocatedSize } }
    /// Bytes in things not changed for over a year: usually the easy yes.
    var oldBytes: Int64 { items.filter { $0.ageDays > 365 }.reduce(0) { $0 + $1.allocatedSize } }
    /// The three biggest, by a short readable name.
    var peek: [String] { items.prefix(3).map(LookThrough.shortName) }
}

enum LookThrough {
    private static let archiveTypes: Set<String> = ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz"]
    private static let installerTypes: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip"]

    /// Items that count: actionable, and not the one-click ready kind Home frees.
    static func candidates(_ items: [ScanItem]) -> [ScanItem] {
        items.filter { $0.isActionable && !CLI.isReady($0) }
    }

    static func groups(from items: [ScanItem], titles: [String: String] = [:],
                       home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [LookGroup] {
        let homePath = home.standardizedFileURL.path
        func under(_ folder: String, _ item: ScanItem) -> Bool {
            item.resolvedURL.standardizedFileURL.path.hasPrefix(homePath + "/" + folder + "/")
        }
        var buckets: [String: [ScanItem]] = [:]
        for item in candidates(items) {
            let ext = item.resolvedURL.pathExtension.lowercased()
            let name = item.resolvedURL.lastPathComponent
            let key: String
            if item.categoryID == "installers" || installerTypes.contains(ext) { key = "installers" }
            else if name.hasPrefix("Screen Recording") || name.hasPrefix("Screenshot") { key = "recordings" }
            else if item.categoryID == "android" { key = "android" }
            else if item.categoryID == "orphaned" { key = "orphaned" }
            else if item.categoryID == "dev-projects" { key = "projects" }
            else if under("Movies", item) { key = "movies" }
            else if under("Downloads", item) { key = archiveTypes.contains(ext) ? "archives" : "downloads" }
            else if under("Desktop", item) { key = "desktop" }
            else { key = "cat:" + item.categoryID }
            buckets[key, default: []].append(item)
        }
        return buckets.map { key, items in
            let sorted = items.sorted { $0.allocatedSize > $1.allocatedSize }
            let (title, line) = describe(key, count: sorted.count, titles: titles)
            return LookGroup(id: key, title: title, line: line, items: sorted)
        }
        .sorted { $0.bytes > $1.bytes }
    }

    private static func describe(_ key: String, count n: Int, titles: [String: String]) -> (String, String) {
        func files(_ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        switch key {
        case "movies": return ("Videos in Movies", files("video"))
        case "archives": return ("Zip files in Downloads", files("archive"))
        case "downloads": return ("Other big downloads", files("file"))
        case "installers": return ("App installers", files("installer") + " · once an app is installed you don't need these")
        case "recordings": return ("Screen recordings", files("recording"))
        case "desktop": return ("Desktop files", files("file"))
        case "android": return ("Old Android kit", "Only needed if you build Android apps")
        case "orphaned": return ("Leftovers from deleted apps", files("folder") + " from apps no longer on this Mac")
        case "projects": return ("Rebuildable files in your projects", files("folder") + " · your code is never touched")
        default:
            let id = String(key.dropFirst(4))
            return (titles[id] ?? "Other", files("item"))
        }
    }

    /// "WhatsApp" from "group.net.whatsapp.WhatsApp.shared", "Cymatics Equinox" from a zip name.
    static func shortName(_ item: ScanItem) -> String {
        var name = item.resolvedURL.deletingPathExtension().lastPathComponent
        if item.categoryID == "orphaned" {
            let parts = name.split(separator: ".").filter { !["group", "com", "net", "org", "io", "app", "shared"].contains($0.lowercased()) }
            if let last = parts.last { name = String(last) }
        }
        name = name.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        return name.count > 30 ? String(name.prefix(29)) + "…" : name
    }
}
