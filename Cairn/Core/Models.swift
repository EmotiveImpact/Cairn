import Foundation
import Darwin

// MARK: - Severity (computed, never assumed)

/// SAFE = regenerates locally, trivial cost (may be pre-selected once the
/// regenerability check passes). REVIEW = regenerates expensively or holds the
/// only local copy (never pre-selected). RISKY = irreplaceable; never selectable
/// without an explicit per-item confirm.
enum Severity: Int, Comparable, Codable, CaseIterable {
    case safe = 0
    case review = 1
    case risky = 2

    static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .safe: return "Safe"
        case .review: return "Review"
        case .risky: return "Risky"
        }
    }
}

// MARK: - Clean method

/// A tool invocation (the paid "correct command" feature). Never built as a
/// shell string — `tool` is resolved to an absolute path and `arguments` is an
/// explicit array (no `/bin/sh -c`).
struct ToolCommand: Equatable {
    var tool: String           // "docker", "xcrun", "go", "pnpm"…
    var arguments: [String]
    var display: String        // shown in UI, e.g. "docker builder prune"
    /// `docker system prune -a --volumes` etc. — destroys named volumes; must be
    /// behind a typed confirmation, never a checkbox.
    var destroysData: Bool = false
}

/// How an item is reclaimed.
enum CleanMethod: Equatable {
    case trash                 // move the path to ITS OWN volume's Trash
    case emptyTrash            // empty a Trash directory (the genuine reclaim)
    case tool(ToolCommand)     // run a CLI tool (paid)
    case adviceOnly            // non-actionable advice card (Docker.raw, Nix, sleepimage)

    // Everything except advice has a reviewed executor in Cleaner.
    var isActionable: Bool { if case .adviceOnly = self { return false } else { return true } }
    var isPaid: Bool { if case .tool = self { return true } else { return false } }
}

/// What happens to reviewed files. Trash keeps Put Back but frees nothing until
/// the Trash is emptied; deleting frees the space straight away.
enum RemovalMode: String, CaseIterable, Identifiable, Sendable {
    case smart    // rebuildable caches and build output are deleted, personal files go to Trash
    case delete   // everything is deleted immediately
    case trash    // everything goes to Trash (recoverable, frees nothing yet)
    var id: String { rawValue }
    var title: String {
        switch self {
        case .smart: return "Smart"
        case .delete: return "Delete now"
        case .trash: return "Move to Trash"
        }
    }
    var detail: String {
        switch self {
        case .smart: return "Rebuildable caches and build files are deleted so space is freed now. Personal files go to Trash."
        case .delete: return "Everything selected is deleted and the space is freed now. No Put Back."
        case .trash: return "Everything selected goes to Trash. Space is freed when the Trash is emptied."
        }
    }
    /// The saved preference, readable off the main actor.
    static var current: RemovalMode {
        UserDefaults.standard.string(forKey: "cairn.removalMode").flatMap(RemovalMode.init(rawValue:)) ?? .smart
    }
    /// Whether a reviewed item should skip the Trash under this mode.
    func deletesImmediately(_ item: ScanItem) -> Bool {
        switch self {
        case .delete: return true
        case .trash: return false
        case .smart: return item.isRebuildable
        }
    }
}

// MARK: - Category

enum CategoryGroup: String, Codable, Sendable {
    case developer
    case ai
    case creative
    case general
}

struct CategoryInfo: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let group: CategoryGroup
    /// Whether enabling this scanner requires Full Disk Access (most dev-dir
    /// scanners do NOT — `~/.npm`, `~/.cargo`, `~/go` are plain 0700 user dirs).
    let requiresFDA: Bool
}

// MARK: - ScanItem

/// The filesystem object seen when a result was created. A path can be reused
/// by a different file after review, so a path comparison alone is insufficient.
struct SourceIdentity: Equatable, Codable, Sendable {
    let device: UInt64
    let inode: UInt64
    static func read(_ url: URL) -> SourceIdentity? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return SourceIdentity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino))
    }
}

/// Captures both the object and its resolved location when a user reviews it.
/// A later item at the same path is not the reviewed item.
struct SourceSnapshot: Equatable, Sendable {
    let resolvedPath: String
    let identity: SourceIdentity

    static func read(_ url: URL) -> SourceSnapshot? {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        guard let identity = SourceIdentity.read(resolved) else { return nil }
        return SourceSnapshot(resolvedPath: resolved.path, identity: identity)
    }

    func matches(_ url: URL) -> Bool { Self.read(url) == self }
}

struct ScanItem: Identifiable {
    let id = UUID()
    var url: URL                       // original path as surfaced
    var resolvedURL: URL               // symlink-resolved real path (what we act on)
    var allocatedSize: Int64           // on-disk bytes (inode-aware where available)
    var itemCount: Int                 // files counted
    var latestModified: Date
    var categoryID: String
    var severity: Severity
    var isRegenerable: Bool            // computed; SAFE requires this true
    var requiresQuitBundleIDs: [String] // owning apps that must quit before cleaning
    var requiresRunning: Bool          // e.g. Docker daemon must be UP to prune
    var cleanMethod: CleanMethod
    var note: String
    var permissionDenied: Bool         // size may be incomplete (FDA)
    var volumeURL: URL?                // the volume this lives on (for volume-aware trash)
    var selected: Bool
    let sourceIdentity: SourceIdentity?
    /// Set by ScanStore from the reviewed RemovalMode just before execution.
    var deleteImmediately = false

    init(
        url: URL,
        resolvedURL: URL? = nil,
        allocatedSize: Int64,
        itemCount: Int = 0,
        latestModified: Date = .distantPast,
        categoryID: String,
        severity: Severity,
        isRegenerable: Bool = true,
        requiresQuitBundleIDs: [String] = [],
        requiresRunning: Bool = false,
        cleanMethod: CleanMethod = .trash,
        note: String = "",
        permissionDenied: Bool = false,
        volumeURL: URL? = nil,
        selected: Bool = false,
        sourceIdentity: SourceIdentity? = nil
    ) {
        self.url = url
        let resolved = resolvedURL ?? url.resolvingSymlinksInPath()
        self.resolvedURL = resolved
        self.allocatedSize = allocatedSize
        self.itemCount = itemCount
        self.latestModified = latestModified
        self.categoryID = categoryID
        self.severity = severity
        self.isRegenerable = isRegenerable
        self.requiresQuitBundleIDs = requiresQuitBundleIDs
        self.requiresRunning = requiresRunning
        self.cleanMethod = cleanMethod
        self.note = note
        self.permissionDenied = permissionDenied
        self.volumeURL = volumeURL
        self.selected = selected
        self.sourceIdentity = sourceIdentity ?? SourceIdentity.read(resolved)
    }

    var ageDays: Double {
        max(0, Date().timeIntervalSince(latestModified) / 86_400)
    }

    var isActionable: Bool { cleanMethod.isActionable }

    /// Contents a reinstall or rebuild restores: verified-regenerable caches and
    /// build output, plus any node_modules (dependencies, never personal data).
    var isRebuildable: Bool {
        guard case .trash = cleanMethod, severity != .risky else { return false }
        return (isRegenerable && severity == .safe) || resolvedURL.lastPathComponent == "node_modules"
    }
}

// MARK: - Formatting

enum Fmt {
    /// Formatters are expensive to build (each one does locale lookups). `size` is
    /// called dozens of times per render across the dashboard and tables, so a
    /// fresh formatter per call showed up as constant LocaleCache churn in
    /// profiles. Build once, reuse. NSCache-free: these are immutable after setup.
    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        f.countStyle = .file
        f.allowsNonnumericFormatting = false // "0 KB", never "Zero KB"
        return f
    }()
    private static let decimalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func size(_ bytes: Int64) -> String {
        byteFormatter.string(fromByteCount: max(0, bytes))
    }

    /// "1,284" — grouped integer.
    static func grouped(_ n: Int) -> String {
        decimalFormatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// "2 days ago" — relative to now.
    static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    /// Split a formatted size into (value, unit), e.g. ("118", "GB").
    static func split(_ bytes: Int64) -> (value: String, unit: String) {
        // ByteCountFormatter separates value/unit with a NON-breaking space on some
        // locales, so split on any whitespace (not just U+0020) or the unit is lost.
        let parts = size(bytes).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if parts.count >= 2 { return (parts[0], parts.dropFirst().joined(separator: " ")) }
        return (parts.first ?? "0", "")
    }

    static func age(_ days: Double) -> String {
        if days < 1 {
            let h = Int(days * 24)
            return h <= 0 ? "today" : "\(h)h"
        }
        if days < 30 { return "\(Int(days))d" }
        if days < 365 { return "\(Int(days / 30))mo" }
        return String(format: "%.1fy", days / 365)
    }
}
