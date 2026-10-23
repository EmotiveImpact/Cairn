import Foundation

/// Android SDK, NDK, build-tools, emulator system images, and AVDs (SPEC §3.1,
/// developer wedge). Everything here is re-downloadable via `sdkmanager` or
/// recreatable in Android Studio, but each piece is large and slow to reacquire
/// (multi-GB system images, NDK toolchains) — so it is all REVIEW and never
/// pre-selected. The lone exception is `~/.android/cache`, a genuinely
/// regenerable cache, which is SAFE and pre-selected. These live under plain
/// user dirs (0700) → no Full Disk Access needed.
///
/// `~/.gradle` is owned by a different scanner and is deliberately NOT touched here.
struct AndroidSDKScanner: CairnScanner {
    let info = CategoryInfo(
        id: "android",
        title: "Android SDK & Emulators",
        subtitle: "System images, NDK, AVDs, build-tools",
        systemImage: "smartphone",
        group: .developer,
        requiresFDA: false
    )

    func scan(_ ctx: ScanContext) async {
        let sdk = FileScan.home.appendingPathComponent("Library/Android/sdk")
        let dotAndroid = FileScan.home.appendingPathComponent(".android")

        // 1) Emulator system images — one REVIEW item per API-level child of
        //    sdk/system-images. Re-downloadable via sdkmanager.
        if ctx.isCancelled() { return }
        ctx.progress("System images")
        let systemImages = sdk.appendingPathComponent("system-images")
        if FileScan.exists(systemImages), let children = FileScan.children(of: systemImages) {
            for child in children {
                if ctx.isCancelled() { return }
                guard isRealDirectory(child) else { continue }
                let name = child.lastPathComponent
                if let item = makeItem(
                    at: child,
                    severity: .review,
                    minSize: ctx.minSizeBytes,
                    isRegenerable: true,
                    cleanMethod: .trash,
                    note: "Android system image \(name) — re-download via sdkmanager",
                    selectedIfSafe: false,
                    maxFiles: 60_000
                ) {
                    ctx.emit(item)
                }
            }
        }

        // 2) NDK versions — one item per child of sdk/ndk. The newest version
        //    stays REVIEW. An older side-by-side version untouched for 90+ days
        //    has been superseded and re-downloads via sdkmanager → SAFE.
        if ctx.isCancelled() { return }
        ctx.progress("NDK")
        let ndk = sdk.appendingPathComponent("ndk")
        if FileScan.exists(ndk), let children = FileScan.children(of: ndk) {
            let versions = children.filter(isRealDirectory)
            let newest = versions.map(\.lastPathComponent).max(by: Self.versionLess)
            for child in versions {
                if ctx.isCancelled() { return }
                let name = child.lastPathComponent
                guard var item = makeItem(
                    at: child,
                    severity: .review,
                    minSize: ctx.minSizeBytes,
                    isRegenerable: true,
                    cleanMethod: .trash,
                    note: "Android NDK \(name) — re-download via sdkmanager",
                    selectedIfSafe: false,
                    maxFiles: 60_000
                ) else { continue }
                if name != newest && item.ageDays >= Self.supersededNDKDays {
                    item.severity = .safe
                    item.selected = !item.permissionDenied
                    item.note = "Android NDK \(name) — older than \(newest ?? "the newest version") and unused for \(Int(Self.supersededNDKDays))+ days; re-download via sdkmanager"
                }
                ctx.emit(item)
            }
        }

        // 3) build-tools versions — one REVIEW item per child of sdk/build-tools.
        if ctx.isCancelled() { return }
        ctx.progress("build-tools")
        let buildTools = sdk.appendingPathComponent("build-tools")
        if FileScan.exists(buildTools), let children = FileScan.children(of: buildTools) {
            for child in children {
                if ctx.isCancelled() { return }
                guard isRealDirectory(child) else { continue }
                let name = child.lastPathComponent
                if let item = makeItem(
                    at: child,
                    severity: .review,
                    minSize: ctx.minSizeBytes,
                    isRegenerable: true,
                    cleanMethod: .trash,
                    note: "Android build-tools \(name)",
                    selectedIfSafe: false,
                    maxFiles: 60_000
                ) {
                    ctx.emit(item)
                }
            }
        }

        // 4) Emulator AVDs — one REVIEW item per *.avd under ~/.android/avd.
        //    Recreatable in Android Studio.
        if ctx.isCancelled() { return }
        ctx.progress("AVDs")
        let avd = dotAndroid.appendingPathComponent("avd")
        if FileScan.exists(avd), let children = FileScan.children(of: avd) {
            for child in children {
                if ctx.isCancelled() { return }
                guard child.pathExtension == "avd", isRealDirectory(child) else { continue }
                let name = child.deletingPathExtension().lastPathComponent
                if let item = makeItem(
                    at: child,
                    severity: .review,
                    minSize: ctx.minSizeBytes,
                    isRegenerable: true,
                    cleanMethod: .trash,
                    note: "Android emulator AVD \(name) — recreate in Android Studio",
                    selectedIfSafe: false,
                    maxFiles: 60_000
                ) {
                    ctx.emit(item)
                }
            }
        }

        // 5) ~/.android/cache — ONE SAFE, trashable, pre-selected item.
        if ctx.isCancelled() { return }
        ctx.progress("Android cache")
        let cache = dotAndroid.appendingPathComponent("cache")
        if let item = makeItem(
            at: cache,
            severity: .safe,
            minSize: ctx.minSizeBytes,
            isRegenerable: true,
            cleanMethod: .trash,
            note: "Android cache",
            selectedIfSafe: true,
            maxFiles: 60_000
        ) {
            ctx.emit(item)
        }
    }

    // MARK: - helpers

    /// An older NDK this long untouched is treated as superseded.
    static let supersededNDKDays: Double = 90

    /// Numeric, component-wise version order ("25.1.8937393" < "26.3.11579264").
    static func versionLess(_ a: String, _ b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    /// True only for a real directory (not a symlink, not iCloud stub). We never
    /// follow symlinks, which would double-count or escape the SDK tree.
    private func isRealDirectory(_ url: URL) -> Bool {
        guard let rv = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]) else { return false }
        if rv.isSymbolicLink == true { return false }
        return rv.isDirectory == true
    }
}
