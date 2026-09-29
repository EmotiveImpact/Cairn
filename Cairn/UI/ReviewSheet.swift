import SwiftUI

/// Mandatory dry-run review between scan and clean (SPEC §4.4 / §5). Shows exact
/// items, per-volume free space, quit-first warnings, and Pro gating for
/// tool-mediated cleans.
struct ReviewSheet: View {
    let store: ScanStore
    let proEnabled: Bool
    var onDone: (ScanStore.CleanSummary) -> Void
    var onUpgrade: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    @State private var cleaning = false
    @State private var confirmDestructive = false
    @State private var destructiveConfirmText = ""

    @State private var items: [ScanItem] = []
    @State private var freeBytes: Int64?
    private var total: Int64 { items.reduce(0) { $0 + $1.allocatedSize } }
    private var runningBlockers: [String] {
        let ids = items.flatMap { $0.requiresQuitBundleIDs }
        return RunningApps.displayNames(for: RunningApps.running(amongst: Array(Set(ids))))
    }
    private var paidItems: [ScanItem] { items.filter { $0.cleanMethod.isPaid } }
    private var paidTotal: Int64 { paidItems.reduce(0) { $0 + $1.allocatedSize } }
    /// Estimated size of eligible inputs, never a promise of released capacity.
    private var effectiveTotal: Int64 { proEnabled ? total : total - paidTotal }
    private var destructiveItems: [ScanItem] {
        items.filter { if case .tool(let c) = $0.cleanMethod { return c.destroysData } else { return false } }
    }

    var body: some View {
        CairnDialog(title: cleaning ? "Cleanup in progress" : "Review cleanup", subtitle: "\(items.count) items · about \(Fmt.size(total)) affected. Trash items can be restored while present; tool actions cannot.", height: 540) {
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
                    warnings
                }
            }
        } actions: { footer }
        .interactiveDismissDisabled(cleaning)
        .task { items = store.selectedItems(); freeBytes = await Task.detached { Volumes.homeFree() }.value }
    }

    @ViewBuilder private var warnings: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !runningBlockers.isEmpty {
                warn(Brand.amber, "lock.fill", "Quit first: \(runningBlockers.joined(separator: ", "))",
                     "Cairn will skip their caches while they are running. Close the apps and retry.")
            }
            if !paidItems.isEmpty && !proEnabled {
                warn(Brand.purple, "star.fill", "\(paidItems.count) items need Pro",
                     "Tool-run cleans (e.g. simctl, pnpm, docker) are a Pro feature. Free cleans the rest to Trash.")
            }
            if !destructiveItems.isEmpty {
                Toggle(isOn: $confirmDestructive) {
                    Text("I understand \(destructiveItems.count) destructive item(s) (e.g. docker volumes) can't be undone")
                        .font(.system(size: 11)).foregroundStyle(Brand.danger)
                }
                .toggleStyle(.checkbox).disabled(cleaning)
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
            if !proEnabled && paidTotal > 0 {
                Button { onUpgrade(); dismiss() } label: { Text("Unlock \(Fmt.size(paidTotal)) with Pro →") }
                    .buttonStyle(ControlPanelButtonStyle()).disabled(cleaning)
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
        !cleaning && !store.isScanning && !store.isCleaning && !items.isEmpty && effectiveTotal > 0 && (destructiveItems.isEmpty || confirmDestructive)
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
        let summary = await store.clean(items, proEnabled: proEnabled)
        cleaning = false
        onDone(summary)
        dismiss()
    }
}
