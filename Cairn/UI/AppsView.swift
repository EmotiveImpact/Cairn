import SwiftUI
import AppKit

/// Apps / Uninstaller — Archetype A: a sortable apps table with real bundle
/// icons on the left, and a sticky "What will be removed" summary panel on the
/// right. Owns its own on-demand `AppInventoryStore` (never registered in the
/// shared scanner registry). Every removal goes to the Trash (recoverable).
struct AppsView: View {
    @Bindable var store: AppInventoryStore
    /// Optional hook so the shell can flash a celebration overlay; defaults to a
    /// no-op so the view can construct itself with no required args.
    var onUninstalled: (AppInventoryStore.UninstallSummary) -> Void = { _ in }

    enum Chip: String, CaseIterable {
        case all = "All Apps", large = "Large Apps", unused = "Unused", intel = "Intel Apps", leftover = "Leftover Files"
        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .large: return "arrow.up.right.square"
            case .unused: return "clock"
            case .intel: return "cpu"
            case .leftover: return "doc.on.doc"
            }
        }
    }
    enum SortKey { case name, developer, size, lastOpened }

    @State private var chip: Chip = .all
    @State private var sortKey: SortKey = .size
    @State private var ascending = false
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            PageHero(title: "Apps",
                     subtitle: "Review installed apps. App support and personal data stay in place.",
                     progress: store.unusedReclaimable > 0 ? 1 : 0.02,
                     value: store.unusedReclaimable,
                     caption: "Reclaimable",
                     footnote: store.isScanning ? "Scanning…" : "\(store.unusedCount) unused") {
                Button { store.rescan() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                    .buttonStyle(WhiteButtonStyle())
            }
            pageContent.heroPageContent()
        }
        .task { store.scanIfNeeded() }
        .sheet(isPresented: $confirming) {
            UninstallConfirmSheet(apps: store.selectedApps) {
                confirming = false
            } onConfirm: {
                confirming = false
                Task {
                    let summary = await store.uninstall(store.selectedApps)
                    onUninstalled(summary)
                }
            }
        }
    }

    private var pageContent: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                summaryCard
                filterChips
                table
            }
            .frame(maxWidth: .infinity)
            removalPanel.frame(width: 340)
        }
    }

    // MARK: - Derived data

    private var visible: [AppEntry] {
        var list = store.apps.filter { matches(chip, $0) }
        switch sortKey {
        case .name: list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .developer: list.sort { $0.developer.localizedCaseInsensitiveCompare($1.developer) == .orderedAscending }
        case .size: list.sort { $0.size < $1.size }
        case .lastOpened: list.sort { ($0.lastOpened ?? .distantPast) < ($1.lastOpened ?? .distantPast) }
        }
        return ascending ? list : list.reversed()
    }

    private func count(_ c: Chip) -> Int { store.apps.filter { matches(c, $0) }.count }

    private func matches(_ c: Chip, _ app: AppEntry) -> Bool {
        switch c {
        case .all: return true
        case .large: return app.isLarge
        case .unused: return app.isRemovable && app.isUnused
        case .intel: return app.isIntel
        case .leftover: return app.hasLeftovers
        }
    }

    // MARK: - Header

    // MARK: - Summary card (headline reclaimable for unused apps)

    private var summaryCard: some View {
        let unused = store.unusedReclaimable
        let split = Fmt.split(unused)
        return HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Brand.border, lineWidth: 6).frame(width: 64, height: 64)
                Circle()
                    .trim(from: 0, to: ringFraction)
                    .stroke(Brand.ring, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 64, height: 64)
                    .rotationEffect(.degrees(-90))
                IconTile(systemImage: "app.badge.checkmark", tint: Brand.blue, size: 38)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Reclaimable Space in Unused Apps")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Brand.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(split.value).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Brand.textGradient)
                    Text(split.unit).font(.system(size: 18, weight: .semibold)).foregroundStyle(Brand.textGradient)
                }
                Text("\(Fmt.size(unused)) · Across \(store.unusedCount) apps")
                    .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
            }
            Spacer()
        }
        .cairnCard(18)
    }

    /// Fraction of total app footprint that's reclaimable from unused apps.
    private var ringFraction: CGFloat {
        let total = store.apps.filter { $0.isRemovable }.reduce(Int64(0)) { $0 + $1.totalSize }
        guard total > 0 else { return 0 }
        return max(0.02, min(1, CGFloat(store.unusedReclaimable) / CGFloat(total)))
    }

    // MARK: - Filter chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Chip.allCases, id: \.self) { c in
                    let on = chip == c
                    Button { chip = c } label: {
                        HStack(spacing: 6) {
                            Image(systemName: c.icon).font(.system(size: 11, weight: .semibold))
                            Text(c.rawValue).font(.system(size: 12, weight: .medium)).fixedSize()
                            Text("\(count(c))").font(.system(size: 11, weight: .semibold)).fixedSize()
                                .foregroundStyle(on ? Brand.blue : Brand.textMuted)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Capsule().fill(on ? Brand.blue.opacity(0.16) : Brand.surfaceSubtle))
                        }
                        .fixedSize()
                        .foregroundStyle(on ? Brand.blue : Brand.textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(on ? Brand.blue.opacity(0.10) : .clear)
                            .overlay(Capsule().stroke(on ? Brand.blue.opacity(0.3) : Brand.border, lineWidth: 1)))
                    }.buttonStyle(.plain).pointerCursor()
                }
            }
            .padding(.bottom, 2)
        }
    }

    // MARK: - Table

    private let colFont = Font.system(size: 11, weight: .semibold)

    private var table: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("").frame(width: 30)
                colHeader("Application", .name).frame(maxWidth: .infinity, alignment: .leading)
                colHeader("Developer", .developer).frame(width: 130, alignment: .leading)
                colHeader("Size", .size).frame(width: Brand.colSize, alignment: .trailing)
                colHeader("Last Opened", .lastOpened).frame(width: Brand.colDate, alignment: .trailing)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider().overlay(Brand.border)

            if visible.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visible) { app in
                            row(app)
                            Divider().overlay(Brand.border).padding(.leading, 14)
                        }
                    }
                }
            }

            Divider().overlay(Brand.border)
            HStack {
                Text("\(store.selectedCount) of \(store.removableCount) apps selected")
                    .font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
                Spacer()
                if store.selectedReclaimable > 0 {
                    Text(Fmt.size(store.selectedReclaimable)).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Brand.blue)
                }
            }
            .padding(14)
        }
        .background(CardBackground())
    }

    private func colHeader(_ title: String, _ key: SortKey) -> some View {
        Button { if sortKey == key { ascending.toggle() } else { sortKey = key; ascending = (key == .name || key == .developer) } } label: {
            HStack(spacing: 3) {
                Text(title).font(colFont).foregroundStyle(sortKey == key ? Brand.blue : Brand.textMuted)
                if sortKey == key {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down").font(.system(size: 8)).foregroundStyle(Brand.blue)
                }
            }
        }.buttonStyle(.plain).pointerCursor()
    }

    private func row(_ app: AppEntry) -> some View {
        HStack(spacing: 0) {
            Group {
                if !app.isRemovable {
                    Image(systemName: "lock.fill").font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                        .help("Protected app — Cairn will not remove its conversation or system data")
                } else {
                    Image(systemName: app.selected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 15)).foregroundStyle(app.selected ? Brand.blue : Brand.textMuted)
                        .contentShape(Rectangle())
                        .onTapGesture { store.toggle(app.id) }.pointerCursor()
                }
            }
            .frame(width: 30)

            HStack(spacing: 10) {
                FileIcon(url: app.url, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(app.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.textPrimary).lineLimit(1)
                        if !app.isRemovable { tag("Protected", Brand.textMuted) }
                        else if app.isIntel { tag("Intel", Brand.amber) }
                    }
                    if app.hasLeftovers {
                        Text("\(Fmt.size(app.componentsSize)) in associated data stays on your Mac")
                            .font(.system(size: 10)).foregroundStyle(Brand.textMuted).lineLimit(1)
                    } else {
                        Text("v\(app.version)").font(.system(size: 10)).foregroundStyle(Brand.textMuted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(app.developer).font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
                .lineLimit(1).frame(width: 130, alignment: .leading)
            Text(Fmt.size(app.size)).font(.system(size: 12, weight: .medium))
                .foregroundStyle(Brand.textSecondary).frame(width: Brand.colSize, alignment: .trailing)
            Text(lastOpenedText(app)).font(.system(size: 12))
                .foregroundStyle(app.isUnused ? Brand.amber : Brand.textMuted)
                .frame(width: Brand.colDate, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(app.selected ? Brand.blue.opacity(0.05) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { store.toggle(app.id) }.pointerCursor()
        .opacity(app.isRemovable ? 1 : 0.65)
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 9, weight: .bold)).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    @ViewBuilder private var emptyState: some View {
        if store.isScanning {
            LoadingState(label: "Scanning installed apps…")
        } else {
            EmptyState(icon: "app.dashed", title: "No apps match this filter", caption: "Try a different filter or rescan.")
        }
    }

    // MARK: - Right panel — "What will be removed"

    private var removalPanel: some View {
        let sel = store.selectedApps
        let bundle = sel.reduce(Int64(0)) { $0 + $1.size }
        let support = sel.reduce(Int64(0)) { $0 + $1.supportSize }
        let leftover = sel.reduce(Int64(0)) { $0 + $1.leftoverSize }
        let total = bundle

        return VStack(alignment: .leading, spacing: 16) {
            Text("What will be removed").font(.system(size: 15, weight: .semibold)).foregroundStyle(Brand.textPrimary)

            VStack(spacing: 0) {
                breakdownRow("Applications", "\(sel.count) app\(sel.count == 1 ? "" : "s")", bundle, "app.fill", Brand.blue)
                Divider().overlay(Brand.border).padding(.leading, 40)
                breakdownRow("Support Files", "Kept on this Mac", support, "folder.fill", Brand.cyan)
                Divider().overlay(Brand.border).padding(.leading, 40)
                breakdownRow("Other App Data", "Kept on this Mac", leftover, "doc.on.doc.fill", Brand.purple)
            }
            .cairnCard(0)

            VStack(spacing: 6) {
                HStack {
                    Text("Bundle to Trash").font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.textPrimary)
                    Spacer()
                    Text(Fmt.size(total)).font(.system(size: 16, weight: .bold)).foregroundStyle(Brand.blue)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Brand.blue.opacity(0.06)))

            safeNote

            Button { confirming = true } label: {
                VStack(spacing: 2) {
                    Label("Uninstall Selected (\(sel.count))", systemImage: "trash")
                    if total > 0 { Text("\(Fmt.size(total)) to Trash; space frees when Trash is emptied").font(.system(size: 10)).opacity(0.85) }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(BrandButtonStyle(enabled: !sel.isEmpty))
            .disabled(sel.isEmpty)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(CardBackground())
    }

    private func breakdownRow(_ title: String, _ subtitle: String, _ size: Int64, _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 12) {
            IconTile(systemImage: icon, tint: tint, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.textPrimary)
                Text(subtitle).font(.system(size: 10)).foregroundStyle(Brand.textMuted).lineLimit(1)
            }
            Spacer()
            Text(Fmt.size(size)).font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.textSecondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private var safeNote: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill").foregroundStyle(Brand.safeCyan).font(.system(size: 13))
                Text("Removal boundaries").font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.textPrimary)
            }
            ForEach([
                "Only the selected app bundle moves to Trash.",
                "Running apps are quit automatically before removal.",
                "Support files, conversations, preferences and projects stay in place.",
                "System apps are protected and can't be selected.",
            ], id: \.self) { line in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(Brand.safeCyan)
                    Text(line).font(.system(size: 11)).foregroundStyle(Brand.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).cairnCard(16)
    }

    // MARK: - Helpers

    private func lastOpenedText(_ app: AppEntry) -> String {
        guard let last = app.lastOpened else { return "Never" }
        let days = Date().timeIntervalSince(last) / 86_400
        if days < 1 { return "Today" }
        if days < 30 { return "\(Int(days))d ago" }
        if days < 365 { return "\(Int(days / 30))mo ago" }
        return String(format: "%.1fy ago", days / 365)
    }
}

/// Final confirmation before trashing app bundles. Associated data is retained.
struct UninstallConfirmSheet: View {
    let apps: [AppEntry]
    var onCancel: () -> Void
    var onConfirm: () -> Void

    private var total: Int64 { apps.reduce(0) { $0 + $1.totalSize } }
    private var running: [String] {
        let ids = apps.map { $0.bundleID }.filter { !$0.isEmpty }
        return RunningApps.displayNames(for: RunningApps.running(amongst: ids))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                IconTile(systemImage: "trash.fill", tint: Brand.danger, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Uninstall \(apps.count) app\(apps.count == 1 ? "" : "s")?")
                        .font(.system(size: 18, weight: .bold)).foregroundStyle(Brand.textPrimary)
                    Text("\(Fmt.size(total)) in app bundles moves to Trash. Support data stays.")
                        .font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
                }
                Spacer()
            }
            .padding(20)
            Divider().overlay(Brand.border)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(apps) { app in
                        HStack(spacing: 10) {
                            FileIcon(url: app.url, size: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.textPrimary)
                                Text("\(app.associated.count) associated location\(app.associated.count == 1 ? "" : "s") kept")
                                    .font(.system(size: 10)).foregroundStyle(Brand.textMuted)
                            }
                            Spacer()
                            Text(Fmt.size(app.totalSize)).font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.textSecondary)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 9)
                        Divider().overlay(Brand.border).padding(.leading, 56)
                    }
                }
            }
            .frame(maxHeight: 260)

            if !running.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.amber).font(.system(size: 12))
                    Text("\(running.joined(separator: ", ")) \(running.count == 1 ? "is" : "are") running and will be quit first.")
                        .font(.system(size: 11)).foregroundStyle(Brand.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(Brand.amber.opacity(0.08))
            }

            Divider().overlay(Brand.border)
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { onCancel() }.buttonStyle(GhostButtonStyle())
                Button { onConfirm() } label: {
                    Label("Move to Trash", systemImage: "trash").frame(minWidth: 130)
                }.buttonStyle(BrandButtonStyle())
            }
            .padding(20)
        }
        .frame(width: 480)
        .background(Brand.surfaceElevated)
    }
}
