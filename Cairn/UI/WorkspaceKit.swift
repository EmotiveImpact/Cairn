import SwiftUI
import AppKit

/// Shared geometry for Cairn's native workspaces. Every route uses the same
/// toolbar, row rhythm, detail column and bottom action area.
/// A page in the reference layout (see NightPage), with a details column that
/// appears only when a row is clicked. Nothing slides: the column is simply there.
struct CairnWorkspace<Trailing: View, Content: View, Detail: View, Actions: View>: View {
    var eyebrow: String
    var title: String
    var subtitle: String
    var inspectorVisible: Bool
    var onCloseInspector: (() -> Void)?
    var trailing: () -> Trailing
    var content: () -> Content
    var detail: () -> Detail
    var actions: () -> Actions

    init(eyebrow: String = "", title: String, subtitle: String = "", inspectorVisible: Bool = false,
         onCloseInspector: (() -> Void)? = nil,
         @ViewBuilder trailing: @escaping () -> Trailing,
         @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder detail: @escaping () -> Detail,
         @ViewBuilder actions: @escaping () -> Actions) {
        self.eyebrow = eyebrow; self.title = title; self.subtitle = subtitle
        self.inspectorVisible = inspectorVisible; self.onCloseInspector = onCloseInspector
        self.trailing = trailing; self.content = content; self.detail = detail; self.actions = actions
    }

    var body: some View {
        HStack(spacing: 0) {
            NightPage(eyebrow: eyebrow.isEmpty ? title : eyebrow, title: title, subtitle: subtitle,
                      trailing: trailing, content: content, footer: actions)
            if inspectorVisible {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Details").nightEyebrow()
                        Spacer()
                        if let onCloseInspector {
                            Button(action: onCloseInspector) {
                                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                                    .frame(width: 22, height: 22).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).foregroundStyle(Brand.textMuted)
                            .help("Hide details").accessibilityLabel("Hide details")
                        }
                    }
                    .frame(height: 28).padding(.top, 22).padding(.horizontal, 22)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) { detail() }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 26)
                    }
                }
                .frame(width: 300)
                .frame(maxHeight: .infinity, alignment: .top)
                .overlay(alignment: .leading) { Rectangle().fill(Brand.wash(0.06)).frame(width: 1) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Brand.background).foregroundStyle(Brand.textPrimary)
    }
}

extension CairnWorkspace where Trailing == EmptyView {
    init(eyebrow: String = "", title: String, subtitle: String = "", inspectorVisible: Bool = false,
         onCloseInspector: (() -> Void)? = nil,
         @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder detail: @escaping () -> Detail,
         @ViewBuilder actions: @escaping () -> Actions) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle, inspectorVisible: inspectorVisible,
                  onCloseInspector: onCloseInspector, trailing: { EmptyView() },
                  content: content, detail: detail, actions: actions)
    }
}

struct WorkspaceDetail: View {
    var title: String
    var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .medium))
            Text(text).font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }
}
/// One row in the reference style: thin symbol, name and grey line, size, pill.
struct WorkspaceRow: View {
    var title: String
    var subtitle: String = ""
    var icon: String
    var value: String = ""
    var status: String = ""
    var tone: NightPill.Tone = .neutral
    var focused = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: icon).font(.system(size: 15, weight: .light)).foregroundStyle(Brand.textSecondary)
                        .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.textPrimary).lineLimit(1)
                        if !subtitle.isEmpty {
                            Text(subtitle).font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !value.isEmpty {
                    Text(value).font(.system(size: 13, weight: .medium)).monospacedDigit()
                        .frame(width: 90, alignment: .trailing)
                }
                if !status.isEmpty { NightPill(text: status, tone: tone).frame(width: 120, alignment: .leading) }
            }
            .nightRow()
            .background(focused ? Brand.wash(0.035) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}
/// Plain words for an empty page, aligned with the rows. No icon box.
struct WorkspaceEmpty: View {
    var title: String
    var message: String
    var icon = "magnifyingglass"
    var body: some View {
        NightEmpty(title: title, message: message)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
struct WorkspaceConfirmation: View {
    var title: String
    var explanation: String
    var entries: [String]
    var actionTitle: String
    /// An optional second choice, shown beside the main one.
    var secondaryTitle: String? = nil
    var secondary: (() -> Void)? = nil
    var action: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        CairnDialog(title: title, subtitle: explanation, height: min(520, 320 + CGFloat(max(0, entries.count - 2)) * 24)) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Included locations").font(.system(size: 12, weight: .medium))
                    ForEach(entries, id: \.self) { Text($0).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        } actions: {
            Button("Cancel") { dismiss() }.buttonStyle(ControlPanelButtonStyle()).keyboardShortcut(.cancelAction)
            if let secondaryTitle, let secondary {
                Button(secondaryTitle) { dismiss(); secondary() }.buttonStyle(ControlPanelButtonStyle())
            }
            Button(actionTitle) { dismiss(); action() }.buttonStyle(ControlPanelButtonStyle(primary: true))
        }
    }
}

/// Fixtures exist only behind --preview-ui. They never become scan results.
enum PreviewLibrary {
    static func buckets(_ section: NavSection) -> [ScanStore.Bucket] {
        let rows: [(String, String, String, Double)]
        switch section {
        case .browsers: rows = [("browser-caches", "Chrome temporary cache", "Library/Caches/Google/Chrome/Default/Cache", 1.8), ("safari", "Safari web cache", "Library/Caches/com.apple.Safari", 0.7)]
        case .ai: rows = [("ai-models", "Local model weights", ".ollama/models", 12.4), ("ai-assets", "Generated media", "Pictures/Generated", 3.6)]
        case .creative: rows = [("creative", "Video render cache", "Movies/Render Cache", 4.2), ("audio", "Audio analysis files", "Music/Analysis", 0.6)]
        case .largeFiles: rows = [("large-old", "Large files", "Downloads/Archive.zip", 3.4), ("installers", "Installers", "Downloads/Installer.dmg", 1.2)]
        default: rows = [("app-caches", "Application caches", "Library/Caches", 2.8), ("logs", "Diagnostic logs", "Library/Logs", 0.4), ("installers", "Downloaded installers", "Downloads/Installer.dmg", 1.2)]
        }
        return rows.map { id, name, path, gb in
            var bucket = ScanStore.Bucket(info: CategoryInfo(id: id, title: name, subtitle: Showcase.active ? "~/" + path : "Sample results · not a measurement", systemImage: section.icon, group: .general, requiresFDA: false))
            bucket.append(ScanItem(url: FileScan.home.appendingPathComponent(path), allocatedSize: Int64(gb * 1_073_741_824), categoryID: id, severity: .review, cleanMethod: .adviceOnly, note: "Sample data for the interface preview. A live scan determines whether this specific path is actionable.", selected: false))
            return bucket
        }
    }
}

/// The "Done" screen from the reference (night-screens-v2.html, s5): the freed
/// number, whether macOS confirmed it, used space before and now, a few plain
/// lines, then Done. Bytes moved to Trash are never labelled as free space.
struct WorkspaceCompletion: View {
    let summary: ScanStore.CleanSummary
    let onRecovery: () -> Void
    let onClose: () -> Void
    /// When the clean happened; a receipt opened later from Activity passes its own.
    var date: Date? = nil
    var recoveryTitle = "View receipt"
    /// Offered only from Activity, when this clean's items are still in the Trash.
    var onEmptyTrash: (() -> Void)? = nil
    /// Bytes from this clean still in the Trash now, when known (a receipt opened
    /// later). Nil means "just cleaned", so everything moved is still there.
    var stillInTrash: Int64? = nil
    /// Straight after a clean: lets the screen offer to empty this clean's items
    /// from the Trash, so the space actually comes back. Asks first.
    var store: ScanStore? = nil
    @State private var shownAt = Date()
    @State private var confirmEmpty = false
    @State private var emptying = false
    @State private var emptiedBytes: Int64 = 0
    @State private var sharing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var finished: Date { date ?? shownAt }

    private var freed: Int64 { summary.freedBytes + emptiedBytes }
    private var movedToTrash: Int64 { max(0, summary.accounting.trashBytes - summary.accounting.freedBytes) }
    private var inTrash: Int64 { max(0, min(movedToTrash, stillInTrash ?? (summary.restorable.isEmpty ? 0 : movedToTrash)) - emptiedBytes) }
    /// This clean's recorded Trash items that have not been put back.
    private var trashIDs: Set<UUID> {
        guard let store else { return [] }
        let paths = Set(summary.restorable.map(\.trash.path))
        return Set(store.removalLog.filter { $0.recoverable && $0.trashPath.map { paths.contains($0) } == true }.map(\.id))
    }
    private var confirmed: Bool { summary.capacityChanges.contains { ($0.delta ?? 0) > 0 } }

    /// Cairn deleted more than free space rose by on the one disk it measured:
    /// local snapshots or purgeable space are holding the rest for now.
    private var heldBack: Int64 {
        guard emptiedBytes == 0, summary.capacityChanges.count == 1, let measured else { return 0 }
        let deleted = summary.accounting.freedBytes
        let gap = deleted - max(0, measured.after - measured.before)
        return gap >= 500_000_000 && gap * 3 >= deleted ? gap : 0
    }

    /// The first volume Cairn measured before and after, usually Macintosh HD.
    private var measured: (name: String, before: Int64, after: Int64, total: Int64)? {
        for change in summary.capacityChanges {
            if let before = change.before, let after = change.after, change.delta != nil {
                let total = (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey]))?.volumeTotalCapacity.map(Int64.init)
                guard let total, total > 0 else { return nil }
                return (change.name, before.available, after.available, total)
            }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(summary.interrupted ? "Stopped" : date == nil ? "Done" : "Receipt") · \(finished.formatted(.dateTime.day().month(.wide))), \(finished.formatted(date: .omitted, time: .shortened))")
                .nightEyebrow()
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if freed > 0 {
                    CountingBytes(bytes: freed, duration: 0.8, still: reduceMotion)
                        .font(.system(size: 72, weight: .light)).tracking(-2.9)
                        .foregroundStyle(Brand.textPrimary)
                    Text("freed").font(.system(size: 20)).foregroundStyle(Brand.textMuted)
                } else {
                    if movedToTrash > 0 {
                        // Nothing measured free: say plainly where the bytes went.
                        CountingBytes(bytes: movedToTrash, duration: 0.8, still: reduceMotion)
                            .font(.system(size: 72, weight: .light)).tracking(-2.9)
                            .foregroundStyle(Brand.textPrimary)
                        Text("moved to the Trash").font(.system(size: 20)).foregroundStyle(Brand.textMuted)
                    } else {
                        Text(summary.interrupted ? "Stopped" : "Cleaned").font(.system(size: 72, weight: .light)).tracking(-2.9)
                    }
                }
            }
            .lineLimit(1).minimumScaleFactor(0.5)
            if let warm = ReceiptLine.text(freed: freed, seed: finished) {
                Text(warm).font(.system(size: 14)).foregroundStyle(Brand.room).padding(.top, -6)
            }
            if let measured, confirmed {
                HStack(spacing: 8) {
                    Circle().fill(Brand.room).frame(width: 7, height: 7).shadow(color: Brand.room, radius: 5)
                    Text("Checked on \(measured.name)")
                }
                .font(.system(size: 13)).foregroundStyle(Brand.room)
            } else if emptiedBytes > 0 {
                Text("Emptied from the Trash. The space is free now.")
                    .font(.system(size: 13)).foregroundStyle(Brand.textSecondary)
            } else if freed == 0 && movedToTrash > 0 {
                Text(inTrash > 0 ? "The space comes back when the Trash is emptied."
                                 : "Free space did not rise after this clean.")
                    .font(.system(size: 13)).foregroundStyle(Brand.textSecondary)
            } else if summary.interrupted {
                Text("Stopped before the end").font(.system(size: 13)).foregroundStyle(Brand.amber)
            }
            if heldBack > 0 {
                Text("\(Fmt.size(heldBack)) has not shown up as free space yet. macOS can keep it for a while in local Time Machine snapshots or as purgeable space, then lets it go on its own.")
                    .font(.system(size: 13)).foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let measured {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        Text("Before")
                        usedBar(used: measured.total - measured.before, freed: 0, total: measured.total)
                        Text("\(Fmt.size(measured.before)) free").fontWeight(.medium).foregroundStyle(Brand.textPrimary)
                            .frame(width: 110, alignment: .trailing)
                    }
                    GridRow {
                        Text("Now")
                        usedBar(used: measured.total - measured.after, freed: max(0, measured.after - measured.before), total: measured.total)
                        Text("\(Fmt.size(measured.after)) free").fontWeight(.medium).foregroundStyle(Brand.textPrimary)
                            .frame(width: 110, alignment: .trailing)
                    }
                }
                .font(.system(size: 12.5)).foregroundStyle(Brand.textMuted).monospacedDigit()
            }
            VStack(spacing: 0) {
                line("Items cleaned", "\(summary.trashed)")
                if summary.toolCount > 0 {
                    line("Cleaned by their own tools", "\(summary.toolCount) \(summary.toolCount == 1 ? "command" : "commands")")
                }
                if inTrash > 0 { line("Still in Trash", "\(Fmt.size(inTrash)) · can be put back") }
                else if movedToTrash > 0 && stillInTrash != nil { line("Moved to Trash", "\(Fmt.size(movedToTrash)) · since emptied") }
                if summary.failed > 0 {
                    line("Skipped", [summary.failed == 1 ? nil : "\(summary.failed) items", summary.errors.first ?? (summary.failed == 1 ? "1 item" : nil)]
                        .compactMap { $0 }.joined(separator: " · "), tint: Brand.amber)
                }
                if summary.accounting.missingRecoveryCount > 0 {
                    line("No Put Back recorded", "\(summary.accounting.missingRecoveryCount) · still in Finder's Trash", tint: Brand.amber)
                }
            }
            HStack(spacing: 10) {
                Button("Done", action: onClose)
                    .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
                    .keyboardShortcut(.defaultAction)
                Button(recoveryTitle, action: onRecovery)
                    .buttonStyle(ControlPanelButtonStyle(size: .large))
                if store != nil, onEmptyTrash == nil, inTrash > 0, !trashIDs.isEmpty {
                    Button(emptying ? "Emptying…" : "Empty Trash to free \(Fmt.size(inTrash))") { confirmEmpty = true }
                        .buttonStyle(ControlPanelButtonStyle(size: .large))
                        .disabled(emptying)
                }
                if let onEmptyTrash, inTrash > 0 {
                    Button("Empty from Trash…", action: onEmptyTrash)
                        .buttonStyle(ControlPanelButtonStyle(size: .large))
                }
                if freed > 0 {
                    Button { sharing = true } label: { Label("Share", systemImage: "square.and.arrow.up") }
                        .buttonStyle(ControlPanelButtonStyle(size: .large))
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: 600, alignment: .leading)
        .confirmationDialog("Empty \(Fmt.size(inTrash)) from the Trash?", isPresented: $confirmEmpty) {
            Button("Empty permanently", role: .destructive) { emptyTrash() }
        } message: {
            Text("Only the items from this clean are removed, and the space comes back straight away. They can no longer be put back.")
        }
        .padding(.top, 22).padding(.horizontal, 40).padding(.bottom, 26)
        // Centred top to bottom, as in the reference (.done justify-content: center).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .frame(minWidth: 720, minHeight: 560)
        .background(Brand.background)
        .foregroundStyle(Brand.textPrimary)
        .overlay {
            if sharing {
                ShareCardSheet(freed: freed, cleared: summary.cleared) { sharing = false }
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: sharing)
    }

    private func emptyTrash() {
        guard let store, !emptying else { return }
        emptying = true
        Task {
            let result = await store.deleteFromTrash(trashIDs)
            emptiedBytes += result.bytes
            await StorageControl.shared.refreshCapacity(force: true)
            emptying = false
        }
    }

    /// Used space as a 6 pt bar; on "Now" the space just freed glows ice beside it.
    private func usedBar(used: Int64, freed: Int64, total: Int64) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let usedShare = CGFloat(min(1, max(0, Double(used) / Double(total))))
            let freedShare = CGFloat(min(1, Double(freed) / Double(total)))
            ZStack(alignment: .leading) {
                Capsule().fill(Brand.wash(0.07))
                Capsule().fill(Brand.wash(0.28)).frame(width: width * usedShare)
                if freed > 0 {
                    Capsule().fill(Brand.room).shadow(color: Brand.room.opacity(0.55), radius: 7)
                        .frame(width: max(6, width * freedShare))
                        .offset(x: width * usedShare)
                }
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }

    private func line(_ title: String, _ value: String, tint: Color = Brand.textPrimary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(Brand.textSecondary).fixedSize()
            Spacer(minLength: 16)
            Text(value).fontWeight(.medium).foregroundStyle(tint).lineLimit(1).truncationMode(.tail)
        }
        .font(.system(size: 12.5))
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.wash(0.06)).frame(height: 1) }
    }
}

/// Shared specialist receipt: file estimates, recovery records and observed
/// capacity stay separate. This view makes no causal claim about the delta.
struct CapacityReceiptView: View {
    let changes: [CleanupCapacityChange]
    let estimatedBytes: Int64
    let recoveryCount: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(Fmt.size(estimatedBytes)) estimated file size affected · \(recoveryCount) recovery paths recorded")
            ForEach(changes) { change in
                Text("\(change.name): \(change.changeText) · \(change.after.map { Fmt.size($0.available) + " available now" } ?? "current capacity unavailable")")
                if let date = change.after?.date { Text("Observed \(date.formatted(date: .abbreviated, time: .shortened)) · macOS important-usage capacity") }
            }
            if changes.isEmpty { Text("Capacity change is unavailable.") }
            Text("Trash still occupies disk space. Other Mac activity may affect these readings. Activity checks whether each recorded recovery is still available.")
        }.font(.system(size: 11)).foregroundStyle(Brand.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            .accessibilityElement(children: .combine)
    }
}
