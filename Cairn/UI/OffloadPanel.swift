import SwiftUI
import AppKit

/// Move supported data folders to an external drive and leave a link behind,
/// so the owning app keeps working while the drive is connected.
struct OffloadPanel: View {
    let drive: StorageDrive?
    private var store: RelocationStore { .shared }
    @State private var planned: RelocationTarget?
    @State private var restoring: RelocationTarget?
    private let preview = CommandLine.arguments.contains("--preview-ui")

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Move these to \(drive?.name ?? "an external drive") and Cairn leaves a link in their place. The app that owns them keeps working while the drive is connected. Cairn checks every file before removing the original.")
                .font(.system(size: 12)).foregroundStyle(Brand.textSecondary).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(store.targets) { target in row(target) }
            }
            if let busy = store.busyTarget, let target = store.targets.first(where: { $0.id == busy }) {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("\(target.title): \(Fmt.size(store.copied)) of \(Fmt.size(store.total)) copied and checked").font(.system(size: 12)).monospacedDigit()
                    Spacer()
                    Button("Stop") { store.cancel() }.buttonStyle(ControlPanelButtonStyle())
                }
            }
            if !store.message.isEmpty {
                Text(store.message).font(.system(size: 12)).foregroundStyle(Brand.textSecondary).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { if !preview { await store.refresh() } }
        .sheet(item: $planned) { target in
            if let drive {
                WorkspaceConfirmation(
                    title: "Move \(target.title) to \(drive.name)?",
                    explanation: "Cairn copies every file to \(drive.name), reads each one back from the drive to check it, then removes the original from this Mac\(target.mode == .linkBack ? " and leaves a link so the app still finds it" : ""). \(target.whileDisconnected) You can bring it back at any time.",
                    entries: [target.url.path, "To: \(drive.url.appendingPathComponent(RelocationTarget.driveRoot + "/" + target.driveFolder).path)"],
                    actionTitle: "Move & link") {
                        guard !preview else { return }
                        store.move(target, to: drive)
                    }
            }
        }
        .sheet(item: $restoring) { target in
            WorkspaceConfirmation(
                title: "Bring \(target.title) back to this Mac?",
                explanation: "Cairn copies it back, checks every file, puts it in place, then removes the copy from the drive.",
                entries: [store.latest(target)?.destination ?? "", "Back to: \(target.url.path)"],
                actionTitle: "Bring back") {
                    guard !preview else { return }
                    store.bringBack(target)
                }
        }
    }

    private func row(_ target: RelocationTarget) -> some View {
        let state = store.states[target.id]
        let record = store.latest(target)
        let busy = store.busyTarget != nil
        return HStack(spacing: 14) {
            Image(systemName: target.id == "xcode-archives" ? "archivebox" : "cpu").font(.system(size: 20, weight: .light))
                .foregroundStyle(Brand.textSecondary).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(target.title).font(.system(size: 13, weight: .medium))
                Text(status(state, record)).font(.system(size: 11))
                    .foregroundStyle(state?.linkedTo != nil && state?.driveConnected == false ? Brand.amber : Brand.textMuted)
                    .lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if state?.linkedTo != nil, record?.status == .offloaded {
                Button("Bring back") { restoring = target }
                    .buttonStyle(ControlPanelButtonStyle())
                    .disabled(busy || state?.driveConnected != true)
            } else if let bytes = state?.bytes, bytes > 0 {
                Button("Move to drive") { planned = target }
                    .buttonStyle(ControlPanelButtonStyle())
                    .disabled(busy || drive?.acceptsMove(privateFiles: target.privateFiles) != true)
                    .help(drive?.moveStatus(privateFiles: target.privateFiles) ?? "Plug in a drive")
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.separator).frame(height: 0.5) }
    }

    private func status(_ state: RelocationStore.TargetState?, _ record: RelocationRecord?) -> String {
        if preview { return "Sample · 18.4 GB on this Mac" }
        guard let state else { return "Measuring…" }
        if let linked = state.linkedTo {
            let name = record?.volumeName ?? "the drive"
            return state.driveConnected ? "On \(name) · linked from this Mac" : "On \(name), which is not connected · \(linked)"
        }
        if let record, record.status == .needsReview || record.status == .interrupted { return record.detail }
        guard let bytes = state.bytes else { return "Not found on this Mac" }
        return bytes > 0 ? "\(Fmt.size(bytes)) on this Mac" : "Empty"
    }
}
