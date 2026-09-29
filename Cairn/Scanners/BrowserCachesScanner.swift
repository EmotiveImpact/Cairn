import Foundation

/// Web-browser HTTP/disk caches — pure transient state that browsers refill as
/// you browse (SPEC §3.x). These live in plain user dirs (`~/Library/Caches`,
/// `~/Library/Application Support`) → no Full Disk Access needed. We touch ONLY
/// cache subpaths; cookies, profiles, history, and `Login Data` are never
/// surfaced. Known transient caches are SAFE once their owner is closed;
/// Service Worker storage and caches without a verified owner are advice only.
struct BrowserCachesScanner: CairnScanner {
    let info = CategoryInfo(
        id: "browser-caches",
        title: "Browser Caches",
        subtitle: "Safari, Chrome, Firefox, Brave, Arc, Edge, Opera web caches",
        systemImage: "globe",
        group: .general,
        requiresFDA: false
    )

    /// (browser display name, home-relative cache path, owning bundle id).
    /// `bundleID` empty → no quit-gate (e.g. Opera bundle id not pinned).
    private struct Target {
        let browser: String
        let rel: String
        let bundleID: String
    }

    private var targets: [Target] {
        [
            // Safari
            .init(browser: "Safari", rel: "Library/Caches/com.apple.Safari", bundleID: "com.apple.Safari"),

            // Chrome
            .init(browser: "Chrome", rel: "Library/Caches/Google/Chrome", bundleID: "com.google.Chrome"),
            .init(browser: "Chrome", rel: "Library/Application Support/Google/Chrome/Default/Code Cache", bundleID: "com.google.Chrome"),
            .init(browser: "Chrome", rel: "Library/Application Support/Google/Chrome/Default/GPUCache", bundleID: "com.google.Chrome"),
            .init(browser: "Chrome", rel: "Library/Application Support/Google/Chrome/Default/Service Worker/CacheStorage", bundleID: "com.google.Chrome"),

            // Firefox
            .init(browser: "Firefox", rel: "Library/Caches/Firefox", bundleID: "org.mozilla.firefox"),

            // Brave
            .init(browser: "Brave", rel: "Library/Caches/BraveSoftware/Brave-Browser", bundleID: "com.brave.Browser"),

            // Arc
            .init(browser: "Arc", rel: "Library/Caches/company.thebrowser.Browser", bundleID: "company.thebrowser.Browser"),

            // Edge
            .init(browser: "Edge", rel: "Library/Caches/Microsoft Edge", bundleID: "com.microsoft.edgemac"),

            // Opera (bundle id not pinned — no quit-gate)
            .init(browser: "Opera", rel: "Library/Caches/com.operasoftware.Opera", bundleID: ""),
        ]
    }

    func scan(_ ctx: ScanContext) async {
        for t in targets {
            if ctx.isCancelled() { return }
            let url = FileScan.home.appendingPathComponent(t.rel)
            ctx.progress(t.browser)
            let uncertain = t.rel.contains("Service Worker/CacheStorage") || t.bundleID.isEmpty
            if let item = makeItem(
                at: url,
                severity: uncertain ? .review : .safe,
                minSize: ctx.minSizeBytes,
                isRegenerable: !uncertain,
                requiresQuitBundleIDs: t.bundleID.isEmpty ? [] : [t.bundleID],
                cleanMethod: uncertain ? .adviceOnly : .trash,
                note: uncertain ? "\(t.browser) storage may include offline site data; inspect it before manual removal" :
                    "\(t.browser) web cache — re-downloaded as you browse",
                selectedIfSafe: !uncertain
            ) {
                ctx.emit(item)
            }
        }
    }
}
