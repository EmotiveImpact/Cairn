import Foundation

/// Scanners overlap: an installer is also an old download, and the Chrome cache
/// sits inside the Google cache. This keeps each byte counted once. The first
/// listing of a path wins; a folder that arrives after things inside it
/// replaces them. Used by the app's live scan, the command line and MCP.
struct PathDedupe {
    private(set) var listed: Set<String> = []
    // Most findings are siblings. Only a path known to contain a prior finding
    // needs the descendant search; otherwise each admission is O(path depth).
    private var ancestors: Set<String> = []

    enum Verdict { case skip, keep(replacing: Set<String>) }

    static func key(_ item: ScanItem) -> String { item.resolvedURL.standardizedFileURL.path }

    mutating func admit(_ item: ScanItem) -> Verdict {
        let path = Self.key(item)
        var parent = path
        while !parent.isEmpty, parent != "/" {
            if listed.contains(parent) { return .skip }
            parent = (parent as NSString).deletingLastPathComponent
        }
        let prefix = path + "/"
        let inside: Set<String> = ancestors.contains(path) ? listed.filter { $0.hasPrefix(prefix) } : []
        listed.subtract(inside)
        listed.insert(path)
        var ancestor = (path as NSString).deletingLastPathComponent
        while !ancestor.isEmpty, ancestor != "/" {
            ancestors.insert(ancestor)
            ancestor = (ancestor as NSString).deletingLastPathComponent
        }
        return .keep(replacing: inside)
    }

    /// One pass over a finished list, in order.
    static func apply(_ items: [ScanItem]) -> [ScanItem] {
        var dedupe = PathDedupe()
        var kept: [ScanItem] = []
        for item in items {
            guard case .keep(let replaced) = dedupe.admit(item) else { continue }
            if !replaced.isEmpty { kept.removeAll { replaced.contains(key($0)) } }
            kept.append(item)
        }
        return kept
    }
}
