import SwiftUI

/// Mandatory review between scan and clean (SPEC §4.4 / §5). Shows exact items,
/// what will happen to each one, quit-first warnings and how much space is freed
/// straight away under the chosen removal mode.
struct ReviewSheet: View {
    let store: ScanStore
    let proEnabled: Bool
    var goalPlan: ReviewedSpacePlan? = nil
    var onDone: (ScanStore.CleanSummary) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var cleaning = false
    @State private var items: [ScanItem] = []
    @State private var freeBytes: Int64?
    @State private var mode: RemovalMode = .smart

    private var runnable: [ScanItem] { items.filter { $0.isActionable && $0.severity != .risky } }
    private var skipped: [ScanItem] { items.filter { !$0.isActionable || $0.severity == .risky } }
    private var freedNow: Int64 { runnable.filter(freesNow).reduce(0) { $0 + $1.allocatedSize } }
    private var toTrash: Int64 { runnable.filter { !freesNow($0) }.reduce(0) { $0 + $1.allocatedSize } }
    private var hasPersonalFilesToDelete: Bool {
        mode == .delete && runnable.contains { !$0.isRegenerable && $0.cleanMethod == .trash }
    }
    private var runningBlockers: [String] {
        let ids = runnable.flatMap { $0.requiresQuitBundleIDs }
        return RunningApps.displayNames(for: RunningApps.running(amongst: Array(Set(ids))))
    }

    private func freesNow(_ item: ScanItem) -> Bool {
        switch item.cleanMethod {
        case .tool, .emptyTrash: return true
        case .trash: return mode.deletesImmediately(item)
        case .adviceOnly: return false
        }
    }

    var body: some View {
        CairnDialog(title: cleaning ? "Freeing up space…" : freedNow > 0 ? "Free \(Fmt.size(freedNow))" : "Review cleanup",
                    subtitle: "\(runnable.count) \(runnable.count == 1 ? "item" : "items") selected", wide: true, height: 640) {
            VStack(alignment: .leading, spacing: 18) {
                summary
                if !cleaning {
                    CairnSegmentedControl(label: "Removal", selection: $mode,
                                          options: RemovalMode.allCases.map { ($0.title, $0) })
                        .frame(width: 360)
                    Text(mode.detail).font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
                } else {
                    CairnStateView(kind: .scanning, title: "Cleaning", message: "Keep Cairn open. Every result is recorded in Activity.", compact: true)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groups, id: \.title) { group in
                            HStack(spacing: 11) {
                                BrandLogo.forCategory(group.id, size: 22)
                                Text(group.title).font(.system(size: 14, weight: .medium))
                                Spacer()
                                Text(Fmt.size(group.bytes))
                                    .font(.system(size: 13, weight: .medium)).monospacedDigit()
                            }.padding(.top, 16).padding(.bottom, 6)
                            ForEach(group.items) { row($0) }
                        }
                    }
                }
                warnings
            }
        } actions: { footer }
        .interactiveDismissDisabled(cleaning)
        .task { mode = AppSettings.shared.removalMode; items = goalPlan?.items ?? store.selectedItems(); freeBytes = await Task.detached { Volumes.homeFree() }.value }
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 28) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FREED NOW").eyebrow()
                Text(Fmt.size(freedNow)).font(.system(size: 48, weight: .light)).tracking(-1.4).monospacedDigit()
            }
            if toTrash > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TO TRASH").eyebrow()
                    Text(Fmt.size(toTrash)).font(.system(size: 26, weight: .light)).monospacedDigit()
                        .foregroundStyle(Brand.textSecondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("AVAILABLE NOW").eyebrow()
                Text(freeBytes.map(Fmt.size) ?? "…").font(.system(size: 20, weight: .light)).monospacedDigit()
                if let freeBytes, freedNow > 0 {
                    Text("about \(Fmt.size(freeBytes + freedNow)) after").font(.system(size: 11.5)).foregroundStyle(Brand.room)
                }
            }
        }
    }

    /// Items grouped by the tool or area that made them, largest group first.
    private struct ReviewGroup { let id: String; let title: String; let items: [ScanItem]; let bytes: Int64 }
    private var groups: [ReviewGroup] {
        Dictionary(grouping: runnable, by: \.categoryID).map { id, items in
            ReviewGroup(id: id, title: store.buckets.first { $0.id == id }?.info.title ?? id.capitalized,
                  items: items.sorted { $0.allocatedSize > $1.allocatedSize },
                  bytes: items.reduce(0) { $0 + $1.allocatedSize })
        }
        .sorted { $0.bytes > $1.bytes }
    }

    private func row(_ item: ScanItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.url.lastPathComponent).font(.system(size: 12.5)).foregroundStyle(Brand.textSecondary).lineLimit(1)
                Text(detail(item)).font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    .help(item.resolvedURL.path)
            }
            Spacer(minLength: 8)
            statusPill(item)
            Text(item.allocatedSize > 0 ? Fmt.size(item.allocatedSize) : "—")
                .font(.system(size: 12)).foregroundStyle(Brand.textSecondary).monospacedDigit().frame(width: 72, alignment: .trailing)
        }
        .padding(.vertical, 8).padding(.leading, 39)
        .overlay(alignment: .top) { Rectangle().fill(Brand.separator).frame(height: 0.5) }
    }

    /// One short line: the tool's own command, where it goes, or the path.
    private func detail(_ item: ScanItem) -> String {
        if case .tool(let command) = item.cleanMethod { return "Cleaned by the tool: \(command.display)" }
        if !freesNow(item), item.cleanMethod == .trash { return "Moves to Trash · \(item.resolvedURL.path)" }
        return item.resolvedURL.path
    }

    /// Three states only: Ready, Close app first, Needs you.
    private func statusPill(_ item: ScanItem) -> some View {
        let running = RunningApps.displayNames(for: RunningApps.running(amongst: item.requiresQuitBundleIDs))
        let (text, color): (String, Color) = {
            if let app = running.first { return ("Close \(app) first", Brand.amber) }
            if !item.isRegenerable || item.severity != .safe { return ("Needs you", Brand.textSecondary) }
            return ("Ready", Brand.room)
        }()
        let quiet = color == Brand.textSecondary
        return Text(text).font(.system(size: 11.5)).lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(color.opacity(quiet ? 0.25 : 0.32), lineWidth: 0.75))
    }

    @ViewBuilder private var warnings: some View {
        VStack(alignment: .leading, spacing: 8) {
            if hasPersonalFilesToDelete {
                warn(Brand.amber, "exclamationmark.triangle.fill", "Personal files will be deleted permanently",
                     "Delete now skips the Trash for everything. Choose Smart to send personal files to Trash instead.")
            }
            if !skipped.isEmpty {
                warn(Brand.textMuted, "info.circle", "\(skipped.count) advice-only \(skipped.count == 1 ? "item" : "items") will be skipped", "")
            }
            if let goalPlan {
                Text("Target: \(Fmt.size(goalPlan.target)) available").font(.system(size: 12, weight: .medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.shield").foregroundStyle(Brand.room).font(.system(size: 13))
                Text(runningBlockers.isEmpty
                     ? "Your code, settings and AI chats are never listed. Cairn checks each item again just before removing it."
                     : "Items from \(runningBlockers.joined(separator: ", ")) are skipped while it is open. Everything else goes ahead.")
                    .font(.system(size: 11.5)).foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: 400, alignment: .leading)
            Spacer(minLength: 8)
            Button("Cancel") { dismiss() }.buttonStyle(ControlPanelButtonStyle()).keyboardShortcut(.cancelAction).disabled(cleaning)
            if cleaning { ProgressView().controlSize(.small) }
            Button {
                Task { await runClean() }
            } label: {
                Text(cleaning ? "Cleaning…" : freedNow > 0 ? "Free \(Fmt.size(freedNow))" : "Move to Trash")
                    .frame(minWidth: 120)
            }
            .buttonStyle(ControlPanelButtonStyle(primary: true))
            .keyboardShortcut(.defaultAction)
            .disabled(!canClean)
        }
    }

    private var canClean: Bool {
        !cleaning && !store.isScanning && !store.isCleaning && !runnable.isEmpty
    }

    private func warn(_ color: Color, _ icon: String, _ title: String, _ sub: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color).font(.system(size: 12))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.textPrimary)
                if !sub.isEmpty { Text(sub).font(.system(size: 11)).foregroundStyle(Brand.textMuted) }
            }
        }
    }

    private func runClean() async {
        cleaning = true
        if AppSettings.shared.removalMode != mode, goalPlan == nil { AppSettings.shared.removalMode = mode }
        let summary = await store.clean(items, proEnabled: proEnabled, reviewedPlan: goalPlan, removal: mode)
        cleaning = false
        onDone(summary)
        dismiss()
    }
}
