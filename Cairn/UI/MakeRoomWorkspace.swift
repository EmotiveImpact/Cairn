import SwiftUI

/// A capacity target with a reviewed path into the existing cleaner. Trash
/// actions carry zero immediate-reclaim credit, including when their file sizes
/// are large. Only a fresh capacity observation can complete the user's goal.
struct MakeRoomWorkspace: View {
    let store: ScanStore
    let control: StorageControl
    let receiptRunID: UUID?
    var onBack: () -> Void
    var onScan: () -> Void
    var onReview: (Set<UUID>) -> Void
    var onOpen: (NavSection) -> Void
    @Bindable private var settings = AppSettings.shared
    @State private var selected = Set<UUID>()
    private let preview = CommandLine.arguments.contains("--preview-ui")

    private var available: Int64? { preview ? 9_900_000_000 : control.currentAvailable }
    private var target: Int64 { Int64(settings.goalGB) * 1_000_000_000 }
    private var shortfall: Int64? { SpaceGoal.shortfall(available: available, target: target) }
    private var actions: [ScanItem] {
        if preview { return Self.sampleActions }
        guard store.phase == .finished, !store.includeExternalVolumes else { return [] }
        var seen: [String] = []
        let ordered = store.buckets.flatMap(\.items).sorted { $0.allocatedSize > $1.allocatedSize }
        return ordered.prefix(120).filter { item in
            guard item.isActionable, item.severity != .risky, !item.permissionDenied,
                  item.sourceIdentity != nil,
                  !AppSettings.shared.isExcluded(item.resolvedURL),
                  SafePaths.protectedSessionReason(item.resolvedURL) == nil else { return false }
            guard case .trash = item.cleanMethod else { return false }
            let path = item.resolvedURL.standardizedFileURL.path
            guard !seen.contains(where: { path == $0 || path.hasPrefix($0 + "/") || $0.hasPrefix(path + "/") }) else { return false }
            seen.append(path)
            return true
        }.prefix(60).map { $0 }
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
                    Text("Make room").font(.system(size: 25, weight: .regular)).padding(.top, 16)
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
                            Stepper("\(settings.goalGB) GB", value: $settings.goalGB, in: 5...1_000, step: 5)
                                .font(.system(size: 21, weight: .regular)).frame(width: 156).disabled(preview)
                        }
                        Spacer()
                        if let shortfall {
                            Text(shortfall == 0 ? "Target met now" : "\(Fmt.size(shortfall)) short")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(shortfall == 0 ? Brand.safeCyan : Brand.amber)
                        }
                    }.padding(.top, 28)
                    Text("This is a final available-space target. Copying to an SSD or moving files to Trash does not by itself free internal space.")
                        .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                        .padding(.top, 15).fixedSize(horizontal: false, vertical: true)
                    Rectangle().fill(Brand.separator).frame(height: 0.5).padding(.vertical, 26)
                    Text("OPTIONS TO REVIEW").font(.system(size: 11)).tracking(0.7).foregroundStyle(Brand.textMuted)
                    if let lastReceipt {
                        Text("Last action: \(Fmt.size(lastReceipt.bytes)) in affected file-size estimates. Check the current capacity above to see whether your target is met.")
                            .font(.system(size: 12)).foregroundStyle(Brand.textSecondary).padding(.top, 12)
                    }
                    if store.isScanning && !preview {
                        CairnStateView(kind: .scanning, title: "Measuring your Mac", message: store.progressText)
                            .padding(.top, 17)
                    } else if actions.isEmpty {
                        CairnStateView(kind: .empty, title: "Scan to build a plan",
                            message: "A fresh internal scan finds items Cairn can show for review. Some space may remain unexplained.")
                            .padding(.top, 17)
                        Button("Scan this Mac") { onScan() }.buttonStyle(ControlPanelButtonStyle(primary: true)).padding(.top, 12)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(actions) { item in
                                HStack(spacing: 13) {
                                    Toggle(isOn: Binding(get: { selected.contains(item.id) }, set: { value in
                                        if value { selected.insert(item.id) } else { selected.remove(item.id) }
                                    })) { Text(item.url.lastPathComponent).font(.system(size: 13)) }
                                        .toggleStyle(.checkbox).disabled(preview).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(item.categoryID.replacingOccurrences(of: "-", with: " ").capitalized).font(.system(size: 11)).foregroundStyle(Brand.textMuted).frame(width: 110, alignment: .leading)
                                    Text(Fmt.size(item.allocatedSize)).font(.system(size: 12)).monospacedDigit().frame(width: 92, alignment: .trailing)
                                    Text(effect(item)).font(.system(size: 11)).foregroundStyle(Brand.textMuted).frame(width: 155, alignment: .trailing)
                                }.frame(minHeight: 49)
                                Rectangle().fill(Brand.separator).frame(height: 0.5)
                            }
                        }.padding(.top, 14)
                        Text(preview ? "Sample choices only · actions disabled. Trash sizes are not immediate space gains." : "Showing up to 60 recoverable Trash options from your latest scan. App state, permissions and each target are checked again before an action runs.")
                            .font(.system(size: 11)).foregroundStyle(Brand.textMuted).padding(.top, 18)
                    }
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
                    onReview(Set(selectedActions.map(\.id)))
                }.buttonStyle(ControlPanelButtonStyle(primary: true))
                    .disabled(preview || selectedActions.isEmpty || store.isScanning || store.isCleaning)
            }.font(.system(size: 12)).padding(.horizontal, 20).frame(height: 64)
                .background(Brand.deepPanel)
        }.background(Brand.background).foregroundStyle(Brand.textPrimary)
            .task { if !preview { await control.refreshCapacity() } }
            .onChange(of: store.isCleaning) { _, running in
                if !running && !preview { Task { await control.refreshCapacity(force: true) } }
            }
            .onChange(of: store.scanStartedAt) { _, _ in selected.removeAll() }
    }

    private func effect(_ item: ScanItem) -> String {
        switch item.cleanMethod {
        case .trash: return "Trash · recoverable"
        case .tool: return "Tool · review elsewhere"
        default: return "Review only"
        }
    }
    private static let sampleActions: [ScanItem] = [
        ScanItem(url: URL(fileURLWithPath: "/Sample/Xcode build output"), allocatedSize: 6_400_000_000, categoryID: "developer", severity: .safe),
        ScanItem(url: URL(fileURLWithPath: "/Sample/Node package cache"), allocatedSize: 2_700_000_000, categoryID: "developer", severity: .review),
        ScanItem(url: URL(fileURLWithPath: "/Sample/Temporary browser data"), allocatedSize: 1_300_000_000, categoryID: "browsers", severity: .review)
    ]
}
