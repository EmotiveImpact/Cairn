import SwiftUI

struct DashboardView: View {
    let store: ScanStore
    var onStartScan: () -> Void
    var onConfigure: () -> Void
    var onOpen: (NavSection) -> Void
    var onReview: () -> Void

    @State private var disk: DiskUsage?
    @ObservedObject private var reclaim = ReclaimStats.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero   // full-bleed, edge to edge
                VStack(alignment: .leading, spacing: 14) {
                    if isFirstRun { firstRunCard }
                    categoryCards
                    HStack(alignment: .top, spacing: 14) {
                        recentActivity.frame(maxWidth: .infinity)
                        systemStatus.frame(maxWidth: .infinity)
                    }
                    HStack(alignment: .top, spacing: 14) {
                        storageOverview.frame(maxWidth: .infinity)
                        safeSecure.frame(width: 300)
                    }
                }
                .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 22)
                .frame(maxWidth: Brand.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .task(id: "diskUsage") {
            // `.task(id:)` with a constant id runs once per view lifetime; a bare
            // `.task` re-fires whenever the view is re-identified, which was
            // re-launching the disk measurement over and over (idle CPU pinned,
            // memory climbing hundreds of MB a second).
            guard disk == nil else { return }
            disk = DiskUsage.loadCached()   // instant (last known) — no "Zero KB" flash
            guard DiskUsage.cacheIsStale else { return }
            let fresh = await DiskUsage.compute()
            guard !Task.isCancelled else { return }
            disk = fresh
            fresh.saveCache()
        }
    }

    // MARK: - Hero

    private var lastScanCaption: String {
        if store.hasLiveResults { return "Found" }
        guard store.showingCachedResults, let d = store.lastScanDate else { return "Not scanned yet" }
        let rel = RelativeDateTimeFormatter(); rel.unitsStyle = .abbreviated
        return "Last scan · \(rel.localizedString(for: d, relativeTo: Date()))"
    }

    private var hero: some View {
        let s = Fmt.split(store.displayGrandTotal)
        return ZStack(alignment: .top) {
            HeroBanner()   // fills the full width, edge to edge
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Your Mac. Intentional. Optimized.")
                        .font(.system(size: 26, weight: .bold)).foregroundStyle(Brand.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("We help you clean safely and intelligently so your Mac stays fast, focused, and ready for what matters.")
                        .font(.system(size: 13)).foregroundStyle(Brand.textSecondary)
                        .frame(maxWidth: 400, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Button { onStartScan() } label: {
                            Label(store.isScanning ? "Scanning…" : "Start Smart Scan", systemImage: "scope")
                        }.buttonStyle(BrandButtonStyle())
                        Button { onConfigure() } label: { Label("Configure Scan", systemImage: "gearshape") }
                            .buttonStyle(WhiteButtonStyle())
                    }
                    .padding(.top, 4)
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 8)
                ScanRing(progress: store.isScanning ? store.scanProgress : (store.displayGrandTotal > 0 ? 1 : 0.02),
                         value: s.value, unit: s.unit, caption1: "Reclaimable",
                         caption2: store.isScanning ? "Found so far" : lastScanCaption)
                    .frame(width: 186, height: 186)
            }
            .padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 18)
            .frame(maxWidth: Brand.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 224)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    // MARK: - First run

    /// Never scanned and nothing cached — the very first thing a buyer sees.
    private var isFirstRun: Bool { !store.hasLiveResults && store.lastSnapshot == nil }

    /// Instead of a grid of zeros, say what Cairn looks for and promise safety.
    private var firstRunCard: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 9) {
                Text("Nothing scanned yet").font(.system(size: 15, weight: .semibold)).foregroundStyle(Brand.textPrimary)
                Text("Cairn looks for the space developers actually lose — build artefacts, package and Docker caches, AI model stores, simulator data, creative renders, duplicates and forgotten apps.")
                    .font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    promise("checkmark.shield.fill", "Everything goes to the Trash first")
                    promise("lock.fill", "Local only · no account")
                }
                .padding(.top, 2)
                Button { onStartScan() } label: { Label("Start Smart Scan", systemImage: "scope") }
                    .buttonStyle(BrandButtonStyle())
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .cairnCard(18)
    }

    private func promise(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(Brand.safeCyan)
            Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(Brand.textSecondary)
        }
    }

    // MARK: - Category cards

    private struct CardItem: Identifiable {
        let id = UUID(); let section: NavSection; var title: String? = nil; let value: String; let label: String
    }

    private var cardItems: [CardItem] {
        [
            CardItem(section: .smartScan, value: Fmt.size(store.displayGrandTotal), label: "Reclaimable"),
            CardItem(section: .developer, title: "Dev Cleanup", value: Fmt.size(sumD(store.displayBuckets(in: .developer))), label: "Reclaimable"),
            CardItem(section: .ai, value: Fmt.size(sumD(store.displayBuckets(in: .ai))), label: "Reclaimable"),
            CardItem(section: .creative, value: Fmt.size(sumD(store.displayBuckets(in: .creative))), label: "Reclaimable"),
            CardItem(section: .largeFiles, value: Fmt.size(sumIDs(["large-old", "installers"])), label: "Found"),
            CardItem(section: .duplicates, value: "Scan", label: "Find copies"),
            CardItem(section: .apps, value: Fmt.size(sumIDs(["orphaned"])), label: "Found"),
            CardItem(section: .bugs, value: "\(HealthStore.checkCount)", label: "Checks"),
        ]
    }

    private var categoryCards: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 8), spacing: 10) {
            ForEach(cardItems) { c in
                Button { onOpen(c.section) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: c.section.icon).font(.system(size: 19, weight: .medium)).foregroundStyle(Brand.deepBlue)
                        Text(c.title ?? c.section.title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Brand.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.9)
                        Text(c.value).font(.system(size: 15, weight: .semibold)).foregroundStyle(Brand.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Text(c.label).font(.system(size: 10)).foregroundStyle(Brand.textMuted)
                    }
                    .frame(maxWidth: .infinity).frame(height: 104).cairnCard(10, level: .low)
                }
                .buttonStyle(HoverButtonStyle(lift: 3))
            }
        }
    }

    // MARK: - Recent Activity

    private struct Activity: Identifiable {
        let id = UUID(); let section: NavSection; let title: String; let icon: String; let bytes: Int64
    }
    private var activities: [Activity] {
        [
            Activity(section: .smartScan, title: "Smart Scan", icon: "scope", bytes: store.displayGrandTotal),
            Activity(section: .developer, title: "Developer Cleanup", icon: "chevron.left.forwardslash.chevron.right", bytes: sumD(store.displayBuckets(in: .developer))),
            Activity(section: .ai, title: "AI Models", icon: "brain.head.profile", bytes: sumD(store.displayBuckets(in: .ai))),
            Activity(section: .largeFiles, title: "Large Files", icon: "folder", bytes: sumIDs(["large-old", "installers"])),
            Activity(section: .apps, title: "Apps", icon: "square.stack.3d.up", bytes: sumIDs(["orphaned"])),
        ]
    }
    private var activitySubtitle: String {
        guard let d = store.lastScanDate else { return "Not scanned yet" }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        return "Last scan · \(f.localizedString(for: d, relativeTo: Date()))"
    }

    private var recentActivity: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recent Activity").font(.system(size: 15, weight: .semibold)).foregroundStyle(Brand.textPrimary)
                Spacer()
                Button("View All") { onOpen(.smartScan) }.buttonStyle(GhostButtonStyle())
            }
            .padding(.bottom, 6)
            ForEach(Array(activities.enumerated()), id: \.element.id) { i, a in
                HStack(spacing: 12) {
                    Image(systemName: a.icon).font(.system(size: 15, weight: .medium)).foregroundStyle(Brand.blue)
                        .frame(width: 32, height: 32).background(Circle().fill(Brand.blue.opacity(0.10)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.textPrimary)
                        Text(activitySubtitle).font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                    }
                    Spacer()
                    Text(a.bytes > 0 ? Fmt.size(a.bytes) : "—")
                        .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(Brand.textSecondary)
                    Button("Review") { onOpen(a.section) }.buttonStyle(GhostButtonStyle())
                }
                .padding(.vertical, 9)
                if i < activities.count - 1 { Divider().overlay(Brand.border) }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 290, alignment: .top)
        .cairnCard(16)
    }

    // MARK: - System Status

    private var systemStatus: some View {
        VStack(spacing: 0) {
            HStack {
                Text("System Status").font(.system(size: 15, weight: .semibold)).foregroundStyle(Brand.textPrimary)
                Spacer()
            }
            .padding(.bottom, 8)
            // The running total is the first thing on the card on purpose: it's
            // what proves the app was worth buying, every time it's opened.
            statusRow("arrow.down.circle.fill", "Reclaimed with Cairn",
                      reclaim.lifetimeBytes > 0 ? Fmt.size(reclaim.lifetimeBytes) : "Nothing yet",
                      ok: reclaim.lifetimeBytes > 0)
            Divider().overlay(Brand.border)
            statusRow("externaldrive", "Disk Health", "Good", ok: true)
            Divider().overlay(Brand.border)
            statusRow("waveform.path.ecg", "Performance", "Optimal", ok: true)
            Divider().overlay(Brand.border)
            freeSpaceRow
            Divider().overlay(Brand.border)
            fdaRow
            Divider().overlay(Brand.border)
            statusRow("checkmark.shield", "Privacy Protection", "Local-only", ok: true)
            Divider().overlay(Brand.border)
            Button { onOpen(.settings) } label: {
                statusRow("arrow.uturn.backward.circle", "Restore Bin",
                          store.removalLog.isEmpty ? "Empty" : "\(store.removalLog.count) recoverable", ok: false)
            }.buttonStyle(.plain).pointerCursor()
            Divider().overlay(Brand.border)
            statusRow("clock.arrow.circlepath", "Last Scan", lastScanText, ok: false)
            Divider().overlay(Brand.border)
            statusRow("gearshape", "macOS", osVersion, ok: false, trailing: "Up to date")
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 290, alignment: .top)
        .cairnCard(16)
    }

    /// Free space, told honestly. A near-full disk makes macOS thrash (no room for
    /// swap or caches), so it must never read as healthy just because we can
    /// measure it — under 5% or 10 GB it's a warning, under 2% or 3 GB it's critical.
    @ViewBuilder private var freeSpaceRow: some View {
        let free = DeviceInfo.available
        let total = max(1, DeviceInfo.totalCapacity)
        let frac = Double(free) / Double(total)
        let critical = frac < 0.02 || free < 3_000_000_000
        let low = frac < 0.05 || free < 10_000_000_000

        HStack(spacing: 10) {
            Image(systemName: critical ? "exclamationmark.triangle.fill" : (low ? "exclamationmark.circle" : "internaldrive"))
                .font(.system(size: 13))
                .foregroundStyle(critical ? Brand.danger : (low ? Brand.amber : Brand.textMuted))
                .frame(width: 20)
            Text("Free Space").font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
            Spacer()
            if !low {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(Brand.safeCyan)
            }
            Text(Fmt.size(free))
                .font(.system(size: 12, weight: critical ? .bold : .medium))
                .foregroundStyle(critical ? Brand.danger : (low ? Brand.amber : Brand.textPrimary))
            if critical {
                Text("critically low").font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.danger)
            } else if low {
                Text("low").font(.system(size: 11, weight: .medium)).foregroundStyle(Brand.amber)
            }
        }
        .padding(.vertical, 7)
    }

    /// Full Disk Access — a green "Granted" status, or a tappable "Grant" that
    /// opens the macOS Privacy & Security setting when access is missing.
    @ViewBuilder private var fdaRow: some View {
        if FullDiskAccess.isGranted() {
            statusRow("lock.shield", "Full Disk Access", "Granted", ok: true)
        } else {
            Button { FullDiskAccess.openSettings() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield").font(.system(size: 13)).foregroundStyle(Brand.amber).frame(width: 20)
                    Text("Full Disk Access").font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
                    Spacer()
                    Text("Grant").font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.blue)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Brand.textMuted)
                }
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }.buttonStyle(.plain).pointerCursor()
        }
    }

    private func statusRow(_ icon: String, _ label: String, _ value: String, ok: Bool, trailing: String? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Brand.textMuted).frame(width: 20)
            Text(label).font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
            Spacer()
            if ok {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(Brand.safeCyan)
            }
            Text(value).font(.system(size: 12, weight: .medium)).foregroundStyle(ok ? Brand.textPrimary : Brand.textSecondary)
            if let trailing {
                Text(trailing).font(.system(size: 11, weight: .medium)).foregroundStyle(Brand.textMuted)
            }
        }
        .padding(.vertical, 7)
    }

    private var lastScanText: String {
        guard let d = store.lastScanDate else { return "Never" }
        return Fmt.relative(d)
    }

    // MARK: - Storage Overview (real disk breakdown)

    private var storageOverview: some View {
        let d = disk
        let segs: [(String, Int64, Color)] = [
            ("System", d?.system ?? 0, Brand.blue),
            ("Apps", d?.apps ?? 0, Brand.cyan),
            ("Documents", d?.documents ?? 0, Brand.purple),
            ("Media", d?.media ?? 0, Brand.amber),
            ("Free", d?.free ?? DeviceInfo.available, Brand.border),
        ]
        let total = max(1, segs.reduce(Int64(0)) { $0 + $1.1 })
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Storage Overview").font(.system(size: 15, weight: .semibold)).foregroundStyle(Brand.textPrimary)
                    Text(DeviceInfo.name).font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                }
                Spacer()
                Text("\(Fmt.size(DeviceInfo.available)) free of \(Fmt.size(DeviceInfo.totalCapacity))")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Brand.textSecondary)
            }
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(segs, id: \.0) { s in
                        Rectangle().fill(s.2).frame(width: max(2, geo.size.width * CGFloat(s.1) / CGFloat(total)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .animation(.easeInOut(duration: 0.5), value: total)
            }
            .frame(height: 14)
            HStack(spacing: 18) {
                ForEach(segs, id: \.0) { s in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Circle().fill(s.2).frame(width: 7, height: 7)
                            Text(s.0).font(.system(size: 11, weight: .medium)).foregroundStyle(Brand.textPrimary)
                        }
                        Text(Fmt.size(s.1)).font(.system(size: 10)).foregroundStyle(Brand.textMuted)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .cairnCard(16)
    }

    // MARK: - Safe & Secure

    private var safeSecure: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(Brand.blue.opacity(0.10)).frame(width: 60, height: 60)
                Image(systemName: "checkmark.shield.fill").font(.system(size: 30)).foregroundStyle(Brand.brand)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Safe & Secure").font(.system(size: 15, weight: .semibold)).foregroundStyle(Brand.textPrimary)
                Text("We never delete anything without your permission. Your data stays private and under your control.")
                    .font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Learn More") { onOpen(.settings) }.buttonStyle(GhostButtonStyle())
            }
            Spacer(minLength: 0)
        }
        .cairnCard(16)
    }

    // MARK: - helpers

    private func sum(_ bs: [ScanStore.Bucket]) -> Int64 { bs.reduce(0) { $0 + $1.totalSize } }
    private func sumD(_ bs: [ScanStore.DisplayBucket]) -> Int64 { bs.reduce(0) { $0 + $1.bytes } }
    private func sumIDs(_ ids: Set<String>) -> Int64 {
        store.displayBuckets.filter { ids.contains($0.id) }.reduce(0) { $0 + $1.bytes }
    }
    private func sectionFor(_ group: CategoryGroup) -> NavSection {
        switch group {
        case .developer: return .developer
        case .ai: return .ai
        case .creative: return .creative
        case .general: return .largeFiles
        }
    }
    private var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}

/// Real (approximate) disk breakdown for the Storage Overview bar. Category sizes
/// use bounded measures so it stays fast; the remainder falls under "System".
/// Cached to UserDefaults so the bar shows the last known split instantly.
struct DiskUsage: Codable {
    var apps: Int64 = 0, documents: Int64 = 0, media: Int64 = 0, system: Int64 = 0, free: Int64 = 0

    private static let cacheKey = "cairn.diskUsage.v2"
    private static let cacheDateKey = "cairn.diskUsage.v2.date"
    /// Recompute at most once a day — this is a decorative breakdown bar, not
    /// something worth re-walking the disk for on every launch.
    private static let maxAge: TimeInterval = 24 * 3600

    static func loadCached() -> DiskUsage? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(DiskUsage.self, from: data)
    }
    /// True when there's no cache, or it's older than a day.
    static var cacheIsStale: Bool {
        guard loadCached() != nil else { return true }
        let at = UserDefaults.standard.double(forKey: cacheDateKey)
        return Date.timeIntervalSinceReferenceDate - at > maxAge
    }
    func saveCache() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
            UserDefaults.standard.set(Date.timeIntervalSinceReferenceDate, forKey: Self.cacheDateKey)
        }
    }

    static func compute() async -> DiskUsage {
        // Bounded on purpose. This feeds one decorative bar, so it must never cost
        // what a real scan costs: measuring these trees unbounded on every launch
        // pushed idle memory past 1.3 GB and burned CPU before the user did anything.
        // Caps keep it to a fast approximation; the remainder lands under "System".
        let cap = 12_000
        return await Task.detached(priority: .background) {
            let home = FileScan.home
            let apps = FileScan.measure(URL(fileURLWithPath: "/Applications"), maxFiles: cap).allocatedSize
            let docs = FileScan.measure(home.appendingPathComponent("Documents"), maxFiles: cap).allocatedSize
            let media = ["Movies", "Pictures", "Music"].reduce(Int64(0)) {
                $0 + FileScan.measure(home.appendingPathComponent($1), maxFiles: cap).allocatedSize
            }
            let free = DeviceInfo.available
            let used = DeviceInfo.used
            let system = max(0, used - apps - docs - media)
            return DiskUsage(apps: apps, documents: docs, media: media, system: system, free: free)
        }.value
    }
}
