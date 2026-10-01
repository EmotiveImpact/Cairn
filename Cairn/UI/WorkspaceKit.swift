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
                        Text(title).font(.system(size: 28, weight: .semibold))
                        if !subtitle.isEmpty { Text(subtitle).font(.system(size: 13)).foregroundStyle(Brand.textSecondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 28)
                        .padding(.trailing, headerTrailingInset).padding(.top, 27).padding(.bottom, 21)
                    content().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }.frame(minWidth: 490, maxWidth: .infinity)
                if inspectorVisible {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 19) { detail() }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(22)
                    }.frame(width: 300).background(Brand.deepPanel)
                }
            }
            HStack(spacing: 12) { actions() }.font(.system(size: 12))
                .padding(.horizontal, 22).frame(height: 72)
                .background(Brand.deepPanel.opacity(0.35))
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
            if !value.isEmpty { Text(value).font(.system(size: 29, weight: .regular)).monospacedDigit() }
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
        }.buttonStyle(.plain).background(focused ? Color.white.opacity(0.045) : Color.clear)
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
    var body: some View {
        CairnDialog(title: "Cleanup results", subtitle: "File actions and measured capacity are shown separately", height: 590) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    CairnStateView(kind: summary.interrupted ? .interrupted : summary.failed == 0 && summary.errors.isEmpty ? .completed : .attention,
                        title: summary.interrupted ? "Cleanup stopped" : summary.failed == 0 && summary.errors.isEmpty ? "Cleanup finished" : "Finished with skipped items",
                        message: "\(summary.trashed) \(summary.trashed == 1 ? "action" : "actions") completed · \(summary.failed) skipped", compact: true, horizontalInset: 0)
                    receiptRow("Moved to Trash", value: Fmt.size(summary.accounting.trashBytes), detail: "\(itemCount(summary.accounting.trashCount)) · estimated file size. Files in Trash still occupy disk space.")
                    receiptRow("Recovery recorded", value: itemCount(summary.recoverableCount), detail: "Put Back is available while the recorded Trash entries remain accessible.")
                    if summary.accounting.missingRecoveryCount > 0 {
                        Text("Recovery could not be recorded for \(itemCount(summary.accounting.missingRecoveryCount)). Review Finder’s Trash; app recovery may be unavailable after relaunch.").font(.system(size: 12)).foregroundStyle(Brand.amber)
                    }
                    if summary.toolCount > 0 {
                        receiptRow("Tool actions completed", value: "\(summary.toolCount)", detail: "\(Fmt.size(summary.accounting.toolBytes)) in scanned input estimates. This is not a measurement of bytes removed by the tool.")
                    }
                    Text("Available space after cleanup").font(.system(size: 13, weight: .medium))
                    if summary.capacityChanges.isEmpty {
                        Text("No comparable capacity readings were recorded.").font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                    }
                    ForEach(summary.capacityChanges) { change in
                        receiptRow(change.name, value: change.changeText,
                                   detail: change.delta == nil ? "The volume was unavailable or its identity changed." : "Before \(change.before.map { Fmt.size($0.available) } ?? "—") · After \(change.after.map { Fmt.size($0.available) } ?? "—")")
                    }
                    Text("These are macOS capacity readings, not guaranteed savings from Cairn. Other apps and purgeable data can affect them. Cairn does not empty Trash automatically.").font(.system(size: 11)).foregroundStyle(Brand.textMuted).fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(summary.errors.enumerated()), id: \.offset) { _, error in Text(error).font(.system(size: 12)).textSelection(.enabled) }
                }
            }
        } actions: {
            Button("Activity & Recovery", action: onRecovery).buttonStyle(ControlPanelButtonStyle())
            Button("Done", action: onClose).buttonStyle(ControlPanelButtonStyle(primary: true)).keyboardShortcut(.cancelAction)
        }
    }
    private func itemCount(_ count: Int) -> String { "\(count) \(count == 1 ? "item" : "items")" }
    private func receiptRow(_ title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(value).font(.system(size: 12)).monospacedDigit()
            }
            Text(detail).font(.system(size: 11)).foregroundStyle(Brand.textMuted).fixedSize(horizontal: false, vertical: true)
        }
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
