import SwiftUI
import AppKit

/// Top-level navigation sections (the left sidebar).
enum NavSection: String, CaseIterable, Identifiable {
    case dashboard, changes, makeRoom, smartScan, general, browsers, developer, ai, creative, largeFiles, duplicates, apps, storage, bugs, activity, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Overview"
        case .changes: return "Changes"
        case .makeRoom: return "Make room"
        case .smartScan: return "Smart Scan"
        case .general: return "General Cleanup"
        case .browsers: return "Browsers"
        case .developer: return "Developer Cleanup"
        case .ai: return "AI Models"
        case .creative: return "Creative Pro"
        case .largeFiles: return "Large Files"
        case .duplicates: return "Duplicates"
        case .apps: return "Apps"
        case .storage: return "Storage"
        case .bugs: return "Health"
        case .activity: return "Activity & Recovery"
        case .settings: return "Settings"
        }
    }

    /// Outline SF Symbols matched to the mockup.
    var icon: String {
        switch self {
        case .dashboard: return "house"
        case .changes: return "chart.xyaxis.line"
        case .makeRoom: return "plus.circle"
        case .smartScan: return "scope"
        case .general: return "sparkles"
        case .browsers: return "globe"
        case .developer: return "chevron.left.forwardslash.chevron.right"
        case .ai: return "brain.head.profile"
        case .creative: return "film"
        case .largeFiles: return "folder"
        case .duplicates: return "doc.on.doc"
        case .apps: return "square.stack.3d.up"
        case .storage: return "externaldrive"
        case .bugs: return "heart.text.square"
        case .activity: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }

    /// Sections that open an existing sheet rather than routing content.
    var opensSheet: Bool { false }

    @MainActor
    func buckets(_ store: ScanStore) -> [ScanStore.Bucket] {
        switch self {
        case .smartScan: return store.buckets
        case .general: return store.generalBuckets.filter { $0.id != "browser-caches" }
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
    @StateObject private var license = LicenseManager()
    /// `Cairn --section=duplicates` opens straight onto a page. Used to profile
    /// each screen in isolation (and to grab screenshots) without clicking.
    @State private var section: NavSection = {
        guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--section=") }),
              let s = NavSection(rawValue: String(arg.dropFirst("--section=".count)))
        else { return .dashboard }
        return s
    }()
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var showReview = false
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
    private let previewMode = CommandLine.arguments.contains("--preview-ui")

    private var proEnabled: Bool { license.isUnlocked }
    private var showFDABanner: Bool {
        store.hasScanned && !store.fdaGranted && !fdaBannerDismissed
            && store.buckets.contains { $0.permissionGap }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: $sidebarVisibility) {
                NavSidebar(section: $section)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 200)
            } detail: {
                VStack(spacing: 0) {
                    if let message = store.removalLogError {
                        Text(message).font(.system(size: 12)).foregroundStyle(Brand.amber).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Brand.deepPanel)
                    }
                    if showFDABanner { fdaBanner }
                    // Shell-owned stores survive both navigation and sidebar toggling.
                    if showResultFilter && supportsResultFilter { resultFilter }
                    content
                    statusBar
                }
                .frame(minWidth: 810, maxWidth: .infinity, maxHeight: .infinity)
                .background(AppBackground())
                .navigationTitle(section.title)
                .toolbar { workspaceToolbar }
                .toolbarBackground(Brand.deepPanel, for: .windowToolbar)
                .toolbarBackground(.visible, for: .windowToolbar)
            }
            .navigationSplitViewStyle(.balanced)
        }
        .background(Brand.background)
        .sheet(isPresented: $showReview, onDismiss: {
            goalReviewPending = false
            if let pendingSummary { celebration = CompletionPresentation(summary: pendingSummary); self.pendingSummary = nil }
        }) {
            ReviewSheet(store: store, proEnabled: proEnabled,
                        onDone: { summary in
                            pendingSummary = summary
                            if goalReviewPending { goalReceiptRunID = store.lastCleanRunID }
                            goalReviewPending = false
                        },
                        onUpgrade: { showReview = false; preferencesTab = "License"; section = .settings })
        }
        .sheet(item: $celebration) { result in
            WorkspaceCompletion(summary: result.summary, onRecovery: { celebration = nil; section = .activity }, onClose: { celebration = nil })
        }
        .sheet(isPresented: $showStatePreview) { DialogStatePreview() }
        .task { if previewMode && CommandLine.arguments.contains("--preview-states") { showStatePreview = true } }
        // Land idle on launch (the OSS-cleaner norm): show the last scan's cached
        // results instantly; the user starts a fresh scan from the Dashboard CTA or
        // the Smart Scan page. No auto-scan, no launch CPU/RAM spike.
        .focusedSceneValue(\.cairnFind, supportsResultFilter ? { showResultFilter = true; searchFocused = true } : nil)
        .onChange(of: section) { _, _ in developerSearch = ""; searchFocused = false; showResultFilter = false; showDeveloperInspector = false }
        .onChange(of: store.isCleaning) { _, cleaning in
            if !cleaning && !previewMode { Task { await control.refreshCapacity(force: true) } }
        }
        .onChange(of: MenuBarRoute.shared.pending) { _, _ in handleMenuRequest() }
        .onAppear {
            MenuBarRoute.shared.openWindow = { openWindow(id: "main") }
            CairnMenuBar.shared.scanStatus = { menuScanStatus }
            handleMenuRequest()
            // A visual preview must not alter the installed app's history,
            // schedule a scan, or arm background cleanup of real Mac files.
            guard !previewMode else { return }
            store.loadSnapshot()
            store.loadRemovalLog()
            store.onCompletedScan = { [weak store, weak control] in
                Task {
                    guard let store, let control else { return }
                    await control.refreshCapacity()
                    control.recordCompletedScan(store)
                }
            }
            storageStore.load()
            appStore.onRemovals = { [store] in store.appendRemovals($0) }
            dupStore.onRemovals = { [store] in store.appendRemovals($0) }
            healthStore.onRemovals = { [store] in store.appendRemovals($0) }
            appStore.prepareRemoval = { [store] in store.prepareRemovalLog() }
            dupStore.prepareRemoval = { [store] in store.prepareRemovalLog() }
            healthStore.prepareRemoval = { [store] in store.prepareRemovalLog() }
            StorageHistory.record()   // one free-space sample a day, for the forecast
            control.start()             // bounded capacity history; alerts only when opted in
            // Watch for dev tools quitting. Does nothing unless the setting is on
            // AND Pro is unlocked — the guard lives at the point of use so a trial
            // expiring mid-session can't leave a trigger armed.
            // Automatic cleanup is intentionally not armed; every removal uses review.
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
                    try? data.write(to: folder.appendingPathComponent(route.rawValue + ".png"))
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
                             otherScanBusy: appStore.isScanning || dupStore.isScanning || healthStore.isScanning,
                             categoryCount: store.displayBuckets.filter { $0.bytes > 0 }.count,
                             scanDate: store.lastScanDate, partial: store.phase == .cancelled)
    }

    private func handleMenuRequest() {
        guard let request = MenuBarRoute.shared.pending else { return }
        MenuBarRoute.shared.pending = nil
        switch request.action {
        case .overview: section = .dashboard
        case .changes: section = .changes
        case .makeRoom: section = .makeRoom
        case .activity: section = .activity
        case .results: section = .smartScan
        case .storage(let id): storageDriveID = id; section = .storage
        case .preferences(let tab): preferencesTab = tab; section = .settings
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

    /// System toolbar owns window controls, title alignment and the sidebar
    /// toggle. No hand-positioned window controls or brand spacer.
    @ToolbarContentBuilder private var workspaceToolbar: some ToolbarContent {
        if section != .settings && section != .activity && section != .storage && section != .dashboard && section != .changes && section != .makeRoom {
            ToolbarItem(placement: .primaryAction) {
                Button(action: rescanCurrentSection) {
                    Label(currentScanning ? "Stop scan" : "Rescan", systemImage: currentScanning ? "stop.circle" : "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(previewMode || store.isCleaning || appStore.isUninstalling || dupStore.isRemoving || healthStore.isFixing)
            }
        }
        if section != .settings && section != .dashboard && section != .storage && section != .changes && section != .makeRoom {
            ToolbarItem(placement: .primaryAction) {
                Button { showDeveloperInspector.toggle() } label: {
                    Label(showDeveloperInspector ? "Hide details" : "Details", systemImage: "sidebar.right")
                }
                .help(showDeveloperInspector ? "Hide details" : "Show details")
            }
        }
    }

    private var supportsResultFilter: Bool {
        ![NavSection.dashboard, .makeRoom, .storage, .settings].contains(section)
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

    private var currentScanning: Bool {
        switch section {
        case .apps: return appStore.isScanning
        case .duplicates: return dupStore.isScanning
        case .bugs: return healthStore.isScanning
        default: return store.isScanning
        }
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

    private var statusBar: some View {
        HStack(spacing: 8) {
            Text("Cairn")
            Text("·")
            Text(previewMode ? "Visual preview · sample data · disk actions disabled" : operationStatus)
            Spacer()
            Image(systemName: "lock.shield").foregroundStyle(Brand.textMuted)
            Text("Review before removal")
        }
        .font(.system(size: 10.5)).foregroundStyle(Brand.textMuted)
        .padding(.horizontal, 20).frame(height: 31)
        .background(Brand.deepPanel)
    }

    private var operationStatus: String {
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
        if store.phase == .cancelled { return "Scan stopped · partial results" }
        return store.hasScanned ? "Scan complete · ready to review" : "Ready to scan"
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
                              search: developerSearch, onOpen: { section = $0 })
        case .changes:
            ChangesWorkspace(control: control, store: store, search: developerSearch,
                             onOpen: { section = $0 })
        case .makeRoom:
            MakeRoomWorkspace(store: store, control: control, receiptRunID: goalReceiptRunID,
                onBack: { section = .dashboard },
                onScan: { store.startScan(includeExternalVolumes: false) },
                onReview: { ids in
                    store.clearSelection()
                    store.select { item, _ in ids.contains(item.id) }
                    if store.selectedCount > 0 { goalReviewPending = true; showReview = true }
                }, onOpen: { section = $0 })
        case .smartScan, .general, .browsers, .developer, .ai, .creative, .largeFiles:
            DeveloperCleanupView(store: store, section: section, proEnabled: proEnabled,
                                 searchText: developerSearch, inspectorVisible: $showDeveloperInspector,
                                 onReview: { if !previewMode { showReview = true } },
                                 onUpgrade: { preferencesTab = "License"; section = .settings })
        case .duplicates:
            DuplicatesWorkspace(store: dupStore, search: developerSearch, inspectorVisible: $showDeveloperInspector)
        case .apps:
            AppsWorkspace(store: appStore, search: developerSearch, inspectorVisible: $showDeveloperInspector)
        case .storage:
            StorageWorkspace(store: storageStore, search: developerSearch, focused: $storageDriveID)
        case .bugs:
            HealthWorkspace(store: healthStore, search: developerSearch, inspectorVisible: $showDeveloperInspector)
        case .activity:
            RecoveryWorkspace(store: store, search: developerSearch, inspectorVisible: $showDeveloperInspector)
        case .settings:
            PreferencesWorkspace(store: store, license: license, tab: $preferencesTab)
        }
    }

}

/// The content-area background behind each route.
struct AppBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(hex: 0x1A1F25), Brand.background],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

// MARK: - Sidebar

struct NavSidebar: View {
    @Binding var section: NavSection

    private let cleanItems: [NavSection] = [.smartScan, .general, .browsers, .developer, .ai, .creative]
    private let fileItems: [NavSection] = [.largeFiles, .duplicates]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                CairnLogo(size: 27).accessibilityHidden(true)
                Text("Cairn").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Brand.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20).padding(.top, 17).padding(.bottom, 17)
            .accessibilityElement(children: .combine)
            ScrollView {
                VStack(spacing: 4) {
                    NavRow(item: .dashboard, section: $section)
                    NavRow(item: .changes, section: $section)
                    SidebarDisclosure(title: "Clean", icon: "paintbrush", items: cleanItems, section: $section)
                    SidebarDisclosure(title: "Files", icon: "doc.on.doc", items: fileItems, section: $section)
                    NavRow(item: .apps, section: $section)
                    NavRow(item: .storage, section: $section)
                    NavRow(item: .bugs, section: $section)
                    NavRow(item: .activity, section: $section, label: "Activity")
                        .accessibilityLabel("Activity & Recovery")
                        .help("Review past actions and available recovery")
                }
                .padding(.horizontal, 11).padding(.top, 2)
            }
            NavRow(item: .settings, section: $section)
                .padding(.horizontal, 11).padding(.bottom, 10)
        }
        .frame(width: 200)
        .background(Brand.deepPanel)
    }

}

/// Fade the rows in place. Layout changes happen outside the opacity animation:
/// opening reserves space first; closing releases it only after the fade ends.
private struct SidebarDisclosure: View {
    let title: String
    let icon: String
    let items: [NavSection]
    @Binding var section: NavSection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var occupiesSpace = false
    @State private var visible = false

    var body: some View {
        VStack(spacing: 0) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 11) {
                    Image(systemName: icon).font(.system(size: 15))
                        .frame(width: 21).foregroundStyle(items.contains(section) ? Brand.blue : Brand.textSecondary)
                    Text(title).font(.system(size: 14, weight: .regular)).foregroundStyle(Brand.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(Brand.textMuted)
                }.padding(.horizontal, 11).frame(height: 39).contentShape(Rectangle())
            }
            .buttonStyle(SidebarButtonStyle())
            .focusEffectDisabled(!AppSettings.shared.showSidebarFocus)
            .accessibilityLabel("\(title), \(expanded ? "expanded" : "collapsed")")

            VStack(spacing: 4) {
                ForEach(items) { item in
                    NavRow(item: item, section: $section, child: true,
                           label: item == .general ? "General" :
                                  item == .developer ? "Developer" :
                                  item == .creative ? "Creative" : nil)
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

    var body: some View {
        let selected = section == item
        Button {
            guard section != item else { return }
            SidebarNavigation.update { section = item }
        } label: {
            HStack(spacing: 11) {
                if !child {
                    Image(systemName: item.icon)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(selected ? Brand.blue : Brand.textSecondary)
                        .frame(width: 21)
                }
                Text(label ?? item.title).lineLimit(1)
                    .font(.system(size: child ? 13 : 14, weight: .regular))
                    .foregroundStyle(selected ? Brand.textPrimary : Brand.textSecondary)
                Spacer()
            }
            .padding(.leading, child ? 17 : 11).padding(.trailing, 11)
            .frame(height: child ? 34 : 44)
            .padding(.leading, child ? 38 : 0)
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

private struct TopbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Brand.textSecondary)
            .padding(.horizontal, 10).frame(height: 31)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(configuration.isPressed ? Brand.surfaceSubtle : Brand.surfaceElevated.opacity(0.75)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Brand.inputBorder.opacity(0.65)))
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
