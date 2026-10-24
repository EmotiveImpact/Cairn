import SwiftUI
import AppKit

/// Developers think in projects, not folders. This groups the existing
/// build-output findings by repository and shows how long each has been idle,
/// with git's view of work that is not committed or pushed. Putting a project
/// to sleep selects its rebuildable output and keeps a note of how to bring it
/// back. Selection flows into the shared ReviewSheet; nothing is removed from here.
struct ProjectsWorkspace: View {
    let store: ScanStore
    var search: String = ""
    @Binding var inspectorVisible: Bool
    var onReview: () -> Void

    @State private var projects: [ProjectSummary] = []
    @State private var indexing = false
    @State private var expanded: Set<String> = []
    @State private var git: [String: GitStatus] = [:]
    @State private var sleeping: [SleepingProject] = []
    @State private var copied: String?
    private let preview = CommandLine.arguments.contains("--preview-ui")

    /// A project counts as idle after a month without commits or manifest changes.
    private static let idleDays = 30

    private var bucketItems: [ScanItem] {
        store.buckets.first { $0.id == ProjectIndex.categoryID }?.items ?? []
    }

    /// Changes whenever the set of measured artifacts changes, not on selection.
    private var indexKey: String {
        let items = bucketItems
        return "\(items.count)-\(items.reduce(Int64(0)) { $0 + $1.allocatedSize })-\(store.isScanning)"
    }

    private var visible: [ProjectSummary] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return projects.filter { query.isEmpty || $0.name.lowercased().contains(query) || $0.url.path.lowercased().contains(query) }
            .sorted { $0.rebuildableBytes > $1.rebuildableBytes }
    }
    private var idle: [ProjectSummary] {
        projects.filter { ($0.idleDays() ?? 0) >= Self.idleDays && !$0.rebuildable.isEmpty }
    }
    private var idleBytes: Int64 { idle.flatMap(\.rebuildable).reduce(0) { $0 + $1.allocatedSize } }
    private var asleep: [SleepingProject] { sleeping.filter { ProjectSleep.isAsleep($0) } }
    private var selectedProjectBytes: Int64 {
        let selected = Set(store.selectedItems().map(\.id))
        return projects.flatMap(\.rebuildable).filter { selected.contains($0.id) }.reduce(0) { $0 + $1.allocatedSize }
    }
    /// True once the person has picked something here. Safe caches start ticked
    /// (they make up Home's number), so those alone don't count as a choice.
    private var pickedInProjects: Bool {
        let selected = Set(store.selectedItems().map(\.id))
        return projects.flatMap(\.rebuildable).contains { selected.contains($0.id) && !CLI.isReady($0) }
    }
    private var totalBytes: Int64 { projects.reduce(Int64(0)) { $0 + $1.rebuildableBytes } }
    private var largestBytes: Int64 { max(1, projects.map(\.rebuildableBytes).max() ?? 1) }

    /// The folder most projects share, shown in the eyebrow ("Projects · ~/Developer").
    private var commonRoot: String {
        let parents = projects.map { $0.url.deletingLastPathComponent().path }
        guard let top = Dictionary(grouping: parents, by: { $0 }).max(by: { $0.value.count < $1.value.count })?.key else { return "" }
        return displayPath(URL(fileURLWithPath: top))
    }

    var body: some View {
        NightPage(eyebrow: projects.isEmpty || commonRoot.isEmpty ? "Projects" : "Projects · \(commonRoot)",
                  title: totalBytes > 0 ? "\(Fmt.size(totalBytes)) of build output" : "Projects",
                  subtitle: projects.isEmpty
                      ? "Your coding projects, how long since you worked on them, and what can be rebuilt."
                      : "Across \(projects.count) coding project\(projects.count == 1 ? "" : "s"). Your source code is never touched.") {
            Button { if store.isScanning { store.cancel() } else { store.rescan() } } label: {
                Label(store.isScanning ? "Stop scan" : "Rescan", systemImage: store.isScanning ? "stop.circle" : "arrow.clockwise")
            }
            .buttonStyle(ControlPanelButtonStyle(size: .small))
            .disabled(store.isCleaning)
        } content: {
            list
        } footer: {
            if pickedInProjects {
                // The button frees exactly what this footer counts, nothing picked elsewhere.
                NightTotal(strong: Fmt.size(selectedProjectBytes), rest: "selected from projects")
                Spacer()
                Button("Select none") { clearProjects() }.buttonStyle(ControlPanelButtonStyle(size: .large))
                Button("Review and free \(Fmt.size(selectedProjectBytes))") { keepOnlyProjects(); onReview() }
                    .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
                    .disabled(store.isCleaning || store.isScanning)
            } else {
                NightTotal(strong: Fmt.size(idleBytes), rest: "in projects idle for \(Self.idleDays)+ days")
                Spacer()
                Button("Put idle projects to sleep") { putToSleep(idle) }
                    .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
                    .disabled(idle.isEmpty || store.isCleaning || store.isScanning)
                    .help("Selects rebuildable output in projects untouched for \(Self.idleDays) days or more, keeps a note of how to rebuild it, then shows it for review")
            }
        }
        .task(id: indexKey) { await reindex() }
    }

    // MARK: - Sleep

    /// Selects the projects' rebuildable output, notes how to bring it back,
    /// and opens the normal review. The note only counts once the clean has run.
    private func putToSleep(_ chosen: [ProjectSummary]) {
        let wanted = chosen.filter { !$0.rebuildable.isEmpty }
        guard !wanted.isEmpty else { return }
        if !preview {
            let notes = ProjectSleep.merge(wanted.map { ProjectSleep.note(for: $0) }, into: ProjectSleep.load())
            ProjectSleep.save(notes)
            sleeping = notes
        }
        selectIdle(wanted)
        keepOnlyProjects()
        onReview()
    }

    private func forget(_ note: SleepingProject) {
        sleeping.removeAll { $0.path == note.path }
        ProjectSleep.save(ProjectSleep.load().filter { $0.path != note.path })
    }

    @ViewBuilder private var asleepSection: some View {
        if !asleep.isEmpty {
            Text("Asleep").nightEyebrow().padding(.top, 22).padding(.bottom, 8)
            ForEach(asleep) { note in sleepingRow(note) }
        }
    }

    private func sleepingRow(_ note: SleepingProject) -> some View {
        HStack(spacing: 14) {
            NightName(logo: BrandLogo(name: nil, fallback: "moon.zzz", size: 25),
                      title: note.name, subtitle: displayPath(URL(fileURLWithPath: note.path)))
            Text(Fmt.size(note.bytes)).font(.system(size: 13, weight: .medium)).monospacedDigit()
                .frame(width: 90, alignment: .trailing)
            Text("Asleep since " + note.asleepSince.formatted(.dateTime.day().month(.abbreviated)))
                .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                .lineLimit(1).frame(width: 140, alignment: .leading)
            if let command = note.wakeCommand {
                Button(copied == note.path ? "Copied" : "Copy wake-up command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copied = note.path
                }
                .buttonStyle(ControlPanelButtonStyle(size: .small))
                .help(command)
            }
        }
        .nightRow()
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: note.path)]) }
            Button("Forget this note") { forget(note) }
        }
        .help(note.wakeCommand.map { "Paste into Terminal to rebuild what was cleared: \($0)" }
              ?? "Cairn could not tell how this project rebuilds. Use its own install or build step.")
    }

    // MARK: - Sections

    @ViewBuilder private var list: some View {
        if store.isScanning && projects.isEmpty {
            NightEmpty(title: "Looking for your projects", message: "Measuring build output, dependencies and virtual environments.", busy: true)
        } else if indexing && projects.isEmpty {
            NightEmpty(title: "Grouping by project", message: "Reading when you last worked on each one.", busy: true)
        } else if projects.isEmpty && !asleep.isEmpty {
            NightList { asleepSection }
        } else if projects.isEmpty {
            NightEmpty(title: store.hasScanned ? "No build output found" : "Nothing scanned yet",
                       message: store.hasScanned
                           ? "The last scan found no node_modules, build folders or virtual environments worth showing."
                           : "Press Rescan and Cairn will list each project with the output you can rebuild.")
        } else if visible.isEmpty {
            NightEmpty(title: "No matching projects", message: "Try another name. Escape clears the filter.")
        } else {
            NightList {
                ForEach(visible) { project in
                    row(project)
                    if expanded.contains(project.id) {
                        sleepLine(project)
                        ForEach(project.items) { item in itemRow(item, in: project) }
                    }
                }
                asleepSection
            }
        }
    }

    private func row(_ project: ProjectSummary) -> some View {
        let state = selectionState(project)
        return Button { expanded.formSymmetricDifference([project.id]) } label: {
            HStack(spacing: 14) {
                NightName(logo: BrandLogo(name: nil, fallback: "folder", size: 25),
                          title: project.name, subtitle: subtitle(project))
                NightMeter(share: Double(project.rebuildableBytes) / Double(largestBytes))
                Text(Fmt.size(project.rebuildableBytes)).font(.system(size: 13, weight: .medium)).monospacedDigit()
                    .frame(width: 90, alignment: .trailing)
                Text(lastTouched(project)).font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                    .lineLimit(1).frame(width: 120, alignment: .leading)
                pill(project, state: state).frame(width: 120, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .nightRow()
        .contextMenu {
            if !project.rebuildable.isEmpty {
                Button(state == .all ? "Deselect" : "Select for cleaning") { toggle(project) }
                Button("Put to sleep…") { putToSleep([project]) }
                    .disabled(store.isCleaning || store.isScanning)
            }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([project.url]) }
        }
        .help(activitySentence(project))
    }

    /// Inside an opened project: what git says, and the sleep button.
    private func sleepLine(_ project: ProjectSummary) -> some View {
        let status = git[project.id]
        let text: String
        if let warning = status?.warning { text = warning }
        else if status != nil { text = "Everything is committed and pushed. Sleeping clears \(Fmt.size(project.rebuildableBytes)) that the project can rebuild." }
        else if project.isRepository { text = "Cairn could not read this project's git status. Sleeping only clears files the project can rebuild." }
        else { text = "Not a git repository, so nothing here is backed up by git. Sleeping only clears files the project can rebuild." }
        return HStack(spacing: 14) {
            Image(systemName: status?.warning != nil || status == nil ? "exclamationmark.circle" : "checkmark.circle")
                .font(.system(size: 13)).foregroundStyle(status?.warning != nil ? Brand.amber : Brand.textMuted)
                .frame(width: 22)
            Text(text).font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !project.rebuildable.isEmpty {
                Button("Put to sleep") { putToSleep([project]) }
                    .buttonStyle(ControlPanelButtonStyle(size: .small))
                    .disabled(store.isCleaning || store.isScanning)
            }
        }
        .padding(.leading, 32)
        .nightRow()
    }

    private func subtitle(_ project: ProjectSummary) -> String {
        guard let status = git[project.id], !status.summary.isEmpty else { return displayPath(project.url) }
        return displayPath(project.url) + " · " + status.summary
    }

    private func itemRow(_ item: ScanItem, in project: ProjectSummary) -> some View {
        HStack(spacing: 14) {
            NightName(logo: nil, title: relativeName(item, in: project), subtitle: item.note)
            Spacer().frame(width: 150)
            Text(Fmt.size(item.allocatedSize)).font(.system(size: 12.5)).foregroundStyle(Brand.textSecondary).monospacedDigit()
                .frame(width: 90, alignment: .trailing)
            Spacer().frame(width: 254)
        }
        .padding(.leading, 32)
        .nightRow()
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.resolvedURL]) }
        }
    }

    private func pill(_ project: ProjectSummary, state: SelectionState) -> NightPill {
        if state != .none { return NightPill(text: "Selected", tone: .ok) }
        if project.rebuildable.isEmpty { return NightPill(text: "Nothing to free") }
        if (project.idleDays() ?? 0) < Self.idleDays { return NightPill(text: "Active") }
        // An old project with work that exists only on this Mac.
        if git[project.id]?.backedUp == false { return NightPill(text: "Not pushed", tone: .warn) }
        return NightPill(text: "Idle", tone: .ok)
    }

    private func lastTouched(_ project: ProjectSummary) -> String {
        guard let date = project.lastActivity else { return "Unknown" }
        if Calendar.current.isDateInToday(date) { return "Open today" }
        let text = date.formatted(.relative(presentation: .named, unitsStyle: .wide))
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private func clearProjects() {
        let selected = Set(store.selectedItems().map(\.id))
        for id in projects.flatMap(\.rebuildable).map(\.id) where selected.contains(id) { store.toggle(id) }
    }

    // MARK: - Selection

    private enum SelectionState { case none, some, all }

    private func isSelected(_ id: UUID) -> Bool {
        store.selectedItems().contains { $0.id == id }
    }

    private func selectionState(_ project: ProjectSummary) -> SelectionState {
        let selected = Set(store.selectedItems().map(\.id))
        let ids = project.rebuildable.map(\.id)
        let count = ids.filter(selected.contains).count
        return count == 0 ? .none : count == ids.count ? .all : .some
    }

    private func toggle(_ project: ProjectSummary) {
        let selected = Set(store.selectedItems().map(\.id))
        let ids = project.rebuildable.map(\.id)
        if selectionState(project) == .all {
            for id in ids where selected.contains(id) { store.toggle(id) }
        } else {
            let wanted = Set(ids)
            store.select { item, _ in wanted.contains(item.id) }
        }
    }

    private func selectIdle(_ idle: [ProjectSummary]) {
        let wanted = Set(idle.flatMap(\.rebuildable).map(\.id))
        store.clearSelection()
        store.select { item, _ in wanted.contains(item.id) }
    }

    /// Review shows only this page's picks, so its total matches the button.
    private func keepOnlyProjects() {
        let mine = Set(projects.flatMap(\.rebuildable).map(\.id))
        store.beginScopedReview(Set(store.selectedItems().map(\.id)).intersection(mine))
    }

    // MARK: - Indexing

    private func reindex() async {
        if !preview {
            let notes = await Task.detached(priority: .utility) { () -> [SleepingProject] in
                let loaded = ProjectSleep.load()
                let kept = ProjectSleep.reconcile(loaded)
                if kept != loaded { ProjectSleep.save(kept) }
                return kept
            }.value
            sleeping = notes
        }
        let items = bucketItems
        guard !items.isEmpty else { projects = []; return }
        indexing = true
        let built = await Task.detached(priority: .userInitiated) { ProjectIndex.build(from: items) }.value
        guard !Task.isCancelled else { return }
        projects = built
        indexing = false
        guard !preview else { return }
        // git status is read for repositories only, a few seconds each at most.
        let repositories = built.filter(\.isRepository).sorted { $0.rebuildableBytes > $1.rebuildableBytes }.prefix(80).map(\.url)
        let statuses = await Task.detached(priority: .utility) { () -> [String: GitStatus] in
            var found: [String: GitStatus] = [:]
            for url in repositories {
                if Task.isCancelled { break }
                if let status = ProjectGit.status(of: url) { found[url.path] = status }
            }
            return found
        }.value
        guard !Task.isCancelled else { return }
        git = statuses
    }

    // MARK: - Formatting

    private func displayPath(_ url: URL) -> String {
        let home = FileScan.home.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }

    private func relativeName(_ item: ScanItem, in project: ProjectSummary) -> String {
        let base = project.url.path + "/"
        return item.url.path.hasPrefix(base) ? String(item.url.path.dropFirst(base.count)) : item.url.lastPathComponent
    }

    private func idleText(_ project: ProjectSummary) -> String {
        guard let days = project.idleDays() else { return "Unknown" }
        switch days {
        case 0: return "Today"
        case 1: return "Yesterday"
        case ..<30: return "\(days) days ago"
        default: return "Idle \(days) days"
        }
    }

    private func idleTint(_ project: ProjectSummary) -> Color {
        (project.idleDays() ?? 0) >= 30 ? Brand.textSecondary : Brand.textMuted
    }

    private func activitySentence(_ project: ProjectSummary) -> String {
        guard let date = project.lastActivity else {
            return "Cairn could not find git or manifest dates for this folder."
        }
        let source = project.isRepository ? "Based on git and manifest timestamps" : "Based on manifest timestamps"
        return "\(Fmt.relative(date)). \(source); build output is ignored because tools can touch it in the background."
    }
}
