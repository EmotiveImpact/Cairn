import SwiftUI
import AppKit

/// Top-level navigation sections (the left sidebar).
enum NavSection: String, CaseIterable, Identifiable {
    case dashboard, changes, projects, makeRoom, target, smartScan, general, browsers, developer, ai, appleIntelligence, creative, chatApps, lookThrough, largeFiles, duplicates, apps, games, storage, bugs, activity, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Home"
        case .changes: return "Changes"
        case .projects: return "Projects"
        case .makeRoom: return "Make room"
        case .target: return "I need space"
        case .smartScan: return "Smart Scan"
        case .general: return "General Cleanup"
        case .browsers: return "Browsers"
        case .developer: return "Developer Cleanup"
        case .ai: return "AI Models"
        case .appleIntelligence: return "Apple Intelligence"
        case .creative: return "Creative Pro"
        case .chatApps: return "Chat apps"
        case .lookThrough: return "Look through"
        case .largeFiles: return "Large Files"
        case .duplicates: return "Duplicates"
        case .apps: return "Apps"
        case .games: return "Games"
        case .storage: return "Storage"
        case .bugs: return "Health"
        case .activity: return "Activity"
        case .settings: return "Settings"
        }
    }

    /// Outline SF Symbols matched to the mockup.
    var icon: String {
        switch self {
        case .dashboard: return "house"
        case .changes: return "chart.xyaxis.line"
        case .projects: return "folder"
        case .makeRoom: return "plus.circle"
        case .target: return "scope"
        case .smartScan: return "scope"
        case .general: return "sparkles"
        case .browsers: return "globe"
        case .developer: return "chevron.left.forwardslash.chevron.right"
        case .ai: return "brain.head.profile"
        case .appleIntelligence: return "sparkle"
        case .creative: return "film"
        case .chatApps: return "bubble.left"
        case .lookThrough: return "tray.full"
        case .largeFiles: return "folder"
        case .duplicates: return "doc.on.doc"
        case .apps: return "square.grid.2x2"
        case .games: return "gamecontroller"
        case .storage: return "externaldrive"
        case .bugs: return "heart.text.square"
        case .activity: return "clock"
        case .settings: return "circle.circle"
        }
    }

    /// The mockup's own line icon for the top-level sidebar rows.
    var glyph: SidebarIcon.Glyph? {
        switch self {
        case .dashboard: return .home
        case .projects: return .projects
        case .apps: return .apps
        case .activity: return .activity
        case .settings: return .settings
        default: return nil
        }
    }

    /// Findings that have a page of their own rather than a list section.
    static let ownPages: Set<String> = ["games", "chat-apps"]

    @MainActor
    func buckets(_ store: ScanStore) -> [ScanStore.Bucket] {
        switch self {
        case .smartScan: return store.buckets.filter { !Self.ownPages.contains($0.id) }
        case .general: return store.generalBuckets.filter { $0.id != "browser-caches" && !Self.ownPages.contains($0.id) }
        case .browsers: return store.buckets.filter { $0.id == "browser-caches" }
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
    @Environment(\.openWindow) private var openWindow
    @State private var preferencesTab = "General"
    @State private var storageDriveID: String?
    @State private var store = ScanStore()
    // Per-page stores are owned HERE (not inside their views) so results persist
    // across navigation and their scans run once — never orphaned/re-spawned.
    @State private var healthStore = HealthStore()
    @State private var dupStore = DuplicateStore()
    @State private var appStore = AppInventoryStore()
    @State private var storageStore = StorageTransferStore()
    @State private var control = StorageControl.shared
    @State private var operation = ScanGate.shared.snapshot
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
    @State private var reviewedGoalPlan: ReviewedSpacePlan?
    @State private var goalReviewPending = false
    @State private var goalReceiptRunID: UUID?
    private struct CompletionPresentation: Identifiable { let id = UUID(); let summary: ScanStore.CleanSummary }
    @State private var celebration: CompletionPresentation?
    @State private var pendingSummary: ScanStore.CleanSummary?
    @State private var showStatePreview = false
    @State private var fdaBannerDismissed = false
    @State private var developerSearch = ""
    @FocusState private var searchFocused: Bool
    @State private var showDeveloperInspector = false
    @State private var showResultFilter = false
    @State private var scanActivityIndex = 0
    private let previewMode = CommandLine.arguments.contains("--preview-ui")

    private var proEnabled: Bool { license.isUnlocked }
    private var showFDABanner: Bool {
        store.hasScanned && !store.fdaGranted && !fdaBannerDismissed
            && store.buckets.contains { $0.permissionGap }
    }

    /// Sidebar and page. Kept apart from `body`'s long modifier chain so the
    /// compiler can type-check each in reasonable time.
    private var shellLayout: some View {
        GeometryReader { viewport in
            HStack(spacing: 0) {
                NavSidebar(section: $section, readyBytes: store.recommendedBytes)
                VStack(spacing: 0) {
                    if let message = store.removalLogError {
                        Text(message).font(.system(size: 12)).foregroundStyle(Brand.amber).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Brand.deepPanel)
                    }
                    if showFDABanner { fdaBanner }
                    // Shell-owned stores survive navigation.
                    if showResultFilter && supportsResultFilter { resultFilter }
                    // Pages switch instantly. An implicit animation here animated every
                    // frame on the incoming page, so text slid into place on each switch.
                    mainContent
                        .frame(minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                        .clipped()
                    runningStatus
                }
                .frame(minWidth: 790, maxWidth: .infinity, maxHeight: .infinity)
                .background(AppBackground())
                // The page sits as a rounded card inside the sidebar's frame (Edem chose this, option C).
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(8)
            }
            .frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
        }
    }

    /// The layout with its sheets and scan rotation. Split from `body` so
    /// neither chain is too long for the type checker.
    private var shellWithSheets: some View {
        shellLayout
        .ignoresSafeArea(.container, edges: .top)
        .background(Brand.chrome)
        .sheet(isPresented: $showReview, onDismiss: {
            goalReviewPending = false; reviewedGoalPlan = nil
            store.endScopedReview()
            if let pendingSummary { celebration = CompletionPresentation(summary: pendingSummary); self.pendingSummary = nil }
        }) {
            ReviewSheet(store: store, proEnabled: proEnabled, goalPlan: goalReviewPending ? reviewedGoalPlan : nil,
                        onDone: { summary in
                            pendingSummary = summary
                            if goalReviewPending { goalReceiptRunID = store.lastCleanRunID }
                            goalReviewPending = false
                        })
        }
        .sheet(isPresented: $showStatePreview) { DialogStatePreview() }
        .task { if previewMode && CommandLine.arguments.contains("--preview-states") { showStatePreview = true } }
        // A slow scan can legitimately spend time in one category. Rotate only
        // categories the scanner has actually started; the footer remains calm
        // when there is just one active area or no scan at all.
        .task(id: store.isScanning) {
            scanActivityIndex = 0
            guard store.isScanning else { return }
            while !Task.isCancelled && store.isScanning {
                do { try await Task.sleep(nanoseconds: 2_400_000_000) }
                catch { return }
                let count = activeScanActivities.count
                scanActivityIndex = count > 1 ? (scanActivityIndex + 1) % count : 0
            }
        }
    }

    var body: some View {
        shellWithSheets
        // Land idle on launch (the OSS-cleaner norm): show the last scan's cached
        // results instantly; the user starts a fresh scan from the Dashboard CTA or
        // the Smart Scan page. No auto-scan, no launch CPU/RAM spike.
        .focusedSceneValue(\.cairnFind, supportsResultFilter ? { showResultFilter = true; searchFocused = true } : nil)
        .onChange(of: section) { _, next in
            developerSearch = ""
            searchFocused = false
            showResultFilter = false
            showDeveloperInspector = false
            celebration = nil
        }
        .onChange(of: appStore.isUninstalling) { _, active in if !active && !previewMode { Task { await control.refreshCapacity(force: true) } } }
        .onChange(of: dupStore.isRemoving) { _, active in if !active && !previewMode { Task { await control.refreshCapacity(force: true) } } }
        .onChange(of: healthStore.isFixing) { _, active in if !active && !previewMode { Task { await control.refreshCapacity(force: true) } } }
        .onChange(of: store.isCleaning) { _, cleaning in
            if !cleaning && !previewMode { Task { await control.refreshCapacity(force: true) } }
        }
        // A Finder or Terminal cleanup can happen while Cairn is in the
        // background. Re-read only the cheap volume-capacity metadata on return;
        // never start a whole-machine scan or infer which app caused the change.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if !previewMode { Task { await control.refreshCapacity() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: ScanGate.changed)) { _ in operation = ScanGate.shared.snapshot }
        .onChange(of: MenuBarRoute.shared.pending) { _, _ in handleMenuRequest() }
        // The menu bar Cairn builds stone by stone while a scan runs.
        .onChange(of: store.isScanning && !previewMode ? store.scanProgress : -1) { _, progress in
            CairnMenuBar.shared.setScanProgress(progress < 0 ? nil : progress)
        }
        .onAppear {
            MenuBarRoute.shared.openWindow = { openWindow(id: "main") }
            CairnMenuBar.shared.scanStatus = { menuScanStatus }
            handleMenuRequest()
            // A visual preview must not alter the installed app's history,
            // schedule a scan, or arm background cleanup of real Mac files.
            guard !previewMode else { return }
            store.loadSnapshot()
            Task { _ = await store.reconcileActionJournal(); await store.loadCleanupRuns() }
            store.onCompletedScan = { [weak store, weak control] in
                Task {
                    guard let store, let control else { return }
                    await control.refreshCapacity()
                    await control.recordCompletedScan(store)
                    control.measureLocations()
                }
            }
            storageStore.load()
            TrashWatch.shared.onLeftovers = { CairnMenuBar.shared.showLeftovers($0) }
            TrashWatch.shared.start()
            AppleIntelligence.RemovalWatch.shared.start()
            appStore.onRemovals = { [store] in await store.appendRemovals($0) }
            dupStore.onRemovals = { [store] in await store.appendRemovals($0) }
            healthStore.onRemovals = { [store] in await store.appendRemovals($0) }
            appStore.prepareRemoval = { [store] in await store.prepareRemovalLog() }
            dupStore.prepareRemoval = { [store] in await store.prepareRemovalLog() }
            healthStore.prepareRemoval = { [store] in await store.prepareRemovalLog() }
            appStore.beginReceipt = { [store] in await store.beginSpecialistRun("Apps") }
            dupStore.beginReceipt = { [store] in await store.beginSpecialistRun("Duplicates") }
            healthStore.beginReceipt = { [store] in await store.beginSpecialistRun("Health") }
            appStore.finishReceipt = { [store] in await store.finishSpecialistRun($0, summary: $1) }
            dupStore.finishReceipt = { [store] in await store.finishSpecialistRun($0, summary: $1) }
            healthStore.finishReceipt = { [store] in await store.finishSpecialistRun($0, summary: $1) }
            // Legacy daily history is read-only; StorageControl records new evidence.
            control.start()             // bounded capacity history; alerts only when opted in
            // Legacy clean-on-quit is inert; reserve monitoring only observes.
            // Honor "Auto Scan Weekly": refresh a stale (>7-day-old) scan on open.
            // Never fires on first run — landing idle stays the first impression.
            if !CommandLine.arguments.contains("--no-auto-scan"), AppSettings.shared.autoScanWeekly, store.phase == .idle,
               let last = store.lastScanDate,
               Date().timeIntervalSince(last) > 7 * 86_400 {
                store.startScan(includeExternalVolumes: !AppSettings.shared.ignoreExternalDrives)
            }
        }
        // Records RSS + what the app was doing, to ~/Library/Logs/Cairn-memory.log.
        // Local only. This is how a runaway spike gets traced to the page and scan
        // that caused it, instead of being guessed at after the fact.
        .task {
            guard !previewMode else { return }
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
        // AI tools reach the running app through this bridge to plan and run cleanups.
        .task {
            guard !previewMode else { return }
            AgentBridge.shared.attach(store: store, proEnabled: { license.isUnlocked })
        }
        .task {
            guard !previewMode, let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--scan-memory-report=") }) else { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await ScanUIMemoryCheck.run(store: store, duplicates: dupStore,
                route: { section = $0 }, report: URL(fileURLWithPath: String(argument.dropFirst("--scan-memory-report=".count))))
        }
        // Deterministic screenshots of the actual NSHostingView, with fixtures
        // and no disk actions. This is also a navigation/layout regression pass.
        .task {
            guard previewMode, let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--capture-workspaces=") }) else { return }
            let folder = URL(fileURLWithPath: String(argument.dropFirst("--capture-workspaces=".count)))
            do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) } catch { return }
            for route in NavSection.allCases {
                section = route
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard !Task.isCancelled, let window = NSApp.windows.first(where: { $0.styleMask.contains(.titled) }), let contentView = window.contentView else { return }
                let view = contentView.superview ?? contentView
                view.layoutSubtreeIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let data = bitmap.representation(using: .png, properties: [:]) {
                    let destination = folder.appendingPathComponent(route.rawValue + ".png")
                    await Task.detached(priority: .utility) {
                        try? data.write(to: destination)
                    }.value
                }
            }
            section = .developer
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

    private var menuScanStatus: MenuScanStatus {
        if previewMode { return MenuScanStatus(categoryCount: 3, scanDate: Date()) }
        return MenuScanStatus(scanning: store.isScanning,
                             operationBusy: store.isCleaning || store.isRestoring || appStore.isUninstalling || dupStore.isRemoving || healthStore.isFixing || storageStore.busy || showReview,
                             otherScanBusy: appStore.isScanning || dupStore.isScanning || healthStore.isScanning || control.measuringLocations,
                             categoryCount: store.displayBuckets.filter { $0.bytes > 0 }.count,
                             scanDate: store.lastScanDate, partial: store.phase == .cancelled, operationText: operationStatus,
                             readyBytes: store.recommendedBytes,
                             projectItems: store.buckets.first { $0.id == ProjectIndex.categoryID }?.items ?? [])
    }

    private func handleMenuRequest() {
        guard let request = MenuBarRoute.shared.pending else { return }
        MenuBarRoute.shared.pending = nil
        switch request.action {
        case .overview: section = .dashboard
        case .changes: section = .changes
        case .makeRoom: section = .makeRoom
        case .projects: section = .projects
        case .activity: section = .activity
        case .results: section = .smartScan
        case .storage(let id): storageDriveID = id; section = .storage
        case .preferences(let tab): preferencesTab = tab; section = .settings
        case .leftovers(let found):
            guard !previewMode, !store.isScanning, !store.isCleaning else { section = .apps; return }
            store.addLeftovers(AppLeftovers.items(found))
            if store.selectedCount > 0 { showReview = true }
        case .scan:
            guard !previewMode, menuScanStatus.canStart else { return }
            section = .smartScan
            store.startScan(includeExternalVolumes: !AppSettings.shared.ignoreExternalDrives)
        case .stop:
            guard !previewMode, store.isScanning else { return }
            store.cancel()
            section = .smartScan
        }
    }

    private var supportsResultFilter: Bool {
        ![NavSection.dashboard, .makeRoom, .target, .chatApps, .games, .appleIntelligence, .storage, .settings].contains(section)
    }

    /// Find belongs to the measured list, never to the whole Mac. Cmd-F opens
    /// this inline row; closing it clears the query so no invisible filter stays.
    private var resultFilter: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease").foregroundStyle(Brand.textMuted)
            TextField("Filter these results", text: $developerSearch)
                .textFieldStyle(.plain).font(.system(size: 12))
                .accessibilityLabel("Filter these results")
                .focused($searchFocused)
                .onExitCommand { closeResultFilter() }
            Button("Done") { closeResultFilter() }.buttonStyle(ControlPanelButtonStyle())
        }.padding(.horizontal, 24).frame(height: 44)
            .background(Brand.deepPanel)
            .onAppear { searchFocused = true }
    }

    private func closeResultFilter() {
        developerSearch = ""
        searchFocused = false
        showResultFilter = false
    }

    private func rescanCurrentSection() {
        guard !previewMode else { return }
        switch section {
        case .duplicates: if dupStore.isScanning { dupStore.cancel() } else { dupStore.rescan() }
        case .apps: if appStore.isScanning { appStore.cancel() } else { appStore.rescan() }
        case .bugs: if healthStore.isScanning { healthStore.cancel() } else { healthStore.rescan() }
        default: if store.isScanning { store.cancel() } else { store.rescan() }
        }
    }

    /// The Done screen takes the page beside the sidebar until the next navigation.
    @ViewBuilder private var mainContent: some View {
        if let result = celebration {
            WorkspaceCompletion(summary: result.summary,
                                onRecovery: { celebration = nil; section = .activity },
                                onClose: { celebration = nil },
                                store: store)
        } else {
            content.id(section)
        }
    }

    /// The status line only earns its place while something is running.
    @ViewBuilder private var runningStatus: some View {
        if store.isScanning || store.isCleaning {
            statusBar.fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Text("Cairn").fixedSize()
            Text("·")
            if !previewMode && store.isScanning && (operation.operation == .scan || operation.operation == nil) {
                ProgressView().controlSize(.mini).frame(width: 12, height: 12)
                    .accessibilityLabel("Scan in progress")
            }
            Text(previewMode ? "Visual preview · sample data · disk actions disabled" : operationStatus)
                .lineLimit(1).truncationMode(.middle)
                // Home has its own shimmering scan line; one moving line at a time.
                .shimmer(!previewMode && (store.isScanning || store.isCleaning) && !(section == .dashboard && store.isScanning))
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "lock.shield").foregroundStyle(Brand.textMuted)
            Text("Review before removal").fixedSize()
        }
        .font(.system(size: 10.5)).foregroundStyle(Brand.textMuted)
        .padding(.horizontal, 20).frame(height: 31)
        .background(Brand.background)
    }

    private var operationStatus: String {
        if store.isScanning && (operation.operation == .scan || operation.operation == nil) { return scanActivityStatus }
        if store.isScanning, let active = operation.operation { return active.rawValue + " · Smart Scan waiting" }
        if let active = operation.operation { return active.rawValue + (operation.queued > 0 ? " · \(operation.queued) queued" : "…") }
        if store.isCleaning { return "Cleaning reviewed items…" }
        if store.isRestoring { return "Restoring recorded item…" }
        if storageStore.checkingCopy { return "Verifying external copy…" }
        if storageStore.busy { return "Copying to external storage…" }
        if dupStore.isRemoving { return "Removing reviewed duplicate…" }
        if dupStore.isScanning { return "Scanning duplicates…" }
        if appStore.isUninstalling { return "Removing reviewed app…" }
        if appStore.isScanning { return "Scanning apps…" }
        if healthStore.isFixing { return "Applying reviewed fix…" }
        if healthStore.isScanning { return "Checking health…" }
        if store.isScanning { return store.progressText.isEmpty ? "Scanning…" : store.progressText }
        if control.measuringLocations { return control.measurementStatus }
        if store.phase == .cancelled { return "Scan stopped · partial results" }
        return store.hasScanned ? "Scan complete · ready to review" : "Ready to scan"
    }

    private var activeScanActivities: [String] {
        store.buckets.compactMap { bucket in
            guard !bucket.complete, !bucket.progress.isEmpty else { return nil }
            let detail = bucket.progress == "Scanning…" ? "" : " · \(bucket.progress.replacingOccurrences(of: "\n", with: " ").prefix(54))"
            return bucket.info.title + detail
        }
    }

    private var scanActivityStatus: String {
        let progress = "\(store.completedCount) of \(store.totalCount) areas checked"
        let active = activeScanActivities
        if !active.isEmpty { return "Scanning · \(progress) · Now: \(active[scanActivityIndex % active.count])" }
        if store.completedCount == store.totalCount && store.totalCount > 0 { return "Finishing scan · \(progress)" }
        return operation.operation == .scan ? "Starting scan · \(progress)" : "Waiting for other disk work · \(progress)"
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
            OverviewWorkspace(store: store, storage: storageStore, control: control,
                              search: developerSearch, onOpen: { section = $0 },
                              onCleanRecommended: {
                                  guard !previewMode else { return }
                                  store.selectRecommended()
                                  if store.selectedCount > 0 { showReview = true }
                              })
        case .changes:
            ChangesWorkspace(control: control, store: store, search: developerSearch,
                             onOpen: { section = $0 })
        case .projects:
            ProjectsWorkspace(store: store, search: developerSearch, inspectorVisible: $showDeveloperInspector,
                              onReview: { if !previewMode { showReview = true } })
        case .makeRoom:
            MakeRoomWorkspace(store: store, control: control, receiptRunID: goalReceiptRunID,
                onBack: { section = .dashboard },
                onScan: { store.startScan(includeExternalVolumes: false) },
                onReview: { plan in
                    reviewedGoalPlan = plan
                    store.clearSelection()
                    store.select { item, _ in plan.itemIDs.contains(item.id) }
                    if store.selectedCount > 0 { goalReviewPending = true; showReview = true }
                }, onOpen: { section = $0 })
        case .target:
            TargetWorkspace(store: store, freeNow: control.current?.available,
                            onScan: { store.startScan(includeExternalVolumes: false) },
                            onReview: { if !previewMode { showReview = true } },
                            onOpen: { section = $0 })
        case .chatApps:
            ChatAppsWorkspace(store: store, onReview: { if !previewMode { showReview = true } })
        case .appleIntelligence:
            AppleIntelligenceWorkspace()
        case .games:
            GamesWorkspace(store: store, onReview: { if !previewMode { showReview = true } }, onOpen: { section = $0 })
        case .smartScan, .general, .browsers, .developer, .ai, .creative:
            DeveloperCleanupView(store: store, section: section,
                                 searchText: developerSearch, inspectorVisible: $showDeveloperInspector,
                                 onReview: { if !previewMode { showReview = true } })
        case .lookThrough:
            LookThroughWorkspace(store: store, onReview: { if !previewMode { showReview = true } }, onOpen: { section = $0 })
        case .largeFiles:
            LargeFilesWorkspace(store: store, search: developerSearch,
                                inspectorVisible: $showDeveloperInspector,
                                onRescan: rescanCurrentSection,
                                onReview: { if !previewMode { showReview = true } })
        case .duplicates:
            DuplicatesWorkspace(store: dupStore, search: developerSearch, inspectorVisible: $showDeveloperInspector)
        case .apps:
            AppsWorkspace(store: appStore, search: developerSearch, inspectorVisible: $showDeveloperInspector,
                          onOpenGames: { section = .games })
        case .storage:
            StorageWorkspace(store: storageStore, search: developerSearch, focused: $storageDriveID)
        case .bugs:
            HealthWorkspace(store: healthStore, search: developerSearch, inspectorVisible: $showDeveloperInspector)
        case .activity:
            RecoveryWorkspace(store: store, search: developerSearch, inspectorVisible: $showDeveloperInspector,
                              onOpen: { section = $0 })
        case .settings:
            PreferencesWorkspace(store: store, license: license, tab: $preferencesTab)
        }
    }

}

/// The single dark surface inside Cairn's graphite window surround.
/// The page's background inside its rounded card, with the soft blue glow near the top left.
struct AppBackground: View {
    var body: some View {
        ZStack { Brand.background; Brand.glow }
    }
}

// MARK: - Sidebar

struct NavSidebar: View {
    @Binding var section: NavSection
    var readyBytes: Int64 = 0

    // Six top-level places. Health sits with the other cleanups, external
    // storage with files, and Changes is reached from Activity.
    private let cleanItems: [NavSection] = [.smartScan, .general, .browsers, .developer, .ai, .appleIntelligence, .creative, .chatApps, .bugs]
    private let fileItems: [NavSection] = [.lookThrough, .largeFiles, .duplicates, .storage]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                CairnLogo(size: 27).accessibilityHidden(true)
                Text("Cairn").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Brand.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20).padding(.top, 64).padding(.bottom, 17)
            .accessibilityElement(children: .combine)
            ScrollView {
                VStack(spacing: 2) {
                    NavRow(item: .dashboard, section: $section, also: [.target])
                    NavRow(item: .projects, section: $section)
                    SidebarDisclosure(title: "Clean", glyph: .clean, items: cleanItems, section: $section)
                    SidebarDisclosure(title: "Files", glyph: .files, items: fileItems, section: $section)
                    NavRow(item: .apps, section: $section, also: [.games])
                    NavRow(item: .activity, section: $section, also: [.changes])
                        .help("Free space over time, cleanup receipts and recovery")
                }
                .padding(.horizontal, 10).padding(.top, 2)
            }
            NavRow(item: .settings, section: $section)
                .padding(.horizontal, 10).padding(.bottom, 10)
        }
        .frame(width: 200)
        .background {
            ZStack {
                Brand.chrome
                SidebarSpaceField(readyBytes: readyBytes)
            }
        }
    }

}

/// Fade the rows in place. Layout changes happen outside the opacity animation:
/// opening reserves space first; closing releases it only after the fade ends.
private struct SidebarDisclosure: View {
    let title: String
    let glyph: SidebarIcon.Glyph
    let items: [NavSection]
    @Binding var section: NavSection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var manuallyExpanded = false
    @State private var occupiesSpace = false
    @State private var visible = false
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                expanded.toggle()
                manuallyExpanded = expanded
            } label: {
                HStack(spacing: 10) {
                    SidebarIcon(glyph: glyph)
                        .frame(width: 16).foregroundStyle(items.contains(section) ? Brand.room : Brand.textSecondary)
                    Text(title).font(.system(size: 13.5, weight: .regular)).foregroundStyle(Brand.textSecondary)
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(Brand.textMuted)
                }.padding(.horizontal, 10).frame(height: 33)
                .background {
                    if hovering { RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.04)) }
                }
                .onHover { hovering = $0 }
                .contentShape(Rectangle())
            }
            .buttonStyle(SidebarButtonStyle())
            .focusEffectDisabled(!AppSettings.shared.showSidebarFocus)
            .accessibilityLabel("\(title), \(expanded ? "expanded" : "collapsed")")

            VStack(spacing: 2) {
                ForEach(items) { item in
                    NavRow(item: item, section: $section, child: true,
                           label: item == .general ? "General" :
                                  item == .developer ? "Developer" :
                                  item == .creative ? "Creative" :
                                  item == .bugs ? "Mac health" :
                                  item == .appleIntelligence ? "Apple AI" :
                                  item == .storage ? "External storage" : nil)
                }
            }
            .padding(.top, 4)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(visible ? 1 : 0)
            .frame(height: occupiesSpace ? CGFloat(items.count * 38) : 0, alignment: .top)
            .clipped()
            .allowsHitTesting(expanded && visible)
            .disabled(!expanded)
            .accessibilityHidden(!expanded)
        }
        .onAppear {
            if items.contains(section) { expanded = true }
        }
        .onChange(of: section) { previous, next in
            if items.contains(next) {
                expanded = true
            } else if items.contains(previous) && !manuallyExpanded {
                expanded = false
            }
        }
        .task(id: expanded) {
            if reduceMotion {
                SidebarNavigation.update { occupiesSpace = expanded; visible = expanded }
                return
            }
            if expanded {
                SidebarNavigation.update { occupiesSpace = true }
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.18)) { visible = true }
            } else {
                withAnimation(.easeOut(duration: 0.18)) { visible = false }
                do { try await Task.sleep(for: .milliseconds(180)) }
                catch { return }
                guard !Task.isCancelled else { return }
                SidebarNavigation.update { occupiesSpace = false }
            }
        }
    }
}

/// Selection uses text/icon tone only, with no background or edge marker.
private struct NavRow: View {
    let item: NavSection
    @Binding var section: NavSection
    var child = false
    var label: String? = nil
    /// Pages reached from this row that should keep it highlighted.
    var also: [NavSection] = []
    @State private var hovering = false

    var body: some View {
        let selected = section == item || also.contains(section)
        Button {
            guard section != item else { return }
            SidebarNavigation.update { section = item }
        } label: {
            HStack(spacing: 10) {
                if !child {
                    Group {
                        if let glyph = item.glyph { SidebarIcon(glyph: glyph) }
                        else { Image(systemName: item.icon).font(.system(size: 15, weight: .light)) }
                    }
                    .foregroundStyle(selected ? Brand.room : Brand.textSecondary)
                    .frame(width: 16)
                }
                Text(label ?? item.title).lineLimit(1)
                    .font(.system(size: child ? 13 : 13.5, weight: .regular))
                    .foregroundStyle(selected ? Brand.textPrimary : Brand.textSecondary)
                Spacer()
            }
            .padding(.leading, child ? 20 : 10).padding(.trailing, 10)
            .frame(height: child ? 30 : 33)
            .background {
                if selected && !child {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Brand.surfaceSubtle)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.04))
                }
            }
            .onHover { hovering = $0 }
            .padding(.leading, child ? 26 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarButtonStyle())
            .focusEffectDisabled(!AppSettings.shared.showSidebarFocus)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Sidebar selection supplies its own persistent feedback. Do not let the
/// platform plain-button style dim or scale the label during a mouse press.
private struct SidebarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentTransition(.identity)
    }
}

private enum SidebarNavigation {
    static func update(_ action: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, action)
    }
}
