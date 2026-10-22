import SwiftUI
import AppKit

/// Shared geometry for Cairn's native workspaces. Every route uses the same
/// toolbar, row rhythm, detail column and bottom action area.
struct CairnWorkspace<Content: View, Detail: View, Actions: View>: View {
    var title: String
    var subtitle: String = ""
    var inspectorVisible: Bool = true
    var headerTrailingInset: CGFloat = 0
    @ViewBuilder var content: () -> Content
    @ViewBuilder var detail: () -> Detail
    @ViewBuilder var actions: () -> Actions
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title).font(.system(size: 38, weight: .light))
                        if !subtitle.isEmpty { Text(subtitle).font(.system(size: 13)).foregroundStyle(Brand.textSecondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 30)
                        .padding(.trailing, headerTrailingInset).padding(.top, 27).padding(.bottom, 21)
                    content().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }.frame(minWidth: 490, maxWidth: .infinity)
                if inspectorVisible {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 19) { detail() }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(22)
                    }.frame(width: 300)
                    .overlay(alignment: .leading) { Rectangle().fill(Brand.separator).frame(width: 0.5) }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }.animation(.easeOut(duration: 0.22), value: inspectorVisible)
            HStack(spacing: 12) { actions() }.font(.system(size: 12))
                .padding(.horizontal, 26).frame(height: 72)
                .overlay(alignment: .top) { Rectangle().fill(Brand.separator).frame(height: 0.5) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Brand.background).foregroundStyle(Brand.textPrimary)
    }
}

struct WorkspaceHeading: View {
    var title: String
    var subtitle: String
    var icon: String
    var value: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 28, weight: .light)).foregroundStyle(Brand.textSecondary).frame(width: 38)
                VStack(alignment: .leading, spacing: 4) {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                    Text(title).font(.system(size: 16, weight: .medium))
                }
            }
            if !value.isEmpty { Text(value).font(.system(size: 30, weight: .light)).tracking(-0.8).monospacedDigit() }
        }.padding(.top, 14)
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
struct WorkspaceRow: View {
    var title: String
    var subtitle: String = ""
    var icon: String
    var value: String = ""
    var status: String = ""
    var focused = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 22, weight: .light)).foregroundStyle(Brand.textSecondary).frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.textPrimary).lineLimit(1)
                    if !subtitle.isEmpty { Text(subtitle).font(.system(size: 11)).foregroundStyle(Brand.textMuted).lineLimit(1).truncationMode(.middle) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if !value.isEmpty { Text(value).font(.system(size: 12)).monospacedDigit().foregroundStyle(Brand.textSecondary) }
                if !status.isEmpty { Text(status).font(.system(size: 11)).foregroundStyle(Brand.textMuted).frame(width: 90, alignment: .trailing) }
            }.padding(.horizontal, 18).frame(height: 68).contentShape(Rectangle())
        }.buttonStyle(.plain).background(focused ? Brand.wash(0.045) : Color.clear)
    }
}
struct WorkspaceColumns: View {
    var leading: String
    var trailing: String
    var body: some View {
        HStack { Text(leading); Spacer(); Text(trailing) }
            .font(.system(size: 11)).foregroundStyle(Brand.textSecondary)
            .padding(.horizontal, 20).frame(height: 36).background(Brand.background)
    }
}
struct WorkspaceEmpty: View {
    var title: String
    var message: String
    var icon = "magnifyingglass"
    var body: some View {
        CairnStateView(kind: .empty, title: title, message: message)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
struct WorkspaceConfirmation: View {
    var title: String
    var explanation: String
    var entries: [String]
    var actionTitle: String
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
            var bucket = ScanStore.Bucket(info: CategoryInfo(id: id, title: name, subtitle: "Sample results · not a measurement", systemImage: section.icon, group: .general, requiresFDA: false))
            bucket.append(ScanItem(url: FileScan.home.appendingPathComponent(path), allocatedSize: Int64(gb * 1_073_741_824), categoryID: id, severity: .review, cleanMethod: .adviceOnly, note: "Sample data for the interface preview. A live scan determines whether this specific path is actionable.", selected: false))
            return bucket
        }
    }
}

/// Completion belongs to the same quiet workspace; no celebratory full-page
/// takeover, and bytes moved to Trash are never labelled as free disk space.
struct WorkspaceCompletion: View {
    let summary: ScanStore.CleanSummary
    let onRecovery: () -> Void
    let onClose: () -> Void
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The measured gain on the internal volume when macOS reports one,
    /// otherwise the size of what was deleted or cleaned.
    private var measuredGain: Int64? {
        let gains = summary.capacityChanges.compactMap(\.delta).filter { $0 > 0 }
        return gains.isEmpty ? nil : gains.reduce(0, +)
    }
    private var freed: Int64 { max(summary.accounting.freedBytes, measuredGain ?? 0) }
    private var inTrash: Int64 { summary.restorable.isEmpty ? 0 : max(0, summary.bytes - summary.accounting.freedBytes) }
    private var clean: Bool { !summary.interrupted && summary.failed == 0 && summary.errors.isEmpty }

    /// The first volume Cairn measured before and after, usually Macintosh HD.
    private var measured: (name: String, before: Int64, after: Int64, total: Int64?)? {
        for change in summary.capacityChanges {
            if let before = change.before, let after = change.after, change.delta != nil {
                let total = (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey]))?.volumeTotalCapacity.map(Int64.init)
                return (change.name, before.available, after.available, total)
            }
        }
        return nil
    }
    var body: some View {
        CairnDialog(title: summary.interrupted ? "Cleanup stopped" : "Done", subtitle: "", wide: true, height: 560) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        if freed > 0 {
                            Text(Fmt.size(appeared ? freed : 0))
                                .font(.system(size: 64, weight: .light)).tracking(-2.2).monospacedDigit()
                                .contentTransition(.numericText())
                            Text("freed").font(.system(size: 20)).foregroundStyle(Brand.textSecondary)
                        } else {
                            Text("Cleaned").font(.system(size: 52, weight: .light)).tracking(-1.6)
                        }
                    }
                    if let measured, measuredGain != nil {
                        HStack(spacing: 8) {
                            Circle().fill(Brand.room).frame(width: 7, height: 7).shadow(color: Brand.room, radius: 5)
                            Text("Checked on \(measured.name)")
                        }
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.room).padding(.top, 12)
                    } else if !clean {
                        Label(summary.interrupted ? "Stopped before the end" : "\(summary.failed) skipped",
                              systemImage: "exclamationmark.circle")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.amber).padding(.top, 12)
                    }
                    if let measured {
                        VStack(spacing: 10) {
                            bar("Before", measured.before, measured.total, Brand.inUse)
                            bar("Now", measured.after, measured.total, Brand.room)
                        }.padding(.top, 22)
                    }
                    VStack(spacing: 0) {
                        row("Items cleaned", "\(summary.trashed)")
                        if summary.toolCount > 0 {
                            row("Cleaned by their tools", "\(summary.toolCount) \(summary.toolCount == 1 ? "command" : "commands")")
                        }
                        if inTrash > 0 {
                            row("Still in Trash", "\(Fmt.size(inTrash)) · can be put back")
                        }
                        if summary.failed > 0 {
                            row("Skipped", "\(summary.failed) \(summary.failed == 1 ? "item" : "items")", tint: Brand.amber)
                        }
                    }.padding(.top, 20)
                    if summary.accounting.missingRecoveryCount > 0 {
                        Text("Put Back could not be recorded for \(summary.accounting.missingRecoveryCount) Trash \(summary.accounting.missingRecoveryCount == 1 ? "item" : "items"). They are still in Finder's Trash.")
                            .font(.system(size: 12)).foregroundStyle(Brand.amber).padding(.top, 12)
                    }
                    ForEach(Array(summary.errors.prefix(4).enumerated()), id: \.offset) { _, error in
                        Text(error).font(.system(size: 12)).foregroundStyle(Brand.textMuted).textSelection(.enabled).padding(.top, 8)
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            }
        } actions: {
            Button(inTrash > 0 ? "Delete from Trash…" : "View receipt", action: onRecovery).buttonStyle(ControlPanelButtonStyle())
            Button("Done", action: onClose).buttonStyle(ControlPanelButtonStyle(primary: true)).keyboardShortcut(.defaultAction)
        }
        .onAppear {
            if reduceMotion { appeared = true }
            else { withAnimation(.easeOut(duration: 0.9).delay(0.15)) { appeared = true } }
        }
    }
    private func bar(_ label: String, _ available: Int64, _ total: Int64?, _ tint: Color) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 12)).foregroundStyle(Brand.textSecondary).frame(width: 52, alignment: .leading)
            GeometryReader { geo in
                let share = total.map { Double(available) / Double(max(1, $0)) } ?? 0
                ZStack(alignment: .trailing) {
                    Capsule().fill(Brand.track)
                    Capsule().fill(tint).frame(width: max(6, geo.size.width * CGFloat(min(1, share))))
                        .shadow(color: tint == Brand.room ? Brand.room.opacity(0.5) : .clear, radius: 6)
                }
            }.frame(height: 6)
            Text("\(Fmt.size(available)) free").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                .frame(width: 96, alignment: .trailing)
        }
    }
    private func row(_ title: String, _ detail: String, tint: Color = Brand.textPrimary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 12.5)).foregroundStyle(Brand.textSecondary)
            Spacer()
            Text(detail).font(.system(size: 12.5, weight: .medium)).foregroundStyle(tint).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.separator).frame(height: 0.5) }
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
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.bottom, 12)
            .accessibilityElement(children: .combine)
    }
}
