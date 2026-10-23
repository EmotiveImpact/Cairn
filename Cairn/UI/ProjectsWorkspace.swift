import SwiftUI
import AppKit

/// Developers think in projects, not folders. This groups the existing
/// build-output findings by repository and shows how long each has been idle.
/// Selection flows into the shared ReviewSheet; nothing is removed from here.
struct ProjectsWorkspace: View {
    let store: ScanStore
    var search: String = ""
    @Binding var inspectorVisible: Bool
    var onReview: () -> Void

    @State private var projects: [ProjectSummary] = []
    @State private var indexing = false
    @State private var expanded: Set<String> = []

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
                Button("Review idle projects") { selectIdle(idle); onReview() }
                    .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
                    .disabled(idle.isEmpty || store.isCleaning || store.isScanning)
                    .help("Selects rebuildable output in projects untouched for \(Self.idleDays) days or more, then shows it for review")
            }
        }
        .task(id: indexKey) { await reindex() }
    }

    // MARK: - Sections

    @ViewBuilder private var list: some View {
        if store.isScanning && projects.isEmpty {
            NightEmpty(title: "Looking for your projects", message: "Measuring build output, dependencies and virtual environments.", busy: true)
        } else if indexing && projects.isEmpty {
            NightEmpty(title: "Grouping by project", message: "Reading when you last worked on each one.", busy: true)
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
                        ForEach(project.items) { item in itemRow(item, in: project) }
                    }
                }
            }
        }
    }

    private func row(_ project: ProjectSummary) -> some View {
        let state = selectionState(project)
        return Button { expanded.formSymmetricDifference([project.id]) } label: {
            HStack(spacing: 14) {
                NightName(logo: BrandLogo(name: nil, fallback: "folder", size: 25),
                          title: project.name, subtitle: displayPath(project.url))
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
            }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([project.url]) }
        }
        .help(activitySentence(project))
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
        let items = bucketItems
        guard !items.isEmpty else { projects = []; return }
        indexing = true
        let built = await Task.detached(priority: .userInitiated) { ProjectIndex.build(from: items) }.value
        guard !Task.isCancelled else { return }
        projects = built
        indexing = false
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
