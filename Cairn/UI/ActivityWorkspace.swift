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
    @State private var openReceipt = false
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
    @State private var purged: Set<UUID> = []
    @State private var purgedBytes: Int64 = 0
    @State private var purging = false
    @State private var confirmPurge = false

    private let preview = CommandLine.arguments.contains("--preview-ui")
    private let inset: CGFloat = 40

    /// The reference result screen's clean, for the design preview and the showcase's Done screen.
    static var sampleSummary: ScanStore.CleanSummary {
        var result = ScanStore.CleanSummary(failed: 1, errors: ["Xcode build files · Xcode was open"])
        for bytes in [8_200_000_000, 5_100_000_000, 3_400_000_000, 1_900_000_000, 1_000_000_000] as [Int64] {
            result.accounting.record(.init(bytesAffected: bytes, usedTool: false))
        }
        result.accounting.record(.init(bytesAffected: 1_600_000_000, usedTool: true))
        result.accounting.record(.init(bytesAffected: 800_000_000, usedTool: true))
        result.capacityChanges = [.init(id: "sample",
                                        before: .init(volumeID: "sample", name: "Macintosh HD", available: 9_900_000_000),
                                        after: .init(volumeID: "sample", name: "Macintosh HD", available: 31_900_000_000))]
        return result
    }
    /// The showcase's Done screen: the 38.6 GB from Home and the review sheet,
    /// freed straight away, with free space rising from 42.6 to 81.2 GB.
    static var showcaseSummary: ScanStore.CleanSummary {
        var result = ScanStore.CleanSummary(failed: 0, errors: [])
        for bytes in [14_200_000_000, 5_200_000_000, 2_500_000_000, 1_800_000_000, 5_100_000_000] as [Int64] {
            result.accounting.record(.init(bytesAffected: bytes, usedTool: false, deleted: true))
        }
        result.accounting.record(.init(bytesAffected: 9_800_000_000, usedTool: true, deleted: true))
        let before = PreviewStorageScenario.availableBytes
        result.capacityChanges = [.init(id: "sample",
                                        before: .init(volumeID: "sample", name: "Macintosh HD", available: before),
                                        after: .init(volumeID: "sample", name: "Macintosh HD", available: before + 38_600_000_000))]
        return result
    }
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
        if preview { return PreviewStorageScenario.cleans.map { .init(date: $0.date, freed: $0.freed) } }
        return store.cleanupRuns.compactMap { run in
            let freed = Self.freed(run.summary)
            return freed > 0 ? FreeSpaceCard.Clean(date: run.finished ?? run.started, freed: freed) : nil
        }
    }
    static func freed(_ summary: ScanStore.CleanSummary) -> Int64 { summary.freedBytes }
    private var capacity: CapacityReading? {
        if preview { return PreviewStorageScenario.current }
        return currentCapacity ?? StorageControl.shared.current
    }

    /// Freed in the last 30 days, the same window as the chart.
    private var freedThisMonth: Int64 {
        let start = Date().addingTimeInterval(-30 * 86_400)
        return freeSpaceCleans.filter { $0.date >= start }.reduce(0) { $0 + $1.freed }
    }
    private var overviewTitle: String {
        if freedThisMonth > 0 { return "\(Fmt.size(freedThisMonth)) freed this past month" }
        if preview || !store.cleanupRuns.isEmpty { return "Nothing freed this past month" }
        return "No cleans yet"
    }
    private var showsOverview: Bool {
        inspected == nil && !showingAllActivity && !(openReceipt && openedRun != nil)
    }
    /// The clean whose receipt is open, with when it ran.
    private var openedRun: (summary: ScanStore.CleanSummary, date: Date?)? {
        if preview { return (Self.sampleSummary, Date().addingTimeInterval(-86_400)) }
        let id = selectedRunID ?? store.lastCleanRunID
        let run = store.cleanupRuns.first { $0.id == id }
        let live = selectedRunID == nil || selectedRunID == store.lastCleanRunID ? store.lastCleanSummary : nil
        guard let summary = live ?? run?.summary else { return nil }
        return (summary, run?.finished ?? run?.started)
    }
    /// This receipt's items that are still in the Trash, by their recovery record.
    private var deletableIDs: Set<UUID> {
        Set((receipt?.rows ?? []).compactMap { row in
            row.recoveryID.flatMap { availableTrash.contains($0) && !purged.contains($0) ? $0 : nil }
        })
    }

    /// What this receipt's items still hold in the Trash right now.
    private var stillInTrashBytes: Int64 {
        (receipt?.rows ?? []).reduce(0) { total, row in
            guard let id = row.recoveryID, availableTrash.contains(id), !purged.contains(id) else { return total }
            return total + (row.bytes ?? 0)
        }
    }
    /// What one receipt moved, grouped by folder name ("node_modules", "dist").
    private struct ReceiptGroup: Identifiable {
        let name: String
        let count: Int
        let bytes: Int64
        let inTrash: Bool
        var id: String { name }
    }
    private var receiptGroups: [ReceiptGroup] {
        Dictionary(grouping: receipt?.rows ?? [], by: \.name).map { name, rows in
            ReceiptGroup(name: name, count: rows.count, bytes: rows.reduce(0) { $0 + ($1.bytes ?? 0) },
                         inTrash: rows.contains { row in
                             row.recoveryID.map { availableTrash.contains($0) && !purged.contains($0) } ?? false
                         })
        }
        .sorted { $0.bytes > $1.bytes }
    }

    /// A past receipt opened from Activity: a page like the others, top aligned,
    /// with the number, three plain figures and what the clean actually moved.
    private func receiptPage(_ summary: ScanStore.CleanSummary, date: Date?) -> some View {
        let freed = summary.freedBytes
        let moved = max(0, summary.accounting.trashBytes - summary.accounting.freedBytes)
        let inTrashNow = preview ? moved : stillInTrashBytes
        let change = summary.capacityChanges.first { $0.before != nil && $0.after != nil }
        let groups = receiptGroups
        let shown = Array(groups.prefix(6))
        let hidden = groups.dropFirst(6).reduce(0) { $0 + $1.count } + (receipt?.hiddenRowCount ?? 0)
        let line: String = {
            if freed > 0, let change, (change.delta ?? 0) > 0 { return "Checked on \(change.name) before and after." }
            if moved > 0 && inTrashNow > 0 { return "Moved to the Trash. Empty it to get the space back, or put items back." }
            if moved > 0 { return "Moved to the Trash, and the Trash has since been emptied." }
            return "Cleaned with each tool's own command."
        }()
        return VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 0) {
                Button { openReceipt = false } label: {
                    HStack(spacing: 6) { Image(systemName: "chevron.left").font(.system(size: 9, weight: .semibold)); Text("Activity") }
                }
                .buttonStyle(.plain)
                Text(" · Receipt" + (date.map { " · \($0.formatted(.dateTime.day().month(.wide))), \($0.formatted(date: .omitted, time: .shortened))" } ?? ""))
            }
            .nightEyebrow()
            .frame(height: 28)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    CountingBytes(bytes: freed > 0 ? freed : max(moved, summary.bytes), duration: 0.8, still: true)
                        .font(.system(size: 60, weight: .light)).tracking(-2.4)
                    Text(freed > 0 ? "freed" : "cleaned").font(.system(size: 20)).foregroundStyle(Brand.textMuted)
                }
                .lineLimit(1).minimumScaleFactor(0.5)
                Text(line).font(.system(size: 13.5)).foregroundStyle(Brand.textSecondary)
            }

            HStack(spacing: 0) {
                figure("Items", "\(summary.trashed) cleaned")
                figure("Skipped", summary.failed > 0 ? "\(summary.failed)" : "None",
                       tint: summary.failed > 0 ? Brand.amber : Brand.textPrimary, divider: true)
                figure("Free space", change.flatMap { c in
                    guard let before = c.before?.available, let after = c.after?.available else { return nil }
                    return "\(Fmt.size(before)) → \(Fmt.size(after))"
                } ?? "Not measured", divider: true)
            }
            .overlay(alignment: .top) { Rectangle().fill(Brand.wash(0.07)).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Brand.wash(0.07)).frame(height: 1) }

            VStack(alignment: .leading, spacing: 4) {
                Text("What was cleaned").nightEyebrow()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(shown) { group in
                            HStack(spacing: 14) {
                                Image(systemName: "folder").font(.system(size: 13)).foregroundStyle(Brand.textMuted).frame(width: 22)
                                NightName(title: group.name,
                                          subtitle: "\(group.count) \(group.count == 1 ? "item" : "items")")
                                Text(Fmt.size(group.bytes)).font(.system(size: 13, weight: .medium)).monospacedDigit()
                                    .frame(width: 90, alignment: .trailing)
                                NightPill(text: group.inTrash ? "In Trash" : "Emptied")
                                    .frame(width: 110, alignment: .leading)
                            }
                            .nightRow()
                        }
                        if summary.toolCount > 0 {
                            HStack(spacing: 14) {
                                Image(systemName: "terminal").font(.system(size: 13)).foregroundStyle(Brand.textMuted).frame(width: 22)
                                NightName(title: "Cleaned by their own tools",
                                          subtitle: "\(summary.toolCount) \(summary.toolCount == 1 ? "command" : "commands")")
                                Text(Fmt.size(summary.accounting.toolBytes)).font(.system(size: 13, weight: .medium)).monospacedDigit()
                                    .frame(width: 90, alignment: .trailing)
                                NightPill(text: "Done", tone: .ok).frame(width: 110, alignment: .leading)
                            }
                            .nightRow()
                        }
                        if summary.failed > 0 {
                            HStack(spacing: 14) {
                                Image(systemName: "exclamationmark.circle").font(.system(size: 13)).foregroundStyle(Brand.amber).frame(width: 22)
                                NightName(title: "Skipped", subtitle: "\(summary.failed) \(summary.failed == 1 ? "item" : "items")"
                                          + (summary.errors.first.map { " · \($0)" } ?? ""))
                                Text("—").foregroundStyle(Brand.textMuted).frame(width: 90, alignment: .trailing)
                                NightPill(text: "Skipped", tone: .warn).frame(width: 110, alignment: .leading)
                            }
                            .nightRow()
                        }
                        if hidden > 0 {
                            Button("See all \((receipt?.rows.count ?? 0) + (receipt?.hiddenRowCount ?? 0)) items") { focused = nil; showingAllActivity = true }
                                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Brand.deepBlue).padding(.top, 12)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            HStack(spacing: 10) {
                Text("Free space can also change because of other apps and macOS, so Cairn records it rather than claiming it.")
                    .font(.system(size: 12)).foregroundStyle(Brand.textMuted).lineLimit(2)
                Spacer(minLength: 16)
                if let emptyTrashAction {
                    Button("Empty from Trash…", action: emptyTrashAction).buttonStyle(ControlPanelButtonStyle(size: .large))
                }
                Button("Moved items") { focused = nil; showingAllActivity = true }
                    .buttonStyle(ControlPanelButtonStyle(size: .large))
                Button("Done") { openReceipt = false }
                    .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.top, 22).padding(.horizontal, inset).padding(.bottom, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(Brand.textPrimary)
    }

    private func figure(_ label: String, _ value: String, tint: Color = Brand.textPrimary, divider: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).nightEyebrow()
            Text(value).font(.system(size: 22, weight: .light)).foregroundStyle(tint).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.vertical, 14).padding(.leading, divider ? 20 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) { if divider { Rectangle().fill(Brand.wash(0.07)).frame(width: 1) } }
    }

    private var emptyTrashAction: (() -> Void)? {
        guard !preview, !deletableIDs.isEmpty else { return nil }
        return { confirmPurge = true }
    }

    var body: some View {
        Group {
            if showsOverview {
                overview
            } else if inspected == nil && !showingAllActivity, let opened = openedRun {
                receiptPage(opened.summary, date: opened.date)
                    .disabled(purging)
                    .confirmationDialog("Empty \(deletableIDs.count) \(deletableIDs.count == 1 ? "item" : "items") from the Trash?", isPresented: $confirmPurge) {
                        Button("Empty permanently", role: .destructive) { purgeFromTrash(deletableIDs) }
                    } message: {
                        Text("The space is released straight away. Put Back will no longer be possible for these items.")
                    }
            } else {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if let entry = inspected { itemDetail(entry) } else { activityList }
                        }
                        .padding(.horizontal, inset).padding(.top, 22).padding(.bottom, 28)
                        .frame(maxWidth: 1200, alignment: .leading).frame(maxWidth: .infinity)
                    }
                    .frame(maxHeight: .infinity)
                    if let entry = inspected { itemActionBar(entry) }
                }
            }
        }
        .background(Brand.background)
        .foregroundStyle(Brand.textPrimary)
        .task {
            await refresh()
            if !preview {
                await StorageControl.shared.refreshCapacity(force: true)
                currentCapacity = StorageControl.shared.current
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

    /// The Activity screen from the reference: how much was freed, the free space
    /// line, and one row per clean with its checked amount and a way into its receipt.
    private var overview: some View {
        NightPage(eyebrow: "Activity", title: overviewTitle,
                  subtitle: "Every clean leaves a receipt. Space is checked on your Mac before and after.") {
            Button("What changed") { onOpen(.changes) }
                .buttonStyle(ControlPanelButtonStyle(size: .small))
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    FreeSpaceCard(readings: freeSpaceReadings, cleans: freeSpaceCleans)
                    if hasSafetyNotices { safetyNotices }
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(runLines) { line in runRow(line) }
                        if runLines.isEmpty {
                            NightEmpty(title: "No receipts yet",
                                       message: "When you clean, the receipt appears here with the space checked before and after.")
                        }
                    }
                    if !preview && !allEntries.isEmpty {
                        Button("Moved items and Put Back") { focused = nil; showingAllActivity = true }
                            .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Brand.deepBlue)
                    }
                }
            }
            .scrollIndicators(.automatic)
        }
    }

    private struct RunLine: Identifiable {
        let id: UUID
        let title: String
        let date: Date
        let amount: String
        let pill: String
        let tone: NightPill.Tone
    }

    private var runLines: [RunLine] {
        if preview {
            let day: TimeInterval = 86_400
            return [RunLine(id: UUID(), title: "Xcode, Docker and npm", date: Date().addingTimeInterval(-11 * day), amount: "Freed 14.0 GB", pill: "Checked", tone: .ok),
                    RunLine(id: UUID(), title: "Developer caches and simulators", date: Date().addingTimeInterval(-21 * day), amount: "Freed 17.1 GB", pill: "Checked", tone: .ok)]
        }
        return store.cleanupRuns.map { run in
            let freed = Self.freed(run.summary)
            let inTrash = max(0, run.summary.accounting.trashBytes - run.summary.accounting.freedBytes)
            let amount = freed > 0 ? "Freed \(Fmt.size(freed))"
                : inTrash > 0 ? "\(Fmt.size(inTrash)) in Trash"
                : "\(run.summary.accounting.completedCount) \(run.summary.accounting.completedCount == 1 ? "item" : "items")"
            let verified = run.summary.capacityChanges.contains { ($0.delta ?? 0) > 0 }
            let pill: (String, NightPill.Tone)
            if store.isRunActive(run.id) { pill = ("In progress", .neutral) }
            else if run.summary.interrupted { pill = ("Stopped", .warn) }
            else if verified { pill = ("Checked", .ok) }
            else if run.summary.failed > 0 { pill = ("\(run.summary.failed) skipped", .warn) }
            else if run.summary.recoverableCount > 0 { pill = ("Can put back", .neutral) }
            else { pill = ("Recorded", .neutral) }
            return RunLine(id: run.id, title: runTitle(run), date: run.started,
                           amount: amount, pill: pill.0, tone: pill.1)
        }
    }

    /// The row's grid from the reference: name and date | amount 130 | pill 110 | link 100.
    private func runRow(_ line: RunLine) -> some View {
        Button {
            selectedRunID = line.id; focused = nil; showingAllActivity = false; openReceipt = true
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.textPrimary)
                        .lineLimit(1).truncationMode(.tail)
                    Text("\(line.date.formatted(.dateTime.day().month(.wide))), \(line.date.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(line.amount).font(.system(size: 13, weight: .medium)).monospacedDigit()
                    .foregroundStyle(Brand.textPrimary).lineLimit(1)
                    .frame(width: 130, alignment: .trailing)
                NightPill(text: line.pill, tone: line.tone)
                    .frame(width: 110, alignment: .leading)
                Text("See receipt").font(.system(size: 12)).foregroundStyle(Brand.deepBlue)
                    .frame(width: 100, alignment: .trailing)
            }
            .nightRow()
        }
        .buttonStyle(.plain)
    }

    private static let categoryTitles: [String: String] = Dictionary(
        ScannerRegistry.all().map { ($0.info.id, $0.info.title) }, uniquingKeysWith: { first, _ in first })

    /// "Xcode, Docker and npm": what the clean touched, largest first, from the
    /// recorded items. Falls back to the run's own name for tool-only cleans.
    private func runTitle(_ run: CleanupRun) -> String {
        let trashPaths = Set(run.summary.restorable.map(\.trash.path))
        var bytes: [String: Int64] = [:]
        for entry in store.removalLog where entry.trashPath.map({ trashPaths.contains($0) }) == true {
            bytes[entry.category, default: 0] += entry.bytes
        }
        let names = bytes.sorted { $0.value > $1.value }
            .map { Self.categoryTitles[$0.key] ?? $0.key.replacingOccurrences(of: "-", with: " ").capitalized }
        switch names.count {
        case 0: return run.kind ?? "Clean"
        case 1: return names[0]
        case 2, 3: return names.dropLast().joined(separator: ", ") + " and " + names.last!
        default: return names.prefix(2).joined(separator: ", ") + " and \(names.count - 2) more"
        }
    }

    private func receiptLine(_ label: String, _ value: String, tint: Color = Brand.textPrimary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Brand.textSecondary).fixedSize()
            Spacer(minLength: 16)
            Text(value).fontWeight(.medium).foregroundStyle(tint).monospacedDigit()
                .lineLimit(1).truncationMode(.middle)
        }
        .font(.system(size: 12.5))
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.wash(0.06)).frame(height: 1) }
    }

    private var activityList: some View {
        VStack(alignment: .leading, spacing: 0) {
            backToActivity
            VStack(alignment: .leading, spacing: 4) {
                Text("Moved items").font(.system(size: 40, weight: .light)).tracking(-0.8)
                Text("Everything Cairn has moved, and Put Back while it is still in the Trash.")
                    .font(.system(size: 13)).foregroundStyle(Brand.textMuted)
            }.padding(.top, 20).padding(.bottom, 24)
            if hasSafetyNotices { safetyNotices.padding(.bottom, 16) }
            if !restoreMessage.isEmpty {
                CairnStateView(kind: restoreSucceeded ? .completed : .attention,
                               title: restoreSucceeded ? "Item restored" : "Restore could not finish",
                               message: restoreMessage, compact: true).padding(.bottom, 12)
            }
            if entries.isEmpty {
                NightEmpty(title: search.isEmpty ? "Nothing moved yet" : "No matching items",
                           message: search.isEmpty ? "Items you clean appear here with where they came from and whether they can be put back." : "Try another search.")
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(entries) { entry in
                        Button { focused = entry.id; restoreMessage = "" } label: {
                            HStack(spacing: 14) {
                                NightName(title: entry.name, subtitle: entry.originalPath)
                                Text(Fmt.size(entry.bytes)).font(.system(size: 13, weight: .medium)).monospacedDigit()
                                    .frame(width: 90, alignment: .trailing)
                                NightPill(text: status(for: entry),
                                          tone: entry.restoredAt != nil || availableTrash.contains(entry.id) ? .ok : .neutral)
                                    .frame(width: 110, alignment: .leading)
                            }
                            .nightRow()
                        }.buttonStyle(.plain)
                    }
                }
            }
            Text("Recorded size is an estimate, not space freed. History does not expire automatically; Trash contents can still disappear outside Cairn.")
                .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 18)
            if preview && !Showcase.active { sampleFootnote }
        }
    }

    private func itemDetail(_ entry: ScanStore.RemovalLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            backToActivity
            Text("Moved item · \(entry.date.formatted(.dateTime.day().month(.wide))), \(entry.date.formatted(date: .omitted, time: .shortened))")
                .nightEyebrow().padding(.top, 20)
            Text(entry.name).font(.system(size: 40, weight: .light)).tracking(-0.8)
                .lineLimit(1).truncationMode(.middle).minimumScaleFactor(0.6).padding(.top, 14)
            NightPill(text: status(for: entry),
                      tone: entry.restoredAt != nil || availableTrash.contains(entry.id) ? .ok : .neutral)
                .padding(.top, 12)
            VStack(spacing: 0) {
                receiptLine("Size when moved", Fmt.size(entry.bytes))
                receiptLine("Where it was", entry.originalPath)
                receiptLine("Where it is now", entry.restoredAt != nil ? "Back where it was"
                            : availableTrash.contains(entry.id) ? (entry.trashPath ?? "In the Trash") : "No longer in the Trash")
            }
            .textSelection(.enabled).frame(maxWidth: 720).padding(.top, 18)
            if !restoreMessage.isEmpty {
                CairnStateView(kind: restoreSucceeded ? .completed : .attention,
                               title: restoreSucceeded ? "Item restored" : "Restore could not finish",
                               message: restoreMessage, compact: true).padding(.top, 16)
            }
            if hasSafetyNotices { safetyNotices.padding(.top, 16) }
            if preview && !Showcase.active { sampleFootnote }
        }
    }

    private func itemActionBar(_ entry: ScanStore.RemovalLogEntry) -> some View {
        HStack(spacing: 10) {
            Spacer()
            if let path = entry.trashPath, availableTrash.contains(entry.id) {
                Button("Show in Trash") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                    .buttonStyle(ControlPanelButtonStyle(size: .large)).disabled(preview)
                Button("Put Back…") { restorePlan = entry; confirmRestore = true }
                    .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
                    .disabled(preview || store.isRestoring || store.isCleaning || store.isScanning)
            } else {
                Button("Done") { focused = nil }
                    .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
            }
        }
        .padding(.horizontal, inset).padding(.top, 6).padding(.bottom, 26)
    }

    private var hasSafetyNotices: Bool {
        (!preview && (store.receiptError ?? store.removalLogError ?? journalError) != nil)
            || !needsManualReview.isEmpty || !reviewMessage.isEmpty
            || actionJournal.contains { $0.state == .reviewed }
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
        Button {
            if focused != nil { focused = nil } else { showingAllActivity = false; openReceipt = false }
        } label: {
            Label(focused != nil ? "Moved items" : "Activity", systemImage: "chevron.left")
        }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Brand.deepBlue)
    }
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
    private func status(for entry: ScanStore.RemovalLogEntry) -> String {
        if entry.restoredAt != nil { return "Restored" }
        if availableTrash.contains(entry.id) { return "In Trash" }
        if entry.actionKind == "tool" { return "Tool action" }
        if entry.actionKind == "delete" || purged.contains(entry.id) { return "Deleted" }
        return "Unavailable"
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

/// Free space over the last month, drawn as in the reference: a thin ice line
/// with a soft glow, a hollow dot for each clean and a solid dot for today.
struct FreeSpaceCard: View {
    struct Clean: Identifiable {
        let date: Date
        let freed: Int64
        var id: Date { date }
    }
    let readings: [CapacityReading]
    let cleans: [Clean]

    private func gb(_ bytes: Int64) -> Double { Double(bytes) / 1e9 }
    private func available(near date: Date) -> Double {
        gb((readings.first { $0.date >= date } ?? readings.last)?.available ?? 0)
    }
    /// The plotted range hugs the line so a few GB of change is visible.
    private var range: ClosedRange<Double> {
        let values = readings.map { gb($0.available) }
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let span = max(hi - lo, max(hi * 0.1, 1))
        return max(0, lo - span * 0.5)...(hi + span * 0.3)
    }
    private var xTicks: [Date] {
        guard let first = readings.first?.date, let last = readings.last?.date, last > first else { return [] }
        let step = last.timeIntervalSince(first) / 3
        return (0...3).map { first.addingTimeInterval(Double($0) * step) }
    }
    private let axisInk = Brand.textMuted.opacity(0.72)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Free space · last 30 days").nightEyebrow()
                Spacer()
                HStack(spacing: 6) {
                    Circle().strokeBorder(Brand.room, lineWidth: 1.5).frame(width: 8, height: 8)
                    Text("Clean")
                }
                .font(.system(size: 11.5)).foregroundStyle(Brand.textMuted)
            }
            if readings.count >= 2 {
                let range = range
                Chart {
                    ForEach(readings) { reading in
                        AreaMark(x: .value("Date", reading.date),
                                 yStart: .value("Low", range.lowerBound),
                                 yEnd: .value("GB", gb(reading.available)))
                            .foregroundStyle(LinearGradient(colors: [Brand.room.opacity(0.18), Brand.room.opacity(0)],
                                                            startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Date", reading.date), y: .value("GB", gb(reading.available)))
                            .foregroundStyle(Brand.room)
                            .lineStyle(StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                            .shadow(color: Brand.room.opacity(0.55), radius: 4)
                    }
                    ForEach(cleans.filter { clean in readings.first.map { clean.date >= $0.date } ?? false }) { clean in
                        PointMark(x: .value("Date", clean.date), y: .value("GB", available(near: clean.date)))
                            .symbol {
                                Circle().fill(Brand.background)
                                    .overlay(Circle().strokeBorder(Brand.room, lineWidth: 1.6))
                                    .frame(width: 8, height: 8)
                            }
                    }
                    if let last = readings.last {
                        PointMark(x: .value("Date", last.date), y: .value("GB", gb(last.available)))
                            .symbol {
                                ZStack {
                                    Circle().fill(Brand.room.opacity(0.18)).frame(width: 18, height: 18)
                                    Circle().fill(Brand.room).frame(width: 9, height: 9)
                                }
                            }
                    }
                }
                .chartYScale(domain: range)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 4])).foregroundStyle(Brand.wash(0.06))
                        AxisValueLabel {
                            if let value = value.as(Double.self) {
                                Text(Fmt.size(Int64(value * 1e9))).font(.system(size: 10.5)).foregroundStyle(axisInk)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: xTicks) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(Calendar.current.isDateInToday(date) ? "Today" : date.formatted(.dateTime.day().month(.abbreviated)))
                                    .font(.system(size: 10.5)).foregroundStyle(axisInk)
                            }
                        }
                    }
                }
                .frame(height: 140)
                .accessibilityLabel("Free space over the last 30 days, with \(cleans.count) cleans marked")
            } else {
                Text("The line appears once Cairn has checked your free space a few times.")
                    .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            }
        }
        .padding(.top, 14).padding(.horizontal, 16).padding(.bottom, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.wash(0.02)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Brand.wash(0.07), lineWidth: 1))
    }
}
