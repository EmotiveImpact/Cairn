import SwiftUI

/// Mandatory dry-run review between scan and clean (SPEC §4.4 / §5). Shows exact
/// items, per-volume free space and quit-first warnings. Unsupported legacy
/// tool actions remain visible for review but cannot enter execution.
struct ReviewSheet: View {
    let store: ScanStore
    let proEnabled: Bool
    var goalPlan: ReviewedSpacePlan? = nil
    var onDone: (ScanStore.CleanSummary) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var cleaning = false
    @State private var items: [ScanItem] = []
    @State private var freeBytes: Int64?
    private var total: Int64 { items.reduce(0) { $0 + $1.allocatedSize } }
    private var runningBlockers: [String] {
        let ids = items.flatMap { $0.requiresQuitBundleIDs }
        return RunningApps.displayNames(for: RunningApps.running(amongst: Array(Set(ids))))
    }
    private var unsupportedItems: [ScanItem] { items.filter { !$0.isActionable || $0.severity == .risky } }

    var body: some View {
        CairnDialog(title: cleaning ? "Cleanup in progress" : "Review cleanup", subtitle: "\(items.count) items · about \(Fmt.size(total)) in measured size estimates. Items moved to Trash remain there until emptied.", height: 540) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if cleaning { CairnStateView(kind: .scanning, title: "Applying reviewed actions", message: "Keep Cairn open. Each result will be recorded in Activity & Recovery.", compact: true) }
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text(item.url.lastPathComponent).font(.system(size: 13, weight: .medium)); Spacer(); Text(Fmt.size(item.allocatedSize)).font(.system(size: 12)).monospacedDigit() }
                            Text(item.resolvedURL.path).font(.system(size: 12)).foregroundStyle(Brand.textMuted).textSelection(.enabled)
                            if case .tool(let command) = item.cleanMethod { Text(command.display).font(.system(size: 12, design: .monospaced)).textSelection(.enabled) }
                            Divider()
                        }
                    }
                    if let goalPlan {
                        Text("Target: \(Fmt.size(goalPlan.target)) available · immediate reclaim credit: 0 bytes").font(.system(size: 12, weight: .medium))
                        Text(goalPlan.recoveryText).font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                        Text("Source identity, size and modification time are captured for this review. Changes to the source or scan settings require another review.").font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                    }
                    warnings
                }
            }
        } actions: { footer }
        .interactiveDismissDisabled(cleaning)
        .task { items = goalPlan?.items ?? store.selectedItems(); freeBytes = await Task.detached { Volumes.homeFree() }.value }
    }

    @ViewBuilder private var warnings: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !runningBlockers.isEmpty {
                warn(Brand.amber, "lock.fill", "Quit first: \(runningBlockers.joined(separator: ", "))",
                     "Cairn will skip their caches while they are running. Close the apps and retry.")
            }
            if !unsupportedItems.isEmpty {
                warn(Brand.amber, "info.circle", "\(unsupportedItems.count) review-only item(s)",
                     "Cairn will not run broad tool commands or remove protected data. Return to the results and select supported Trash actions.")
            }
            HStack(spacing: 6) {
                Image(systemName: "internaldrive").foregroundStyle(Brand.textMuted).font(.system(size: 11))
                Text("Available on this Mac now: \(freeBytes.map(Fmt.size) ?? "measuring…"). Moving files to Trash does not release their space.")
                    .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }.buttonStyle(ControlPanelButtonStyle()).keyboardShortcut(.cancelAction).disabled(cleaning)
            if cleaning {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await runClean() }
            } label: {
                Text(cleaning ? "Cleaning…" : "Run reviewed cleanup")
            }
            .buttonStyle(ControlPanelButtonStyle(primary: true))
            .disabled(!canClean)
        }
    }

    private var canClean: Bool {
        !cleaning && !store.isScanning && !store.isCleaning && !items.isEmpty && total > 0 && unsupportedItems.isEmpty
    }

    private func warn(_ color: Color, _ icon: String, _ title: String, _ sub: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color).font(.system(size: 12))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.textPrimary)
                Text(sub).font(.system(size: 11)).foregroundStyle(Brand.textMuted)
            }
        }
    }

    private func runClean() async {
        cleaning = true
        let summary = await store.clean(items, proEnabled: proEnabled, reviewedPlan: goalPlan)
        cleaning = false
        onDone(summary)
        dismiss()
    }
}
