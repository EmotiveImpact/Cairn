import Foundation

/// Xcode & CoreSimulator developer artifacts (SPEC §3.1, developer wedge).
/// DerivedData rebuilds on demand → SAFE. DeviceSupport debug symbols re-extract
/// on the next device attach → REVIEW. Archives hold the only local dSYMs used to
/// symbolicate shipped crashes → never trashable, advice-only / RISKY. Simulator
/// caches are regenerable; unavailable Devices are pruned via `simctl`, never rm.
/// Superseded simulator runtimes are offered for `simctl runtime delete`, and
/// extra copies of Xcode are sized as advice for the Apps page.
/// These live under plain user dirs (0700) → no Full Disk Access needed.
struct XcodeScanner: CairnScanner {
    let info = CategoryInfo(
        id: "xcode",
        title: "Xcode & Simulators",
        subtitle: "DerivedData, DeviceSupport, Archives, simulators, old runtimes & Xcode copies",
        systemImage: "hammer.fill",
        group: .developer,
        requiresFDA: false
    )

    private let xcodeBundleID = "com.apple.dt.Xcode"
    private let simulatorBundleID = "com.apple.iphonesimulator"

    func scan(_ ctx: ScanContext) async {
        let xcode = FileScan.home.appendingPathComponent("Library/Developer/Xcode")
        let coreSimulator = FileScan.home.appendingPathComponent("Library/Developer/CoreSimulator")

        // 1) DerivedData — one SAFE, trashable item per project subfolder.
        ctx.progress("DerivedData")
        let derivedData = xcode.appendingPathComponent("DerivedData")
        if FileScan.exists(derivedData), let folders = FileScan.children(of: derivedData) {
            for folder in folders {
                if ctx.isCancelled() { return }
                let name = folder.lastPathComponent
                if let item = makeItem(
                    at: folder,
                    severity: .safe,
                    minSize: ctx.minSizeBytes,
                    isRegenerable: true,
                    requiresQuitBundleIDs: [xcodeBundleID],
                    cleanMethod: .trash,
                    note: "DerivedData for \(name) — Xcode rebuilds on demand",
                    selectedIfSafe: true
                ) {
                    ctx.emit(item)
                }
            }
        }

        // 2) Platform DeviceSupport — one REVIEW item per build subfolder.
        let deviceSupportDirs = ["iOS DeviceSupport", "watchOS DeviceSupport", "tvOS DeviceSupport"]
        for dirName in deviceSupportDirs {
            if ctx.isCancelled() { return }
            ctx.progress(dirName)
            let supportDir = xcode.appendingPathComponent(dirName)
            guard FileScan.exists(supportDir), let builds = FileScan.children(of: supportDir) else { continue }
            for build in builds {
                if ctx.isCancelled() { return }
                let buildName = build.lastPathComponent
                if let item = makeItem(
                    at: build,
                    severity: .review,
                    minSize: ctx.minSizeBytes,
                    isRegenerable: true,
                    requiresQuitBundleIDs: [xcodeBundleID],
                    cleanMethod: .trash,
                    note: "Debug symbols for \(buildName) — re-extracts on next attach"
                ) {
                    ctx.emit(item)
                }
            }
        }

        // 3) Archives — ONE advice-only, RISKY item. Holds the only local
        //    .xcarchive dSYMs needed to symbolicate already-shipped crashes.
        //    Never trashable: construct ScanItem directly, bypassing makeItem.
        if ctx.isCancelled() { return }
        ctx.progress("Archives")
        let archives = xcode.appendingPathComponent("Archives")
        if FileScan.exists(archives) {
            let stats = FileScan.measure(archives)
            ctx.emit(ScanItem(
                url: archives,
                allocatedSize: stats.allocatedSize,
                itemCount: stats.fileCount,
                latestModified: stats.latestModified,
                categoryID: info.id,
                severity: .risky,
                isRegenerable: false,
                requiresQuitBundleIDs: [],
                requiresRunning: false,
                cleanMethod: .adviceOnly,
                note: "Holds .xcarchive dSYMs to symbolicate shipped crashes — remove manually only if sure",
                permissionDenied: stats.permissionDenied,
                volumeURL: FileScan.volumeURL(of: archives),
                selected: false
            ))
        }

        // 4) CoreSimulator/Caches — SAFE, trashable simulator caches.
        if ctx.isCancelled() { return }
        ctx.progress("Simulator caches")
        let simCaches = coreSimulator.appendingPathComponent("Caches")
        if let item = makeItem(
            at: simCaches,
            severity: .safe,
            minSize: ctx.minSizeBytes,
            isRegenerable: true,
            requiresQuitBundleIDs: [simulatorBundleID],
            cleanMethod: .trash,
            note: "Simulator caches",
            selectedIfSafe: true
        ) {
            ctx.emit(item)
        }

        // 5) CoreSimulator/Devices — advice only. Even an unavailable device can
        //    hold app data that is not safely reconstructable. Size the dir.
        if ctx.isCancelled() { return }
        ctx.progress("Simulator devices")
        let devices = coreSimulator.appendingPathComponent("Devices")
        if FileScan.exists(devices) {
            let stats = FileScan.measure(devices)
            let prune = ToolCommand(tool: "xcrun", arguments: ["simctl", "delete", "unavailable"],
                                    display: "xcrun simctl delete unavailable")
            ctx.emit(ScanItem(
                url: devices,
                allocatedSize: stats.allocatedSize,
                itemCount: stats.fileCount,
                latestModified: stats.latestModified,
                categoryID: info.id,
                severity: .review,
                isRegenerable: true,
                requiresQuitBundleIDs: [simulatorBundleID],
                requiresRunning: false,
                cleanMethod: .tool(prune),
                note: "Simulators for runtimes that are no longer installed — removed with simctl. Available simulators are kept.",
                permissionDenied: stats.permissionDenied,
                volumeURL: FileScan.volumeURL(of: devices),
                selected: false
            ))
        }

        // 6) Downloaded simulator runtimes (one iOS version each, several GB).
        //    They live outside the home folder, so Cairn only removes them
        //    with simctl. The newest runtime per platform is never offered.
        if ctx.isCancelled() { return }
        emitOldRuntimes(ctx)

        // 7) Extra copies of Xcode. App bundles are removed in Apps, never
        //    from a cleanup list, so these are sized as advice.
        if ctx.isCancelled() { return }
        emitExtraXcodes(ctx)
    }

    // MARK: - Simulator runtimes

    struct Runtime: Equatable {
        var identifier: String
        var platform: String
        var version: String
        var sizeBytes: Int64
        var lastUsed: Date?
        var path: String?
    }

    /// Only ask simctl when a full Xcode and downloaded runtimes are both
    /// present: on a Mac without developer tools `xcrun` would offer to
    /// install them instead of answering.
    private func emitOldRuntimes(_ ctx: ScanContext) {
        let images = URL(fileURLWithPath: "/Library/Developer/CoreSimulator")
        guard FileScan.exists(images), !installedXcodes().isEmpty else { return }
        ctx.progress("Simulator runtimes")
        guard let result = try? ToolRunner.run("xcrun", ["simctl", "runtime", "list", "-j"], timeout: 20),
              result.ok else { return }
        for runtime in Self.supersededRuntimes(Self.parseRuntimes(result.stdout)) {
            if ctx.isCancelled() { return }
            let lastUsed = runtime.lastUsed.map { "last used \(Fmt.age(Date().timeIntervalSince($0) / 86_400))" } ?? "not used recently"
            let delete = ToolCommand(tool: "xcrun", arguments: ["simctl", "runtime", "delete", runtime.identifier],
                                     display: "xcrun simctl runtime delete \(runtime.identifier)")
            let url = runtime.path.map { URL(fileURLWithPath: $0) }
                ?? images.appendingPathComponent("Images/\(runtime.identifier).dmg")
            ctx.emit(ScanItem(
                url: url,
                allocatedSize: runtime.sizeBytes,
                latestModified: runtime.lastUsed ?? .distantPast,
                categoryID: info.id,
                severity: .review,
                isRegenerable: true,
                requiresQuitBundleIDs: [xcodeBundleID, simulatorBundleID],
                requiresRunning: false,
                cleanMethod: .tool(delete),
                note: "\(runtime.platform) \(runtime.version) simulator download, \(lastUsed). A newer \(runtime.platform) is installed; Xcode downloads this one again if a project needs it",
                volumeURL: FileScan.volumeURL(of: images),
                selected: false
            ))
        }
    }

    /// `simctl runtime list -j` is a dictionary keyed by runtime id. Fields
    /// are read defensively: anything without an id, version and size, or
    /// marked not deletable, is skipped.
    static func parseRuntimes(_ json: String) -> [Runtime] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let dates = ISO8601DateFormatter()
        dates.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainDates = ISO8601DateFormatter()
        return object.compactMap { key, value -> Runtime? in
            guard let entry = value as? [String: Any],
                  (entry["deletable"] as? Bool) ?? false,
                  let version = entry["version"] as? String,
                  let size = (entry["sizeBytes"] as? NSNumber)?.int64Value, size > 0 else { return nil }
            let id = (entry["identifier"] as? String) ?? key
            let platformID = (entry["platformIdentifier"] as? String) ?? (entry["runtimeIdentifier"] as? String) ?? ""
            let platform = ["xros": "visionOS", "watch": "watchOS", "appletv": "tvOS", "iphone": "iOS"]
                .first { platformID.lowercased().contains($0.key) }?.value ?? "Simulator"
            let used = (entry["lastUsedAt"] as? String).flatMap { dates.date(from: $0) ?? plainDates.date(from: $0) }
            return Runtime(identifier: id, platform: platform, version: version, sizeBytes: size,
                           lastUsed: used, path: entry["path"] as? String)
        }
    }

    /// Every runtime except the newest version of each platform.
    static func supersededRuntimes(_ runtimes: [Runtime]) -> [Runtime] {
        let byPlatform = Dictionary(grouping: runtimes, by: \.platform)
        return byPlatform.values.flatMap { group -> [Runtime] in
            guard let newest = group.max(by: { AndroidSDKScanner.versionLess($0.version, $1.version) }) else { return [] }
            return group.filter { $0.identifier != newest.identifier && AndroidSDKScanner.versionLess($0.version, newest.version) }
        }.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    // MARK: - Extra Xcode copies

    private func installedXcodes() -> [URL] {
        (FileScan.children(of: URL(fileURLWithPath: "/Applications")) ?? []).filter {
            $0.pathExtension == "app" && $0.lastPathComponent.hasPrefix("Xcode")
                && FileScan.exists($0.appendingPathComponent("Contents/Developer"))
        }
    }

    private func emitExtraXcodes(_ ctx: ScanContext) {
        let copies = installedXcodes().map { ($0, Self.bundleVersion($0)) }
        guard copies.count > 1,
              let newest = copies.max(by: { AndroidSDKScanner.versionLess($0.1, $1.1) }) else { return }
        for (app, version) in copies where app != newest.0 {
            if ctx.isCancelled() { return }
            ctx.progress(app.lastPathComponent)
            let stats = FileScan.measure(app, maxFiles: 400_000)
            ctx.emit(ScanItem(
                url: app,
                allocatedSize: stats.allocatedSize,
                itemCount: stats.fileCount,
                latestModified: stats.latestModified,
                categoryID: info.id,
                severity: .review,
                isRegenerable: false,
                requiresQuitBundleIDs: [xcodeBundleID],
                requiresRunning: false,
                cleanMethod: .adviceOnly,
                note: "\(app.deletingPathExtension().lastPathComponent) \(version) — an older copy beside Xcode \(newest.1). Remove it in Apps if no project needs it",
                permissionDenied: stats.permissionDenied,
                volumeURL: FileScan.volumeURL(of: app),
                selected: false
            ))
        }
    }

    private static func bundleVersion(_ app: URL) -> String {
        guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return "0" }
        return (plist["CFBundleShortVersionString"] as? String) ?? "0"
    }
}
