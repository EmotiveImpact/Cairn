import Foundation

/// Media-production cache & render scratch — the creative wedge. Adobe Premiere /
/// After Effects media cache, Final Cut / Motion / Compressor / Logic caches,
/// Topaz, CapCut, DaVinci Resolve render cache, plus stale screen recordings and
/// large exports sitting loose in the user's own folders.
///
/// HARD RULE: this scanner NEVER touches project media or libraries — only the
/// cache / render-scratch subpaths apps regenerate on demand. Regenerable app
/// caches are SAFE; render caches that are expensive to rebuild (Resolve) and the
/// user's own recordings / exports are REVIEW; `.fcpbundle` libraries are
/// advice-only (Final Cut owns the internal render files — reclaim via the app).
///
/// All targets live in plain user dirs (`~/Library/...`, `~/Movies`, `~/Desktop`)
/// → no Full Disk Access needed.
struct CreativeCachesScanner: CairnScanner {
    let info = CategoryInfo(
        id: "creative",
        title: "Creative Caches",
        subtitle: "Premiere/AE media cache, Final Cut, Resolve, Topaz, exports…",
        systemImage: "film.stack.fill",
        group: .creative,
        requiresFDA: false
    )

    // MARK: - Tuning

    /// Floor for screen recordings (the SPEC asks for a smaller 1 MB threshold so
    /// we surface even modest loose recordings).
    private static let recordingFloor: Int64 = 1 * 1024 * 1024  // 1 MB
    /// Large-export threshold for loose videos in ~/Movies.
    private static let largeExportFloor: Int64 = 500 * 1024 * 1024  // 500 MB
    /// Cap files counted when sizing big cache trees (so one pathological media
    /// cache can't dominate the scan).
    private static let maxCacheFiles = 50_000

    /// Owning-app bundle ids that must quit before a cache is cleaned.
    private static let adobeBundleIDs = [
        "com.adobe.PremierePro", "com.adobe.AfterEffects",
    ]
    private static let finalCutBundleIDs = ["com.apple.FinalCut"]
    private static let motionBundleIDs = ["com.apple.motionapp"]
    private static let compressorBundleIDs = ["com.apple.Compressor"]
    private static let logicBundleIDs = ["com.apple.logic10"]
    private static let capcutBundleIDs = ["com.lemon.lvoverseas"]
    private static let photoshopBundleIDs = ["com.adobe.Photoshop"]
    private static let lightroomBundleIDs = ["com.adobe.LightroomClassicCC7", "com.adobe.Lightroom5"]
    private static let blenderBundleIDs = ["org.blenderfoundation.blender"]
    private static let abletonBundleIDs = ["com.ableton.live"]

    private static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]

    // MARK: - Scan

    func scan(_ ctx: ScanContext) async {
        scanSafeCaches(ctx)
        if ctx.isCancelled() { return }
        scanReviewCaches(ctx)
        if ctx.isCancelled() { return }
        scanScreenRecordings(ctx)
        if ctx.isCancelled() { return }
        scanLargeExports(ctx)
        if ctx.isCancelled() { return }
        scanFinalCutLibraries(ctx)
    }

    // MARK: - SAFE: regenerable app caches

    private func scanSafeCaches(_ ctx: ScanContext) {
        let home = FileScan.home

        // Fixed-path SAFE caches: (relative path, label, owning bundle ids).
        let fixed: [(rel: String, label: String, quit: [String])] = [
            ("Library/Application Support/Adobe/Common/Media Cache",
             "Adobe media cache", Self.adobeBundleIDs),
            ("Library/Application Support/Adobe/Common/Media Cache Files",
             "Adobe media cache files", Self.adobeBundleIDs),
            ("Library/Caches/Adobe/Common",
             "After Effects cache", Self.adobeBundleIDs),
            ("Library/Caches/com.apple.FinalCut",
             "Final Cut cache", Self.finalCutBundleIDs),
            ("Library/Caches/com.apple.motionapp",
             "Motion cache", Self.motionBundleIDs),
            ("Library/Caches/com.apple.Compressor",
             "Compressor cache", Self.compressorBundleIDs),
            ("Library/Caches/com.apple.logic10",
             "Logic cache", Self.logicBundleIDs),
            ("Library/Caches/com.lemon.lvoverseas",
             "CapCut cache", Self.capcutBundleIDs),
            ("Library/Caches/Adobe Camera Raw 2",
             "Camera Raw cache", Self.photoshopBundleIDs),
            ("Library/Caches/Adobe/Lightroom",
             "Lightroom cache", Self.lightroomBundleIDs),
            ("Library/Caches/Blender",
             "Blender cache", Self.blenderBundleIDs),
            ("Library/Caches/Ableton",
             "Ableton cache", Self.abletonBundleIDs),
        ]

        for entry in fixed {
            if ctx.isCancelled() { return }
            let url = home.appendingPathComponent(entry.rel)
            emitSafeCache(at: url, label: entry.label, quit: entry.quit, ctx: ctx)
        }

        // After Effects: children of ~/Library/Caches/Adobe whose name contains
        // "After Effects" (e.g. "Adobe After Effects").
        if ctx.isCancelled() { return }
        let adobeCaches = home.appendingPathComponent("Library/Caches/Adobe")
        if FileScan.exists(adobeCaches) {
            for child in directorySubdirs(of: adobeCaches) {
                if ctx.isCancelled() { return }
                guard child.lastPathComponent.contains("After Effects") else { continue }
                emitSafeCache(at: child, label: "After Effects cache (\(child.lastPathComponent))",
                              quit: Self.adobeBundleIDs, ctx: ctx)
            }
        }

        // Lightroom: children of ~/Library/Caches/Adobe/Lightroom (its own cache
        // subtrees). The Adobe/Lightroom root itself is emitted via `fixed` above;
        // here we leave it as the single fixed entry and instead pick up Lightroom
        // caches that live directly under ~/Library/Caches (handled below alongside
        // Photoshop / Topaz).

        // Name-matched caches directly under ~/Library/Caches (case-insensitive):
        //  - "Photoshop"  → Photoshop scratch/cache dirs
        //  - "Lightroom"  → Lightroom caches that sit at the Caches root
        //  - "topaz"      → Topaz caches
        if ctx.isCancelled() { return }
        let caches = home.appendingPathComponent("Library/Caches")
        if FileScan.exists(caches) {
            for child in directorySubdirs(of: caches) {
                if ctx.isCancelled() { return }
                let name = child.lastPathComponent
                let lower = name.lowercased()
                if lower.contains("photoshop") {
                    emitSafeCache(at: child, label: "Photoshop cache (\(name))",
                                  quit: Self.photoshopBundleIDs, ctx: ctx)
                } else if lower.contains("lightroom") {
                    emitSafeCache(at: child, label: "Lightroom cache (\(name))",
                                  quit: Self.lightroomBundleIDs, ctx: ctx)
                } else if lower.contains("topaz") {
                    emitSafeCache(at: child, label: "Topaz cache (\(name))",
                                  quit: [], ctx: ctx)
                }
            }
        }
    }

    /// Emit a SAFE, regenerable, pre-selectable cache item.
    private func emitSafeCache(at url: URL, label: String, quit: [String], ctx: ScanContext) {
        guard FileScan.exists(url) else { return }
        ctx.progress(label)
        if let item = makeItem(
            at: url,
            severity: .safe,
            minSize: ctx.minSizeBytes,
            isRegenerable: true,
            requiresQuitBundleIDs: quit,
            cleanMethod: .trash,
            note: "\(label) — regenerates",
            selectedIfSafe: true,
            maxFiles: Self.maxCacheFiles
        ) {
            ctx.emit(item)
        }
    }

    // MARK: - REVIEW: DaVinci Resolve render cache

    private func scanReviewCaches(_ ctx: ScanContext) {
        let home = FileScan.home

        // Fixed Resolve cache directory under ~/Movies.
        let cacheClip = home.appendingPathComponent("Movies/DaVinci Resolve/CacheClip")
        emitResolveCache(at: cacheClip, ctx: ctx)

        // ~/Library/Caches/com.blackmagic-design.DaVinciResolve* (enumerate match).
        if ctx.isCancelled() { return }
        let caches = home.appendingPathComponent("Library/Caches")
        if FileScan.exists(caches) {
            for child in directorySubdirs(of: caches) {
                if ctx.isCancelled() { return }
                guard child.lastPathComponent.hasPrefix("com.blackmagic-design.DaVinciResolve")
                else { continue }
                emitResolveCache(at: child, ctx: ctx)
            }
        }
    }

    /// Emit a REVIEW Resolve render-cache item (regenerable but expensive → never
    /// pre-selected).
    private func emitResolveCache(at url: URL, ctx: ScanContext) {
        guard FileScan.exists(url) else { return }
        ctx.progress("DaVinci Resolve cache")
        if let item = makeItem(
            at: url,
            severity: .review,
            minSize: ctx.minSizeBytes,
            isRegenerable: true,
            cleanMethod: .trash,
            note: "Resolve render cache — regenerates but large",
            selectedIfSafe: false,
            maxFiles: Self.maxCacheFiles
        ) {
            ctx.emit(item)
        }
    }

    // MARK: - REVIEW: screen recordings on the Desktop

    private func scanScreenRecordings(_ ctx: ScanContext) {
        let desktop = FileScan.home.appendingPathComponent("Desktop")
        guard FileScan.exists(desktop) else { return }
        ctx.progress("Scanning Desktop for screen recordings")
        guard let children = FileScan.children(of: desktop) else { return }

        for child in children {
            if ctx.isCancelled() { return }

            let rv = try? child.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            if rv?.isSymbolicLink == true { continue }
            if rv?.isDirectory == true { continue }

            let name = child.lastPathComponent
            let ext = child.pathExtension.lowercased()
            let looksLikeRecording =
                name.hasPrefix("Screen Recording") || ext == "mov" || ext == "mp4"
            guard looksLikeRecording else { continue }

            let stats = FileScan.measure(child)
            // measure() zeroes out symlinks / iCloud stubs.
            guard stats.fileCount > 0, stats.allocatedSize >= Self.recordingFloor else { continue }

            ctx.progress(name)
            let age = max(0, Date().timeIntervalSince(stats.latestModified) / 86_400)
            let item = ScanItem(
                url: child,
                allocatedSize: stats.allocatedSize,
                itemCount: stats.fileCount,
                latestModified: stats.latestModified,
                categoryID: info.id,
                severity: .review,
                isRegenerable: false,            // the user's own recording
                cleanMethod: .trash,
                note: "Screen recording on Desktop (\(Fmt.age(age)))",
                permissionDenied: stats.permissionDenied,
                volumeURL: FileScan.volumeURL(of: child),
                selected: false
            )
            ctx.emit(item)
        }
    }

    // MARK: - REVIEW: large video exports in ~/Movies (top level only)

    private func scanLargeExports(_ ctx: ScanContext) {
        let movies = FileScan.home.appendingPathComponent("Movies")
        guard FileScan.exists(movies) else { return }
        ctx.progress("Scanning Movies for large exports")
        guard let children = FileScan.children(of: movies) else { return }

        for child in children {
            if ctx.isCancelled() { return }

            let rv = try? child.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            if rv?.isSymbolicLink == true { continue }
            if rv?.isDirectory == true { continue }   // top-level files only; never descend

            guard Self.videoExtensions.contains(child.pathExtension.lowercased()) else { continue }

            let stats = FileScan.measure(child)
            guard stats.fileCount > 0, stats.allocatedSize >= Self.largeExportFloor else { continue }

            ctx.progress(child.lastPathComponent)
            let age = max(0, Date().timeIntervalSince(stats.latestModified) / 86_400)
            let item = ScanItem(
                url: child,
                allocatedSize: stats.allocatedSize,
                itemCount: stats.fileCount,
                latestModified: stats.latestModified,
                categoryID: info.id,
                severity: .review,
                isRegenerable: false,            // the user's own export
                cleanMethod: .trash,
                note: "Large video in Movies (\(Fmt.age(age)))",
                permissionDenied: stats.permissionDenied,
                volumeURL: FileScan.volumeURL(of: child),
                selected: false
            )
            ctx.emit(item)
        }
    }

    // MARK: - ADVICE: Final Cut libraries

    /// If ~/Movies holds any top-level `*.fcpbundle`, emit ONE advice-only card.
    /// We NEVER touch the library itself — Final Cut owns the render files inside
    /// and the safe reclaim is its own menu command.
    private func scanFinalCutLibraries(_ ctx: ScanContext) {
        let movies = FileScan.home.appendingPathComponent("Movies")
        guard FileScan.exists(movies) else { return }
        guard let children = FileScan.children(of: movies) else { return }

        let bundle = children.first { child in
            child.pathExtension.lowercased() == "fcpbundle"
        }
        guard let bundle else { return }

        ctx.progress("Final Cut libraries")
        // Advice-only: non-actionable card. Built directly via ScanItem so we
        // bypass makeItem's min-size skip and never mark it trashable.
        let item = ScanItem(
            url: bundle,
            allocatedSize: 0,
            itemCount: 0,
            latestModified: .distantPast,
            categoryID: info.id,
            severity: .review,
            isRegenerable: false,
            cleanMethod: .adviceOnly,
            note: "Final Cut libraries contain render files — reclaim safely via Final Cut: File > Delete Generated Library Files",
            volumeURL: FileScan.volumeURL(of: bundle),
            selected: false
        )
        ctx.emit(item)
    }

    // MARK: - Helpers

    /// Immediate subdirectories of `dir` (one level), skipping symlinks. Empty on
    /// error. Used for the "enumerate children matching <name>" cases.
    private func directorySubdirs(of dir: URL) -> [URL] {
        guard let children = FileScan.children(of: dir) else { return [] }
        return children.filter { child in
            let rv = try? child.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            return rv?.isSymbolicLink != true && rv?.isDirectory == true
        }
    }
}
