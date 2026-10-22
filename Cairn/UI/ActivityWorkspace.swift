import SwiftUI
import AppKit
import Charts

/// New cleanup runs have durable receipts. Legacy actions remain individual
/// records; we never infer run groupings from coincident timestamps.
struct RecoveryWorkspace: View {
    let store: ScanStore
    var search: String
    @Binding var inspectorVisible: Bool
    var onOpen: (NavSection) -> Void = { _ in }

    @State private var showingAllActivity = false
    @State private var selectedRunID: UUID?
    @State private var focused: UUID?
    @State private var availableTrash: Set<UUID> = []
    @State private var actionJournal: [ActionJournal.Entry] = []
    @State private var journalError: String?
    @State private var reviewing: ActionJournal.Entry?
    @State private var reviewMessage = ""
    @State private var restoreMessage = ""
    @State private var restoreSucceeded = false
    @State private var confirmRestore = false
    @State private var restorePlan: ScanStore.RemovalLogEntry?
    @State private var currentCapacity: CapacityReading?
    @State private var checkingSpace = false
    @State private var reclaimBaseline: CapacityReading?
    @State private var purged: Set<UUID> = []
    @State private var purgedBytes: Int64 = 0
    @State private var purging = false
    @State private var confirmPurge = false

    private let preview = CommandLine.arguments.contains("--preview-ui")
    private let inset: CGFloat = 34

    private static let sampleEntries: [ScanStore.RemovalLogEntry] = {
        [ScanStore.RemovalLogEntry(name: "Old-installer.dmg", originalPath: "~/Downloads/Old-installer.dmg", trashPath: "~/.Trash/Old-installer.dmg", bytes: 940_000_000, date: Date(), category: "installers"),
         ScanStore.RemovalLogEntry(name: "Assets-export.zip", originalPath: "~/Downloads/Assets-export.zip", trashPath: "~/.Trash/Assets-export.zip", bytes: 2_160_000_000, date: Date(), category: "large-old")]
    }()
    private var allEntries: [ScanStore.RemovalLogEntry] { preview ? Self.sampleEntries : store.removalLog }
    private var entries: [ScanStore.RemovalLogEntry] {
        if search.isEmpty { return allEntries }
        return allEntries.filter { ($0.name + $0.originalPath).localizedCaseInsensitiveContains(search) }
    }
    private var inspected: ScanStore.RemovalLogEntry? { entries.first { $0.id == focused } }
    private var needsManualReview: [ActionJournal.Entry] {
        let recordedPaths = Set(store.removalLog.compactMap(\.trashPath))
        return actionJournal.filter { entry in
            entry.state == .pending || (entry.state == .succeeded && entry.trashPath.map { !recordedPaths.contains($0) } == true)
        }
    }
    private var receipt: ActivityReceipt? {
        if preview { return .sample }
        let run = store.cleanupRuns.first { $0.id == (selectedRunID ?? store.lastCleanRunID) }
        let liveSummary = selectedRunID == nil || selectedRunID == store.lastCleanRunID ? store.lastCleanSummary : nil
        guard let summary = liveSummary ?? run?.summary else { return nil }
        let rows = Array(summary.restorable.prefix(80).enumerated()).map { index, pair in
            let record = store.removalLog.first { $0.trashPath == pair.trash.path && $0.originalPath == pair.original.path }
            return ActivityReceipt.Row(id: "\(index):\(pair.trash.path)", name: pair.original.lastPathComponent,
                                       bytes: record?.bytes, recoveryID: record?.id, trashPath: record?.trashPath)
        }
        let date = rows.compactMap { row -> Date? in
            guard let id = row.recoveryID else { return nil }
            return store.removalLog.first { $0.id == id }?.date
        }.max()
        return ActivityReceipt(date: run?.started ?? date, movedCount: summary.accounting.trashCount,
                               movedBytes: summary.accounting.trashBytes, skippedCount: summary.failed,
                               recoveryCount: summary.recoverableCount, missingRecoveryCount: summary.accounting.missingRecoveryCount,
                               toolCount: summary.toolCount, toolBytes: summary.accounting.toolBytes,
                               interrupted: summary.interrupted, rows: rows,
                               hiddenRowCount: max(0, summary.restorable.count - rows.count),
                               issues: summary.errors, capacityChanges: summary.capacityChanges,
                               inProgress: run.map { store.isRunActive($0.id) } ?? false,
                               freedBytes: summary.accounting.freedBytes)
    }
    private var freeSpaceReadings: [CapacityReading] {
        if preview { return PreviewStorageScenario.capacityHistory }
        let start = Date().addingTimeInterval(-30 * 86_400)
        return StorageControl.shared.latestCapacity.filter { $0.date >= start }.sorted { $0.date < $1.date }
    }
    /// Cleans that released space, for the dots on the chart.
    private var freeSpaceCleans: [FreeSpaceCard.Clean] {
        if preview, let last = PreviewStorageScenario.capacityHistory.last {
            return [.init(date: last.date, freed: 6_400_000_000)]
        }
        return store.cleanupRuns.compactMap { run in
            let freed = Self.freed(run.summary)
            return freed > 0 ? FreeSpaceCard.Clean(date: run.finished ?? run.started, freed: freed) : nil
        }
    }
    static func freed(_ summary: ScanStore.CleanSummary) -> Int64 {
        let gains = summary.capacityChanges.compactMap(\.delta).filter { $0 > 0 }.reduce(0, +)
        return max(summary.accounting.freedBytes, gains)
    }
    private var capacity: CapacityReading? {
        if preview { return PreviewStorageScenario.current }
        return currentCapacity ?? StorageControl.shared.current
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if inspected == nil {
                        FreeSpaceCard(readings: freeSpaceReadings, cleans: freeSpaceCleans,
                                      onChanges: { onOpen(.changes) })
                            .padding(.bottom, 26)
                    }
                    if let entry = inspected { itemDetail(entry) }
                    else if !showingAllActivity, let receipt { receiptDetail(receipt) }
                    else { activityList }
                }
                .padding(.horizontal, inset).padding(.top, 26).padding(.bottom, 28)
                .frame(maxWidth: 1200, alignment: .leading).frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
            if let entry = inspected { itemActionBar(entry) }
            else if !showingAllActivity && receipt != nil { receiptActionBar }
        }
        .background(Brand.background)
        .foregroundStyle(Brand.textPrimary)
        .task {
            await refresh()
            if !preview {
                await StorageControl.shared.refreshCapacity(force: true)
                currentCapacity = StorageControl.shared.current
                reclaimBaseline = currentCapacity
            }
        }
        .sheet(isPresented: $confirmRestore) {
            if let entry = restorePlan {
                WorkspaceConfirmation(title: "Restore \(entry.name)?",
                    explanation: "Return the recorded Trash item to its original path. Existing files will not be overwritten.",
                    entries: [entry.originalPath], actionTitle: "Put Back") {
                    Task {
                        restoreSucceeded = await store.restoreFromLog(entry)
                        restoreMessage = restoreSucceeded ? "Restored \(entry.name)." : store.restoreMessage ?? "Restore failed. The history record was retained."
                        await refresh()
                    }
                }
            }
        }
        .sheet(item: $reviewing) { entry in
            InterruptedActionReview(entry: entry) {
                let recorded = await Task.detached(priority: .utility) {
                    ActionJournal.shared.acknowledgeManualReview(entry.id)
                }.value
                if recorded {
                    reviewMessage = "The safety stop was cleared after your review. Cairn did not change files or decide whether the interrupted move succeeded."
                    await refresh()
                }
                return recorded
            }
        }
    }

    private func receiptDetail(_ receipt: ActivityReceipt) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            backToActivity
            HStack(alignment: .top, spacing: 15) {
                Image(systemName: receipt.interrupted ? "pause.circle.fill" : receipt.skippedCount > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(receipt.interrupted || receipt.skippedCount > 0 ? Brand.amber : Brand.safeCyan)
                    .frame(width: 44, alignment: .leading).padding(.top, 2)
                VStack(alignment: .leading, spacing: 5) {
                    Text(receipt.title).font(.system(size: 30, weight: .light))
                    Text(receipt.date.map { "\($0.formatted(date: .abbreviated, time: .shortened)) · Clean receipt" } ?? "Clean receipt · this session")
                        .font(.system(size: 13)).foregroundStyle(Brand.textMuted)
                }
            }.padding(.top, 33)

            HStack(alignment: .top, spacing: 30) {
                metric(title: "Space freed", value: Fmt.size(receipt.freedBytes + purgedBytes),
                       detail: "Deleted, emptied or cleaned by tools", accent: Brand.safeCyan)
                Rectangle().fill(Brand.separator).frame(width: 1, height: 91)
                metric(title: "Still in Trash", value: Fmt.size(max(0, receipt.inTrashBytes - purgedBytes)),
                       detail: "Put Back is available until you delete it")
                Rectangle().fill(Brand.separator).frame(width: 1, height: 91)
                metric(title: capacity.map { Date().timeIntervalSince($0.date) < 120 ? "Available now" : "Latest available reading" } ?? "Available space",
                       value: capacity.map { Fmt.size($0.available) } ?? "Unavailable",
                       detail: capacityDetail(receipt))
            }.padding(.leading, 44).padding(.top, 34).padding(.bottom, 23)

            let deletable = receipt.rows.filter { row in
                row.recoveryID.map { availableTrash.contains($0) && !purged.contains($0) } ?? false
            }
            if !deletable.isEmpty && !preview {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(Fmt.size(deletable.reduce(0) { $0 + ($1.bytes ?? 0) })) is still sitting in the Trash")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Delete it now to get the space back. This cannot be put back.")
                            .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                    }
                    Spacer()
                    Button(purging ? "Deleting…" : "Delete from Trash") { confirmPurge = true }
                        .buttonStyle(ControlPanelButtonStyle(primary: true))
                        .disabled(purging || store.isCleaning)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: Brand.rCard).fill(Brand.blue.opacity(0.10)))
                .padding(.leading, 44).padding(.bottom, 24)
                .confirmationDialog("Delete \(deletable.count) \(deletable.count == 1 ? "item" : "items") from the Trash?", isPresented: $confirmPurge) {
                    Button("Delete permanently", role: .destructive) {
                        let ids = Set(deletable.compactMap(\.recoveryID))
                        purgeFromTrash(ids)
                    }
                } message: {
                    Text("The space is released straight away. Put Back will no longer be possible for these items.")
                }
            }
            if let change = SpaceGoal.observedChange(from: reclaimBaseline, to: capacity) {
                Text(change == 0 ? "No measured change since opening this activity." : "\(Fmt.size(abs(change))) \(change > 0 ? "more" : "less") available since opening this activity. Other Mac activity may contribute.")
                    .font(.system(size: 12)).foregroundStyle(Brand.textSecondary).padding(.bottom, 20)
            }
            sectionRule
            HStack {
                Text("Item").frame(maxWidth: .infinity, alignment: .leading)
                Text("Result").frame(width: 138, alignment: .leading)
                Text("Recovery").frame(width: 150, alignment: .leading)
            }.font(.system(size: 11, weight: .medium)).foregroundStyle(Brand.textMuted)
                .padding(.horizontal, 6).padding(.vertical, 12)
            sectionRule

            LazyVStack(spacing: 0) {
                ForEach(receipt.rows) { row in
                    HStack(spacing: 12) {
                        Image(systemName: "doc.fill").font(.system(size: 22)).foregroundStyle(Brand.textSecondary).frame(width: 33)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                            Text(row.bytes.map(Fmt.size) ?? "Size unavailable")
                                .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.recoveryID.map { purged.contains($0) } == true ? "Deleted" : "Moved to Trash")
                            .font(.system(size: 12)).frame(width: 138, alignment: .leading)
                        if preview {
                            Button("Show in Trash") {}.buttonStyle(ControlPanelButtonStyle())
                                .disabled(true).frame(width: 150, alignment: .leading)
                        } else if let recoveryID = row.recoveryID, let path = row.trashPath,
                           availableTrash.contains(recoveryID) {
                            Button("Show in Trash") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                                .buttonStyle(ControlPanelButtonStyle()).disabled(preview)
                                .frame(width: 150, alignment: .leading)
                        } else {
                            Text(preview ? "Sample only" : "Check recovery")
                                .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                                .frame(width: 150, alignment: .leading)
                        }
                    }.padding(.horizontal, 6).frame(minHeight: 68)
                        .overlay(alignment: .bottom) { sectionRule }
                }
                ForEach(Array(receipt.issues.prefix(8).enumerated()), id: \.offset) { _, issue in
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 21)).foregroundStyle(Brand.amber).frame(width: 33)
                        Text(issue).font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        Text("Needs review").font(.system(size: 12)).foregroundStyle(Brand.amber)
                            .frame(width: 138, alignment: .leading)
                        Text("—").font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                            .frame(width: 150, alignment: .leading)
                    }.padding(.horizontal, 6).padding(.vertical, 15)
                        .overlay(alignment: .bottom) { sectionRule }
                }
            }
            if receipt.hiddenRowCount > 0 {
                Button("\(receipt.hiddenRowCount) more recorded items · View all activity") { showingAllActivity = true }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Brand.deepBlue).padding(.top, 13)
            }
            if receipt.skippedCount > 0 || !receipt.issues.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Label(receipt.skippedCount > 0 ? "\(receipt.skippedCount) skipped · review what happened" : "Review the action notes", systemImage: "exclamationmark.circle")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.amber)
                    Text(receipt.skippedCount > 0 ? "Cairn did not retry skipped actions. Check the original location and scan again before reviewing another cleanup." : "These messages describe the latest Clean action. The record does not imply that more space was freed.")
                        .font(.system(size: 11)).foregroundStyle(Brand.textSecondary)
                    if receipt.issues.count > 8 { Text("\(receipt.issues.count - 8) more messages are retained in this session.").font(.system(size: 11)).foregroundStyle(Brand.textMuted) }
                }.padding(.top, 22).padding(.bottom, 20)
            }
            if receipt.toolCount > 0 {
                Text("\(receipt.toolCount) tool actions affected an estimated \(Fmt.size(receipt.toolBytes)) of scanned input. This does not measure what those tools removed.")
                    .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 16)
            }
            safetyNotices.padding(.top, 16)
            sectionRule.padding(.top, 20)
            HStack(alignment: .top, spacing: 15) {
                Image(systemName: "doc.text").font(.system(size: 22)).foregroundStyle(Brand.textSecondary).frame(width: 44)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Recovery recorded").font(.system(size: 13, weight: .medium))
                    Text("\(receipt.recoveryCount) \(receipt.recoveryCount == 1 ? "path" : "paths") recorded. Put Back works only while the exact Trash entry remains available.")
                        .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    if receipt.missingRecoveryCount > 0 {
                        Text("\(receipt.missingRecoveryCount) moved \(receipt.missingRecoveryCount == 1 ? "item has" : "items have") no recorded recovery path. Check Finder Trash manually.")
                            .font(.system(size: 11)).foregroundStyle(Brand.amber)
                    }
                }
                Spacer(minLength: 8)
                Button("View recovery details") { showingAllActivity = true }
                    .buttonStyle(ControlPanelButtonStyle())
            }.padding(.vertical, 20)
            if !receipt.capacityChanges.isEmpty {
                sectionRule
                VStack(alignment: .leading, spacing: 9) {
                    Text("Available-space readings at cleanup")
                        .font(.system(size: 12, weight: .medium))
                    ForEach(receipt.capacityChanges) { change in
                        HStack(alignment: .firstTextBaseline) {
                            Text(change.name).frame(maxWidth: .infinity, alignment: .leading)
                            Text(change.changeText).monospacedDigit()
                        }.font(.system(size: 11)).foregroundStyle(Brand.textSecondary)
                    }
                    Text("Other Mac activity and purgeable data can affect these readings.")
                        .font(.system(size: 10.5)).foregroundStyle(Brand.textMuted)
                }.padding(.vertical, 18)
            }
            if preview { sampleFootnote }
        }
    }

    private var activityList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Activity").font(.system(size: 38, weight: .light))
                    Text("Reviewed actions and the recovery paths Cairn recorded.")
                        .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                }
                Spacer()
                if receipt != nil {
                    Button("Clean receipt") { focused = nil; showingAllActivity = false }
                        .buttonStyle(ControlPanelButtonStyle())
                }
            }.padding(.bottom, 24)
            safetyNotices
            if !restoreMessage.isEmpty {
                CairnStateView(kind: restoreSucceeded ? .completed : .attention,
                               title: restoreSucceeded ? "Item restored" : "Restore could not finish",
                               message: restoreMessage, compact: true).padding(.bottom, 12)
            }
            if !preview, !store.cleanupRuns.isEmpty {
                Text("Cleanup receipts").font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
                LazyVStack(spacing: 0) {
                    ForEach(store.cleanupRuns) { run in
                        Button {
                            selectedRunID = run.id; focused = nil; showingAllActivity = false
                        } label: {
                            let freed = Self.freed(run.summary)
                            let verified = run.summary.capacityChanges.contains { ($0.delta ?? 0) > 0 }
                            HStack(spacing: 14) {
                                VStack(spacing: 0) {
                                    Text(run.started.formatted(.dateTime.day())).font(.system(size: 20, weight: .light))
                                    Text(run.started.formatted(.dateTime.month(.abbreviated))).font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                                }.frame(width: 40)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(freed > 0 ? "Freed \(Fmt.size(freed))" : "\(run.kind ?? "Cleanup"): \(run.summary.accounting.completedCount) items")
                                        .font(.system(size: 14, weight: .medium))
                                    Text("\(run.kind ?? "Cleanup") · \(run.started.formatted(date: .omitted, time: .shortened))\(run.summary.failed > 0 ? " · \(run.summary.failed) skipped" : "")")
                                        .font(.system(size: 11.5)).foregroundStyle(Brand.textMuted)
                                }
                                Spacer()
                                if store.isRunActive(run.id) {
                                    ReceiptPill(text: "In progress", tint: Brand.blue)
                                } else if run.summary.interrupted {
                                    ReceiptPill(text: "Interrupted", tint: Brand.amber)
                                } else if verified {
                                    ReceiptPill(text: "Checked", tint: Brand.room)
                                } else if run.summary.recoverableCount > 0 {
                                    ReceiptPill(text: "Can put back", tint: Brand.textSecondary)
                                }
                                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Brand.textMuted)
                            }.padding(.vertical, 12).contentShape(Rectangle())
                        }.buttonStyle(.plain).overlay(alignment: .top) { if run.id != store.cleanupRuns.first?.id { sectionRule } }
                    }
                }
                .overlay(alignment: .top) { Rectangle().fill(Brand.separator).frame(height: 1) }
                .padding(.bottom, 24)
            }
            HStack {
                Text("Recorded actions").font(.system(size: 14, weight: .medium))
                Spacer()
                Text("\(entries.count) shown").font(.system(size: 11)).foregroundStyle(Brand.textMuted)
            }.padding(.bottom, 12)
            if entries.isEmpty {
                WorkspaceEmpty(title: search.isEmpty ? "No recorded actions" : "No matching actions",
                    message: search.isEmpty ? "Reviewed cleanups will appear here with their original path and recovery status." : "Try another search to find a recorded action.",
                    icon: "clock.arrow.circlepath")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        Button { focused = entry.id; restoreMessage = "" } label: {
                            HStack(spacing: 13) {
                                Image(systemName: entry.restoredAt != nil ? "arrow.uturn.backward.circle" : "doc")
                                    .font(.system(size: 20)).foregroundStyle(Brand.textSecondary).frame(width: 30)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.textPrimary)
                                    Text(entry.originalPath).font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                                        .lineLimit(1).truncationMode(.middle)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Text(Fmt.size(entry.bytes)).font(.system(size: 12)).monospacedDigit()
                                    .foregroundStyle(Brand.textSecondary).frame(width: 93, alignment: .trailing)
                                Text(status(for: entry)).font(.system(size: 11))
                                    .foregroundStyle(availableTrash.contains(entry.id) ? Brand.deepBlue : Brand.textMuted)
                                    .frame(width: 104, alignment: .trailing)
                                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Brand.textMuted)
                            }.padding(.horizontal, 5).frame(minHeight: 68).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .overlay(alignment: .bottom) { sectionRule }
                    }
                }
            }
            Text("Recorded size is an estimate, not space freed. History does not expire automatically; Trash contents can still disappear outside Cairn.")
                .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 18)
            if preview { sampleFootnote }
        }
    }

    private func itemDetail(_ entry: ScanStore.RemovalLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            backToActivity
            HStack(alignment: .top, spacing: 15) {
                Image(systemName: entry.restoredAt != nil ? "checkmark.circle.fill" : availableTrash.contains(entry.id) ? "clock.arrow.circlepath" : "exclamationmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(entry.restoredAt != nil ? Brand.safeCyan : availableTrash.contains(entry.id) ? Brand.deepBlue : Brand.amber)
                    .frame(width: 44, alignment: .leading).padding(.top, 2)
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.name).font(.system(size: 30, weight: .light))
                    Text("\(entry.date.formatted(date: .abbreviated, time: .shortened)) · Recorded action")
                        .font(.system(size: 13)).foregroundStyle(Brand.textMuted)
                }
            }.padding(.top, 33)
            HStack(alignment: .top, spacing: 30) {
                metric(title: "Recorded file size", value: Fmt.size(entry.bytes), detail: "Estimate · not space freed")
                Rectangle().fill(Brand.separator).frame(width: 1, height: 91)
                metric(title: "Recovery", value: status(for: entry),
                       detail: entry.restoredAt != nil ? "Already put back" : availableTrash.contains(entry.id) ? "Exact Trash item found" : "Original item cannot be restored here")
            }.padding(.leading, 44).padding(.top, 34).padding(.bottom, 28)
            sectionRule
            detailLine("Original location", entry.originalPath)
            detailLine("Recorded Trash location", entry.trashPath ?? "No Trash path was recorded for this action.")
            detailLine("What this means", "This individual history record has no verified available-space change. Moving a file to Trash does not immediately free internal capacity.")
            if !restoreMessage.isEmpty {
                CairnStateView(kind: restoreSucceeded ? .completed : .attention,
                               title: restoreSucceeded ? "Item restored" : "Restore could not finish",
                               message: restoreMessage, compact: true).padding(.top, 16)
            }
            safetyNotices.padding(.top, 16)
            if preview { sampleFootnote }
        }
    }

    private var receiptActionBar: some View {
        HStack(spacing: 9) {
            Spacer()
            if checkingSpace { ProgressView().controlSize(.small) }
            Button(checkingSpace ? "Checking…" : "Check available space") { checkSpace() }
                .buttonStyle(ControlPanelButtonStyle(primary: true)).disabled(preview || checkingSpace)
            Button("Done") { showingAllActivity = true }.buttonStyle(ControlPanelButtonStyle())
        }
        .padding(.horizontal, inset).frame(height: 72)
        .background(Brand.deepPanel.opacity(0.35))
        .overlay(alignment: .top) { sectionRule }
    }

    private func itemActionBar(_ entry: ScanStore.RemovalLogEntry) -> some View {
        HStack(spacing: 9) {
            Spacer()
            if let path = entry.trashPath, availableTrash.contains(entry.id) {
                Button("Show in Trash") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                    .buttonStyle(ControlPanelButtonStyle()).disabled(preview)
                Button("Put Back…") { restorePlan = entry; confirmRestore = true }
                    .buttonStyle(ControlPanelButtonStyle(primary: true))
                    .disabled(preview || store.isRestoring || store.isCleaning || store.isScanning)
            }
            Button("Done") { focused = nil; showingAllActivity = true }.buttonStyle(ControlPanelButtonStyle())
        }
        .padding(.horizontal, inset).frame(height: 72)
        .background(Brand.deepPanel.opacity(0.35))
        .overlay(alignment: .top) { sectionRule }
    }

    private var safetyNotices: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = store.receiptError ?? store.removalLogError ?? journalError, !preview {
                CairnStateView(kind: .attention, title: "Recovery history needs attention", message: error, compact: true)
            }
            if !needsManualReview.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Action needs manual review", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.amber)
                    Text("A move may have been interrupted or its recovery record may be missing. Cairn will not replay it. Check the original and Trash locations before further cleanup.")
                        .font(.system(size: 11)).foregroundStyle(Brand.textSecondary)
                    ForEach(needsManualReview.prefix(5)) { entry in
                        HStack {
                            Text("\(entry.state == .pending ? "Uncertain" : "Recovery record missing") · \(entry.path)")
                                .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                                .lineLimit(2).textSelection(.enabled)
                            Spacer()
                            if entry.state == .pending {
                                Button("Review…") { reviewing = entry }.buttonStyle(ControlPanelButtonStyle())
                            }
                        }
                    }
                    Button("Show action journal") { NSWorkspace.shared.activateFileViewerSelecting([ActionJournal.shared.location]) }
                        .buttonStyle(ControlPanelButtonStyle())
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Brand.surfaceElevated, in: RoundedRectangle(cornerRadius: Brand.rCard))
            }
            if !reviewMessage.isEmpty {
                CairnStateView(kind: .completed, title: "Manual review recorded", message: reviewMessage, compact: true)
            }
            let reviewed = actionJournal.filter { $0.state == .reviewed }
            if !reviewed.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("REVIEWED UNCERTAIN ACTIONS").font(.system(size: 10, weight: .medium)).tracking(0.6).foregroundStyle(Brand.textMuted)
                    ForEach(Array(reviewed.suffix(3).reversed())) { entry in
                        Text("\(entry.path) · outcome unknown").font(.system(size: 11)).foregroundStyle(Brand.textMuted).textSelection(.enabled)
                    }
                }.padding(.vertical, 10)
            }
        }
    }

    private var backToActivity: some View {
        Button { focused = nil; showingAllActivity = true } label: {
            Label("All activity", systemImage: "chevron.left")
        }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Brand.deepBlue)
    }
    private var sectionRule: some View { Rectangle().fill(Brand.separator).frame(height: 0.5) }
    private var sampleFootnote: some View {
        Text("Design preview · Sample data · Actions disabled")
            .font(.system(size: 10)).foregroundStyle(Brand.textMuted).padding(.top, 26)
    }
    private func purgeFromTrash(_ ids: Set<UUID>) {
        guard !purging else { return }
        purging = true
        Task {
            let result = await store.deleteFromTrash(ids)
            purged.formUnion(ids)
            purgedBytes += result.bytes
            await StorageControl.shared.refreshCapacity(force: true)
            currentCapacity = StorageControl.shared.current
            await refresh()
            purging = false
        }
    }
    private func metric(title: String, value: String, detail: String, accent: Color = Brand.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13)).foregroundStyle(Brand.textSecondary)
            Text(value).font(.system(size: 43, weight: .regular)).monospacedDigit().minimumScaleFactor(0.68).lineLimit(1)
                .foregroundStyle(accent)
            Text(detail).font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func detailLine(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Brand.textMuted)
            Text(value).font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 17).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { sectionRule }
    }
    private func status(for entry: ScanStore.RemovalLogEntry) -> String {
        if entry.restoredAt != nil { return "Restored" }
        if availableTrash.contains(entry.id) { return "In Trash" }
        if entry.actionKind == "tool" { return "Tool action" }
        if entry.actionKind == "delete" || purged.contains(entry.id) { return "Deleted" }
        return "Unavailable"
    }
    private func capacityDetail(_ receipt: ActivityReceipt) -> String {
        if preview { return "No measured increase yet" }
        guard let capacity else { return "Check available space to obtain a current reading" }
        let checked = "Checked \(capacity.date.formatted(date: .omitted, time: .shortened))"
        guard let change = receipt.capacityChanges.first(where: { $0.after?.volumeID == capacity.volumeID }),
              let delta = change.delta else { return checked + " · No comparable cleanup reading" }
        return checked + " · At cleanup: " + (delta == 0 ? "no measured change" : change.changeText.lowercased())
    }
    private func checkSpace() {
        guard !preview, !checkingSpace else { return }
        checkingSpace = true
        Task {
            await StorageControl.shared.refreshCapacity(force: true)
            currentCapacity = StorageControl.shared.current
            await refresh()
            checkingSpace = false
        }
    }
    private func refresh() async {
        guard !preview else { availableTrash = Set(Self.sampleEntries.map(\.id)); return }
        _ = await store.reconcileActionJournal()
        await store.loadCleanupRuns()
        let records = store.removalLog
        availableTrash = await Task.detached(priority: .utility) {
            Set(records.filter { entry in
                guard entry.recoverable, let path = entry.trashPath else { return false }
                let identity = SourceIdentity.read(URL(fileURLWithPath: path))
                return identity != nil && (entry.trashIdentity == nil || entry.trashIdentity == identity)
            }.map(\.id))
        }.value
        let journal = await Task.detached(priority: .utility) { (ActionJournal.shared.recent, ActionJournal.shared.error) }.value
        actionJournal = journal.0; journalError = journal.1
    }
}

private struct ActivityReceipt {
    struct Row: Identifiable {
        let id: String
        let name: String
        let bytes: Int64?
        let recoveryID: UUID?
        let trashPath: String?
    }
    let date: Date?
    let movedCount: Int
    let movedBytes: Int64
    let skippedCount: Int
    let recoveryCount: Int
    let missingRecoveryCount: Int
    let toolCount: Int
    let toolBytes: Int64
    let interrupted: Bool
    let rows: [Row]
    let hiddenRowCount: Int
    let issues: [String]
    let capacityChanges: [CleanupCapacityChange]
    var inProgress = false
    var freedBytes: Int64 = 0
    var inTrashBytes: Int64 { max(0, movedBytes + toolBytes - freedBytes) }

    var title: String {
        if inProgress { return "Cleanup in progress" }
        if interrupted { return "Cleanup stopped" }
        if skippedCount == 1 { return "Finished with one skipped item" }
        if skippedCount > 1 { return "Finished with \(skippedCount) skipped items" }
        return "Cleanup finished"
    }
    static var sample: Self {
        Self(date: Date(), movedCount: 2, movedBytes: 3_100_000_000, skippedCount: 1,
             recoveryCount: 2, missingRecoveryCount: 0, toolCount: 0, toolBytes: 0, interrupted: false,
             rows: [Row(id: "old-installer", name: "Old-installer.dmg", bytes: 940_000_000, recoveryID: nil, trashPath: nil),
                    Row(id: "assets-export", name: "Assets-export.zip", bytes: 2_160_000_000, recoveryID: nil, trashPath: nil)],
             hiddenRowCount: 0, issues: ["Product-demo.mov: file changed since review."], capacityChanges: [])
    }
}


private struct ReceiptPill: View {
    let text: String
    let tint: Color
    var body: some View {
        let quiet = tint == Brand.textSecondary
        Text(text).font(.system(size: 11.5))
            .foregroundStyle(tint)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(tint.opacity(quiet ? 0.25 : 0.32), lineWidth: 0.75))
    }
}

/// Free space over the last month, with a dot for each clean that released space.
/// Replaces the separate Changes chart as the first thing Activity shows.
struct FreeSpaceCard: View {
    struct Clean: Identifiable {
        let date: Date
        let freed: Int64
        var id: Date { date }
    }
    let readings: [CapacityReading]
    let cleans: [Clean]
    var onChanges: () -> Void

    private var freedThisMonth: Int64 { cleans.reduce(0) { $0 + $1.freed } }
    private func available(near date: Date) -> Double {
        let reading = readings.first { $0.date >= date } ?? readings.last
        return Double(reading?.available ?? 0) / 1e9
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Free space, last 30 days").eyebrow()
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(readings.last.map { "\(Fmt.size($0.available)) free" } ?? "No readings yet")
                            .font(.system(size: 30, weight: .light)).monospacedDigit()
                        if freedThisMonth > 0 {
                            Text("· \(Fmt.size(freedThisMonth)) freed this month")
                                .font(.system(size: 12.5)).foregroundStyle(Brand.textMuted)
                        }
                    }
                }
                Spacer()
                Button("What changed", action: onChanges)
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Brand.deepBlue)
            }
            if readings.count >= 2 {
                let high = (readings.map { Double($0.available) / 1e9 }.max() ?? 1) * 1.15
                Chart {
                    ForEach(readings) { reading in
                        AreaMark(x: .value("Date", reading.date), y: .value("GB", Double(reading.available) / 1e9))
                            .foregroundStyle(LinearGradient(colors: [Brand.room.opacity(0.16), Brand.room.opacity(0)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Date", reading.date), y: .value("GB", Double(reading.available) / 1e9))
                            .foregroundStyle(Brand.room).lineStyle(StrokeStyle(lineWidth: 1.7, lineJoin: .round))
                            .shadow(color: Brand.room.opacity(0.6), radius: 4)
                    }
                    ForEach(cleans.filter { clean in readings.first.map { clean.date >= $0.date } ?? false }) { clean in
                        PointMark(x: .value("Date", clean.date), y: .value("GB", available(near: clean.date)))
                            .symbol { Circle().fill(Brand.background).overlay(Circle().strokeBorder(Brand.room, lineWidth: 1.6)).frame(width: 9, height: 9) }
                            .annotation(position: .top, alignment: .center, spacing: 4) {
                                Text("+\(Fmt.size(clean.freed))").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Brand.room)
                            }
                    }
                }
                .chartYScale(domain: 0...max(1, high))
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3])).foregroundStyle(Brand.separator)
                    AxisValueLabel { if let gb = value.as(Double.self) { Text("\(Int(gb)) GB") } }
                } }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                .frame(height: 130)
                .accessibilityLabel("Free space over the last 30 days, with \(cleans.count) cleans marked")
            } else {
                Text("A line appears here once Cairn has checked your free space a few times.")
                    .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: Brand.rHero).fill(Brand.wash(0.02)))
        .overlay(RoundedRectangle(cornerRadius: Brand.rHero).strokeBorder(Brand.separator, lineWidth: 1))
    }
}
