import Foundation

/// Xcode & CoreSimulator developer artifacts (SPEC §3.1, developer wedge).
/// DerivedData rebuilds on demand → SAFE. DeviceSupport debug symbols re-extract
/// on the next device attach → REVIEW. Archives hold the only local dSYMs used to
/// symbolicate shipped crashes → never trashable, advice-only / RISKY. Simulator
/// caches are regenerable; the Devices store is pruned via `simctl`, never rm.
/// These live under plain user dirs (0700) → no Full Disk Access needed.
struct XcodeScanner: CairnScanner {
    let info = CategoryInfo(
        id: "xcode",
        title: "Xcode & Simulators",
        subtitle: "DerivedData, DeviceSupport, Archives, simulator caches & devices",
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

        // 5) CoreSimulator/Devices — ONE REVIEW item, pruned via simctl (never rm,
        //    since active devices hold real installed-app state). Size the dir.
        if ctx.isCancelled() { return }
        ctx.progress("Simulator devices")
        let devices = coreSimulator.appendingPathComponent("Devices")
        if FileScan.exists(devices) {
            let stats = FileScan.measure(devices)
            let prune = ToolCommand(
                tool: "xcrun",
                arguments: ["simctl", "delete", "unavailable"],
                display: "xcrun simctl delete unavailable"
            )
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
                note: "Unavailable/old simulator devices — removed via simctl",
                permissionDenied: stats.permissionDenied,
                volumeURL: FileScan.volumeURL(of: devices),
                selected: false
            ))
        }
    }
}
