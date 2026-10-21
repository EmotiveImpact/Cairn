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
        CairnDialog(title: cleaning ? "Freeing up space…" : "Review cleanup",
                    subtitle: "\(runnable.count) \(runnable.count == 1 ? "item" : "items") selected", wide: true, height: 620) {
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
                        ForEach(runnable) { row($0) }
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
                Text(Fmt.size(freedNow)).font(.system(size: 40, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Brand.safeCyan)
            }
            if toTrash > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TO TRASH").eyebrow()
                    Text(Fmt.size(toTrash)).font(.system(size: 24, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Brand.textSecondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("AVAILABLE NOW").eyebrow()
                Text(freeBytes.map(Fmt.size) ?? "…").font(.system(size: 18, weight: .medium)).monospacedDigit()
                if let freeBytes, freedNow > 0 {
                    Text("about \(Fmt.size(freeBytes + freedNow)) after").font(.system(size: 11)).foregroundStyle(Brand.safeCyan)
                }
            }
        }
    }

    private func row(_ item: ScanItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.url.lastPathComponent).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(item.resolvedURL.path).font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                if case .tool(let command) = item.cleanMethod {
                    Text(command.display).font(.system(size: 11, design: .monospaced)).foregroundStyle(Brand.textSecondary)
                }
            }
            Spacer(minLength: 8)
            actionBadge(item)
            Text(item.allocatedSize > 0 ? Fmt.size(item.allocatedSize) : "—")
                .font(.system(size: 12, weight: .medium)).monospacedDigit().frame(width: 72, alignment: .trailing)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.separator).frame(height: 0.5) }
    }

    private func actionBadge(_ item: ScanItem) -> some View {
        let (text, color): (String, Color) = {
            switch item.cleanMethod {
            case .tool: return ("Run command", Brand.purple)
            case .emptyTrash: return ("Delete", Brand.safeCyan)
            case .trash: return freesNow(item) ? ("Delete", Brand.safeCyan) : ("Trash", Brand.textSecondary)
            case .adviceOnly: return ("Advice", Brand.textMuted)
            }
        }()
        return Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.13)))
    }

    @ViewBuilder private var warnings: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !runningBlockers.isEmpty {
                warn(Brand.amber, "lock.fill", "Quit first: \(runningBlockers.joined(separator: ", "))",
                     "Their caches are skipped while they are running.")
            }
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
        HStack {
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
