import SwiftUI
import AppKit

/// Bugs & Fixes — a system-health FIXER (Archetype C, centered hero).
/// Centered header + a blue→teal shield badge + an issue-list card + a gradient
/// "Fix All" footer. Owns its own on-demand HealthStore (NOT in the shared
/// ScannerRegistry, so it never pollutes Smart Scan totals). Every fix moves the
/// artifact to the Trash (recoverable); advice-only groups show "Review", never
/// "Fix".
struct HealthView: View {
    @Bindable var store: HealthStore
    @State private var didStart = false
    @State private var reviewGroup: HealthGroup?
    @State private var fixAllConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Health used to wear a centred header over the old purple
                // AmbientBackground, which made it read as a different app from
                // every other page. Same full-bleed hero as the rest now.
                PageHero(title: "Health", subtitle: subtitle) {
                    Button { store.rescan() } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(WhiteButtonStyle())
                    .disabled(store.isScanning)
                    if !store.isHealthy && !store.allFixable.isEmpty {
                        Button { fixAllConfirm = true } label: {
                            Label("Fix all", systemImage: "wrench.and.screwdriver.fill")
                        }
                        .buttonStyle(WhiteButtonStyle())
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    lastScanRow
                    ShieldBadge(healthy: store.isHealthy).frame(maxWidth: .infinity)
                    content
                }
                .heroPageContent()
            }
        }
        .task {
            guard !didStart else { return }
            didStart = true
            store.scanIfNeeded()
        }
        .sheet(item: $reviewGroup) { group in
            HealthReviewSheet(group: group,
                              canFix: group.actionable && !group.fixableItems.isEmpty,
                              onFix: { Task { await store.fix(group: group); reviewGroup = nil } },
                              onClose: { reviewGroup = nil })
        }
        .sheet(isPresented: $fixAllConfirm) {
            FixAllSheet(items: store.allFixable,
                        onConfirm: { Task { await store.fix(items: store.allFixable); fixAllConfirm = false } },
                        onCancel: { fixAllConfirm = false })
        }
        .alert(item: Binding(get: { store.lastResult }, set: { store.lastResult = $0 })) { result in
            Alert(title: Text(result.ok ? "Done" : "Finished with issues"),
                  message: Text(resultMessage(result)),
                  dismissButton: .default(Text("OK")))
        }
    }

    private var subtitle: String {
        if store.isScanning { return "Checking your Mac for issues that can be safely fixed." }
        if store.isHealthy { return "Everything looks great — nothing needs fixing right now." }
        let n = store.totalIssues
        return "We found \(n) issue\(n == 1 ? "" : "s") that can be safely reviewed and fixed."
    }

    // MARK: - Last scan

    /// Rescan now lives in the hero, so this is just the quiet status line.
    private var lastScanRow: some View {
        HStack(spacing: 6) {
            if store.isScanning { ProgressView().controlSize(.small) }
            Text(store.isScanning ? "Checking…" : "Last checked \(lastScanText)")
                .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
            Spacer()
        }
    }

    private var lastScanText: String {
        guard let d = store.lastScanAt else { return "Not yet" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: d, relativeTo: Date())
    }

    // MARK: - Content (scanning / healthy / list)

    @ViewBuilder private var content: some View {
        if store.isScanning && store.visibleGroups.isEmpty {
            scanningState
        } else if store.isHealthy {
            healthyState
        } else {
            issueListCard
            footer
        }
    }

    private var scanningState: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(store.progressText.isEmpty ? "Checking your Mac's health…" : store.progressText)
                .font(.system(size: 13)).foregroundStyle(Brand.textMuted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 50)
    }

    private var healthyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 34)).foregroundStyle(Brand.safeCyan)
            Text("Your Mac is healthy — nothing to fix right now.")
                .font(.system(size: 14, weight: .medium)).foregroundStyle(Brand.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    // MARK: - Issue list

    private var issueListCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.visibleGroups.enumerated()), id: \.element.id) { idx, group in
                HealthIssueRow(
                    group: group,
                    onPrimary: {
                        if group.actionable && !group.fixableItems.isEmpty {
                            Task { await store.fix(group: group) }
                        } else {
                            reviewGroup = group
                        }
                    },
                    onOpen: { reviewGroup = group }
                )
                if idx < store.visibleGroups.count - 1 {
                    Divider().overlay(Brand.border)
                }
            }
        }
        .background(CardBackground())
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 12) {
            Button { fixAllConfirm = true } label: {
                Label(fixAllLabel, systemImage: "sparkles")
            }
            .buttonStyle(BrandButtonStyle(enabled: !store.allFixable.isEmpty, prominent: true))
            .disabled(store.allFixable.isEmpty)

            Text("Safe to fix. You can review details before any changes are made.")
                .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                .multilineTextAlignment(.center)
        }
    }

    private var fixAllLabel: String {
        let n = store.allFixable.count
        return n > 0 ? "Fix All (\(n) issue\(n == 1 ? "" : "s"))" : "Fix All"
    }

    private func resultMessage(_ r: HealthStore.FixResult) -> String {
        var parts: [String] = []
        if r.trashed > 0 { parts.append("Moved \(r.trashed) item\(r.trashed == 1 ? "" : "s") to the Trash (\(Fmt.size(r.bytes)), recoverable).") }
        if r.failed > 0 { parts.append("\(r.failed) could not be fixed.") }
        if let first = r.errors.first { parts.append(first) }
        if parts.isEmpty { parts.append("Nothing to fix.") }
        return parts.joined(separator: "\n")
    }
}

// MARK: - Shield badge hero

/// Large blue→teal shield-with-checkmark over the faint mountain illustration,
/// with a soft glow ring behind it. Mirrors DashboardView.hero chrome.
private struct ShieldBadge: View {
    var healthy: Bool

    var body: some View {
        ZStack {
            // Soft radial glow ring.
            Circle()
                .fill(RadialGradient(colors: [Brand.blue.opacity(0.28), Brand.cyan.opacity(0.10), .clear],
                                     center: .center, startRadius: 8, endRadius: 110))
                .frame(width: 220, height: 220)
            Circle()
                .stroke(Brand.brand, lineWidth: 2)
                .opacity(0.35)
                .frame(width: 132, height: 132)
            Image(systemName: healthy ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(Brand.brand)
                .shadow(color: Brand.blue.opacity(0.35), radius: 14, y: 6)
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                CardBackground(radius: Brand.rHero, level: .high)
                RoundedRectangle(cornerRadius: Brand.rHero, style: .continuous).fill(Brand.brandWash)
                HeroIllustration()
                    .clipShape(RoundedRectangle(cornerRadius: Brand.rHero, style: .continuous))
            }
        )
    }
}

// MARK: - Issue row

private struct HealthIssueRow: View {
    let group: HealthGroup
    var onPrimary: () -> Void
    var onOpen: () -> Void

    @State private var hovering = false

    private var isFix: Bool { group.actionable && !group.fixableItems.isEmpty }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Brand.blue.opacity(0.12)).frame(width: 38, height: 38)
                Image(systemName: group.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Brand.blue)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(group.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Brand.textPrimary)
                Text(group.subtitle).font(.system(size: 12)).foregroundStyle(Brand.textMuted).lineLimit(2)
            }
            Spacer(minLength: 12)
            Text("\(group.count) item\(group.count == 1 ? "" : "s")")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.textSecondary)
            if isFix {
                Button("Fix") { onPrimary() }.buttonStyle(BrandButtonStyle())
            } else {
                Button("Review") { onPrimary() }.buttonStyle(GhostButtonStyle())
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(hovering ? Brand.surfaceSubtle : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onOpen() }
    }
}

// MARK: - Review sheet (per group)

/// Lists the underlying issues so the user can inspect each path (Reveal in
/// Finder) before any change. Actionable groups also offer a "Fix" here.
private struct HealthReviewSheet: View {
    let group: HealthGroup
    var canFix: Bool
    var onFix: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                IconTile(systemImage: group.systemImage, tint: Brand.blue, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.title).font(.system(size: 16, weight: .bold)).foregroundStyle(Brand.textPrimary)
                    Text("\(group.count) item\(group.count == 1 ? "" : "s")")
                        .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                }
                Spacer()
            }
            .padding(18)
            Divider().overlay(Brand.border)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(group.items) { issue in
                        HealthDetailRow(issue: issue)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
            }
            .frame(maxHeight: 360)

            Divider().overlay(Brand.border)
            HStack(spacing: 10) {
                if !canFix {
                    Label("Advice only — Cairn won't change these for you.", systemImage: "info.circle")
                        .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                }
                Spacer()
                Button("Close") { onClose() }.buttonStyle(GhostButtonStyle())
                if canFix {
                    Button("Move to Trash") { onFix() }.buttonStyle(BrandButtonStyle())
                }
            }
            .padding(16)
        }
        .frame(width: 520)
        .background(Brand.surfaceElevated)
    }
}

private struct HealthDetailRow: View {
    let issue: HealthIssue
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: issue.fixable ? "trash" : "info.circle")
                .font(.system(size: 13)).foregroundStyle(issue.fixable ? Brand.blue : Brand.textMuted)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(issue.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.textPrimary).lineLimit(1)
                Text(issue.detail).font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                    .lineLimit(2).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if let url = issue.url {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0.4)
                .help("Reveal in Finder")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Brand.surfaceSubtle : .clear))
        .onHover { hovering = $0 }
    }
}

// MARK: - Fix All confirm sheet

private struct FixAllSheet: View {
    let items: [HealthIssue]
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                IconTile(systemImage: "sparkles", tint: Brand.blue, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Fix All").font(.system(size: 16, weight: .bold)).foregroundStyle(Brand.textPrimary)
                    Text("\(items.count) item\(items.count == 1 ? "" : "s") will move to the Trash (recoverable)")
                        .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                }
                Spacer()
            }
            .padding(18)
            Divider().overlay(Brand.border)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(items) { issue in HealthDetailRow(issue: issue) }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
            }
            .frame(maxHeight: 320)

            Divider().overlay(Brand.border)
            HStack {
                Label("Only safely-fixable items are included. Advice-only issues are left untouched.",
                      systemImage: "checkmark.shield")
                    .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                Spacer()
                Button("Cancel") { onCancel() }.buttonStyle(GhostButtonStyle())
                Button("Move to Trash") { onConfirm() }.buttonStyle(BrandButtonStyle(enabled: !items.isEmpty)).disabled(items.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 520)
        .background(Brand.surfaceElevated)
    }
}
