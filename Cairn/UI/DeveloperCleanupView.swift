import SwiftUI

/// Developer Cleanup — Archetype A: tool table (real app icons) + right donut
/// summary panel with "why it's safe" and the clean CTA.
struct DeveloperCleanupView: View {
    let store: ScanStore
    var proEnabled: Bool = false
    var onReview: () -> Void
    var onUpgrade: () -> Void = {}

    private var buckets: [ScanStore.Bucket] {
        store.developerBuckets.filter { !$0.items.isEmpty }.sorted { $0.totalSize > $1.totalSize }
    }
    /// Items that reclaim via a tool's own command (the paid wedge).
    private var hasToolCleans: Bool {
        store.developerBuckets.contains { $0.items.contains { $0.cleanMethod.isPaid } }
    }
    private var total: Int64 { store.developerBuckets.reduce(0) { $0 + $1.totalSize } }
    private var selected: Int64 { store.developerBuckets.reduce(0) { $0 + $1.selectedSize } }

    private let palette: [Color] = [Brand.blue, Brand.cyan, Brand.purple, Color(hex: 0x2496ED), Color(hex: 0xF05133), Brand.amber, Brand.safeCyan]
    private var slices: [DonutChart.Slice] {
        buckets.prefix(6).enumerated().map { i, b in
            DonutChart.Slice(label: b.info.title, value: b.totalSize, color: palette[i % palette.count])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHero(title: "Developer Cleanup",
                     subtitle: "Build artefacts, package caches and simulator data — rebuildable by design.",
                     progress: total > 0 ? 1 : 0.02,
                     value: total,
                     caption: "Reclaimable",
                     footnote: selected > 0 ? "\(Fmt.size(selected)) selected" : "\(buckets.count) tools") {
                Button { for b in store.developerBuckets { store.selectAllSafe(in: b.id) } } label: {
                    Label("Select all safe", systemImage: "checklist")
                }.buttonStyle(WhiteButtonStyle())
                Button { store.rescan() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                    .buttonStyle(WhiteButtonStyle())
            }
            HStack(alignment: .top, spacing: 16) {
                tableCard.frame(maxWidth: .infinity)
                summaryPanel.frame(width: 340)
            }
            .heroPageContent()
        }
    }

    private var tableCard: some View {
        VStack(spacing: 0) {
            HStack {
                Button { for b in store.developerBuckets { store.selectAllSafe(in: b.id) } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checklist").font(.system(size: 13)).foregroundStyle(Brand.blue)
                        Text("Select All Safe").font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.textSecondary)
                    }
                }.buttonStyle(.plain)
                Spacer()
                Text("Size").font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.textMuted).frame(width: Brand.colSize, alignment: .trailing)
                Text("Safe to Delete").font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.textMuted).frame(width: 96, alignment: .center)
                Spacer().frame(width: 22)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider().overlay(Brand.border)
            if buckets.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(buckets) { b in
                            DevToolRow(store: store, bucketID: b.id, proEnabled: proEnabled)
                                // Rows rise in as they're found instead of appearing
                                // in a block. Pairs with the batched scan stream.
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            Divider().overlay(Brand.border).padding(.leading, 16)
                        }
                    }
                    .animation(.easeOut(duration: 0.28), value: buckets.count)
                }
            }
        }
        .background(CardBackground())
    }

    @ViewBuilder private var empty: some View {
        if store.isScanning {
            LoadingState(label: "Scanning developer caches…")
        } else {
            EmptyState(icon: "checkmark.seal.fill", title: "No developer junk found",
                       caption: "Your tools are tidy — nothing to reclaim right now.", tint: Brand.safeCyan)
        }
    }

    private var summaryPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reclaimable Space").font(.system(size: 13)).foregroundStyle(Brand.textSecondary)
                CountingSize(bytes: total, size: 34, weight: .bold, color: Brand.blue)
                Text(selected > 0 ? "Selected: \(Fmt.size(selected))" : "Select items to clean")
                    .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading).cairnCard(16)

            VStack(spacing: 14) {
                DonutChart(slices: slices, centerTop: "total", centerValue: Fmt.size(total))
                    .frame(height: 150)
                DonutLegend(slices: slices)
            }.cairnCard(16)

            if hasToolCleans { commandPanel }

            whySafe

            Button { onReview() } label: {
                VStack(spacing: 2) {
                    Label("Clean Developer Junk", systemImage: "sparkles")
                    if selected > 0 { Text("\(Fmt.size(selected)) will be reclaimed").font(.system(size: 10)).opacity(0.85) }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(BrandButtonStyle(enabled: selected > 0))
            .disabled(selected == 0)
        }
    }

    /// The correct-command surface — Cairn's core differentiator made visible.
    /// Lists the ACTUAL commands the scanners found for this Mac, each with the
    /// reason deleting the folder by hand would be wrong, plus the honest split of
    /// what free can clean vs what needs Pro.
    private var commandPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "terminal.fill").font(.system(size: 12)).foregroundStyle(Brand.deepBlue)
                Text("Correct-command cleans").font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.textPrimary)
            }

            ForEach(toolCleans) { c in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(c.app).font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.textPrimary)
                        if c.destroysData {
                            StatusPill("DESTRUCTIVE", color: Brand.danger)
                        } else if !proEnabled {
                            StatusPill("PRO", color: Brand.purple)
                        }
                        Spacer(minLength: 0)
                        Text(Fmt.size(c.bytes)).font(.system(size: 11, weight: .semibold))
                            .monospacedDigit().foregroundStyle(Brand.textSecondary)
                    }
                    Text(c.display)
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(Brand.deepBlue)
                        .lineLimit(1).truncationMode(.middle)
                        .padding(.horizontal, 6).padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Brand.blue.opacity(0.08)))
                        .textSelection(.enabled)
                    Text(c.why).font(.system(size: 9.5)).foregroundStyle(Brand.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(9)
                .background(RoundedRectangle(cornerRadius: Brand.rSm, style: .continuous).fill(Brand.surfaceSubtle)
                    .overlay(RoundedRectangle(cornerRadius: Brand.rSm, style: .continuous).stroke(Brand.border, lineWidth: 1)))
            }

            if !proEnabled, paidBytes > 0 {
                VStack(alignment: .leading, spacing: 7) {
                    Text("\(Fmt.size(paidBytes)) needs Pro")
                        .font(.system(size: 11.5, weight: .bold)).foregroundStyle(Brand.textPrimary)
                    Text(freeBytes > 0
                         ? "Free cleans the other \(Fmt.size(freeBytes)) to the Trash."
                         : "These caches only reclaim via their tool's own command.")
                        .font(.system(size: 10)).foregroundStyle(Brand.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { onUpgrade() } label: {
                        Text("Unlock Pro — \(LicenseConfig.price), yours forever").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BrandButtonStyle())
                }
                .padding(11)
                .background(RoundedRectangle(cornerRadius: Brand.rSm, style: .continuous).fill(Brand.purple.opacity(0.07))
                    .overlay(RoundedRectangle(cornerRadius: Brand.rSm, style: .continuous).stroke(Brand.purple.opacity(0.26), lineWidth: 1)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cairnCard(14)
    }

    /// One distinct tool command found on this Mac, with its reclaimable total.
    private struct ToolClean: Identifiable {
        let id: String            // the command string — dedupes repeats (e.g. git gc per repo)
        let app: String
        let display: String
        let why: String
        let bytes: Int64
        let destroysData: Bool
    }

    /// Group every `.tool` item by its command so 45 `git gc` repos read as one row.
    private var toolCleans: [ToolClean] {
        var byCommand: [String: ToolClean] = [:]
        for bucket in store.developerBuckets {
            for item in bucket.items {
                guard case let .tool(cmd) = item.cleanMethod else { continue }
                let key = cmd.tool   // group by tool, not full args (git gc has a per-repo path)
                let existing = byCommand[key]
                byCommand[key] = ToolClean(
                    id: key,
                    app: Self.appName(for: cmd.tool),
                    display: existing?.display ?? cmd.display,
                    why: Self.rationale(for: cmd.tool),
                    bytes: (existing?.bytes ?? 0) + item.allocatedSize,
                    destroysData: (existing?.destroysData ?? false) || cmd.destroysData
                )
            }
        }
        return byCommand.values.sorted { $0.bytes > $1.bytes }
    }

    private var paidBytes: Int64 {
        store.developerBuckets.flatMap(\.items).filter { $0.cleanMethod.isPaid }
            .reduce(0) { $0 + $1.allocatedSize }
    }
    private var freeBytes: Int64 { max(0, total - paidBytes) }

    private static func appName(for tool: String) -> String {
        switch tool {
        case "docker": return "Docker"
        case "git": return "Git"
        case "xcrun": return "Simulators"
        case "conda": return "Conda"
        case "tmutil": return "Time Machine"
        case "pnpm": return "pnpm"
        case "npm": return "npm"
        case "go": return "Go"
        case "cargo": return "Cargo"
        case "brew": return "Homebrew"
        default: return tool.capitalized
        }
    }

    /// Why the folder-delete is wrong — the actual value Cairn is selling.
    private static func rationale(for tool: String) -> String {
        switch tool {
        case "docker":
            return "Deleting the Docker.raw folder corrupts the daemon. This asks Docker to reclaim it properly."
        case "git":
            return "Repacks loose objects safely. Never touches your working tree or history."
        case "xcrun":
            return "Removes simulator devices for SDKs you no longer have. Deleting the folder leaves Xcode confused."
        case "conda":
            return "Clears package tarballs and index caches without breaking your environments."
        case "tmutil":
            return "Local APFS snapshots must be released by macOS — they aren't files you can delete."
        case "brew":
            return "Removes downloaded bottles Homebrew can re-fetch on demand."
        default:
            return "Reclaimed through \(tool)'s own command so its index stays consistent."
        }
    }

    private var whySafe: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill").foregroundStyle(Brand.safeCyan).font(.system(size: 13))
                Text("Why it's safe").font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.textPrimary)
            }
            ForEach([
                "These files are rebuildable and not needed by macOS.",
                "App data, documents, and source code are never touched.",
                "You can deselect anything you want to keep.",
                "Nothing is deleted without your confirmation.",
            ], id: \.self) { line in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(Brand.safeCyan)
                    Text(line).font(.system(size: 11)).foregroundStyle(Brand.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).cairnCard(16)
    }
}

/// One expandable tool row with a real icon + severity pill.
struct DevToolRow: View {
    let store: ScanStore
    let bucketID: String
    var proEnabled: Bool = false
    @State private var expanded = false

    private var bucket: ScanStore.Bucket? { store.buckets.first { $0.id == bucketID } }
    private var toolCommand: ToolCommand? {
        for item in bucket?.items ?? [] { if case let .tool(cmd) = item.cleanMethod { return cmd } }
        return nil
    }

    var body: some View {
        if let bucket {
            let worst = bucket.items.map { $0.severity }.max() ?? .safe
            VStack(spacing: 0) {
                Button { withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() } } label: {
                    HStack(spacing: 12) {
                        ToolIcon.forCategory(bucket.id, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bucket.info.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Brand.textPrimary)
                            HStack(spacing: 6) {
                                Text(bucket.info.subtitle).font(.system(size: 11)).foregroundStyle(Brand.textMuted).lineLimit(1)
                                if let cmd = toolCommand { toolPill(cmd) }
                            }
                        }
                        Spacer()
                        Text(Fmt.size(bucket.totalSize)).font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.textSecondary)
                            .frame(width: Brand.colSize, alignment: .trailing)
                        pill(worst).frame(width: 96, alignment: .center)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.textMuted)
                            .rotationEffect(.degrees(expanded ? 90 : 0)).frame(width: 22)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)

                if expanded {
                    Divider().overlay(Brand.border).padding(.leading, 16)
                    HStack(spacing: 8) {
                        Button("Select safe") { store.selectAllSafe(in: bucket.id) }.buttonStyle(GhostButtonStyle())
                        Button("None") { store.selectNone(in: bucket.id) }.buttonStyle(GhostButtonStyle())
                        Spacer()
                    }.padding(.horizontal, 14).padding(.vertical, 8)
                    LazyVStack(spacing: 2) {
                        ForEach(bucket.items) { item in ItemRow(store: store, item: item) }
                    }.padding(.horizontal, 6).padding(.bottom, 8)
                }
            }
        }
    }

    /// A "runs <cmd>" (Pro/trial) or locked "PRO" pill for tool-command cleans.
    private func toolPill(_ cmd: ToolCommand) -> some View {
        HStack(spacing: 4) {
            Image(systemName: proEnabled ? "terminal" : "lock.fill").font(.system(size: 9, weight: .bold))
            Text(proEnabled ? cmd.display : "PRO · \(cmd.tool)").font(.system(size: 10, weight: .bold)).lineLimit(1)
        }
        .foregroundStyle(Brand.purple)
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Capsule().fill(Brand.purple.opacity(0.12)))
        .help(proEnabled ? "Reclaims via: \(cmd.display)" : "Pro runs: \(cmd.display)")
    }

    private func pill(_ s: Severity) -> some View { StatusPill(severity: s) }
}
