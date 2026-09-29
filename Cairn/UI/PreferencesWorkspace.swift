import SwiftUI
import AppKit

struct PreferencesWorkspace: View {
    let store: ScanStore
    @ObservedObject var license: LicenseManager
    @Bindable private var settings = AppSettings.shared
    @Binding var tab: String
    @State private var message = ""
    private let preview = CommandLine.arguments.contains("--preview-ui")
    private let tabs = ["General", "Scanning", "Monitoring", "Protection", "Excluded locations", "License", "About & CLI"]
    var body: some View {
        CairnWorkspace(title: "Preferences", subtitle: preview ? "Preview · changes disabled" : "Saved on this Mac", inspectorVisible: false) {
            VStack(spacing: 0) {
                Picker("Preferences", selection: $tab) { ForEach(tabs, id: \.self) { Text($0) } }
                    .pickerStyle(.segmented).labelsHidden().padding(.horizontal, 26).padding(.bottom, 16)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) { preferences }.padding(.horizontal, 22)
                }.disabled(preview)
            }
        } detail: {
            WorkspaceHeading(title: tab, subtitle: "Cairn settings", icon: "gearshape")
            WorkspaceDetail(title: "A deliberate default", text: "Cleanup requires a review. Protected paths cannot be made removable by switching off a setting.")
            WorkspaceDetail(title: "External storage", text: "Storage shows drive identity and supported path guidance. Cairn does not redirect macOS swap or synchronize active database folders.")
            WorkspaceDetail(title: "Recovery", text: "Removal history is retained. Put Back works only while the corresponding Trash item still exists. Trash is not a backup.")
        } actions: {
            Text(message.isEmpty ? "Settings take effect immediately" : message).foregroundStyle(Brand.textMuted).lineLimit(2)
            Spacer()
            Button("macOS privacy settings") { FullDiskAccess.openSettings() }.buttonStyle(ControlPanelButtonStyle()).disabled(preview)
        }
    }
    @ViewBuilder private var preferences: some View {
        switch tab {
        case "General":
            option("Sidebar focus outline", "Show an outline around the sidebar control reached with the keyboard.", $settings.showSidebarFocus)
            option("Open at login", "Register Cairn with macOS login items.", $settings.openAtLogin)
            option("Menu bar", "Keep a small Cairn menu in the macOS menu bar.", $settings.showMenuBarItem)
            option("Scan notifications", "Notify when a scan completes. macOS permission is required.", $settings.scanNotifications)
        case "Scanning":
            option("Refresh older scans", "On launch, rescan if the previous scan is more than a week old.", $settings.autoScanWeekly)
            option("Skip external drives", "Keep general scans on this Mac.", $settings.ignoreExternalDrives)
            option("Developer caches", "Include supported developer-tool cache categories.", $settings.includeDeveloperCaches)
            option("Simulator data", "Include simulator measurements; device contents are inspection-only.", $settings.includeSimulators)
            option("Extra large-file confirmation", "Request an additional confirmation for large file removal.", $settings.askBeforeDeleting)
            option("Local snapshot before cleanup", "Ask Time Machine for a local snapshot. Cleanup stops if the request fails; a snapshot is not an external backup.", $settings.createRestoreSnapshot)
            option("Recommendations", "Show relevant cleanup suggestions from measured results.", $settings.smartRecommendations)
        case "Monitoring":
            option("Space reserve alerts", "Check available space while Cairn is running and alert when it remains below your chosen reserve. Nothing is removed.", $settings.reserveEnabled)
                .onChange(of: settings.reserveEnabled) { _, enabled in
                    if enabled && !preview {
                        settings.reservePaused = false
                        Notify.requestAuth()
                        StorageControl.shared.start()
                        Task { await StorageControl.shared.refreshCapacity() }
                    }
                }
            if settings.reserveEnabled {
                option("Pause alerts", "Keep your target but stop background checks and notifications until resumed.", $settings.reservePaused)
            }
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Reserve target").font(.system(size: 13, weight: .medium))
                    Text("An alert threshold, not storage held aside by macOS.").font(.system(size: 11.5)).foregroundStyle(Brand.textMuted)
                }
                Spacer()
                Stepper("\(settings.reserveGB) GB", value: $settings.reserveGB, in: 5...500, step: 5)
                    .frame(width: 150)
            }.padding(.vertical, 18)
            fixed("How it works", "Cairn checks capacity roughly every five minutes while it is open. It never clears files in the background. If Cairn is closed, monitoring stops until it runs again.")
            if let checked = StorageControl.shared.lastChecked {
                fixed("Last checked", checked.formatted(date: .abbreviated, time: .shortened))
            }
        case "Protection":
            fixed("Conversation storage", "Known Codex and ChatGPT session, state and support locations are excluded.")
            fixed("System files & credentials", "Protected by the shared safety guard at scan and action time.")
            fixed("Running applications", "Cache cleanup skips known owners that are still running.")
            fixed("Source & recovery data", "Source, Git metadata, worktrees and recovery locations are protected.")
            fixed("No automatic Trash emptying", "Cairn does not permanently empty Trash.")
            fixed("Unknown application data", "An absent application or old folder date never proves its data is disposable.")
            Text("Automatic cleanup on app quit is disabled in this build. Review the measured paths before every removal.").font(.system(size: 12)).foregroundStyle(Brand.textMuted).padding(.vertical, 18)
        case "Excluded locations":
            Text("Excluded paths and their children are blocked by cleanup.").font(.system(size: 12)).foregroundStyle(Brand.textSecondary).padding(.vertical, 18)
            ForEach(settings.excludedPaths, id: \.self) { path in
                HStack { Text(path).font(.system(size: 11)).textSelection(.enabled); Spacer(); Button("Remove") { settings.remove(path) }.buttonStyle(.borderless) }.padding(.vertical, 14)
            }
            Button("Add location…") { let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = false; panel.begin { response in if response == .OK, let url = panel.url { settings.add(url) } } }.buttonStyle(ControlPanelButtonStyle()).padding(.vertical, 18)
        case "License":
            ProStatusCard(license: license).padding(.vertical, 20)
        default:
            fixed("Cairn", "Native macOS storage and maintenance workspace · local development build")
            fixed("Command-line access", "The existing status, scan, clean and categories commands remain available. Installation is optional.")
            Button("Copy CLI installation command") {
                guard let binary = Bundle.main.executableURL else { return }
                guard CLIInstallPolicy.state(at: CLIInstallPolicy.target, for: binary) != .conflict else { message = "Another file owns /usr/local/bin/cairn. It was left unchanged."; return }
                let command = "sudo mkdir -p /usr/local/bin && sudo ln -s \(CLIInstallPolicy.quoteForShell(binary.path)) /usr/local/bin/cairn"
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(command, forType: .string)
                message = "Command copied. Review it in Terminal; no installation has run."
            }.buttonStyle(ControlPanelButtonStyle()).padding(.vertical, 18)
        }
    }
    private func option(_ title: String, _ detail: String, _ value: Binding<Bool>) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 13, weight: .medium)); Text(detail).font(.system(size: 11.5)).foregroundStyle(Brand.textMuted).fixedSize(horizontal: false, vertical: true) }.frame(maxWidth: .infinity, alignment: .leading)
                Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }.padding(.vertical, 18)
        }
    }
    private func fixed(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Text(title).font(.system(size: 13, weight: .medium)); Spacer(); if tab == "Protection" { Image(systemName: "lock.fill").foregroundStyle(Brand.textMuted) } }
            Text(detail).font(.system(size: 11.5)).foregroundStyle(Brand.textMuted).fixedSize(horizontal: false, vertical: true)
        }.padding(.top, 18)
    }
}

struct RecoveryWorkspace: View {
    let store: ScanStore
    var search: String
    @Binding var inspectorVisible: Bool
    @State private var focused: UUID?
    @State private var message = ""
    @State private var restoreSucceeded = false
    @State private var confirm = false
    @State private var plan: ScanStore.RemovalLogEntry?
    @State private var availableTrash: Set<UUID> = []
    @State private var actionJournal: [ActionJournal.Entry] = []
    private let preview = CommandLine.arguments.contains("--preview-ui")
    @State private var samples = [ScanStore.RemovalLogEntry(name: "Build output", originalPath: "~/Library/Developer/Xcode/DerivedData/Sample", trashPath: "~/.Trash/Sample", bytes: 2_300_000_000, date: Date(), category: "xcode"), ScanStore.RemovalLogEntry(name: "Tool-managed cache", originalPath: "Tool command", trashPath: nil, bytes: 400_000_000, date: Date().addingTimeInterval(-86400), category: "dev-caches")]
    private var entries: [ScanStore.RemovalLogEntry] { (preview ? samples : store.removalLog).filter { search.isEmpty || ($0.name + $0.originalPath).localizedCaseInsensitiveContains(search) } }
    private var needsManualReview: [ActionJournal.Entry] {
        let recordedPaths = Set(store.removalLog.compactMap(\.trashPath))
        return actionJournal.filter { entry in
            entry.state == .pending || (entry.state == .succeeded && entry.trashPath.map { !recordedPaths.contains($0) } == true)
        }
    }
    private var inspected: ScanStore.RemovalLogEntry? { entries.first { $0.id == focused } ?? entries.first }
    var body: some View {
        CairnWorkspace(title: "Activity  ›  Recovery", subtitle: "\(entries.count) records", inspectorVisible: inspectorVisible) {
            VStack(spacing: 0) {
                if !preview, let journalError = ActionJournal.shared.error {
                    CairnStateView(kind: .attention, title: "Action journal needs attention", message: journalError, compact: true)
                        .padding(14)
                }
                if !needsManualReview.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ACTION NEEDS MANUAL REVIEW").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(Brand.amber)
                        Text("A move may have been interrupted or its recovery record may be missing. Cairn will not replay it. Check the original and Trash locations before further cleanup.")
                            .font(.system(size: 11)).foregroundStyle(Brand.textSecondary)
                        ForEach(needsManualReview.prefix(5)) { entry in
                            Text("\(entry.state == .pending ? "Uncertain" : "Recovery record missing") · \(entry.path)")
                                .font(.system(size: 11)).foregroundStyle(Brand.textMuted).textSelection(.enabled)
                        }
                        Button("Show action journal") { NSWorkspace.shared.activateFileViewerSelecting([ActionJournal.shared.location]) }
                            .buttonStyle(ControlPanelButtonStyle())
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                }
                WorkspaceColumns(leading: "Operation", trailing: "Estimate · recovery")
                if !message.isEmpty { CairnStateView(kind: restoreSucceeded ? .completed : .attention, title: restoreSucceeded ? "Item restored" : "Restore could not finish", message: message, compact: true) }
                if entries.isEmpty { WorkspaceEmpty(title: "No recorded operations", message: "Reviewed cleanups appear here with their original path and recorded Trash location.", icon: "clock.arrow.circlepath") }
                else { ScrollView { LazyVStack(spacing: 0) { ForEach(entries) { entry in
                    WorkspaceRow(title: entry.name, subtitle: entry.originalPath, icon: "clock.arrow.circlepath", value: Fmt.size(entry.bytes), status: entry.restoredAt != nil ? "Restored" : availableTrash.contains(entry.id) ? "In Trash" : entry.actionKind == "tool" ? "Tool action" : "Unavailable", focused: inspectorVisible && inspected?.id == entry.id) { focused = entry.id; inspectorVisible = true }
                } } } }
            }
        } detail: {
            if let entry = inspected {
                WorkspaceHeading(title: entry.name, subtitle: Fmt.relative(entry.date), icon: "arrow.uturn.backward", value: Fmt.size(entry.bytes))
                WorkspaceDetail(title: "Recorded size", text: "This is a file-size estimate from the scan, not measured space freed. Trash items continue to occupy disk space.")
                WorkspaceDetail(title: "Original location", text: entry.originalPath)
                WorkspaceDetail(title: "Recorded Trash location", text: entry.trashPath ?? "No Trash path was recorded for this action.")
                WorkspaceDetail(title: "Recovery", text: availableTrash.contains(entry.id) ? "The recorded Trash entry is present. Put Back refuses to overwrite an existing original." : "The Trash entry is absent or cannot be accessed. The history record alone cannot restore the contents.")
            }
            WorkspaceDetail(title: "History stays", text: "An unsuccessful restore keeps the operation record. Cairn does not erase the history just because a Trash item is missing.")
        } actions: {
            Text(message.isEmpty ? "Recovery depends on the original Trash item" : message).foregroundStyle(Brand.textMuted).lineLimit(2)
            Spacer()
            Button("Put Back…") { plan = inspected; confirm = true }.buttonStyle(ControlPanelButtonStyle(primary: true)).disabled(preview || store.isRestoring || inspected.map { !availableTrash.contains($0.id) } ?? true)
        }.task { await refresh() }
        .sheet(isPresented: $confirm) {
            if let entry = plan { WorkspaceConfirmation(title: "Restore \(entry.name)?", explanation: "Return the recorded Trash item to its original path. Existing files will not be overwritten.", entries: [entry.originalPath], actionTitle: "Put Back") { Task { restoreSucceeded = await store.restoreFromLog(entry); message = restoreSucceeded ? "Restored \(entry.name)." : "Restore failed. The history record was retained."; await refresh() } } }
        }
    }
    private func refresh() async {
        guard !preview else { availableTrash = Set(samples.filter(\.recoverable).map(\.id)); return }
        let records = store.removalLog
        availableTrash = await Task.detached { Set(records.filter { $0.recoverable && $0.trashPath.map { FileManager.default.fileExists(atPath: $0) } ?? false }.map(\.id)) }.value
        actionJournal = await Task.detached(priority: .utility) { ActionJournal.shared.recent }.value
    }
}
