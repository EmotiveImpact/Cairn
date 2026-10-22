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

    private enum Sort: String { case size, idle }
    @State private var sort: Sort = .size
    @State private var idleFilter = "All projects"
    @State private var focusedID: String?
    @State private var projects: [ProjectSummary] = []
    @State private var indexing = false

    private static let idleFilters = ["All projects", "Idle 30+ days", "Idle 90+ days"]

    private var bucketItems: [ScanItem] {
        store.buckets.first { $0.id == ProjectIndex.categoryID }?.items ?? []
    }

    /// Changes whenever the set of measured artifacts changes, not on selection.
    private var indexKey: String {
        let items = bucketItems
        return "\(items.count)-\(items.reduce(Int64(0)) { $0 + $1.allocatedSize })-\(store.isScanning)"
    }

    private var visible: [ProjectSummary] {
        let minimumIdle = idleFilter == "Idle 90+ days" ? 90 : idleFilter == "Idle 30+ days" ? 30 : 0
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = projects.filter { project in
            (minimumIdle == 0 || (project.idleDays() ?? 0) >= minimumIdle)
                && (query.isEmpty || project.name.lowercased().contains(query) || project.url.path.lowercased().contains(query))
        }
        switch sort {
        case .size: return filtered.sorted { $0.rebuildableBytes > $1.rebuildableBytes }
        case .idle: return filtered.sorted { ($0.idleDays() ?? -1) > ($1.idleDays() ?? -1) }
        }
    }

    private var focused: ProjectSummary? {
        projects.first { $0.id == focusedID } ?? visible.first
    }

    private var selectedProjectBytes: Int64 {
        projects.flatMap(\.rebuildable).filter { isSelected($0.id) }.reduce(0) { $0 + $1.allocatedSize }
    }

    var body: some View {
        CairnWorkspace(title: totalBytes > 0 ? "\(Fmt.size(totalBytes)) of build output" : "Projects",
                       subtitle: projects.isEmpty
                           ? "Your repositories, how long since you worked on them, and what can be rebuilt"
                           : "Across \(projects.count) coding project\(projects.count == 1 ? "" : "s"). Your source code is never touched.",
                       inspectorVisible: inspectorVisible, headerTrailingInset: 150) {
            VStack(spacing: 0) {
                controls
                WorkspaceColumns(leading: "Project", trailing: "Rebuildable · last activity")
                list
            }
        } detail: {
            detail
        } actions: {
            actions
        }
        .task(id: indexKey) { await reindex() }
    }

    // MARK: - Sections

    private var controls: some View {
        HStack(spacing: 12) {
            CairnSegmentedControl(label: "Sort", selection: $sort,
                                  options: [("Largest", Sort.size), ("Idle longest", Sort.idle)])
                .frame(width: 210, height: 32)
            Picker("Show", selection: $idleFilter) {
                ForEach(Self.idleFilters, id: \.self) { Text($0) }
            }.cairnFilterSurface().frame(width: 150)
            Spacer(minLength: 6)
            Text(summaryLine).font(.system(size: 11.5)).foregroundStyle(Brand.textSecondary)
        }
        .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 11)
    }

    private var totalBytes: Int64 { projects.reduce(Int64(0)) { $0 + $1.rebuildableBytes } }
    private var largestBytes: Int64 { max(1, projects.map(\.rebuildableBytes).max() ?? 1) }

    private var summaryLine: String {
        let total = projects.reduce(Int64(0)) { $0 + $1.rebuildableBytes }
        guard !projects.isEmpty else { return "" }
        return "\(projects.count) project\(projects.count == 1 ? "" : "s") · \(Fmt.size(total)) rebuildable"
    }

    @ViewBuilder private var list: some View {
        if store.isScanning && projects.isEmpty {
            CairnStateView(kind: .scanning, title: "Looking for your projects",
                           message: "Cairn is measuring build output, dependencies and virtual environments.", compact: true)
        } else if indexing && projects.isEmpty {
            CairnStateView(kind: .scanning, title: "Grouping by repository", message: "Reading project activity dates.", compact: true)
        } else if projects.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                WorkspaceEmpty(title: store.hasScanned ? "No project build output found" : "Find your projects",
                               message: store.hasScanned
                                   ? "The last scan found no node_modules, build folders or virtual environments worth showing."
                                   : "Run a scan and Cairn will list each repository with the output you can rebuild.",
                               icon: "folder.badge.gearshape")
                if !store.hasScanned {
                    Button("Scan this Mac") { store.startScan(includeExternalVolumes: !AppSettings.shared.ignoreExternalDrives) }
                        .buttonStyle(BrandButtonStyle()).padding(.horizontal, 26)
                }
            }
        } else if visible.isEmpty {
            WorkspaceEmpty(title: "No matching projects", message: "Try another filter or search.", icon: "folder")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visible) { project in row(project) }
                }
                .overlay(alignment: .top) { Rectangle().fill(Brand.separator).frame(height: 1) }
                .padding(.horizontal, 18).padding(.vertical, 8)
            }
        }
    }

    private func row(_ project: ProjectSummary) -> some View {
        let state = selectionState(project)
        return HStack(spacing: 12) {
            Button { toggle(project) } label: {
                Image(systemName: state == .all ? "checkmark.square.fill" : state == .some ? "minus.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundStyle(state == .none ? Brand.textMuted : Brand.room)
            }
            .buttonStyle(.plain)
            .disabled(project.rebuildable.isEmpty)
            .accessibilityLabel(state == .none ? "Select \(project.name)" : "Deselect \(project.name)")

            Button {
                focusedID = project.id
                inspectorVisible = true
            } label: {
                HStack(spacing: 12) {
                    BrandLogo(name: nil, fallback: "folder", size: 22)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.textPrimary).lineLimit(1)
                        Text(displayPath(project.url)).font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                            .lineLimit(1).truncationMode(.middle)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Brand.track)
                            Capsule().fill(Brand.room.opacity(0.8))
                                .frame(width: max(3, geo.size.width * CGFloat(Double(project.rebuildableBytes) / Double(largestBytes))))
                        }
                    }.frame(width: 120, height: 3).accessibilityHidden(true)
                    Text(Fmt.size(project.rebuildableBytes)).font(.system(size: 12, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Brand.textPrimary).frame(width: Brand.colSize, alignment: .trailing)
                    Text(idleText(project)).font(.system(size: 11)).foregroundStyle(idleTint(project))
                        .frame(width: 104, alignment: .trailing)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).frame(height: 62)
        .background(inspectorVisible && focused?.id == project.id ? Brand.wash(0.045) : Color.clear)
        .overlay(alignment: .top) { Rectangle().fill(Brand.separator).frame(height: 0.5) }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var detail: some View {
        if let project = focused {
            WorkspaceHeading(title: project.name,
                             subtitle: project.isRepository ? "Repository" : "Project folder",
                             icon: "folder.badge.gearshape",
                             value: Fmt.size(project.rebuildableBytes))
            WorkspaceDetail(title: "Last activity", text: activitySentence(project))
            WorkspaceDetail(title: "Location", text: project.url.path)
            VStack(alignment: .leading, spacing: 10) {
                Text("Found in this project").font(.system(size: 12, weight: .medium))
                ForEach(project.items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(item.severity.color).frame(width: 6, height: 6).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(relativeName(item, in: project)).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                            if !item.note.isEmpty {
                                Text(item.note).font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 4)
                        Text(Fmt.size(item.allocatedSize)).font(.system(size: 11)).monospacedDigit().foregroundStyle(Brand.textSecondary)
                    }
                }
            }
            HStack(spacing: 8) {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([project.url]) }
                    .buttonStyle(ControlPanelButtonStyle())
                if !project.rebuildable.isEmpty {
                    Button(selectionState(project) == .all ? "Deselect" : "Select rebuildable") { toggle(project) }
                        .buttonStyle(ControlPanelButtonStyle())
                }
            }
            WorkspaceDetail(title: "What happens", text: "Only output your tools can rebuild is offered. Source code, git history and settings are never part of a project clean. You review every path before anything is removed.")
        } else {
            WorkspaceDetail(title: "Projects", text: "Select a project to see what Cairn found in it.")
        }
    }

    @ViewBuilder private var actions: some View {
        let idle = projects.filter { ($0.idleDays() ?? 0) >= 30 && !$0.rebuildable.isEmpty }
        Button("Select idle projects") { selectIdle(idle) }
            .buttonStyle(ControlPanelButtonStyle())
            .disabled(idle.isEmpty || store.isCleaning)
            .help("Selects rebuildable output in projects untouched for 30 days or more")
        Spacer()
        if selectedProjectBytes > 0 {
            Text("\(Fmt.size(selectedProjectBytes)) selected from projects").foregroundStyle(Brand.textSecondary)
        }
        Button("Review cleanup…", action: onReview)
            .buttonStyle(BrandButtonStyle(enabled: store.selectedCount > 0))
            .disabled(store.selectedCount == 0 || store.isCleaning || store.isScanning)
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
        store.select { item, _ in wanted.contains(item.id) }
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
