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
    @State private var expanded: Set<String> = CommandLine.arguments.contains("--preview-ui")
        ? [FileScan.home.appendingPathComponent("Developer/storefront-web").path] : []
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
    private var asleep: [SleepingProject] { preview ? sleeping : sleeping.filter { ProjectSleep.isAsleep($0) } }
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
        NightNumberPage(eyebrow: projects.isEmpty || commonRoot.isEmpty ? "Projects" : "Projects · \(commonRoot)",
                        number: idleBytes > 0 ? Fmt.size(idleBytes) : totalBytes > 0 ? Fmt.size(totalBytes) : "Projects",
                        phrase: idleBytes > 0 ? "can go to sleep" : totalBytes > 0 ? "of build output" : "",
                        lead: idleBytes > 0
                            ? "Untouched for a month. Sleeping clears what they can rebuild and keeps a note to bring it back."
                            : projects.isEmpty
                                ? "Your coding projects, how long since you worked on them, and what can be rebuilt."
                                : "Across \(projects.count) coding project\(projects.count == 1 ? "" : "s"). Your source code is never touched.") {
            Button {
                guard !preview else { return }
                if store.isScanning { store.cancel() } else { store.rescan() }
            } label: {
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
                NightTotal(strong: Fmt.size(idleBytes), rest: idleLine)
                Spacer()
                Button(sleepTargets.count < idle.count
                       ? "Put \(sleepTargets.count) ready project\(sleepTargets.count == 1 ? "" : "s") to sleep"
                       : "Put idle projects to sleep") { putToSleep(sleepTargets) }
                    .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
                    .disabled(idle.isEmpty || store.isCleaning || store.isScanning)
                    .help("Selects rebuildable output in projects untouched for \(Self.idleDays) days or more, keeps a note of how to rebuild it, then shows it for review")
            }
        }
        .task(id: indexKey) { await reindex() }
    }

    // MARK: - Sleep

    /// Idle projects whose git work is all pushed (or that git can't speak for).
    private var ready: [ProjectSummary] { idle.filter { git[$0.id]?.backedUp != false } }
    /// The footer button sleeps the ready ones when some still need pushing;
    /// a single project with unpushed work is put to sleep from its own row.
    private var sleepTargets: [ProjectSummary] { ready.isEmpty ? idle : ready }
    private var idleLine: String {
        let waiting = idle.count - ready.count
        let base = "in \(idle.count) idle project\(idle.count == 1 ? "" : "s")"
        return waiting > 0 ? base + " · \(waiting) need\(waiting == 1 ? "s" : "") pushing first" : base
    }

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
            Text("Asleep · \(asleep.count)").nightEyebrow().padding(.top, 22).padding(.bottom, 8)
            ForEach(asleep) { note in sleepingRow(note) }
        }
    }

    private func sleepingRow(_ note: SleepingProject) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "moon").font(.system(size: 15)).foregroundStyle(Brand.room).frame(width: 22, height: 22)
                NightName(logo: nil, title: note.name, subtitle: displayPath(URL(fileURLWithPath: note.path)))
            }
            Text(Fmt.size(note.bytes) + " cleared").font(.system(size: 12)).foregroundStyle(Brand.textMuted).monospacedDigit()
                .lineLimit(1).frame(width: 120, alignment: .leading)
            Text("Asleep since " + note.asleepSince.formatted(.dateTime.day().month(.abbreviated)))
                .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                .lineLimit(1).frame(width: 140, alignment: .leading)
            if let command = note.wakeCommand {
                NightLink(title: copied == note.path ? "Copied" : "Wake: " + command, systemImage: "doc.on.doc") {
                    copy(command)
                    copied = note.path
                }
                .lineLimit(1)
                .frame(width: 170, alignment: .trailing)
                .help("Copies the command. Paste it into Terminal in the project folder to rebuild what was cleared.")
            } else {
                Spacer().frame(width: 170)
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

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
            // Soften the last row into the footer instead of a hard cut.
            .mask(VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 28)
            })
        }
    }

    private func row(_ project: ProjectSummary) -> some View {
        let state = selectionState(project)
        return Button { expanded.formSymmetricDifference([project.id]) } label: {
            HStack(spacing: 14) {
                HStack(spacing: 10) {
                    BrandLogo(name: nil, fallback: "folder", size: 25).frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.name).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Brand.textPrimary)
                            .lineLimit(1).truncationMode(.middle)
                        gitLine(project).font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
        .help(displayPath(project.url) + " · " + activitySentence(project))
    }

    /// Inside an opened project: what git says, and the sleep button. Amber
    /// when work exists only on this Mac.
    private func sleepLine(_ project: ProjectSummary) -> some View {
        let status = git[project.id]
        let names = project.rebuildable.map { relativeName($0, in: project) }.prefix(3).joined(separator: " and ")
        let clears = names.isEmpty ? "files the project can rebuild" : names
        let warning = status?.warning?.components(separatedBy: ". Sleeping").first
        let strong: String
        let text: String
        if let warning {
            strong = "This work is only on this Mac."
            text = "\(warning). Push it first, or sleep anyway: sleeping only clears \(clears), never your code."
        } else if status != nil {
            strong = "Everything is committed and pushed."
            text = "Sleeping clears \(Fmt.size(project.rebuildableBytes)) in \(clears), and keeps a note of how to rebuild it."
        } else if project.isRepository {
            strong = ""
            text = "Cairn could not read this project's git status. Sleeping only clears \(clears), never your code."
        } else {
            strong = "Not in git,"
            text = "so nothing here is backed up by git. Sleeping only clears \(clears), never your code."
        }
        return NightNote(tone: warning != nil ? .warn : .info, strong: strong, text: text) {
            if let command = pushCommand(project, status: status) {
                NightLink(title: copied == project.id ? "Copied" : "Copy git push") {
                    copy(command)
                    copied = project.id
                }
                .help(command)
            }
            if !project.rebuildable.isEmpty {
                Button { putToSleep([project]) } label: { Label("Put to sleep", systemImage: "moon") }
                    .buttonStyle(ControlPanelButtonStyle(size: .small))
                    .disabled(store.isCleaning || store.isScanning)
            }
        }
        .padding(.leading, 34)
        .padding(.vertical, 6)
    }

    /// The command that pushes this branch, when commits are waiting. Cairn
    /// only copies it; it never runs git commands that change anything.
    private func pushCommand(_ project: ProjectSummary, status: GitStatus?) -> String? {
        guard let status, let branch = status.branch else { return nil }
        let folder = "'" + project.url.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        if status.upstream == nil { return "git -C \(folder) push -u origin \(branch)" }
        return status.ahead > 0 ? "git -C \(folder) push" : nil
    }

    /// "checkout-redesign · 3 not pushed · 2 changed", the problem part in amber.
    private func gitLine(_ project: ProjectSummary) -> Text {
        guard let status = git[project.id] else {
            return Text(project.isRepository ? displayPath(project.url) : "not in git").foregroundStyle(Brand.textMuted)
        }
        let head = Text((status.branch ?? "detached") + " · ").foregroundStyle(Brand.textMuted)
        if status.backedUp {
            return head + Text("✓ ").foregroundStyle(Brand.room) + Text("all pushed").foregroundStyle(Brand.textMuted)
        }
        var parts: [String] = []
        if status.upstream == nil { parts.append("never pushed") }
        else if status.ahead > 0 { parts.append("\(status.ahead) not pushed") }
        if status.changed > 0 { parts.append("\(status.changed) unsaved") }
        if status.untracked > 0 { parts.append("\(status.untracked) new file\(status.untracked == 1 ? "" : "s")") }
        // Problems first, so a long branch name never hides them.
        return Text(parts.joined(separator: " · ")).foregroundStyle(Brand.amber)
            + Text(" · " + (status.branch ?? "detached")).foregroundStyle(Brand.textMuted)
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
        if (project.idleDays() ?? 0) < Self.idleDays { return NightPill(text: "Active", tone: .quiet) }
        // An old project with work that exists only on this Mac.
        if git[project.id]?.backedUp == false { return NightPill(text: "Not pushed", tone: .warn) }
        if git[project.id]?.backedUp == true { return NightPill(text: "Ready to sleep", tone: .ok) }
        return NightPill(text: "Idle")
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
        if preview {
            projects = Self.sampleProjects
            git = Self.sampleGit
            sleeping = Self.sampleSleeping
            return
        }
        do {
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

    // MARK: - Preview

    /// Fixed display data for `--preview-ui`: 21.7 GB across eight projects,
    /// five of them idle. The paths are never read and nothing here can be cleaned.
    private static let sampleProjects: [ProjectSummary] = {
        let root = FileScan.home.appendingPathComponent("Developer")
        let gb: Double = 1_000_000_000
        func project(_ name: String, idle days: Int, repository: Bool = true, _ output: [(String, Double)]) -> ProjectSummary {
            let url = root.appendingPathComponent(name)
            let items = output.map { path, size in
                ScanItem(url: url.appendingPathComponent(path), allocatedSize: Int64(size * gb),
                         categoryID: ProjectIndex.categoryID, severity: .safe,
                         note: path.hasSuffix("node_modules") || path == "Pods" || path == ".venv"
                             ? "Dependencies, installed again when needed" : "Build output, made again on the next build")
            }
            return ProjectSummary(url: url, items: items, isRepository: repository,
                                  lastActivity: Date().addingTimeInterval(-Double(days) * 86_400))
        }
        return [
            project("storefront-web", idle: 94, [("node_modules", 3.9), (".next", 1.3)]),
            project("ios-banking", idle: 2, [("build", 2.6), ("Pods", 1.6)]),
            project("ml-experiments", idle: 121, [(".venv", 3.4)]),
            project("design-system", idle: 45, [("node_modules", 2.1), ("storybook-static", 0.4)]),
            project("api-gateway", idle: 0, [("target", 2.3)]),
            project("marketing-site", idle: 210, [("node_modules", 1.6), ("dist", 0.2)]),
            project("android-companion", idle: 61, repository: false, [("build", 1.4), (".gradle", 0.3)]),
            project("cli-tools", idle: 5, [("target", 0.6)]),
        ]
    }()

    /// What git says about the sample projects: two old ones hold work that
    /// exists only on this Mac.
    private static let sampleGit: [String: GitStatus] = {
        let root = FileScan.home.appendingPathComponent("Developer")
        func path(_ name: String) -> String { root.appendingPathComponent(name).path }
        return [
            path("storefront-web"): GitStatus(branch: "checkout-redesign", upstream: "origin/checkout-redesign", ahead: 3, changed: 2),
            path("ios-banking"): GitStatus(branch: "main", upstream: "origin/main"),
            path("ml-experiments"): GitStatus(branch: "main", untracked: 4),
            path("design-system"): GitStatus(branch: "main", upstream: "origin/main"),
            path("api-gateway"): GitStatus(branch: "develop", upstream: "origin/develop", changed: 1),
            path("marketing-site"): GitStatus(branch: "main", upstream: "origin/main"),
            path("cli-tools"): GitStatus(branch: "main", upstream: "origin/main", ahead: 1),
        ]
    }()

    private static let sampleSleeping: [SleepingProject] = {
        let root = FileScan.home.appendingPathComponent("Developer")
        return [
            SleepingProject(path: root.appendingPathComponent("old-portfolio").path, name: "old-portfolio",
                            asleepSince: Date().addingTimeInterval(-41 * 86_400), bytes: 2_800_000_000,
                            cleared: [], wakeCommand: "cd ~/Developer/old-portfolio && npm install"),
            SleepingProject(path: root.appendingPathComponent("rust-game").path, name: "rust-game",
                            asleepSince: Date().addingTimeInterval(-18 * 86_400), bytes: 4_100_000_000,
                            cleared: [], wakeCommand: "cd ~/Developer/rust-game && cargo build"),
        ]
    }()

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
