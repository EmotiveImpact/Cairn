import SwiftUI
import AppKit

/// Top-level navigation sections (the left sidebar).
enum NavSection: String, CaseIterable, Identifiable {
    case dashboard, smartScan, developer, ai, creative, largeFiles, duplicates, apps, bugs, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .smartScan: return "Smart Scan"
        case .developer: return "Developer Cleanup"
        case .ai: return "AI Models"
        case .creative: return "Creative Pro"
        case .largeFiles: return "Large Files"
        case .duplicates: return "Duplicates"
        case .apps: return "Apps"
        case .bugs: return "Health"
        case .settings: return "Settings"
        }
    }

    /// Outline SF Symbols matched to the mockup.
    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .smartScan: return "scope"
        case .developer: return "chevron.left.forwardslash.chevron.right"
        case .ai: return "brain.head.profile"
        case .creative: return "film"
        case .largeFiles: return "folder"
        case .duplicates: return "doc.on.doc"
        case .apps: return "square.stack.3d.up"
        case .bugs: return "heart.text.square"
        case .settings: return "gearshape"
        }
    }

    /// Sections that open an existing sheet rather than routing content.
    var opensSheet: Bool { false }

    @MainActor
    func buckets(_ store: ScanStore) -> [ScanStore.Bucket] {
        switch self {
        case .smartScan: return store.buckets
        case .developer: return store.developerBuckets
        case .ai: return store.aiBuckets
        case .creative: return store.creativeBuckets
        case .largeFiles: return store.buckets.filter { ["large-old", "installers"].contains($0.id) }
        case .apps: return store.buckets.filter { $0.id == "orphaned" }
        default: return []
        }
    }
}

struct AppShell: View {
    @State private var store = ScanStore()
    // Per-page stores are owned HERE (not inside their views) so results persist
    // across navigation and their scans run once — never orphaned/re-spawned.
    @State private var healthStore = HealthStore()
    @State private var dupStore = DuplicateStore()
    @State private var appStore = AppInventoryStore()
    @StateObject private var license = LicenseManager()
    /// `Cairn --section=duplicates` opens straight onto a page. Used to profile
    /// each screen in isolation (and to grab screenshots) without clicking.
    @State private var section: NavSection = {
        guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--section=") }),
              let s = NavSection(rawValue: String(arg.dropFirst("--section=".count)))
        else { return .dashboard }
        return s
    }()
    @State private var showReview = false
    @State private var celebration: ScanStore.CleanSummary?
    @State private var fdaBannerDismissed = false

    private var proEnabled: Bool { license.isUnlocked }
    private var showFDABanner: Bool {
        store.hasScanned && !store.fdaGranted && !fdaBannerDismissed
            && store.buckets.contains { $0.permissionGap }
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                NavSidebar(section: $section, store: store, license: license)
                VStack(spacing: 0) {
                    if showFDABanner { fdaBanner }
                    // NOTE: deliberately no `.id(section)` + cross-fade here.
                    // Keying the content on the section tore down and rebuilt an
                    // entire heavy page (tables, thumbnails, panels) on every nav,
                    // which pushed SwiftUI's AttributeGraph into a rebuild storm and
                    // wedged the main thread. Plain switching reuses the graph.
                    content
                }
                    .frame(minWidth: 820, maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppBackground())
            }
            if let celebration { CelebrationOverlay(summary: celebration, store: store) { self.celebration = nil } }
        }
        // NO minimum-width frame here. The sidebar is a hard `.frame(width: 250)`
        // and the content area declares `.frame(minWidth: 820)` — together they
        // require 1070pt. Declaring 1040 here made those constraints mutually
        // unsatisfiable, so near the minimum width AppKit re-solved the layout
        // forever: 100% main thread, RSS climbing ~45MB/s, navigation frozen
        // app-wide, and no view body ever re-evaluating (it was layout, not
        // render). The window owns the floor instead — see AppDelegate, which
        // sets minSize to exactly 250 + 820.
        .focusEffectDisabled()   // no blue keyboard-focus outline on nav rows / buttons
        .sheet(isPresented: $showReview) {
            ReviewSheet(store: store, proEnabled: proEnabled,
                        onDone: { summary in
                            if celebration == nil && summary.failed == 0 && summary.bytes > 0 { withAnimation(.spring(duration: 0.4)) { celebration = summary } }
                        },
                        onUpgrade: { showReview = false; withAnimation(.easeOut(duration: 0.22)) { section = .settings } })
        }
        // Land idle on launch (the OSS-cleaner norm): show the last scan's cached
        // results instantly; the user starts a fresh scan from the Dashboard CTA or
        // the Smart Scan page. No auto-scan, no launch CPU/RAM spike.
        .onAppear {
            store.loadSnapshot()
            store.loadRemovalLog()
            StorageHistory.record()   // one free-space sample a day, for the forecast
            // Watch for dev tools quitting. Does nothing unless the setting is on
            // AND Pro is unlocked — the guard lives at the point of use so a trial
            // expiring mid-session can't leave a trigger armed.
            SmartTriggers.shared.start(store: store, isProUnlocked: { proEnabled })
            // Honor "Auto Scan Weekly": refresh a stale (>7-day-old) scan on open.
            // Never fires on first run — landing idle stays the first impression.
            if AppSettings.shared.autoScanWeekly, store.phase == .idle,
               let last = store.lastScanDate,
               Date().timeIntervalSince(last) > 7 * 86_400 {
                store.startScan(includeExternalVolumes: !AppSettings.shared.ignoreExternalDrives)
            }
        }
        // Records RSS + what the app was doing, to ~/Library/Logs/Cairn-memory.log.
        // Local only. This is how a runaway spike gets traced to the page and scan
        // that caused it, instead of being guessed at after the fact.
        .task {
            MemoryWatch.start {
                var parts = ["page=\(section.rawValue)"]
                if store.isScanning { parts.append("smartScan=\(Int(store.scanProgress * 100))%") }
                if dupStore.isScanning { parts.append("duplicates=scanning") }
                if appStore.isScanning { parts.append("apps=scanning") }
                if healthStore.isScanning { parts.append("health=scanning") }
                parts.append("items=\(store.buckets.reduce(0) { $0 + $1.items.count })")
                parts.append("dupGroups=\(dupStore.groups.count)")
                return parts.joined(separator: "  ")
            }
        }
        // `Cairn --cycle-sections` walks the sidebar automatically. Navigation is
        // the one thing a single-page launch can't exercise, and it's where the
        // runaway memory shows up in real use.
        .task {
            guard CommandLine.arguments.contains("--cycle-sections") else { return }
            let all = NavSection.allCases
            var i = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                i += 1
                section = all[i % all.count]
            }
        }
    }

    private var fdaBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill").foregroundStyle(Brand.amber).font(.system(size: 14))
            Text("Some results are incomplete — grant Full Disk Access so Cairn can measure and clean everything.")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Brand.textPrimary)
            Spacer(minLength: 8)
            Button("Open Settings") { FullDiskAccess.openSettings() }.buttonStyle(GhostButtonStyle())
            Button { withAnimation { fdaBannerDismissed = true } } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Brand.textMuted)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(Brand.amber.opacity(0.10))
        .overlay(Rectangle().fill(Brand.amber.opacity(0.30)).frame(height: 1), alignment: .bottom)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .dashboard:
            dashboardScreen
        case .smartScan:
            SmartScanView(store: store, onReview: { showReview = true }, onMissionReview: { showReview = true })
        case .largeFiles:
            LargeFilesView(store: store, proEnabled: proEnabled, onReview: { showReview = true })
        case .developer:
            DeveloperCleanupView(store: store, proEnabled: proEnabled,
                                 onReview: { showReview = true },
                                 onUpgrade: { withAnimation(.easeOut(duration: 0.22)) { section = .settings } })
        case .ai, .creative:
            SectionView(store: store, section: section, onReview: { showReview = true })
        case .duplicates:
            DuplicatesView(store: dupStore)
        case .apps:
            AppsView(store: appStore) { summary in
                if celebration == nil && summary.failed == 0 && summary.bytes > 0 {
                    withAnimation(.spring(duration: 0.4)) {
                        celebration = ScanStore.CleanSummary(trashed: summary.trashedApps, failed: 0, bytes: summary.bytes, errors: [], restorable: [], recoverableCount: summary.trashedApps, permanentCount: 0)
                    }
                }
            }
        case .bugs:
            HealthView(store: healthStore)
        case .settings:
            SettingsPage(store: store, license: license)
        }
    }

    private var dashboardScreen: some View {
        DashboardView(
            store: store,
            onStartScan: { withAnimation(.easeOut(duration: 0.22)) { section = .smartScan }; if !store.isScanning { store.startScan(includeExternalVolumes: !AppSettings.shared.ignoreExternalDrives) } },
            onConfigure: { withAnimation(.easeOut(duration: 0.22)) { section = .settings } },
            onOpen: { sec in withAnimation(.easeOut(duration: 0.22)) { section = sec } },
            onReview: { showReview = true })
    }
}

/// The content-area background. Light gradient now; a faint mountain image can be
/// layered in later by dropping it here.
struct AppBackground: View {
    var body: some View {
        // White at the top (so the full-bleed hero blends into its white sky),
        // easing into the faint blue-white surface lower down.
        LinearGradient(colors: [.white, Brand.background],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

// MARK: - Sidebar

struct NavSidebar: View {
    @Binding var section: NavSection
    let store: ScanStore
    @ObservedObject var license: LicenseManager

    // Mockup layout + the full pillar set (AI Models + Creative Pro kept).
    private let items: [NavSection] = [.dashboard, .smartScan, .developer, .ai, .creative, .largeFiles, .duplicates, .apps, .bugs, .settings]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                CairnLogo(size: 34)
                Text("Cairn").font(.system(size: 23, weight: .bold)).foregroundStyle(Brand.textPrimary)
            }
            .padding(.horizontal, 18).padding(.vertical, 20)

            VStack(spacing: Space.xs) {
                ForEach(items) { item in
                    NavRow(item: item, section: $section)
                }
            }
            .padding(.horizontal, 12)

            Spacer()
            ProPill(license: license) { section = .settings }
                .padding(.horizontal, 14).padding(.bottom, 6)
            DeviceCard(store: store).padding(.horizontal, 14).padding(.bottom, 14)
        }
        .frame(width: 250)
        .background(Brand.deepPanel)
        .overlay(Rectangle().fill(Brand.border).frame(width: 1), alignment: .trailing)
    }

}

/// One sidebar row — animated hover tint + selection, with a smooth section change.
private struct NavRow: View {
    let item: NavSection
    @Binding var section: NavSection
    @State private var hovering = false

    var body: some View {
        let selected = section == item
        Button {
            section = item
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(selected ? Brand.blue : Brand.textSecondary)
                    .frame(width: 24)
                Text(item.title)
                    .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Brand.blue : Brand.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Brand.blue.opacity(0.10) : (hovering ? Brand.blue.opacity(0.05) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.14), value: hovering)
        .onHover { hovering = $0 }
        .pointerCursor()
    }
}

struct DeviceCard: View {
    let store: ScanStore

    // CRITICAL: never read live disk values from this body.
    //
    // These used to call `DeviceInfo.available` / `.usedFraction` directly, and the
    // storage bar's width (inside a GeometryReader) therefore depended on free
    // space. Free space fluctuates constantly — especially on a nearly-full disk —
    // so layout read the disk, got a different number, re-laid out, read again…
    // an infinite layout-feedback loop that pinned the main thread at 100% CPU and
    // froze navigation across the entire app. The values are snapshotted into
    // @State and refreshed on a slow timer instead.
    @State private var freeBytes: Int64 = 0
    @State private var usedFraction: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                deviceImage.frame(width: 40, height: 30)
                Text(DeviceInfo.name).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Brand.textPrimary).lineLimit(1)
            }
            Text(DeviceInfo.specLine).font(.system(size: 11)).foregroundStyle(Brand.textMuted)
            Text(DeviceInfo.storageLine).font(.system(size: 11)).foregroundStyle(Brand.textMuted)

            // Storage bar — driven by the snapshot, never a live read.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Brand.border)
                    Capsule().fill(Brand.brand)
                        .frame(width: max(0, geo.size.width * usedFraction))
                }
            }
            .frame(height: 6)
            .padding(.top, 2)

            Text("\(Fmt.size(freeBytes)) available")
                .font(.system(size: 11)).foregroundStyle(Brand.textSecondary)
        }
        .cairnCard(14)
        .task(id: "deviceStats") {
            while !Task.isCancelled {
                let free = DeviceInfo.available
                let frac = DeviceInfo.usedFraction
                // Only publish a real change, so tiny fluctuations don't redraw.
                if abs(frac - usedFraction) > 0.001 || abs(free - freeBytes) > 50_000_000 {
                    freeBytes = free
                    usedFraction = frac
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)   // 5s
            }
        }
    }

    /// A render for THIS Mac's model if we ship one (`mac-macmini.png`,
    /// `mac-laptopcomputer.png`, …), else nil. Keyed off the model-matched symbol
    /// name so a MacBook never shows a Mac mini — falling back to Apple's own
    /// per-model SF Symbol, which is always correct for the hardware.
    static let macImage: NSImage? = {
        Bundle.main.url(forResource: "mac-\(DeviceInfo.deviceSymbol)", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
    }()

    @ViewBuilder private var deviceImage: some View {
        if let img = DeviceCard.macImage {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: DeviceInfo.deviceSymbol)
                .font(.system(size: 27, weight: .regular))
                .foregroundStyle(Brand.textPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
