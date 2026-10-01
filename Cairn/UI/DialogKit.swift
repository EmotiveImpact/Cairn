import SwiftUI

/// Shared geometry for review, information and result sheets. Each caller owns
/// its scrollable content and action guards; destructive actions have no Return shortcut.
struct CairnDialog<Content: View, Actions: View>: View {
    var title: String
    var subtitle: String = ""
    var wide = false
    var height: CGFloat = 460
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 22, weight: .semibold))
                if !subtitle.isEmpty { Text(subtitle).font(.system(size: 12)).foregroundStyle(Brand.textMuted).fixedSize(horizontal: false, vertical: true) }
            }.padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 8)
            content().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(24)
            HStack(spacing: 10) { Spacer(minLength: 0); actions() }.padding(.horizontal, 24).frame(height: 66)
        }.frame(width: wide ? 740 : 600, height: height)
            .foregroundStyle(Brand.textPrimary).background(Brand.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct CairnStateView: View {
    enum Kind { case scanning, empty, interrupted, completed, attention }
    var kind: Kind
    var title: String
    var message: String
    var compact = false
    var horizontalInset: CGFloat? = nil
    private var icon: String {
        switch kind { case .scanning: return "scope"; case .empty: return "tray"; case .interrupted: return "pause.circle"; case .completed: return "checkmark.circle"; case .attention: return "exclamationmark.circle" }
    }
    private var tint: Color { kind == .interrupted || kind == .attention ? Brand.amber : kind == .completed ? Brand.safeCyan : kind == .scanning ? Brand.blue : Brand.textMuted }
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.07))
                if kind == .scanning { ProgressView().controlSize(.small) }
                else { Image(systemName: icon).font(.system(size: 23, weight: .light)).foregroundStyle(tint) }
            }.frame(width: compact ? 34 : 42, height: compact ? 34 : 42).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: compact ? 13 : 18, weight: .medium))
                Text(message).font(.system(size: 12)).foregroundStyle(Brand.textMuted).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, compact ? 16 : 26)
            .padding(.horizontal, horizontalInset ?? (compact ? 16 : 26))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}

/// Sample-only QA surface. No scanner, filesystem operation or persisted setting.
struct DialogStatePreview: View {
    @Environment(\.dismiss) private var dismiss
    @State private var state = "Scanning"
    @State private var showConfirmation = false
    @State private var showCompletion = false
    private let states = ["Scanning", "Empty", "Interrupted", "Completed", "Skipped"]
    var body: some View {
        CairnDialog(title: "State preview", subtitle: "Sample data · no disk actions") {
            VStack(alignment: .leading, spacing: 24) {
                CairnSegmentedControl(label: "State", selection: $state, options: states.map { ($0, $0) }).frame(height: 32)
                CairnStateView(kind: kind, title: title, message: message)
                if state == "Interrupted" || state == "Skipped" { Text("Review recorded results before starting again. Existing files and history remain available.").font(.system(size: 12)).foregroundStyle(Brand.textMuted) }
            }
        } actions: {
            Button("Review sample") { showConfirmation = true }.buttonStyle(ControlPanelButtonStyle())
            Button("Result sample") { showCompletion = true }.buttonStyle(ControlPanelButtonStyle())
            Button("Done") { dismiss() }.buttonStyle(ControlPanelButtonStyle()).keyboardShortcut(.cancelAction)
        }
        .sheet(isPresented: $showConfirmation) {
            WorkspaceConfirmation(title: "Review sample locations", explanation: "This is an inert UI fixture. No file operation will run.", entries: ["/Sample/Build output/Project with a long folder name/DerivedData/Build/Products/Debug/Sample.app", "/Sample/Downloads/export.zip"], actionTitle: "Finish preview") {}
        }
        .sheet(isPresented: $showCompletion) {
            WorkspaceCompletion(summary: Self.receiptSample, onRecovery: { showCompletion = false }, onClose: { showCompletion = false })
        }
    }
    private static var receiptSample: ScanStore.CleanSummary {
        var result = ScanStore.CleanSummary(failed: 1, errors: ["Sample build cache skipped: owning application is running."])
        result.accounting.record(.init(movedToTrashURL: URL(fileURLWithPath: "/Sample/.Trash/Build"), bytesAffected: 2_300_000_000, usedTool: false), recoveryRecorded: true)
        result.accounting.record(.init(bytesAffected: 400_000_000, usedTool: true))
        result.capacityChanges = [.init(id: "sample", before: .init(volumeID: "sample", name: "Macintosh HD", available: 9_900_000_000), after: .init(volumeID: "sample", name: "Macintosh HD", available: 9_900_000_000))]
        return result
    }
    private var kind: CairnStateView.Kind { switch state { case "Scanning": return .scanning; case "Empty": return .empty; case "Interrupted": return .interrupted; case "Completed": return .completed; default: return .attention } }
    private var title: String { switch state { case "Scanning": return "Reading your files"; case "Empty": return "Nothing to review here"; case "Interrupted": return "Scan stopped"; case "Completed": return "Cleanup finished"; default: return "Finished with skipped items" } }
    private var message: String { switch state { case "Scanning": return "Measuring build output. You can stop the scan at any time; nothing is being removed."; case "Empty": return "No matching items in this view. Try another search or run a fresh scan."; case "Interrupted": return "These results may be incomplete. Run a fresh scan before deciding what to remove."; case "Completed": return "Two items moved to Trash. They still occupy disk space and can be restored while present."; default: return "One item was skipped because its owner is running. Completed actions remain recorded in Activity & Recovery." } }
}
