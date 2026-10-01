import SwiftUI
import AppKit

struct AppsWorkspace: View {
    let store: AppInventoryStore
    var search: String
    @Binding var inspectorVisible: Bool
    @State private var focused: UUID?
    @State private var filter = "All apps"
    @State private var viewMode = "Installed apps"
    @State private var sort = "Size"
    @State private var localSearch = ""
    @State private var confirm = false
    @State private var busy = false
    @State private var result = ""
    @State private var resultHasFailures = false
    @State private var receipt: (changes: [CleanupCapacityChange], bytes: Int64, recoveries: Int)?
    @State private var plan: [AppEntry] = []
    @State private var samples = sampleApps()
    private let preview = CommandLine.arguments.contains("--preview-ui")
    private var apps: [AppEntry] { (preview ? samples : store.apps).filter { app in
        (search.isEmpty || (app.name + app.bundleID).localizedCaseInsensitiveContains(search))
        && (localSearch.isEmpty || (app.name + app.bundleID).localizedCaseInsensitiveContains(localSearch))
        && (filter != "Unused" || app.isUnused) && (filter != "Large" || app.isLarge)
        && (filter != "Removable" || app.isRemovable)
    }.sorted {
        if sort == "Name" { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return (viewMode == "Related data" ? $0.componentsSize : $0.size) >
            (viewMode == "Related data" ? $1.componentsSize : $1.size)
    } }
    private var selected: [AppEntry] { (preview ? samples : store.apps).filter { $0.selected && $0.isRemovable } }
    private var inspected: AppEntry? { apps.first { $0.id == focused } ?? apps.first }
    var body: some View {
        CairnWorkspace(title: "Apps", subtitle: "See the space used by applications and their related data", inspectorVisible: inspectorVisible, headerTrailingInset: 150) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    CairnSegmentedControl(label: "View", selection: $viewMode, options: [("Installed apps", "Installed apps"), ("Related data", "Related data")]).frame(width: 230, height: 32)
                    Spacer(minLength: 6)
                    TextField("Search apps", text: $localSearch).textFieldStyle(.roundedBorder)
                        .frame(minWidth: 120, maxWidth: 210)
                }.padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 11)
                HStack(spacing: 12) {
                    Picker("Show", selection: $filter) {
                        ForEach(["All apps", "Unused", "Large", "Removable"], id: \.self) { Text($0) }
                    }.cairnFilterSurface().frame(width: 145)
                    Spacer()
                    Picker("Sort by", selection: $sort) {
                        Text("Size").tag("Size")
                        Text("Name").tag("Name")
                    }.cairnFilterSurface().frame(width: 130)
                }.font(.system(size: 11)).padding(.horizontal, 18).padding(.bottom, 10)
                HStack(spacing: 8) {
                    Text("App").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Application").frame(width: 72, alignment: .trailing)
                    Text("Related data").frame(width: 78, alignment: .trailing)
                    Text("Total").frame(width: 64, alignment: .trailing)
                }.font(.system(size: 10.5, weight: .medium)).foregroundStyle(Brand.textMuted)
                    .padding(.leading, 46).padding(.trailing, 16).frame(height: 35)
                    .overlay(Rectangle().fill(Brand.separator).frame(height: 0.5), alignment: .bottom)
                if !result.isEmpty { CairnStateView(kind: resultHasFailures ? .attention : .completed, title: resultHasFailures ? "Finished with skipped applications" : "Application removal finished", message: result + ". Associated data was kept.", compact: true) }
                if let receipt { CapacityReceiptView(changes: receipt.changes, estimatedBytes: receipt.bytes, recoveryCount: receipt.recoveries) }
                if busy { CairnStateView(kind: .scanning, title: "Removing reviewed applications", message: "Associated data stays in place. Results will appear here.", compact: true) }
                if store.isScanning { CairnStateView(kind: .scanning, title: "Reading applications", message: store.progress, compact: true) }
                else if store.wasCancelled { CairnStateView(kind: .interrupted, title: "Scan stopped", message: "Previous results may still be shown. Rescan to refresh them.", compact: true) }
                if apps.isEmpty && !store.isScanning && !store.wasCancelled { WorkspaceEmpty(title: "No matching applications", message: !search.isEmpty || !localSearch.isEmpty || filter != "All apps" ? "Try another search or choose All apps." : "Rescan to measure installed applications.") }
                else { ScrollView { LazyVStack(spacing: 0) { ForEach(apps) { app in
                    HStack(spacing: 0) {
                        Button { toggle(app) } label: {
                            Image(systemName: !app.isRemovable ? "lock" : app.selected ? "checkmark.square.fill" : "square")
                                .font(.system(size: 14)).foregroundStyle(app.selected ? Brand.blue : Brand.textMuted)
                        }.buttonStyle(.plain).disabled(!app.isRemovable || busy || viewMode == "Related data")
                            .frame(width: 38).accessibilityLabel(app.isRemovable ? "Select \(app.name) bundle" : "\(app.name) is protected")
                        Button { focused = app.id; inspectorVisible = true } label: {
                            HStack(spacing: 8) {
                                FileIcon(url: app.url, size: 30)
                                Text(app.name).font(.system(size: 12.5, weight: .medium))
                                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                Text(Fmt.size(app.size)).frame(width: 72, alignment: .trailing)
                                Text(Fmt.size(app.componentsSize)).frame(width: 78, alignment: .trailing)
                                Text(Fmt.size(app.size + app.componentsSize))
                                    .foregroundStyle(Brand.textPrimary).frame(width: 64, alignment: .trailing)
                            }.font(.system(size: 11.5)).monospacedDigit()
                                .foregroundStyle(Brand.textSecondary)
                                .padding(.trailing, 16).frame(height: 61).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }.background(inspectorVisible && inspected?.id == app.id ? Color.white.opacity(0.045) : Color.clear)
                        .overlay(Rectangle().fill(Brand.separator).frame(height: 0.5), alignment: .bottom)
                } } } }
                Text("Application and related-data sizes are separate estimates. Removing an app bundle keeps its related data.")
                    .font(.system(size: 10.5)).foregroundStyle(Brand.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18).padding(.vertical, 9)
            }
        } detail: {
            if let app = inspected {
                VStack(spacing: 7) {
                    FileIcon(url: app.url, size: 58)
                    Text(app.name).font(.system(size: 16, weight: .semibold))
                    Text(app.developer).font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                }.frame(maxWidth: .infinity).padding(.vertical, 8)
                WorkspaceDetail(title: "Application bundle", text: Fmt.size(app.size))
                WorkspaceDetail(title: "Related data retained", text: Fmt.size(app.componentsSize))
                WorkspaceDetail(title: "Combined estimate", text: Fmt.size(app.size + app.componentsSize))
                Text(app.url.path).font(.system(size: 11)).foregroundStyle(Brand.textMuted).textSelection(.enabled)
                WorkspaceDetail(title: "Removal", text: app.isRemovable ? "Only the application bundle is moved to Trash. Running apps must close before removal." : "This application is protected from removal.")
                WorkspaceDetail(title: "Kept on this Mac", text: "\(Fmt.size(app.componentsSize)) of associated data. Documents, settings, support data, saved sessions and credentials remain in place.")
                if !app.associated.isEmpty {
                    DisclosureGroup("Related locations · \(app.associated.count)") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(app.associated.prefix(8), id: \.self) { path in
                                Text(path.path).font(.system(size: 10.5)).foregroundStyle(Brand.textMuted)
                                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            }
                            if app.associated.count > 8 {
                                Text("\(app.associated.count - 8) more locations")
                                    .font(.system(size: 10.5)).foregroundStyle(Brand.textMuted)
                            }
                        }.padding(.top, 8)
                    }.font(.system(size: 11.5)).foregroundStyle(Brand.textSecondary)
                }
                WorkspaceDetail(title: "Last opened", text: app.lastOpened.map { Fmt.relative($0) } ?? "Not reported by macOS; this does not prove the app is unused.")
                Button("Show application") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }.buttonStyle(ControlPanelButtonStyle()).disabled(preview)
            }
        } actions: {
            Text(result.isEmpty ? "\(selected.count) selected · \(Fmt.size(selected.reduce(0) { $0 + $1.size }))" : result).lineLimit(2)
            Spacer()
            if busy { ProgressView().controlSize(.small) }
            Button("Clear selection") { for app in selected { toggle(app) } }.buttonStyle(ControlPanelButtonStyle()).disabled(selected.isEmpty || busy)
            Button("Review removal…") { plan = selected; confirm = true }.buttonStyle(ControlPanelButtonStyle(primary: true)).disabled(selected.isEmpty || preview || busy || store.isUninstalling || store.isScanning)
        }
        .sheet(isPresented: $confirm) { WorkspaceConfirmation(title: "Remove \(plan.count) applications?", explanation: "Move these application bundles to Trash. Close running applications first; applications that remain open are skipped. Associated data is retained.", entries: plan.map { $0.url.path }, actionTitle: "Move to Trash") {
            busy = true
            Task { let outcome = await store.uninstall(plan); receipt = (outcome.capacityChanges, outcome.bytes, outcome.recordedRecoveries); resultHasFailures = outcome.failed > 0 || !outcome.errors.isEmpty; result = "\(outcome.trashedApps) removed · \(outcome.failed) skipped" + (outcome.errors.first.map { " · \($0)" } ?? ""); busy = false }
        } }
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
    var body: some View {
        CairnWorkspace(title: "Duplicates", subtitle: "Review matching files before choosing what to keep", inspectorVisible: inspectorVisible, headerTrailingInset: 150) {
            VStack(spacing: 0) {
                HStack {
                    Text(preview ? "\(groups.count) sample group\(groups.count == 1 ? "" : "s")" : "\(groups.count) verified content group\(groups.count == 1 ? "" : "s")")
                        .font(.system(size: 11.5)).foregroundStyle(Brand.textSecondary)
                    Spacer()
                    Text("Extra file size · not space freed")
                        .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                }.padding(.horizontal, 18).padding(.bottom, 12)
                    .overlay(Rectangle().fill(Brand.separator).frame(height: 0.5), alignment: .bottom)
                if store.isRemoving { CairnStateView(kind: .scanning, title: "Verifying and removing extra copies", message: "Keepers remain in place. Each file is checked again before removal.", compact: true) }
                else if !message.isEmpty { CairnStateView(kind: resultHasFailures ? .attention : .completed, title: resultHasFailures ? "Finished with skipped copies" : "Duplicate cleanup finished", message: message + ". Items in Trash still occupy disk space.", compact: true) }
                if let receipt { CapacityReceiptView(changes: receipt.changes, estimatedBytes: receipt.bytes, recoveryCount: receipt.recoveries) }
                if store.isScanning { CairnStateView(kind: .scanning, title: "Comparing file contents", message: store.progressText, compact: true) }
                else if store.phase == .cancelled { CairnStateView(kind: .interrupted, title: "Comparison stopped", message: "Results may be incomplete. Rescan before choosing extra copies.", compact: true) }
                else if store.wasLimited { CairnStateView(kind: .attention, title: "Partial comparison", message: store.progressText, compact: true) }
                if groups.isEmpty && !store.isScanning && store.phase != .cancelled { WorkspaceEmpty(title: search.isEmpty ? "No duplicate groups" : "No matching duplicate groups", message: !search.isEmpty ? "Try another search to see your measured groups." : store.hasScanned ? "No identical-file groups were found in the locations checked." : "Scan Documents, Downloads, Desktop, Pictures and Movies for identical files.", icon: "doc.on.doc") }
                else { ScrollView { LazyVStack(spacing: 0) {
                    ForEach(groups) { group in
                        Button {
                            focused = group.id; inspectorVisible = true
                            expanded.formSymmetricDifference([group.id])
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .rotationEffect(.degrees(expanded.contains(group.id) ? 90 : 0))
                                    .foregroundStyle(Brand.textMuted).frame(width: 14)
                                if let url = group.representativeURL { FileIcon(url: url, size: 34) }
                                else { Image(systemName: "doc.on.doc").frame(width: 34) }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(group.name).font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Brand.textPrimary).lineLimit(1)
                                    Text("\(group.count) matching copies · \(Fmt.size(group.copySize)) each")
                                        .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Text(Fmt.size(group.reclaimableSize))
                                    .font(.system(size: 11.5)).monospacedDigit()
                                    .foregroundStyle(Brand.textSecondary)
                                    .help("Combined file sizes of extra copies. Moving them to Trash does not free space; copies may also share disk blocks.")
                                Image(systemName: "chevron.right").font(.system(size: 9))
                                    .foregroundStyle(Brand.textMuted)
                            }.padding(.horizontal, 17).frame(height: 72).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .background(inspectorVisible && inspected?.id == group.id ? Color.white.opacity(0.045) : Color.clear)
                            .overlay(Rectangle().fill(Brand.separator).frame(height: 0.5), alignment: .bottom)
                        if expanded.contains(group.id) { ForEach(group.files) { file in
                            HStack(spacing: 10) {
                                Button { store.toggle(file.id) } label: {
                                    Image(systemName: file.isKeeper ? "lock.shield" : file.selected ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(file.selected ? Brand.blue : Brand.textMuted)
                                }.buttonStyle(.plain).disabled(file.isKeeper || preview || store.isRemoving)
                                    .accessibilityLabel(file.isKeeper ? "Keeper: \(file.url.path)" : "Select extra copy \(file.url.path)")
                                FileIcon(url: file.url, size: 27)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(file.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                        .font(.system(size: 11)).foregroundStyle(Brand.textPrimary)
                                        .lineLimit(1).truncationMode(.middle)
                                    Text("\(Fmt.size(file.size)) · Modified \(file.modified.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.system(size: 10)).foregroundStyle(Brand.textMuted)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                if file.isKeeper {
                                    Text("KEEP").font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(Brand.blue)
                                } else {
                                    Button("Keep this") { store.setKeeper(file.id, in: group.id) }
                                        .font(.system(size: 10)).disabled(preview || store.isRemoving)
                                }
                                Button { NSWorkspace.shared.activateFileViewerSelecting([file.url]) } label: {
                                    Image(systemName: "folder").font(.system(size: 11))
                                }.buttonStyle(.plain).help("Show in Finder").disabled(preview)
                            }.padding(.leading, 34).padding(.trailing, 18).frame(height: 63)
                                .background(Brand.deepPanel.opacity(0.35))
                                .overlay(Rectangle().fill(Brand.separator).frame(height: 0.5), alignment: .bottom)
                        } }
                    }
                    if !preview && store.hasMoreGroups { Button("Show more groups") { store.showMoreGroups() }.padding(16) }
                } } }
            }
        } detail: {
            if let group = inspected {
                VStack(spacing: 8) {
                    if let url = group.representativeURL { FileIcon(url: url, size: 58) }
                    Text(group.name).font(.system(size: 15, weight: .semibold))
                        .multilineTextAlignment(.center)
                    Text("\(group.count) matching copies · \(Fmt.size(group.copySize)) each")
                        .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                }.frame(maxWidth: .infinity).padding(.vertical, 6)
                WorkspaceDetail(title: "Exact content match", text: preview ? "Sample group for interface preview." : "Full SHA-256 contents matched at the time of comparison. Cairn checks them again before moving anything.")
                ForEach(group.files.indices, id: \.self) { index in
                    let file = group.files[index]
                    WorkspaceDetail(title: "Location \(index + 1)\(file.isKeeper ? " · keeper" : "")", text: "\(file.url.path)\n\(Fmt.size(file.size)) · Modified \(file.modified.formatted(date: .abbreviated, time: .shortened))")
                }
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
        }
        .sheet(isPresented: $confirm) { WorkspaceConfirmation(title: "Remove selected extra copies?", explanation: "Keepers stay in place. Cairn verifies content again, then moves only selected extra copies to Trash.", entries: store.groups.flatMap(\.files).filter(\.selected).map { $0.url.path }, actionTitle: "Verify & move to Trash") { Task { let result = await store.removeSelected(); receipt = (result.capacityChanges, result.bytes, result.recordedRecoveries); resultHasFailures = result.failed > 0 || !result.errors.isEmpty; message = "\(result.trashed) moved · \(result.failed) skipped" + (result.errors.first.map { " · \($0)" } ?? "") } } }
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
    private var available: Int64? { preview ? PreviewStorageScenario.availableBytes : StorageControl.shared.currentAvailable }
    private var reserve: Int64? {
        preview ? PreviewStorageScenario.reserveBytes : AppSettings.shared.reserveEnabled ? StorageControl.shared.reserveBytes : nil
    }
    var body: some View {
        CairnWorkspace(title: "Health", subtitle: "What needs attention, and what Cairn has checked", inspectorVisible: inspectorVisible, headerTrailingInset: 150) {
            VStack(spacing: 0) {
                healthOverview
                WorkspaceColumns(leading: "Finding", trailing: "Action")
                if store.isFixing { CairnStateView(kind: .scanning, title: "Applying reviewed changes", message: "Only the reviewed locations are affected.", compact: true) }
                else if let result = store.lastResult { CairnStateView(kind: result.failed == 0 ? .completed : .attention, title: result.failed == 0 ? "Reviewed changes finished" : "Finished with skipped findings", message: "\(result.trashed) moved · \(result.failed) skipped. " + result.errors.joined(separator: "\n"), compact: true) }
                if let result = store.lastResult { CapacityReceiptView(changes: result.capacityChanges, estimatedBytes: result.bytes, recoveryCount: result.recordedRecoveries) }
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
        }
        .sheet(isPresented: $confirm) { WorkspaceConfirmation(title: "Move this finding to Trash?", explanation: "Only the listed file is affected. Inspect its contents and make sure it is no longer needed.", entries: plan.compactMap { $0.url?.path }, actionTitle: "Move to Trash") { fixing = true; Task { await store.fix(items: plan); fixing = false } } }
    }
    private var healthOverview: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("AVAILABLE SPACE").font(.system(size: 10.5, weight: .medium))
                .tracking(0.7).foregroundStyle(Brand.textMuted)
            if let available {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Fmt.size(available)).font(.system(size: 32, weight: .regular))
                        .monospacedDigit().foregroundStyle(Brand.textPrimary)
                    Text("available").font(.system(size: 13)).foregroundStyle(Brand.textSecondary)
                }.padding(.top, 6)
                if let reserve {
                    let difference = available - reserve
                    Label(difference >= 0 ? "\(Fmt.size(difference)) above your \(Fmt.size(reserve)) reserve" : "\(Fmt.size(-difference)) below your \(Fmt.size(reserve)) reserve",
                          systemImage: difference >= 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(difference >= 0 ? Brand.safeCyan : Brand.amber)
                        .padding(.top, 5)
                } else {
                    Text("Reserve alerts are off. Set a reserve in Settings to track a threshold.")
                        .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                        .padding(.top, 5)
                }
            } else {
                Text("No current capacity reading")
                    .font(.system(size: 17)).foregroundStyle(Brand.textSecondary)
                    .padding(.top, 7)
            }
            if preview {
                Text("Sample capacity · interface preview")
                    .font(.system(size: 10.5)).foregroundStyle(Brand.textMuted).padding(.top, 8)
            } else if let date = StorageControl.shared.current?.date {
                Text("Observed \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 10.5)).foregroundStyle(Brand.textMuted).padding(.top, 8)
            }
            Rectangle().fill(Brand.separator).frame(height: 0.5).padding(.vertical, 17)
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: issues.isEmpty ? "checkmark.shield" : "waveform.path.ecg")
                    .font(.system(size: 19, weight: .light)).foregroundStyle(Brand.textSecondary)
                    .frame(width: 23)
                VStack(alignment: .leading, spacing: 4) {
                    Text(issues.isEmpty ? (preview || store.hasScanned ? "No findings in the checks completed" : "Health checks have not run yet") : "\(issues.count) finding\(issues.count == 1 ? "" : "s") to review")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.textPrimary)
                    Text(store.isScanning ? "Checks are still running." : "Cairn checks specific locations; this is not a complete Mac health or security assessment.")
                        .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Rectangle().fill(Brand.separator).frame(height: 0.5).padding(.vertical, 17)
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 19, weight: .light)).foregroundStyle(Brand.textSecondary)
                    .frame(width: 23)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Protected during cleanup")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.textPrimary)
                    Text("Known session history, repositories, credentials and recovery data are excluded by the cleanup guard.")
                        .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let last = store.lastScanAt, !preview {
                Text("Last health check \(last.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 10.5)).foregroundStyle(Brand.textMuted)
                    .padding(.top, 14)
            }
        }
        .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
