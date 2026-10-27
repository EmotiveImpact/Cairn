import SwiftUI
import AppKit

struct PreferencesWorkspace: View {
    let store: ScanStore
    @ObservedObject var license: LicenseManager
    @Bindable private var settings = AppSettings.shared
    @Binding var tab: String
    @State private var message = ""
    @State private var showRulesList = false
    @State private var showReport = false
    @State private var checkingRules = false
    @AppStorage(CairnAppearance.key) private var appearance = CairnAppearance.dark.rawValue
    private let preview = CommandLine.arguments.contains("--preview-ui")
    private let tabs = ["General", "Cleaning", "Scanning", "Monitoring", "Protection", "Excluded locations", "AI tools", "License", "About & CLI"]
    private var tabLine: String {
        switch tab {
        case "General": return "How Cairn looks and starts."
        case "Cleaning": return "What happens when you clean."
        case "Scanning": return "What Cairn looks at when it scans."
        case "Monitoring": return "Watching your free space while Cairn runs. Nothing is ever removed."
        case "Protection": return "What Cairn never touches, whatever you choose."
        case "Excluded locations": return "Folders Cairn will never clean."
        case "AI tools": return "Let your AI coding tools ask Cairn about space."
        case "License": return "Your Cairn licence."
        default: return "Version and the command line."
        }
    }
    var body: some View {
        CairnWorkspace(eyebrow: preview ? "Settings · preview, changes off" : "Settings", title: tab, subtitle: tabLine) {
            VStack(alignment: .leading, spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(tabs, id: \.self) { item in
                            Button(item) { tab = item }
                                .buttonStyle(.plain).font(.system(size: 12)).fixedSize()
                                .foregroundStyle(tab == item ? Brand.textPrimary : Brand.textMuted)
                                .accessibilityAddTraits(tab == item ? .isSelected : [])
                        }
                    }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) { preferences }
                        .frame(maxWidth: 720, alignment: .leading)
                }.disabled(preview)
            }
        } detail: {
            EmptyView()
        } actions: {
            Text(message.isEmpty ? "Changes take effect straight away" : message)
                .font(.system(size: 13)).foregroundStyle(Brand.textMuted).lineLimit(2)
            Spacer()
            Button("macOS privacy settings") { FullDiskAccess.openSettings() }
                .buttonStyle(ControlPanelButtonStyle(size: .large)).disabled(preview)
        }
        .sheet(isPresented: $showRulesList) { RulesListSheet() }
        .sheet(isPresented: $showReport) { ProblemReportSheet(store: store) }
    }
    @ViewBuilder private var preferences: some View {
        switch tab {
        case "General":
            VStack(alignment: .leading, spacing: 10) {
                Text("Appearance").font(.system(size: 13, weight: .medium))
                CairnSegmentedControl(label: "Appearance", selection: $appearance,
                                      options: CairnAppearance.allCases.map { ($0.title, $0.rawValue) })
                    .frame(width: 330)
            }.nightRow()
            option("Sidebar focus outline", "Show an outline around the sidebar control reached with the keyboard.", $settings.showSidebarFocus)
            option("Open at login", "Register Cairn with macOS login items.", $settings.openAtLogin)
            option("Menu bar", "Show available internal storage beside Cairn's macOS menu bar icon.", $settings.showMenuBarItem)
            option("Offer leftovers when an app goes in the Bin", "When you drag an app to the Bin, Cairn shows what it left behind from the menu bar. Needs the menu bar icon and Full Disk Access. Nothing is removed until you review it.", $settings.offerAppLeftovers)
            option("Scan notifications", "Notify when a scan completes. macOS permission is required.", $settings.scanNotifications)
            option("Play a sound when a clean finishes", "A single soft chime. Off by default.", $settings.finishSound)
        case "Cleaning":
            VStack(alignment: .leading, spacing: 10) {
                Text("When you clean").font(.system(size: 13, weight: .medium))
                CairnSegmentedControl(label: "Removal", selection: $settings.removalMode,
                                      options: RemovalMode.allCases.map { ($0.title, $0) })
                    .frame(width: 360)
                Text(settings.removalMode.detail).font(.system(size: 11.5)).foregroundStyle(Brand.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }.nightRow()
            fixed("Tool cleans", "Docker, pnpm, Go, Homebrew, conda, simctl, git gc and Time Machine snapshots are cleaned with each tool's own command, so nothing is deleted behind the tool's back.")
            fixed("Always protected", "System files, credentials, Mail, Messages, Photos, iCloud, source repositories and AI conversation history are never removed, whichever mode you choose.")
        case "Scanning":
            option("Refresh older scans", "On launch, rescan if the previous scan is more than a week old.", $settings.autoScanWeekly)
            option("Skip external drives", "Keep general scans on this Mac.", $settings.ignoreExternalDrives)
            option("Developer caches", "Include package-manager, build and tool caches.", $settings.includeDeveloperCaches)
            option("Simulator data", "Include simulator caches and simulators for runtimes that are no longer installed.", $settings.includeSimulators)
            option("Extra large-file confirmation", "Request an additional confirmation for large file removal.", $settings.askBeforeDeleting)
            option("Recommendations", "Show relevant cleanup suggestions from measured results.", $settings.smartRecommendations)
            action("What Cairn looks for", "Every place Cairn checks, written from the app itself.", "See the list") { showRulesList = true }
            if RuleUpdates.enabled {
                action("Cleaning rules", "Version \(RuleUpdates.installedVersion). New places to look, signed by Cairn. They can only add cache folders, and everything still goes through review.",
                       checkingRules ? "Checking…" : "Check now") { checkRules() }
                    .disabled(checkingRules)
            } else {
                fixed("Cleaning rules", "Built into this version of Cairn. New places to look come with app updates.")
            }
        case "Monitoring":
            option("Space reserve alerts", "Check available space while Cairn is running and alert when it remains below your chosen reserve. Nothing is removed.", preview ? .constant(true) : $settings.reserveEnabled)
                .onChange(of: settings.reserveEnabled) { _, enabled in
                    if enabled && !preview {
                        settings.reservePaused = false
                        Notify.requestAuth()
                        StorageControl.shared.start()
                        Task { await StorageControl.shared.refreshCapacity(); await StorageControl.shared.refreshNotificationStatus() }
                    }
                    if !preview { StorageControl.shared.configureMonitoring() }
                }
            option("Watch known folders", "Observe metadata for build output, package and browser caches, Downloads and Codex local data. No file contents are read and no cleanup runs.", $settings.locationMonitoringEnabled)
                .onChange(of: settings.locationMonitoringEnabled) { _, _ in
                    if !preview { StorageControl.shared.start(); StorageControl.shared.configureMonitoring() }
                }
            option("Suggest when a folder grows", "Show a review suggestion after two complete, comparable measurements. Cairn never removes files from a suggestion.", $settings.growthSuggestionsEnabled)
                .onChange(of: settings.growthSuggestionsEnabled) { _, _ in
                    if !preview { StorageControl.shared.start(); StorageControl.shared.configureMonitoring() }
                }
            if settings.growthSuggestionsEnabled || preview {
                HStack {
                    Text("Growth threshold").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Stepper("\(settings.growthSuggestionGB) GB", value: $settings.growthSuggestionGB, in: 1...20)
                        .frame(width: 145)
                }.nightRow()
                ForEach(ObservedRoot.catalogue().filter { GrowthSuggestions.selectableIDs.contains($0.id) }) { root in
                    option(root.title, root.id == "downloads" ? "Personal files: suggestion opens an inspection only." : "Suggest an inspection when this location grows by the chosen amount.",
                           Binding(get: { settings.growthSuggestionIDs.contains(root.id) }, set: { selected in
                               if selected { settings.growthSuggestionIDs = Array(Set(settings.growthSuggestionIDs + [root.id])).sorted() }
                               else { settings.growthSuggestionIDs.removeAll { $0 == root.id } }
                           }))
                }
                .onChange(of: settings.growthSuggestionIDs) { _, _ in
                    if !preview { StorageControl.shared.configureMonitoring() }
                }
                fixed("Suggestion state", settings.locationMonitoringEnabled ? "Cairn will suggest inspections from recent compatible measurements. You can also measure known locations manually in Changes." : "Turn on Watch known folders for background measurements, or measure manually in Changes. Suggestions do not trigger cleanup.")
            }
            if preview || settings.reserveEnabled {
                option("Quiet hours · 22:00–08:00", "Keep in-app reserve status visible but send no reserve notifications during these local hours.", $settings.reserveQuietHours)
            }
            if preview || settings.reserveEnabled || (settings.locationMonitoringEnabled && settings.growthSuggestionsEnabled) {
                if !preview {
                    HStack(spacing: 16) {
                        if settings.reservePaused {
                            Text(settings.reservePauseUntil.map { "Paused until " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "Paused indefinitely").font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                            Spacer()
                            Button("Resume") { StorageControl.shared.resumeMonitoring() }.buttonStyle(ControlPanelButtonStyle())
                        } else {
                            Text("Pause monitoring").font(.system(size: 13))
                            Spacer()
                            Menu("Pause…") {
                                Button("For one hour") { StorageControl.shared.pauseMonitoring(until: Date().addingTimeInterval(3_600)) }
                                Button("Until tomorrow") { StorageControl.shared.pauseMonitoring(until: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))) }
                                Button("Indefinitely") { StorageControl.shared.pauseMonitoring(until: nil) }
                            }.fixedSize()
                        }
                    }
                    .nightRow()
                }
                fixed("Current state", preview ? "Sample reserve only · monitoring is not running in this preview." : StorageControl.shared.monitoringStatus)
                fixed("Notifications", preview ? "Disabled in sample preview." : StorageControl.shared.notificationStatus)
            }
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Reserve target").font(.system(size: 13, weight: .medium))
                    Text("An alert threshold, not storage held aside by macOS.").font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                }
                Spacer()
                Stepper("\(preview ? Int(PreviewStorageScenario.reserveBytes / 1_000_000_000) : settings.reserveGB) GB", value: $settings.reserveGB, in: 5...500, step: 5)
                    .frame(width: 150)
            }.nightRow()
            fixed("How it works", "Capacity is checked roughly every five minutes while monitoring runs. Optional folder monitoring waits at least a minute after writes and fifteen minutes between attempts, yields to your scans, and pauses under resource pressure. Quitting Cairn stops monitoring. Closing the window can leave the menu-bar app running.")
            if let checked = StorageControl.shared.lastChecked {
                fixed("Last checked", checked.formatted(date: .abbreviated, time: .shortened))
            }
        case "Protection":
            fixed("Conversation storage", "Known Codex and ChatGPT session, state and support locations are excluded.")
            fixed("System files & credentials", "Protected by the shared safety guard at scan and action time.")
            fixed("Running applications", "Cache cleanup skips known owners that are still running.")
            fixed("Source & recovery data", "Source, Git metadata, worktrees and recovery locations are protected.")
            fixed("Nothing runs without review", "Every deletion, Trash emptying and tool clean is shown to you first.")
            fixed("Unknown application data", "An absent application or old folder date never proves its data is disposable.")
        case "Excluded locations":
            if settings.excludedPaths.isEmpty {
                NightEmpty(title: "No folders excluded", message: "Add a folder and Cairn will never clean anything inside it.")
            }
            ForEach(settings.excludedPaths, id: \.self) { path in
                HStack {
                    Text(path).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Spacer()
                    Button("Remove") { settings.remove(path) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Brand.deepBlue)
                }.nightRow()
            }
            Button("Add a folder…") { let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = false; panel.begin { response in if response == .OK, let url = panel.url { settings.add(url) } } }.buttonStyle(ControlPanelButtonStyle()).padding(.vertical, 14)
        case "AI tools":
            AgentConnectionsPanel()
        case "License":
            ProStatusCard(license: license).padding(.vertical, 14)
        default:
            fixed("Cairn", "Native macOS storage and maintenance workspace · local development build")
            fixed("Command-line access", "Status, scan and categories are read-only. Clean previews eligible items but cannot remove them from the CLI. Installation is optional.")
            Button("Copy CLI installation command") {
                guard let binary = Bundle.main.executableURL else { return }
                guard CLIInstallPolicy.state(at: CLIInstallPolicy.target, for: binary) != .conflict else { message = "Another file owns /usr/local/bin/cairn. It was left unchanged."; return }
                let command = "sudo mkdir -p /usr/local/bin && sudo ln -s \(CLIInstallPolicy.quoteForShell(binary.path)) /usr/local/bin/cairn"
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(command, forType: .string)
                message = "Command copied. Review it in Terminal; no installation has run."
            }.buttonStyle(ControlPanelButtonStyle()).padding(.vertical, 14)
            action("Send a report", "Shows you the whole report first, to change or add to. It holds no file names, folder names or your account name.", "Send a report…") { showReport = true }
        }
    }
    /// A row with a button on the right, for things that open or run rather than switch.
    private func action(_ title: String, _ detail: String, _ button: String, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(Brand.textMuted).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button(button, action: perform).buttonStyle(ControlPanelButtonStyle())
        }
        .nightRow()
    }
    private func checkRules() {
        checkingRules = true
        Task {
            switch await RuleUpdates.check() {
            case .off: message = "Rules updates are off in this version."
            case .upToDate(let version): message = "Cleaning rules are up to date (version \(version))."
            case .updated(let version, let spots): message = "Cleaning rules updated to version \(version): \(spots) places to look. Scan again to use them."
            case .failed(let reason): message = reason
            }
            checkingRules = false
        }
    }
    /// A setting as a reference row: name and grey line on the left, switch on the right.
    private func option(_ title: String, _ detail: String, _ value: Binding<Bool>) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(Brand.textMuted).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .nightRow()
    }
    private func fixed(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                if tab == "Protection" { Image(systemName: "lock").font(.system(size: 11)).foregroundStyle(Brand.textMuted) }
            }
            Text(detail).font(.system(size: 12)).foregroundStyle(Brand.textMuted).fixedSize(horizontal: false, vertical: true)
        }
        .nightRow()
    }
}

/// Acknowledgement changes only Cairn's journal. The user must inspect both
/// locations; a missing Trash path after a crash cannot be reconstructed here.
struct InterruptedActionReview: View {
    let entry: ActionJournal.Entry
    let onAcknowledge: () async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var checkedOriginal = false
    @State private var checkedTrash = false
    @State private var working = false
    @State private var failure = false

    var body: some View {
        CairnDialog(title: "Review interrupted action", subtitle: "The filesystem outcome is unknown. Nothing will be replayed.", height: 520) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Original location").font(.system(size: 12, weight: .semibold))
                    Text(entry.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    Text("Recorded Trash location").font(.system(size: 12, weight: .semibold))
                    Text(entry.trashPath ?? "None was recorded. Check Finder Trash for this item and keep any uncertain data.")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Brand.textMuted).textSelection(.enabled)
                    Toggle("I checked the original location and any newer item there.", isOn: $checkedOriginal)
                    Toggle("I checked Finder Trash and the recovery history.", isOn: $checkedTrash)
                    Text("Acknowledging clears the block on future cleanup. It does not restore, remove, or mark this action successful. The uncertain record stays in the journal.")
                        .font(.system(size: 11)).foregroundStyle(Brand.textMuted).fixedSize(horizontal: false, vertical: true)
                    if failure { Text("The review could not be saved. No block was cleared; the journal remains available.").font(.system(size: 11)).foregroundStyle(Brand.amber) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        } actions: {
            Button("Cancel") { dismiss() }.buttonStyle(ControlPanelButtonStyle()).keyboardShortcut(.cancelAction)
            Button("Record manual review") {
                working = true
                Task {
                    if await onAcknowledge() { dismiss() }
                    else { failure = true; working = false }
                }
            }
            .buttonStyle(ControlPanelButtonStyle(primary: true))
            .disabled(!checkedOriginal || !checkedTrash || working)
        }
    }
}
