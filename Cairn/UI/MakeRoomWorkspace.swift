import SwiftUI

/// The planner ranks only candidates that can actually reach the existing
/// reviewed Trash executor. Filtering precedes the display cap so a long list
/// of blocked findings cannot hide a valid option farther down the scan.
enum MakeRoomCandidates {
    static func select(_ items: [ScanItem], isExcluded: (URL) -> Bool, limit: Int = 60) -> [ScanItem] {
        var seen: [String] = []
        var identities = Set<String>()
        var options: [ScanItem] = []
        let ranked = items.sorted { a, b in
            if a.severity != b.severity { return a.severity < b.severity }
            if a.allocatedSize != b.allocatedSize { return a.allocatedSize > b.allocatedSize }
            return a.resolvedURL.path < b.resolvedURL.path
        }
        for item in ranked {
            if options.count >= limit { break }
            guard SpaceActionCapability.forItem(item).executableAfterReview,
                  item.sourceIdentity != nil, !isExcluded(item.resolvedURL),
                  SafePaths.protectedSessionReason(item.resolvedURL) == nil else { continue }
            guard case .trash = item.cleanMethod else { continue }
            let path = item.resolvedURL.standardizedFileURL.path
            guard !seen.contains(where: { path == $0 || path.hasPrefix($0 + "/") || $0.hasPrefix(path + "/") }) else { continue }
            if let identity = item.sourceIdentity {
                guard identities.insert("\(identity.device):\(identity.inode)").inserted else { continue }
            }
            seen.append(path)
            options.append(item)
        }
        return options
    }
}

/// A capacity target with a reviewed path into the existing cleaner. Trash
/// actions carry zero immediate-reclaim credit, including when their file sizes
/// are large. Only a fresh capacity observation can complete the user's goal.
struct MakeRoomWorkspace: View {
    let store: ScanStore
    let control: StorageControl
    let receiptRunID: UUID?
    var onBack: () -> Void
    var onScan: () -> Void
    var onReview: (ReviewedSpacePlan) -> Void
    var onOpen: (NavSection) -> Void
    @Bindable private var settings = AppSettings.shared
    @State private var selected = Set<UUID>()
    @State private var startingCapacity: CapacityReading?
    @State private var checkingSpace = false
    @State private var preparingReview = false
    @State private var planError: String?
    private let preview = CommandLine.arguments.contains("--preview-ui")

    private var available: Int64? { preview ? PreviewStorageScenario.availableBytes : control.currentAvailable }
    private var goalState: SpaceGoalState {
        SpaceGoalState.evaluate(current: preview ? PreviewStorageScenario.current : control.current, target: target)
    }
    private var target: Int64 { Int64(preview ? PreviewStorageScenario.goalGB : settings.goalGB) * 1_000_000_000 }
    private var shortfall: Int64? { SpaceGoal.shortfall(available: available, target: target) }
    private var observedChange: Int64? {
        preview ? nil : SpaceGoal.observedChange(from: startingCapacity, to: control.current)
    }
    private var actions: [ScanItem] {
        if preview { return Self.sampleActions }
        guard store.phase == .finished, store.comparisonScopeStable, !store.includeExternalVolumes else { return [] }
        return MakeRoomCandidates.select(store.buckets.flatMap(\.items), isExcluded: AppSettings.shared.isExcluded)
    }
    private var selectedActions: [ScanItem] { actions.filter { selected.contains($0.id) } }
    private var affectedBytes: Int64 { selectedActions.reduce(0) { $0 + $1.allocatedSize } }
    private var lastReceipt: ScanStore.CleanSummary? {
        guard !preview, let receiptRunID, store.lastCleanRunID == receiptRunID else { return nil }
        return store.lastCleanSummary
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Button { onBack() } label: { Label("Overview", systemImage: "chevron.left") }
                            .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Brand.deepBlue)
                        Spacer()
                        Text(preview ? "SAMPLE PLAN · ACTIONS DISABLED" : "REVIEWED PLAN")
                            .font(.system(size: 10)).tracking(0.8).foregroundStyle(Brand.textMuted)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text("Make room").font(.system(size: 28, weight: .semibold))
                        Spacer()
                        Button { checkSpace() } label: {
                            Label(checkingSpace ? "Checking…" : "Check space", systemImage: "arrow.clockwise")
                        }.buttonStyle(ControlPanelButtonStyle()).disabled(preview || checkingSpace)
                    }.padding(.top, 16)
                    Text("Set the space you want available on your internal drive. Cairn will show what it can safely review.")
                        .font(.system(size: 12)).foregroundStyle(Brand.textMuted).padding(.top, 6)
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("CURRENTLY AVAILABLE").font(.system(size: 10)).tracking(0.7).foregroundStyle(Brand.textMuted)
                            Text(available.map(Fmt.size) ?? "Unavailable")
                                .font(.system(size: 28, weight: .regular)).monospacedDigit()

                        }
                        Image(systemName: "arrow.right").foregroundStyle(Brand.textMuted)
                        VStack(alignment: .leading, spacing: 7) {
                            Text("MY TARGET").font(.system(size: 10)).tracking(0.7).foregroundStyle(Brand.textMuted)
                            Stepper("\(preview ? PreviewStorageScenario.goalGB : settings.goalGB) GB", value: $settings.goalGB, in: 5...1_000, step: 5)
                                .font(.system(size: 21, weight: .regular)).frame(width: 156).disabled(preview)
                        }
                        Spacer()
                        if let shortfall {
                            Text(shortfall == 0 ? "Target met now" : "\(Fmt.size(shortfall)) still needed")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(shortfall == 0 ? Brand.safeCyan : Brand.amber)
                        } else {
                            Text("Space unavailable").font(.system(size: 14)).foregroundStyle(Brand.amber)
                        }
                    }.padding(.top, 28)
                    if !preview, let checked = control.lastChecked {
                        Text("Available space checked at \(checked.formatted(date: .omitted, time: .shortened)). Return from Finder or press Check space to update it.")
                            .font(.system(size: 11)).foregroundStyle(Brand.textMuted).padding(.top, 12)
                    }
                    if let observedChange, observedChange != 0 {
                        Text("\(Fmt.size(abs(observedChange))) \(observedChange > 0 ? "more" : "less") available since opening this plan. Other Mac activity may also affect this reading.")
                            .font(.system(size: 11)).foregroundStyle(Brand.textSecondary).padding(.top, 8)
                    }
                    Text("This is a final available-space target. Copying to an SSD or moving files to Trash does not by itself free internal space.")
                        .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                        .padding(.top, 15).fixedSize(horizontal: false, vertical: true)
                    Rectangle().fill(Brand.separator).frame(height: 0.5).padding(.vertical, 26)
                    Text("NEEDS YOUR REVIEW").font(.system(size: 11)).tracking(0.7).foregroundStyle(Brand.textMuted)
                    if let lastReceipt {
                        Text("Last action: \(Fmt.size(lastReceipt.bytes)) in affected file-size estimates. Check the current capacity above to see whether your target is met.")
                            .font(.system(size: 12)).foregroundStyle(Brand.textSecondary).padding(.top, 12)
                    }
                    if let planError {
                        Text(planError).font(.system(size: 12)).foregroundStyle(Brand.amber).padding(.top, 12)
                    }
                    if goalState == .met {
                        CairnStateView(kind: .empty, title: "Your target is already met", message: "No cleanup is needed for this target. Current available space can still change as you use your Mac.").padding(.top, 17)
                    } else if goalState == .impossible {
                        CairnStateView(kind: .empty, title: "This target exceeds your drive's capacity", message: "Choose a smaller final available-space target. Cairn will not propose unnecessary removals.").padding(.top, 17)
                    } else if goalState == .unavailable {
                        CairnStateView(kind: .empty, title: "Check available space first", message: "A recent internal-volume reading is needed to build a plan.").padding(.top, 17)
                    } else if store.isScanning && !preview {
                        CairnStateView(kind: .scanning, title: "Measuring your Mac", message: store.progressText)
                            .padding(.top, 17)
                    } else if actions.isEmpty {
                        CairnStateView(kind: .empty, title: store.hasScanned ? "No eligible actions for this target" : "Scan to build a plan",
                            message: "Cairn cannot currently promise enough immediate space for this target. Review large files or storage options below; scan again if the evidence is old.")
                            .padding(.top, 17)
                        Button("Scan this Mac") { onScan() }.buttonStyle(ControlPanelButtonStyle(primary: true)).padding(.top, 12)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(actions) { item in
                                HStack(spacing: 13) {
                                    Toggle(isOn: Binding(get: { selected.contains(item.id) }, set: { value in
                                        if value { selected.insert(item.id) } else { selected.remove(item.id) }
                                    })) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.url.lastPathComponent).font(.system(size: 13)).lineLimit(1)
                                            Text(item.categoryID.replacingOccurrences(of: "-", with: " ").capitalized).font(.system(size: 10)).foregroundStyle(Brand.textMuted)
                                        }.help(item.resolvedURL.path)
                                    }
                                        .toggleStyle(.checkbox).disabled(preview).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(Fmt.size(item.allocatedSize)).font(.system(size: 12)).monospacedDigit().frame(width: 92, alignment: .trailing)
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(effect(item))
                                        Text(item.isRegenerable ? "Rebuild / download later" : "Original leaves this folder")
                                    }.font(.system(size: 11)).foregroundStyle(Brand.textMuted).frame(width: 175, alignment: .trailing)
                                }.frame(minHeight: 49)
                                Rectangle().fill(Brand.separator).frame(height: 0.5)
                            }
                        }.padding(.top, 14)
                        Text(preview ? "Sample choices only · actions disabled. Trash sizes are not immediate space gains." : "Showing up to 60 recoverable Trash options from your latest scan. App state, permissions and each target are checked again before an action runs.")
                            .font(.system(size: 11)).foregroundStyle(Brand.textMuted).padding(.top, 18)
                    }
                    DisclosureGroup("Not available now · guaranteed immediate reclaim") {
                        Text("This build offers reviewed Trash actions and retained-source exports. Both receive zero immediate-reclaim credit. A certified tool cleanup needs its own tested adapter and explicit recovery disclosure.")
                            .font(.system(size: 11)).foregroundStyle(Brand.textMuted).padding(.top, 8)
                    }.font(.system(size: 12)).padding(.top, 20)
                    Rectangle().fill(Brand.separator).frame(height: 0.5).padding(.vertical, 24)
                    HStack(spacing: 18) {
                        Button("Review large files") { onOpen(.largeFiles) }.buttonStyle(.plain).foregroundStyle(Brand.deepBlue)
                        Button("External storage") { onOpen(.storage) }.buttonStyle(.plain).foregroundStyle(Brand.deepBlue)
                        Spacer()
                    }.font(.system(size: 12))
                }.padding(30).frame(maxWidth: 980, alignment: .leading).frame(maxWidth: .infinity)
            }
            HStack(spacing: 12) {
                Text(selected.isEmpty ? "Choose exact items to review" : "\(Fmt.size(affectedBytes)) selected file size · immediate space gain unconfirmed")
                    .foregroundStyle(Brand.textMuted).lineLimit(1)
                Spacer()
                Button("Review \(selectedActions.count) item\(selectedActions.count == 1 ? "" : "s")…") {
                    prepareReview()
                }.buttonStyle(ControlPanelButtonStyle(primary: true))
                    .disabled(preview || preparingReview || selectedActions.isEmpty || store.isScanning || store.isCleaning || goalState == .met || goalState == .impossible || goalState == .unavailable)
            }.font(.system(size: 12)).padding(.horizontal, 20).frame(height: 64)
                .background(Brand.background)
        }.background(Brand.background).foregroundStyle(Brand.textPrimary)
            .task {
                guard !preview else { return }
                await control.refreshCapacity()
                if startingCapacity == nil { startingCapacity = control.current }
            }
            .onChange(of: store.isCleaning) { _, running in
                if !running && !preview { Task { await control.refreshCapacity(force: true) } }
            }
            .onChange(of: store.scanStartedAt) { _, _ in selected.removeAll() }
    }

    private func prepareReview() {
        guard !preview, !preparingReview, let scanStarted = store.scanStartedAt else { return }
        let chosen = selectedActions, target = target
        let exclusions = settings.excludedPaths, fda = store.fdaGranted
        let developer = settings.includeDeveloperCaches, simulators = settings.includeSimulators
        preparingReview = true; planError = nil
        Task {
            defer { preparingReview = false }
            await control.refreshCapacity(force: true)
            guard let capacity = control.current else { planError = "Available space could not be checked."; return }
            let plan = await Task.detached(priority: .utility) {
                ReviewedSpacePlan.capture(items: chosen, capacity: capacity, target: target, scanStarted: scanStarted,
                    exclusions: exclusions, fullDiskAccess: fda, developerCaches: developer, simulators: simulators)
            }.value
            guard let plan, store.comparisonScopeStable, store.scanStartedAt == scanStarted, Set(selectedActions.map(\.id)) == plan.itemIDs,
                  self.target == target, settings.excludedPaths == exclusions else {
                planError = "The evidence or selection changed, or is too old. Run a fresh internal scan and review again."
                return
            }
            onReview(plan)
        }
    }
    private func effect(_ item: ScanItem) -> String {
        switch item.cleanMethod {
        case .trash: return "Trash · recoverable"
        case .tool: return "Tool · review elsewhere"
        default: return "Review only"
        }
    }
    private func checkSpace() {
        guard !preview, !checkingSpace else { return }
        checkingSpace = true
        Task {
            await control.refreshCapacity(force: true)
            checkingSpace = false
        }
    }
    private static let sampleActions: [ScanItem] = [
        ScanItem(url: URL(fileURLWithPath: "/Sample/Xcode build output"), allocatedSize: 6_400_000_000, categoryID: "developer", severity: .safe),
        ScanItem(url: URL(fileURLWithPath: "/Sample/Node package cache"), allocatedSize: 2_700_000_000, categoryID: "developer", severity: .review),
        ScanItem(url: URL(fileURLWithPath: "/Sample/Temporary browser data"), allocatedSize: 1_300_000_000, categoryID: "browsers", severity: .review)
    ]
}
