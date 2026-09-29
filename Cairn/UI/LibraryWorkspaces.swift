import SwiftUI
import AppKit

struct AppsWorkspace: View {
    let store: AppInventoryStore
    var search: String
    @Binding var inspectorVisible: Bool
    @State private var focused: UUID?
    @State private var filter = "All apps"
    @State private var confirm = false
    @State private var busy = false
    @State private var result = ""
    @State private var resultHasFailures = false
    @State private var plan: [AppEntry] = []
    @State private var samples = sampleApps()
    private let preview = CommandLine.arguments.contains("--preview-ui")
    private var apps: [AppEntry] { (preview ? samples : store.apps).filter { app in
        (search.isEmpty || (app.name + app.bundleID).localizedCaseInsensitiveContains(search)) && (filter != "Unused" || app.isUnused) && (filter != "Large" || app.isLarge) && (filter != "Removable" || app.isRemovable)
    }.sorted { $0.size > $1.size } }
    private var selected: [AppEntry] { (preview ? samples : store.apps).filter { $0.selected && $0.isRemovable } }
    private var inspected: AppEntry? { apps.first { $0.id == focused } ?? apps.first }
    var body: some View {
        CairnWorkspace(title: "Applications", subtitle: "\(apps.count) apps · bundle size", inspectorVisible: inspectorVisible) {
            VStack(spacing: 0) {
                HStack { Picker("Show", selection: $filter) { ForEach(["All apps", "Unused", "Large", "Removable"], id: \.self) { Text($0) } }.pickerStyle(.segmented).frame(maxWidth: 410); Spacer() }.padding(14)
                WorkspaceColumns(leading: "Application", trailing: "Bundle size")
                if !result.isEmpty { CairnStateView(kind: resultHasFailures ? .attention : .completed, title: resultHasFailures ? "Finished with skipped applications" : "Application removal finished", message: result + ". Associated data was kept.", compact: true) }
                if busy { CairnStateView(kind: .scanning, title: "Removing reviewed applications", message: "Associated data stays in place. Results will appear here.", compact: true) }
                if store.isScanning { CairnStateView(kind: .scanning, title: "Reading applications", message: store.progress, compact: true) }
                else if store.wasCancelled { CairnStateView(kind: .interrupted, title: "Scan stopped", message: "Previous results may still be shown. Rescan to refresh them.", compact: true) }
                if apps.isEmpty && !store.isScanning && !store.wasCancelled { WorkspaceEmpty(title: "No matching applications", message: !search.isEmpty || filter != "All apps" ? "Try another search or choose All apps." : "Rescan to measure installed applications.") }
                else { ScrollView { LazyVStack(spacing: 0) { ForEach(apps) { app in
                    HStack(spacing: 0) {
                        Button { toggle(app) } label: { Image(systemName: app.selected ? "checkmark.square.fill" : "square").font(.system(size: 16)).foregroundStyle(app.selected ? Brand.blue : Brand.textMuted) }.buttonStyle(.plain).disabled(!app.isRemovable || busy).padding(.leading, 16).accessibilityLabel("Select \(app.name)")
                        Button { focused = app.id; inspectorVisible = true } label: {
                            HStack(spacing: 12) {
                                FileIcon(url: app.url, size: 32)
                                VStack(alignment: .leading, spacing: 4) { Text(app.name).font(.system(size: 12.5, weight: .medium)); Text(app.developer).font(.system(size: 10.5)).foregroundStyle(Brand.textMuted).lineLimit(1) }.frame(maxWidth: .infinity, alignment: .leading)
                                if !app.isRemovable { Image(systemName: "lock").foregroundStyle(Brand.textMuted) }
                                Text(Fmt.size(app.size)).font(.system(size: 12)).monospacedDigit()
                            }.padding(.horizontal, 16).frame(height: 62).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }.background(inspectorVisible && inspected?.id == app.id ? Brand.surfaceSubtle : Color.clear)
                } } } }
            }
        } detail: {
            if let app = inspected {
                WorkspaceHeading(title: app.name, subtitle: app.version, icon: "app", value: Fmt.size(app.size))
                Text(app.url.path).font(.system(size: 11)).foregroundStyle(Brand.textMuted).textSelection(.enabled)
                WorkspaceDetail(title: "Removal", text: app.isRemovable ? "Only the application bundle is moved to Trash. Running apps must close before removal." : "This application is protected from removal.")
                WorkspaceDetail(title: "Kept on this Mac", text: "\(Fmt.size(app.componentsSize)) of associated data. Documents, settings, support data, saved sessions and credentials remain in place.")
                WorkspaceDetail(title: "Last opened", text: app.lastOpened.map { Fmt.relative($0) } ?? "Not reported by macOS; this does not prove the app is unused.")
                Button("Show application") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }.buttonStyle(ControlPanelButtonStyle()).disabled(preview)
            }
        } actions: {
            Text(result.isEmpty ? "\(selected.count) selected · \(Fmt.size(selected.reduce(0) { $0 + $1.size }))" : result).lineLimit(2)
            Spacer()
            if busy { ProgressView().controlSize(.small) }
            Button("Clear selection") { for app in selected { toggle(app) } }.buttonStyle(ControlPanelButtonStyle()).disabled(selected.isEmpty || busy)
            Button("Review removal…") { plan = selected; confirm = true }.buttonStyle(ControlPanelButtonStyle(primary: true)).disabled(selected.isEmpty || preview || busy || store.isUninstalling || store.isScanning)
        }.task { if !preview { store.scanIfNeeded() } }
        .sheet(isPresented: $confirm) { WorkspaceConfirmation(title: "Remove \(plan.count) applications?", explanation: "Move these application bundles to Trash. Cairn may ask running applications to quit; applications that remain open are skipped. Associated data is retained.", entries: plan.map { $0.url.path }, actionTitle: "Move to Trash") {
            busy = true
            Task { let outcome = await store.uninstall(plan); resultHasFailures = outcome.failed > 0 || !outcome.errors.isEmpty; result = "\(outcome.trashedApps) removed · \(outcome.failed) skipped" + (outcome.errors.first.map { " · \($0)" } ?? ""); busy = false }
        } }
    }
    private func toggle(_ app: AppEntry) { if preview { if let i = samples.firstIndex(where: { $0.id == app.id }) { samples[i].selected.toggle() } } else { store.toggle(app.id) } }
    private static func sampleApps() -> [AppEntry] {
        [("Xcode", "com.apple.dt.Xcode", 8.2), ("Google Chrome", "com.google.Chrome", 0.7), ("Visual Studio Code", "com.microsoft.VSCode", 0.5), ("Codex", "com.openai.codex", 0.4)].map { name, id, size in AppEntry(name: name, developer: id, bundleID: id, version: "Sample application", url: URL(fileURLWithPath: "/Applications/\(name).app"), size: Int64(size * 1e9), supportSize: 2_000_000_000, leftoverSize: 0, associated: [], lastOpened: Date(), isApple: id.hasPrefix("com.apple"), isIntel: false, isSystem: false) }
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
    @State private var samples = sampleGroups()
    private let preview = CommandLine.arguments.contains("--preview-ui")
    private var groups: [DupGroup] { (preview ? samples : store.visibleGroups).filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.files.contains { $0.url.path.localizedCaseInsensitiveContains(search) } } }
    private var inspected: DupGroup? { groups.first { $0.id == focused } ?? groups.first }
    var body: some View {
        CairnWorkspace(title: "Files  ›  Duplicates", subtitle: "\(groups.count) groups", inspectorVisible: inspectorVisible) {
            VStack(spacing: 0) {
                WorkspaceColumns(leading: "Identical files", trailing: "Extra copies")
                if store.isRemoving { CairnStateView(kind: .scanning, title: "Verifying and removing extra copies", message: "Keepers remain in place. Each file is checked again before removal.", compact: true) }
                else if !message.isEmpty { CairnStateView(kind: resultHasFailures ? .attention : .completed, title: resultHasFailures ? "Finished with skipped copies" : "Duplicate cleanup finished", message: message + ". Items in Trash still occupy disk space.", compact: true) }
                if store.isScanning { CairnStateView(kind: .scanning, title: "Comparing file contents", message: store.progressText, compact: true) }
                else if store.phase == .cancelled { CairnStateView(kind: .interrupted, title: "Comparison stopped", message: "Results may be incomplete. Rescan before choosing extra copies.", compact: true) }
                else if store.wasLimited { CairnStateView(kind: .attention, title: "Partial comparison", message: store.progressText, compact: true) }
                if groups.isEmpty && !store.isScanning && store.phase != .cancelled { WorkspaceEmpty(title: search.isEmpty ? "No duplicate groups" : "No matching duplicate groups", message: !search.isEmpty ? "Try another search to see your measured groups." : store.hasScanned ? "No identical-file groups were found in the locations checked." : "Scan Documents, Downloads, Desktop, Pictures and Movies for identical files.", icon: "doc.on.doc") }
                else { ScrollView { LazyVStack(spacing: 0) {
                    ForEach(groups) { group in
                        WorkspaceRow(title: group.name, subtitle: "\(group.count) identical copies", icon: expanded.contains(group.id) ? "folder.open" : "folder", value: Fmt.size(group.reclaimableSize), focused: inspectorVisible && inspected?.id == group.id) { focused = group.id; inspectorVisible = true; expanded.formSymmetricDifference([group.id]) }
                        if expanded.contains(group.id) { ForEach(group.files) { file in
                            HStack(spacing: 10) {
                                Button { store.toggle(file.id) } label: { Image(systemName: file.isKeeper ? "lock.shield" : file.selected ? "checkmark.square.fill" : "square") }.buttonStyle(.plain).disabled(file.isKeeper || preview || store.isRemoving)
                                Text(file.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                if file.isKeeper { Text("Keep").font(.system(size: 10.5)).foregroundStyle(Brand.blue) }
                                else { Button("Keep this") { store.setKeeper(file.id, in: group.id) }.font(.system(size: 10.5)).disabled(preview || store.isRemoving) }
                            }.padding(.leading, 32).padding(.trailing, 18).frame(height: 40).background(Brand.deepPanel.opacity(0.6))
                        } }
                    }
                    if !preview && store.hasMoreGroups { Button("Show more groups") { store.showMoreGroups() }.padding(16) }
                } } }
            }
        } detail: {
            if let group = inspected {
                WorkspaceHeading(title: group.name, subtitle: "Identical content", icon: "doc.on.doc", value: Fmt.size(group.reclaimableSize))
                WorkspaceDetail(title: "One copy stays", text: group.keeper?.url.path ?? "Choose a copy to keep before removal.")
                WorkspaceDetail(title: "Verified again before removal", text: "Cairn compares full SHA-256 file hashes and checks that the keeper and selected files have not changed. Matching names alone are insufficient.")
                WorkspaceDetail(title: "After removal", text: "Selected extra copies go to Trash. The keeper stays at its existing path. A copy elsewhere is not necessarily a backup.")
                if let url = group.representativeURL { Button("Show keeper") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.buttonStyle(ControlPanelButtonStyle()).disabled(preview) }
            } else { WorkspaceHeading(title: "Keep the right copy", subtitle: "Duplicates", icon: "doc.on.doc"); WorkspaceDetail(title: "Review paths", text: "Files with the same content can serve different projects. Choose intentionally before removing a copy.") }
        } actions: {
            Text(message.isEmpty ? "\(store.selectedCopyCount) copies selected · \(Fmt.size(store.selectedBytes))" : message).lineLimit(2)
            Spacer()
            Button("Select extras") { store.autoSelectRecommended() }.buttonStyle(ControlPanelButtonStyle()).disabled(preview || store.isScanning || store.isRemoving)
            Button("Clear") { store.clearSelection() }.buttonStyle(ControlPanelButtonStyle()).disabled(preview || store.isRemoving)
            Button("Review removal…") { confirm = true }.buttonStyle(ControlPanelButtonStyle(primary: true)).disabled(preview || store.selectedCopyCount == 0 || store.isRemoving || store.isScanning)
        }.task { if !preview { store.startIfNeeded() } }
        .sheet(isPresented: $confirm) { WorkspaceConfirmation(title: "Remove selected extra copies?", explanation: "Keepers stay in place. Cairn verifies content again, then moves only selected extra copies to Trash.", entries: store.groups.flatMap(\.files).filter(\.selected).map { $0.url.path }, actionTitle: "Verify & move to Trash") { Task { let result = await store.removeSelected(); resultHasFailures = result.failed > 0 || !result.errors.isEmpty; message = "\(result.trashed) moved · \(result.failed) skipped" + (result.errors.first.map { " · \($0)" } ?? "") } } }
    }
    private static func sampleGroups() -> [DupGroup] {
        ["Design archive.zip", "Product walkthrough.mov", "Research notes.pdf"].enumerated().map { n, name in
            let size = Int64(3 - n) * 240_000_000
            return DupGroup(name: name, hash: "preview", files: ["Documents", "Downloads"].enumerated().map { i, folder in let url = FileScan.home.appendingPathComponent("\(folder)/\(name)"); return DupFile(url: url, resolvedURL: url, size: size, modified: Date(), isKeeper: i == 0) })
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
    var body: some View {
        CairnWorkspace(title: "Health checks", subtitle: store.isScanning ? "Checking…" : "\(issues.count) findings", inspectorVisible: inspectorVisible) {
            VStack(spacing: 0) {
                WorkspaceColumns(leading: "Finding", trailing: "Action")
                if store.isFixing { CairnStateView(kind: .scanning, title: "Applying reviewed changes", message: "Only the reviewed locations are affected.", compact: true) }
                else if let result = store.lastResult { CairnStateView(kind: result.failed == 0 ? .completed : .attention, title: result.failed == 0 ? "Reviewed changes finished" : "Finished with skipped findings", message: "\(result.trashed) moved · \(result.failed) skipped. " + result.errors.joined(separator: "\n"), compact: true) }
                if store.isScanning { CairnStateView(kind: .scanning, title: "Checking this Mac", message: store.progressText, compact: true) }
                else if store.wasCancelled { CairnStateView(kind: .interrupted, title: "Checks stopped", message: "Earlier findings may still be shown. Rescan to complete the checks.", compact: true) }
                if issues.isEmpty && !store.isScanning && !store.wasCancelled { WorkspaceEmpty(title: !search.isEmpty ? "No matching findings" : store.hasScanned ? "No findings in these checks" : "Ready to check", message: !search.isEmpty ? "Try another search to see your findings." : "Checks cover launch agents, application data, login items, preferences and permissions.", icon: "heart.text.square") }
                else { ScrollView { LazyVStack(spacing: 0) { ForEach(issues) { issue in WorkspaceRow(title: issue.title, subtitle: issue.detail, icon: issue.fixable ? "clock" : "info.circle", status: issue.fixable ? "Review" : "Advice only", focused: inspectorVisible && inspected?.id == issue.id) { focused = issue.id; inspectorVisible = true } } } } }
            }
        } detail: {
            if let issue = inspected {
                WorkspaceHeading(title: issue.title, subtitle: "Health finding", icon: "heart.text.square")
                WorkspaceDetail(title: "Evidence", text: issue.detail)
                WorkspaceDetail(title: "Action", text: issue.fixable ? "Review the obsolete launch-agent file before moving it to Trash. This does not unload a currently running service." : "Inspection only. Cairn does not remove this data or change permissions.")
                if let url = issue.url { WorkspaceDetail(title: "Location", text: url.path); Button("Show location") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.buttonStyle(ControlPanelButtonStyle()).disabled(preview) }
            }
            WorkspaceDetail(title: "Scope", text: "These are focused filesystem checks, not a malware scan or a guarantee of overall Mac health.")
        } actions: {
            if let result = store.lastResult { Text("\(result.trashed) moved · \(result.failed) skipped").lineLimit(1) } else { Text("Changes always require review").foregroundStyle(Brand.textMuted) }
            Spacer()
            Button("Review selected finding…") { if let issue = inspected { plan = [issue]; confirm = true } }.buttonStyle(ControlPanelButtonStyle(primary: true)).disabled(preview || inspected?.fixable != true || fixing || store.isFixing || store.isScanning)
        }.task { if !preview { store.scanIfNeeded() } }
        .sheet(isPresented: $confirm) { WorkspaceConfirmation(title: "Move this finding to Trash?", explanation: "Only the listed file is affected. Inspect its contents and make sure it is no longer needed.", entries: plan.compactMap { $0.url?.path }, actionTitle: "Move to Trash") { fixing = true; Task { await store.fix(items: plan); fixing = false } } }
    }
}
