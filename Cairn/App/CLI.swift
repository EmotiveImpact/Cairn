import Foundation

/// The `cairn` command line.
///
/// The scan engine was already headless — `--selftest` has always run every
/// scanner with no window server — so this is argument parsing and output
/// formatting over the same code the GUI uses. Scans and cleanup previews use
/// the same scanners, while removal remains in the reviewed app workflow.
///
/// CLI cleanup is preview-only until a reviewed selection can be bound to the
/// exact sources the executor will act on. A fresh scan plus `--yes` is not
/// sufficient authorization for a newly discovered set of files.
///
///     cairn status
///     cairn scan [--json] [--category <id>]
///     cairn clean --safe [--category <id>] [--dry-run]
///     cairn categories
enum CLI {
    static let commands: Set<String> = ["status", "scan", "clean", "categories", "help", "--help", "-h"]

    static func run(_ args: [String]) {
        let command = args.first ?? "help"
        let flags = Set(args.dropFirst().filter { $0.hasPrefix("-") })
        let category = value(of: "--category", in: args)

        switch command {
        case "status":      status(json: flags.contains("--json"))
        case "scan":        scan(json: flags.contains("--json"), category: category)
        case "clean":
            // Refuse before collecting candidates. `--yes` must never turn a
            // new scan into consent for a different set of files.
            if flags.contains("--yes") || flags.contains("-y") {
                let message = "CLI cleanup is preview-only. --yes cannot authorize newly scanned files. Open Cairn, select exact items, and review the action there.\n"
                FileHandle.standardError.write(Data(message.utf8))
                exit(2)
            }
            clean(category: category)
        case "categories":  categories()
        default:            help()
        }
    }

    // MARK: - Commands

    private static func status(json: Bool) {
        let free = Volumes.homeFree()
        let total = DeviceInfo.totalCapacity
        let lifetime = Int64(UserDefaults.standard.integer(forKey: "cairn.lifetimeReclaimedBytes"))
        let trend = StorageHistory.summary(currentFree: free)

        if json {
            printJSON([
                "freeBytes": free,
                "totalBytes": total,
                "lifetimeAffectedEstimateBytes": lifetime,
                "trend": trend.text,
            ])
            return
        }
        print("Free space   \(Fmt.size(free)) of \(Fmt.size(total))")
        print("Trend        \(trend.text)")
        print("Affected     \(Fmt.size(lifetime)) in recorded file-size estimates; not space freed")
    }

    private static func scan(json: Bool, category: String?) {
        let items = collect(category: category)
        let total = items.reduce(Int64(0)) { $0 + $1.allocatedSize }

        if json {
            printJSON([
                "totalBytes": total,
                "itemCount": items.count,
                "items": items.map {
                    [
                        "path": $0.resolvedURL.path,
                        "bytes": $0.allocatedSize,
                        "category": $0.categoryID,
                        "severity": $0.severity.label,
                        "regenerable": $0.isRegenerable,
                        "note": $0.note,
                    ] as [String: Any]
                },
            ])
            return
        }

        guard !items.isEmpty else { print("No measured candidates found."); return }
        let byCategory = Dictionary(grouping: items, by: { $0.categoryID })
        for (id, entries) in byCategory.sorted(by: { bytes(of: $0.value) > bytes(of: $1.value) }) {
            print("\n▸ \(id) — \(Fmt.size(bytes(of: entries)))")
            for item in entries.sorted(by: { $0.allocatedSize > $1.allocatedSize }).prefix(10) {
                let tier = item.severity.label.uppercased().padding(toLength: 6, withPad: " ", startingAt: 0)
                print("   \(tier) \(Fmt.size(item.allocatedSize).padding(toLength: 10, withPad: " ", startingAt: 0)) \(item.resolvedURL.path)")
            }
            if entries.count > 10 { print("   … and \(entries.count - 10) more") }
        }
        print("\nTotal measured candidates: \(Fmt.size(total)) across \(items.count) items")
    }

    private static func clean(category: String?) {
        // Preview the narrowly eligible set. No CLI flag authorizes removal;
        // the interactive app records an exact reviewed selection first.
        let candidates = collect(category: category).filter { item in
            guard item.severity == .safe, item.isRegenerable, !item.requiresRunning else { return false }
            if case .trash = item.cleanMethod { return true }
            return false
        }
        let total = candidates.reduce(Int64(0)) { $0 + $1.allocatedSize }

        guard !candidates.isEmpty else { print("Nothing safe to clean."); return }

        print("Would move \(candidates.count) items to the Trash — \(Fmt.size(total)):\n")
        for item in candidates.sorted(by: { $0.allocatedSize > $1.allocatedSize }).prefix(20) {
            print("   \(Fmt.size(item.allocatedSize).padding(toLength: 10, withPad: " ", startingAt: 0)) \(item.resolvedURL.path)")
        }
        if candidates.count > 20 { print("   … and \(candidates.count - 20) more") }
        print("\nPreview only — nothing was removed. Open Cairn to select exact items and review cleanup.")
    }

    private static func categories() {
        for scanner in ScannerRegistry.all() {
            print("\(scanner.info.id.padding(toLength: 16, withPad: " ", startingAt: 0)) \(scanner.info.title)")
        }
    }

    private static func help() {
        print("""
        cairn — reclaim disk space, safely.

          cairn status                     available capacity, trend, affected-size estimates
          cairn scan [--category <id>]     measure cleanup candidates
          cairn clean --safe               preview eligible Trash candidates only
          cairn categories                 list scanner ids

        Flags
          --json          machine-readable output (status, scan)
          --category <id> restrict to one category
          --dry-run       explicit preview (the CLI never removes files)
          --yes, -y       unavailable; CLI cleanup requires exact-item review

        Use the app to select and review exact items before cleanup. The CLI
        never removes files. Cairn protects AI assistant history, iCloud
        mirrors, Keychains, ssh keys and Documents.
        """)
    }

    // MARK: - Helpers

    private static func bytes(of items: [ScanItem]) -> Int64 {
        items.reduce(Int64(0)) { $0 + $1.allocatedSize }
    }

    private static func value(of flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// Runs the scanners synchronously — a CLI has no run loop to return to.
    private static func collect(category: String?) -> [ScanItem] {
        let scanners = ScannerRegistry.all().filter { category == nil || $0.info.id == category }
        if scanners.isEmpty, let category {
            print("Unknown category '\(category)'. Try: cairn categories")
            return []
        }
        let sink = Sink()
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            for scanner in scanners {
                let ctx = ScanContext(
                    fdaGranted: FullDiskAccess.isGranted(),
                    includeExternalVolumes: false,
                    minSizeBytes: 5 * 1024 * 1024,
                    emit: { sink.add($0) },
                    progress: { _ in },
                    isCancelled: { false }
                )
                await scanner.scan(ctx)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return sink.items
    }

    private final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var items: [ScanItem] = []
        func add(_ item: ScanItem) { lock.lock(); items.append(item); lock.unlock() }
    }

    private static func printJSON(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        print(text)
    }
}
