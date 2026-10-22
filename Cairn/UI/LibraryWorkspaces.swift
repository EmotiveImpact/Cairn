import SwiftUI
import AppKit

struct AppsWorkspace: View {
    let store: AppInventoryStore
    var search: String
    @Binding var inspectorVisible: Bool
    @State private var focused: UUID?
    @State private var filter = "All"
    @State private var confirm = false
    @State private var busy = false
    @State private var result = ""
    @State private var resultHasFailures = false
    @State private var receipt: (changes: [CleanupCapacityChange], bytes: Int64, recoveries: Int)?
    @State private var plan: [AppEntry] = []
    @State private var samples = sampleApps()
    private let preview = CommandLine.arguments.contains("--preview-ui")
    private var allApps: [AppEntry] { preview ? samples : store.apps }
    private var apps: [AppEntry] { allApps.filter { app in
        (search.isEmpty || (app.name + app.bundleID).localizedCaseInsensitiveContains(search))
        && (filter != "Not used lately" || app.isUnused) && (filter != "Large" || app.isLarge)
    }.sorted { total($0) > total($1) } }
    private var selected: [AppEntry] { allApps.filter { $0.selected && $0.isRemovable } }
    private var inspected: AppEntry? { apps.first { $0.id == focused } ?? apps.first }
    private var largest: Int64 { apps.map { total($0) }.max() ?? 1 }
    private func total(_ app: AppEntry) -> Int64 { app.size + app.componentsSize }

    var body: some View {
        CairnWorkspace(eyebrow: store.isScanning ? "Apps · reading" : "Apps · \(allApps.count) installed",
                       title: "\(Fmt.size(allApps.reduce(0) { $0 + total($1) })) in apps",
                       subtitle: "Removing an app moves only the app to the Trash. Its settings and documents stay.",
                       inspectorVisible: inspectorVisible, onCloseInspector: { inspectorVisible = false }) {
            Button(store.isScanning ? "Stop scan" : "Rescan") {
                if store.isScanning { store.cancel() } else { store.rescan() }
            }
            .buttonStyle(ControlPanelButtonStyle(size: .small))
            .disabled(preview || busy || store.isUninstalling)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 18) {
                    ForEach(["All", "Not used lately", "Large"], id: \.self) { option in
                        Button(option) { filter = option }
                            .buttonStyle(.plain).font(.system(size: 12))
                            .foregroundStyle(filter == option ? Brand.textPrimary : Brand.textMuted)
                    }
                }
                if busy {
                    NightEmpty(title: "Removing the apps you chose", message: "Their settings and documents stay where they are.", busy: true)
                } else if !result.isEmpty {
                    NightEmpty(title: resultHasFailures ? "Finished, with some apps skipped" : "Apps removed", message: result + ". Their settings and documents were kept.")
                    if let receipt { CapacityReceiptView(changes: receipt.changes, estimatedBytes: receipt.bytes, recoveryCount: receipt.recoveries) }
                }
                if apps.isEmpty {
                    if store.isScanning {
                        NightEmpty(title: "Reading your apps", message: store.progress, busy: true)
                    } else {
                        NightEmpty(title: filter == "All" && search.isEmpty ? "No apps measured yet" : "No matching apps",
                                   message: filter == "All" && search.isEmpty ? "Press Rescan to measure your apps." : "Try All to see every app.")
                    }
                    Spacer(minLength: 0)
                } else {
                    NightList { ForEach(apps) { app in row(app) } }
                }
            }
        } detail: {
            if let app = inspected { detail(app) }
        } actions: {
            NightTotal(strong: Fmt.size(selected.reduce(0) { $0 + $1.size }),
                       rest: selected.isEmpty ? "selected" : "selected from \(selected.count) \(selected.count == 1 ? "app" : "apps")")
            Spacer()
            if busy { ProgressView().controlSize(.small) }
            if !selected.isEmpty {
                Button("Select none") { for app in selected { toggle(app) } }
                    .buttonStyle(ControlPanelButtonStyle(size: .large)).disabled(busy)
            }
            Button("Review removal") { plan = selected; confirm = true }
                .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
                .disabled(selected.isEmpty || preview || busy || store.isUninstalling || store.isScanning)
        }
        .sheet(isPresented: $confirm) { WorkspaceConfirmation(title: "Remove \(plan.count) \(plan.count == 1 ? "app" : "apps")?", explanation: "These apps move to the Trash. Close them first; any still open are skipped. Their settings and documents stay.", entries: plan.map { $0.url.path }, actionTitle: "Move to Trash") {
            busy = true
            Task { let outcome = await store.uninstall(plan); receipt = (outcome.capacityChanges, outcome.bytes, outcome.recordedRecoveries); resultHasFailures = outcome.failed > 0 || !outcome.errors.isEmpty; result = "\(outcome.trashedApps) removed · \(outcome.failed) skipped" + (outcome.errors.first.map { " · \($0)" } ?? ""); busy = false }
        } }
    }

    /// Check | grey app icon, name and sizes | share | total | pill, as in the reference rows.
    private func row(_ app: AppEntry) -> some View {
        HStack(spacing: 14) {
            NightCheck(on: app.selected, enabled: app.isRemovable && !busy && !preview) { toggle(app) }
                .accessibilityLabel(app.isRemovable ? "Select \(app.name)" : "\(app.name) is protected")
            Button { focused = app.id; inspectorVisible = true } label: {
                HStack(spacing: 14) {
                    HStack(spacing: 10) {
                        FileIcon(url: app.url, size: 22).saturation(0).opacity(0.85)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.textPrimary).lineLimit(1)
                            Text("\(Fmt.size(app.size)) app · \(Fmt.size(app.componentsSize)) settings and data")
                                .font(.system(size: 12)).foregroundStyle(Brand.textMuted).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    NightMeter(share: Double(total(app)) / Double(max(1, largest)))
                    Text(Fmt.size(total(app))).font(.system(size: 13, weight: .medium)).monospacedDigit()
                        .frame(width: 90, alignment: .trailing)
                    Group {
                        if !app.isRemovable { NightPill(text: "Protected") }
                        else if app.selected { NightPill(text: "Selected", tone: .ok) }
                        else if app.isUnused { NightPill(text: "Not used lately") }
                        else { Color.clear.frame(height: 1) }
                    }
                    .frame(width: 120, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .nightRow()
        .background(inspectorVisible && inspected?.id == app.id ? Brand.wash(0.035) : Color.clear)
    }

    @ViewBuilder private func detail(_ app: AppEntry) -> some View {
        HStack(spacing: 12) {
            FileIcon(url: app.url, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.system(size: 15, weight: .medium))
                Text(app.developer).font(.system(size: 12)).foregroundStyle(Brand.textMuted)
            }
        }
        WorkspaceDetail(title: "The app", text: Fmt.size(app.size))
        WorkspaceDetail(title: "Its settings and data", text: "\(Fmt.size(app.componentsSize)). These stay on your Mac when the app is removed.")
        WorkspaceDetail(title: "Last opened", text: app.lastOpened.map { Fmt.relative($0) } ?? "macOS has not recorded this, so it may still be in use.")
        WorkspaceDetail(title: "Removing it", text: app.isRemovable ? "Only the app moves to the Trash. Close it first." : "This app is part of macOS or protected, so Cairn will not remove it.")
        if !app.associated.isEmpty {
            DisclosureGroup("Where its data lives · \(app.associated.count)") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(app.associated.prefix(8), id: \.self) { path in
                        Text(path.path).font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                    if app.associated.count > 8 {
                        Text("and \(app.associated.count - 8) more").font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                    }
                }.padding(.top, 8)
            }.font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
        }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
            .buttonStyle(ControlPanelButtonStyle()).disabled(preview)
    }

    private func toggle(_ app: AppEntry) { if preview { if let i = samples.firstIndex(where: { $0.id == app.id }) { samples[i].selected.toggle() } } else { store.toggle(app.id) } }
    private static func sampleApps() -> [AppEntry] {
        let examples: [(name: String, id: String, developer: String, bundleGB: Double, relatedGB: Double)] = [
            ("Xcode", "com.apple.dt.Xcode", "Apple", 4.3, 14.2),
            ("Google Chrome", "com.google.Chrome", "Google", 0.8, 6.6),
            ("Visual Studio Code", "com.microsoft.VSCode", "Microsoft", 0.7, 2.9),
            ("Codex", "com.openai.codex", "OpenAI", 0.4, 2.0)
        ]
        return examples.map { example in
            AppEntry(name: example.name, developer: example.developer, bundleID: example.id,
                     version: "Sample application", url: URL(fileURLWithPath: "/Applications/\(example.name).app"),
                     size: Int64(example.bundleGB * 1e9), supportSize: Int64(example.relatedGB * 1e9),
                     leftoverSize: 0, associated: [], lastOpened: Date().addingTimeInterval(-86_400),
                     isApple: example.id.hasPrefix("com.apple"), isIntel: false, isSystem: false)
        }
    }
}

struct DuplicatesWorkspace: View {
    let store: DuplicateStore
    var search: String
    @Binding var inspectorVisible: Bool
    @State private var expanded: Set<UUID> = []
    @State private var focused: UUID?
    @State private var confirm = false
    @State private var message = ""
    @State private var resultHasFailures = false
    @State private var receipt: (changes: [CleanupCapacityChange], bytes: Int64, recoveries: Int)?
    @State private var samples = sampleGroups()
    private let preview = CommandLine.arguments.contains("--preview-ui")
    private var groups: [DupGroup] { (preview ? samples : store.visibleGroups).filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.files.contains { $0.url.path.localizedCaseInsensitiveContains(search) } } }
    private var inspected: DupGroup? { groups.first { $0.id == focused } ?? groups.first }
    private var largest: Int64 { groups.map(\.reclaimableSize).max() ?? 1 }
    private var extraBytes: Int64 { groups.reduce(0) { $0 + $1.reclaimableSize } }
    var body: some View {
        CairnWorkspace(eyebrow: store.isScanning ? "Files · comparing" : "Files · \(groups.count) \(groups.count == 1 ? "group" : "groups") of copies",
                       title: groups.isEmpty ? "Duplicates" : "\(Fmt.size(extraBytes)) in extra copies",
                       subtitle: "Files with exactly the same contents. One copy always stays.",
                       inspectorVisible: inspectorVisible, onCloseInspector: { inspectorVisible = false }) {
            Button(store.isScanning ? "Stop scan" : "Rescan") {
                if store.isScanning { store.cancel() } else { store.rescan() }
            }
            .buttonStyle(ControlPanelButtonStyle(size: .small))
            .disabled(preview || store.isRemoving)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                if store.isRemoving {
                    NightEmpty(title: "Checking and moving the extra copies", message: "The copy you keep stays put. Each file is checked again first.", busy: true)
                } else if !message.isEmpty {
                    NightEmpty(title: resultHasFailures ? "Finished, with some copies skipped" : "Extra copies moved", message: message + ". Items in the Trash still use space until it is emptied.")
                    if let receipt { CapacityReceiptView(changes: receipt.changes, estimatedBytes: receipt.bytes, recoveryCount: receipt.recoveries) }
                }
                if store.phase == .cancelled {
                    NightEmpty(title: "Comparison stopped", message: "These results may be incomplete. Rescan before choosing copies.")
                } else if store.wasLimited {
                    NightEmpty(title: "Partly compared", message: store.progressText)
                }
                if groups.isEmpty {
                    if store.isScanning {
                        NightEmpty(title: "Comparing file contents", message: store.progressText, busy: true)
                    } else {
                        NightEmpty(title: search.isEmpty ? "No duplicates found" : "No matching duplicates",
                                   message: !search.isEmpty ? "Try another search." : store.hasScanned ? "No identical files in Documents, Downloads, Desktop, Pictures or Movies." : "Press Rescan to look for identical files in Documents, Downloads, Desktop, Pictures and Movies.")
                    }
                    Spacer(minLength: 0)
                } else {
                    NightList {
                        ForEach(groups) { group in
                            groupRow(group)
                            if expanded.contains(group.id) { ForEach(group.files) { file in fileRow(file, in: group) } }
                        }
                        if !preview && store.hasMoreGroups {
                            Button("Show more") { store.showMoreGroups() }
                                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Brand.deepBlue).padding(.vertical, 12)
                        }
                    }
                }
            }
        } detail: {
            if let group = inspected {
                HStack(spacing: 12) {
                    if let url = group.representativeURL { FileIcon(url: url, size: 40) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name).font(.system(size: 15, weight: .medium)).lineLimit(2)
                        Text("\(group.count) copies · \(Fmt.size(group.copySize)) each").font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                    }
                }
                WorkspaceDetail(title: "Same contents", text: preview ? "Sample group for the preview." : "Every byte matched when compared. Cairn checks again before moving anything.")
                ForEach(group.files.indices, id: \.self) { index in
                    let file = group.files[index]
                    WorkspaceDetail(title: file.isKeeper ? "Copy \(index + 1) · kept" : "Copy \(index + 1)", text: "\(file.url.path)\nChanged \(file.modified.formatted(date: .abbreviated, time: .shortened))")
                }
                WorkspaceDetail(title: "After", text: "The extra copies you choose go to the Trash. The kept copy stays where it is. A copy elsewhere is not a backup.")
                if let url = group.representativeURL { Button("Show kept copy") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.buttonStyle(ControlPanelButtonStyle()).disabled(preview) }
            }
        } actions: {
            NightTotal(strong: Fmt.size(store.selectedBytes),
                       rest: store.selectedCopyCount == 0 ? "selected" : "selected from \(store.selectedCopyCount) \(store.selectedCopyCount == 1 ? "copy" : "copies")")
            Spacer()
            if store.selectedCopyCount > 0 {
                Button("Select none") { store.clearSelection() }
                    .buttonStyle(ControlPanelButtonStyle(size: .large)).disabled(preview || store.isRemoving)
            } else {
                Button("Select extra copies") { store.autoSelectRecommended() }
                    .buttonStyle(ControlPanelButtonStyle(size: .large)).disabled(preview || store.isScanning || store.isRemoving || groups.isEmpty)
            }
            Button("Review and move") { confirm = true }
                .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
                .disabled(preview || store.selectedCopyCount == 0 || store.isRemoving || store.isScanning)
        }
        .sheet(isPresented: $confirm) { WorkspaceConfirmation(title: "Move the selected extra copies?", explanation: "The kept copies stay where they are. Cairn checks the contents again, then moves only the copies you selected to the Trash.", entries: store.groups.flatMap(\.files).filter(\.selected).map { $0.url.path }, actionTitle: "Check and move to Trash") { Task { let result = await store.removeSelected(); receipt = (result.capacityChanges, result.bytes, result.recordedRecoveries); resultHasFailures = result.failed > 0 || !result.errors.isEmpty; message = "\(result.trashed) moved · \(result.failed) skipped" + (result.errors.first.map { " · \($0)" } ?? "") } } }
    }

    private func groupRow(_ group: DupGroup) -> some View {
        let picked = group.files.filter(\.selected).count
        return Button {
            focused = group.id; inspectorVisible = true
            expanded.formSymmetricDifference([group.id])
        } label: {
            HStack(spacing: 14) {
                HStack(spacing: 10) {
                    Group {
                        if let url = group.representativeURL { FileIcon(url: url, size: 22).saturation(0).opacity(0.85) }
                        else { Image(systemName: "doc.on.doc").font(.system(size: 14, weight: .light)).foregroundStyle(Brand.textSecondary) }
                    }
                    .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.textPrimary).lineLimit(1)
                        Text("\(group.count) copies · \(Fmt.size(group.copySize)) each")
                            .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                NightMeter(share: Double(group.reclaimableSize) / Double(max(1, largest)))
                Text(Fmt.size(group.reclaimableSize)).font(.system(size: 13, weight: .medium)).monospacedDigit()
                    .frame(width: 90, alignment: .trailing)
                NightPill(text: picked > 0 ? "\(picked) selected" : "Keeps one", tone: picked > 0 ? .ok : .neutral)
                    .frame(width: 120, alignment: .leading)
            }
            .nightRow()
            .background(inspectorVisible && inspected?.id == group.id ? Brand.wash(0.035) : Color.clear)
        }
        .buttonStyle(.plain)
        .help("Extra copies' combined size. Copies can share disk blocks, so the space you get back may be less.")
    }

    private func fileRow(_ file: DupFile, in group: DupGroup) -> some View {
        HStack(spacing: 14) {
            if file.isKeeper {
                Image(systemName: "lock").font(.system(size: 11)).foregroundStyle(Brand.textMuted).frame(width: 22, height: 22)
            } else {
                NightCheck(on: file.selected, enabled: !preview && !store.isRemoving) { store.toggle(file.id) }
                    .accessibilityLabel("Select copy \(file.url.path)")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(file.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 12.5)).foregroundStyle(Brand.textPrimary).lineLimit(1).truncationMode(.middle)
                Text("Changed \(file.modified.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if file.isKeeper {
                NightPill(text: "Kept", tone: .ok).frame(width: 120, alignment: .leading)
            } else {
                Button("Keep this one") { store.setKeeper(file.id, in: group.id) }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Brand.deepBlue)
                    .disabled(preview || store.isRemoving).frame(width: 120, alignment: .leading)
            }
        }
        .padding(.leading, 36)
        .nightRow()
        .contextMenu { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) } }
    }

    private static func sampleGroups() -> [DupGroup] {
        ["Design archive.zip", "Product walkthrough.mov", "Research notes.pdf"].enumerated().map { n, name in
            let size = Int64(3 - n) * 240_000_000
            return DupGroup(name: name, hash: "preview", files: ["Documents", "Downloads"].enumerated().map { i, folder in let url = URL(fileURLWithPath: "/Sample/\(folder)/\(name)"); return DupFile(url: url, resolvedURL: url, size: size, modified: Date(), isKeeper: i == 0) })
        }
    }
}

struct HealthWorkspace: View {
    let store: HealthStore
    var search: String
    @Binding var inspectorVisible: Bool
    @State private var focused: UUID?
    @State private var confirm = false
    @State private var fixing = false
    @State private var plan: [HealthIssue] = []
    private let preview = CommandLine.arguments.contains("--preview-ui")
    @State private var sampleGroups: [HealthGroup] = [HealthGroup(id: "launch-agents", title: "Launch agents", subtitle: "Review missing targets", systemImage: "clock", items: [HealthIssue(title: "Old helper", url: FileScan.home.appendingPathComponent("Library/LaunchAgents/example.plist"), detail: "Sample: launch agent refers to a program that is no longer present.", fixable: true)], actionable: true), HealthGroup(id: "orphaned", title: "Application support", subtitle: "Inspection only", systemImage: "folder", items: [HealthIssue(title: "Unmatched application data", url: nil, detail: "An unknown owner does not mean this data is disposable. Keep saved work and application state.", fixable: false)], actionable: false)]
    private var groups: [HealthGroup] { preview ? sampleGroups : store.groups }
    private var issues: [HealthIssue] { groups.flatMap(\.items).filter { search.isEmpty || ($0.title + $0.detail).localizedCaseInsensitiveContains(search) } }
    private var inspected: HealthIssue? { issues.first { $0.id == focused } ?? issues.first }
    private var title: String {
        if !issues.isEmpty { return "\(issues.count) \(issues.count == 1 ? "thing" : "things") to look at" }
        return preview || store.hasScanned ? "Nothing needs attention" : "Not checked yet"
    }
    var body: some View {
        CairnWorkspace(eyebrow: store.isScanning ? "Mac health · checking" : store.lastScanAt.map { "Mac health · checked \(Fmt.relative($0))" } ?? "Mac health",
                       title: title,
                       subtitle: "Old launch agents, leftover app data, login items, preferences and permissions. This is not a virus scan.",
                       inspectorVisible: inspectorVisible, onCloseInspector: { inspectorVisible = false }) {
            Button(store.isScanning ? "Stop" : "Check again") {
                if store.isScanning { store.cancel() } else { store.rescan() }
            }
            .buttonStyle(ControlPanelButtonStyle(size: .small))
            .disabled(preview || store.isFixing)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                if store.isFixing {
                    NightEmpty(title: "Applying what you reviewed", message: "Only the reviewed locations are touched.", busy: true)
                } else if let result = store.lastResult {
                    NightEmpty(title: result.failed == 0 ? "Done" : "Done, with some skipped",
                               message: "\(result.trashed) moved · \(result.failed) skipped. " + result.errors.joined(separator: "\n"))
                    CapacityReceiptView(changes: result.capacityChanges, estimatedBytes: result.bytes, recoveryCount: result.recordedRecoveries)
                }
                if store.wasCancelled {
                    NightEmpty(title: "Checks stopped", message: "Earlier findings may still be shown. Check again to finish.")
                }
                if issues.isEmpty {
                    if store.isScanning {
                        NightEmpty(title: "Checking this Mac", message: store.progressText, busy: true)
                    } else {
                        NightEmpty(title: !search.isEmpty ? "No matching findings" : store.hasScanned || preview ? "All clear" : "Ready to check",
                                   message: !search.isEmpty ? "Try another search." : "Saved work, repositories, passwords and recovery data are always left alone.")
                    }
                    Spacer(minLength: 0)
                } else {
                    NightList {
                        ForEach(issues) { issue in
                            WorkspaceRow(title: issue.title, subtitle: issue.detail, icon: issue.fixable ? "clock" : "info.circle",
                                         status: issue.fixable ? "Review" : "Advice only", tone: issue.fixable ? .warn : .neutral,
                                         focused: inspectorVisible && inspected?.id == issue.id) {
                                focused = issue.id; inspectorVisible = true
                            }
                        }
                    }
                }
            }
        } detail: {
            if let issue = inspected {
                Text(issue.title).font(.system(size: 15, weight: .medium))
                WorkspaceDetail(title: "What Cairn found", text: issue.detail)
                WorkspaceDetail(title: "What you can do", text: issue.fixable ? "Review the old launch agent file, then move it to the Trash. A service that is running now is not stopped." : "Nothing to remove. Cairn only points this out.")
                if let url = issue.url {
                    WorkspaceDetail(title: "Where", text: url.path)
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.buttonStyle(ControlPanelButtonStyle()).disabled(preview)
                }
            }
        } actions: {
            Text(inspected?.fixable == true ? "Nothing moves until you review it" : "Choose a finding to see what it means")
                .font(.system(size: 13)).foregroundStyle(Brand.textMuted)
            Spacer()
            Button("Review this finding") { if let issue = inspected { plan = [issue]; confirm = true } }
                .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
                .disabled(preview || inspected?.fixable != true || fixing || store.isFixing || store.isScanning)
        }
        .sheet(isPresented: $confirm) { WorkspaceConfirmation(title: "Move this to the Trash?", explanation: "Only the file listed is affected. Make sure it is no longer needed.", entries: plan.compactMap { $0.url?.path }, actionTitle: "Move to Trash") { fixing = true; Task { await store.fix(items: plan); fixing = false } } }
    }
}
