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

    private var items: [ScanItem] { store.selectedItems() }
    private var total: Int64 { items.reduce(0) { $0 + $1.allocatedSize } }
    private var runningBlockers: [String] {
        let ids = items.flatMap { $0.requiresQuitBundleIDs }
        return RunningApps.displayNames(for: RunningApps.running(amongst: Array(Set(ids))))
    }
    private var paidItems: [ScanItem] { items.filter { $0.cleanMethod.isPaid } }
    private var paidTotal: Int64 { paidItems.reduce(0) { $0 + $1.allocatedSize } }
    /// What a clean will ACTUALLY reclaim: everything for Pro, free-method items
    /// only otherwise (tool cleans are skipped without Pro).
    private var effectiveTotal: Int64 { proEnabled ? total : total - paidTotal }
    private var destructiveItems: [ScanItem] {
        items.filter { if case .tool(let c) = $0.cleanMethod { return c.destroysData } else { return false } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Brand.border)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(items) { item in
                        HStack(spacing: 10) {
                            SeverityDot(severity: item.severity)
                            Text(item.url.lastPathComponent).font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Brand.textPrimary).lineLimit(1)
                            if item.cleanMethod.isPaid { Text("via tool").font(.system(size: 10)).foregroundStyle(Brand.purple) }
                            if case .emptyTrash = item.cleanMethod { Text("permanent").font(.system(size: 10, weight: .semibold)).foregroundStyle(Brand.danger) }
                            Spacer()
                            Text(Fmt.size(item.allocatedSize)).font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 6)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 280)

            Divider().overlay(Brand.border)
            warnings
            footer
        }
        .frame(width: 560)
        .background(Brand.surfaceElevated)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Review & Clean").font(.system(size: 17, weight: .bold)).foregroundStyle(Brand.textPrimary)
            Text("\(items.count) items · \(Fmt.size(total)) — moved to the Trash (recoverable) unless noted.")
                .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
        }
        .padding(16)
    }

    @ViewBuilder private var warnings: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !runningBlockers.isEmpty {
                warn(Brand.amber, "lock.fill", "Quit first: \(runningBlockers.joined(separator: ", "))",
                     "These apps own selected caches — cleaning while they run can corrupt state.")
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
                .toggleStyle(.checkbox)
            }
            HStack(spacing: 6) {
                Image(systemName: "internaldrive").foregroundStyle(Brand.textMuted).font(.system(size: 11))
                Text("Free on this volume after Empty Trash: \(Fmt.size(Volumes.homeFree() + total))")
                    .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }.buttonStyle(GhostButtonStyle())
            Spacer()
            if cleaning {
                ProgressView().controlSize(.small)
            }
            if !proEnabled && paidTotal > 0 {
                Button { onUpgrade(); dismiss() } label: { Text("Unlock \(Fmt.size(paidTotal)) with Pro →") }
                    .buttonStyle(GhostButtonStyle())
            }
            Button {
                Task { await runClean() }
            } label: {
                Text(cleaning ? "Cleaning…" : "Clean \(Fmt.size(effectiveTotal))")
            }
            .buttonStyle(BrandButtonStyle(enabled: canClean))
            .disabled(!canClean)
        }
        .padding(16)
    }

    private var canClean: Bool {
        !cleaning && !items.isEmpty && effectiveTotal > 0 && (destructiveItems.isEmpty || confirmDestructive)
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
