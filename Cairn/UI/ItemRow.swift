import SwiftUI
import AppKit

struct ItemRow: View {
    let store: ScanStore
    let item: ScanItem
    @State private var hovering = false
    @State private var showInfo = false

    private var selectable: Bool { item.severity != .risky && item.isActionable }

    var body: some View {
        HStack(spacing: 12) {
            checkbox
            SeverityDot(severity: item.severity)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(item.url.lastPathComponent)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Brand.textPrimary)
                        .lineLimit(1)
                    badges
                }
                Text(item.note.isEmpty ? item.resolvedURL.path : item.note)
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(item.isActionable ? Fmt.size(item.allocatedSize) : "—")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Brand.textSecondary)
                if item.latestModified > .distantPast {
                    Text(Fmt.age(item.ageDays))
                        .font(.system(size: 10))
                        .foregroundStyle(Brand.textMuted)
                }
            }
            .frame(width: 70, alignment: .trailing)

            Button { showInfo = true } label: {
                Image(systemName: "info.circle").font(.system(size: 13)).foregroundStyle(Brand.textMuted)
            }
            .buttonStyle(.plain).pointerCursor()
            .opacity(hovering || showInfo ? 1 : 0.25)
            .popover(isPresented: $showInfo, arrowEdge: .trailing) { ItemDetail(item: item) }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(hovering ? Brand.blue.opacity(0.05) : .clear)   // white-on-white before; now visibly seats
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onTapGesture { if selectable { store.toggle(item.id) } }.pointerCursor()
        .help(item.resolvedURL.path)
    }

    @ViewBuilder private var checkbox: some View {
        if selectable {
            Image(systemName: item.selected ? "checkmark.square.fill" : "square")
                .font(.system(size: 16))
                .foregroundStyle(item.selected ? Brand.blue : Brand.textMuted)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: item.selected)
        } else {
            Image(systemName: item.cleanMethod.isActionable ? "exclamationmark.triangle.fill" : "info.circle")
                .font(.system(size: 14))
                .foregroundStyle(item.severity == .risky ? Brand.danger : Brand.textMuted)
        }
    }

    @ViewBuilder private var badges: some View {
        if !item.isActionable {
            tag("ADVICE", Brand.textMuted)
        }
        if item.cleanMethod.isPaid {
            tag("PRO · TOOL", Brand.purple)
        }
        if !item.requiresQuitBundleIDs.isEmpty {
            let running = RunningApps.running(amongst: item.requiresQuitBundleIDs)
            if !running.isEmpty {
                tag("QUIT \(RunningApps.displayNames(for: running).first ?? "APP")".uppercased(), Brand.amber)
            }
        }
        if item.permissionDenied {
            tag("PARTIAL", Brand.amber)
        }
        if item.severity == .review && item.isActionable {
            tag("REVIEW", Brand.amber)
        }
        if item.severity == .risky {
            tag("RISKY", Brand.danger)
        }
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .black)).tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.14)))
    }
}

/// Safe-preview popover: what / why / rebuildable / risk / last used / created by
/// / size / restore — the trust surface (SPEC §4.4).
struct ItemDetail: View {
    let item: ScanItem

    private var createdBy: String {
        if let id = item.requiresQuitBundleIDs.first {
            return RunningApps.displayNames(for: [id]).first ?? (id.components(separatedBy: ".").last ?? id)
        }
        return "—"
    }
    private var rebuildable: String {
        if !item.isActionable { return "Advice only" }
        return item.isRegenerable ? "Yes — regenerates automatically" : "Not guaranteed — review first"
    }
    private var howCleaned: String {
        switch item.cleanMethod {
        case .trash: return "Moved to Trash (recoverable)"
        case .emptyTrash: return "Removed from Trash"
        case .tool(let c): return "Run \(c.display)"
        case .adviceOnly: return "Nothing deleted — guidance only"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SeverityDot(severity: item.severity)
                Text(item.url.lastPathComponent)
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(Brand.textPrimary)
                    .lineLimit(1)
            }
            row("What", item.categoryID == "trash" ? "Item in Trash" : item.note)
            row("Why it's here", whyText)
            row("Rebuildable", rebuildable)
            row("Risk", item.severity.label)
            if item.latestModified > .distantPast { row("Last used", Fmt.age(item.ageDays) + " ago") }
            row("Created by", createdBy)
            row("Reclaims", item.isActionable ? Fmt.size(item.allocatedSize) : "—")
            row("Action", howCleaned)
            row("Path", item.resolvedURL.path, mono: true)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.resolvedURL])
            } label: { Label("Reveal in Finder", systemImage: "magnifyingglass") }
                .buttonStyle(GhostButtonStyle())
                .padding(.top, 2)
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
        .background(Brand.surfaceElevated)
    }

    private var whyText: String {
        switch item.cleanMethod {
        case .adviceOnly: return "Surfaced for awareness — Cairn won't delete it for you."
        case .tool(let c): return "Cleaned with its own tool (\(c.display)) so it stays consistent."
        default: return item.isRegenerable
            ? "A cache or build artifact your tools recreate on demand."
            : "Holds the only local copy — kept unchecked until you decide."
        }
    }

    private func row(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.textMuted)
                .frame(width: 86, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: mono ? .monospaced : .default))
                .foregroundStyle(Brand.textSecondary)
                .textSelection(.enabled)
                .lineLimit(mono ? 3 : 2)
        }
    }
}
