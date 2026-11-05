import SwiftUI

/// Mandatory review between scan and clean (SPEC §4.4 / §5). Shows exact items,
/// what will happen to each one, quit-first warnings and how much space is freed
/// straight away under the chosen removal mode.
struct ReviewSheet: View {
    let store: ScanStore
    let proEnabled: Bool
    var goalPlan: ReviewedSpacePlan? = nil
    /// Fixed items for the showcase screenshot. Nothing in a sample is ever cleaned.
    var sample: ReviewSample? = nil
    var onDone: (ScanStore.CleanSummary) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var cleaning = false
    @State private var items: [ScanItem] = []
    @State private var expanded: Set<String> = []
    @State private var mode: RemovalMode = .smart
    @State private var acknowledgedPermanentDeletion = false
    /// The list's own height, so the sheet is only as tall as what it holds.
    @State private var listHeight: CGFloat?
    /// The most the list takes before it scrolls: the old fixed sheet was 600 points.
    private static let listRoom: CGFloat = 340

    private var runnable: [ScanItem] { items.filter { $0.isActionable && $0.severity != .risky } }
    private var skipped: [ScanItem] { items.filter { !$0.isActionable || $0.severity == .risky } }
    private var freedNow: Int64 { runnable.filter(freesNow).reduce(0) { $0 + $1.allocatedSize } }
    private var toTrash: Int64 { runnable.filter { !freesNow($0) }.reduce(0) { $0 + $1.allocatedSize } }
    private var hasPersonalFilesToDelete: Bool {
        mode == .delete && runnable.contains { !$0.isRegenerable && $0.cleanMethod == .trash }
    }
    private var runningBlockers: [String] {
        let ids = runnable.flatMap { $0.requiresQuitBundleIDs }
        return RunningApps.displayNames(for: RunningApps.running(amongst: Array(Set(ids))))
    }

    private func freesNow(_ item: ScanItem) -> Bool {
        switch item.cleanMethod {
        case .tool, .emptyTrash: return true
        case .trash: return mode.deletesImmediately(item)
        case .adviceOnly: return false
        }
    }

    /// The same total the button on the page showed, so the number never shrinks
    /// on the way in. The note underneath says which part is freed now and which
    /// part waits in the Trash.
    private var title: String {
        if freedNow > 0 && toTrash > 0 { return "Clean \(Fmt.size(freedNow + toTrash))" }
        if freedNow > 0 { return "Free \(Fmt.size(freedNow))" }
        if toTrash > 0 { return "Move \(Fmt.size(toTrash)) to the Trash" }
        return "Nothing to free"
    }
    /// Says plainly what can and cannot be put back afterwards.
    private var trashNote: String? {
        if hasPersonalFilesToDelete {
            return "These files will be deleted for good. They may be your only copies, and they can't be put back."
        }
        if freedNow > 0 && toTrash > 0 {
            return "\(Fmt.size(freedNow)) of caches and build files is freed straight away. They rebuild on their own when needed. "
                + "Your own files (\(Fmt.size(toTrash))) go to the Trash, where you can put them back. Empty the Trash to free that space too."
        }
        if freedNow > 0 {
            return "Caches and build files are removed straight away and can't be put back. They rebuild on their own when needed."
        }
        if toTrash > 0 {
            return "Your own files go to the Trash, where you can put them back. The space comes back when the Trash is emptied."
        }
        return nil
    }

    /// The review sheet from the reference (night-screens-v2.html, s2): eyebrow,
    /// light title, one line per tool with its size and status, then the promise
    /// and two buttons. Each tool's exact items open under it on request.
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(cleaning ? "Freeing space · keep Cairn open" : "Check once, then free").nightEyebrow()
                Text(title).font(.system(size: 30, weight: .light)).tracking(-0.6)
                if let trashNote {
                    // Wraps onto more lines rather than cutting off with "…".
                    Text(trashNote).font(.system(size: 13)).foregroundStyle(Brand.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groups, id: \.id) { groupRow($0) }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if $0 > 0 { listHeight = $0 } }
            }
            // A short list leaves no empty band above the buttons; a long one scrolls.
            .frame(height: min(listHeight ?? Self.listRoom, Self.listRoom))
            if runnable.contains(where: { $0.cleanMethod == .trash }) {
                VStack(alignment: .leading, spacing: 10) {
                    // The same switcher, heading and spacing as Settings › Appearance and Cleaning.
                    Text("For this clean").font(.system(size: 13, weight: .medium))
                    CairnSegmentedControl(label: "For this clean", selection: $mode,
                                          options: RemovalMode.allCases.map { ($0.title, $0) })
                        .frame(width: 360)
                        .disabled(cleaning || sample != nil || goalPlan != nil)
                    Text(goalPlan == nil
                         ? "Just for this clean. Tool commands and emptying the Trash can't be put back, whichever you pick."
                         : "This clean keeps the choice it was planned with. To pick differently, review the files from their own page.")
                        .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    if hasPersonalFilesToDelete {
                        HStack(alignment: .top, spacing: 10) {
                            NightCheck(on: acknowledgedPermanentDeletion, enabled: !cleaning) { acknowledgedPermanentDeletion.toggle() }
                                .accessibilityLabel("I understand my own files here will be deleted for good and can't be put back")
                            Text("I understand my own files here will be deleted for good and can't be put back.")
                                .font(.system(size: 12)).foregroundStyle(Brand.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .onTapGesture { if !cleaning { acknowledgedPermanentDeletion.toggle() } }
                        }
                    }
                }
            }
            notes
            footer
        }
        .padding(.vertical, 26).padding(.horizontal, 30)
        .frame(width: 760)
        .foregroundStyle(Brand.textPrimary)
        .background(Brand.surfaceElevated)
        .interactiveDismissDisabled(cleaning)
        .onChange(of: mode) { _, _ in acknowledgedPermanentDeletion = false }
        .task { mode = sample?.mode ?? AppSettings.shared.removalMode; items = sample?.items ?? goalPlan?.items ?? store.selectedItems() }
    }

    /// Items grouped by the tool or area that made them, largest group first.
    private struct ReviewGroup { let id: String; let title: String; let items: [ScanItem]; let bytes: Int64 }
    private var groups: [ReviewGroup] {
        Dictionary(grouping: runnable, by: \.categoryID).map { id, items in
            ReviewGroup(id: id, title: store.buckets.first { $0.id == id }?.info.title ?? sample?.titles[id] ?? id.capitalized,
                  items: items.sorted { $0.allocatedSize > $1.allocatedSize },
                  bytes: items.reduce(0) { $0 + $1.allocatedSize })
        }
        .sorted { $0.bytes > $1.bytes }
    }

    private func groupRow(_ group: ReviewGroup) -> some View {
        let open = expanded.contains(group.id)
        let state = status(of: group.items)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BrandLogo.forCategory(group.id, size: 22)
                Text(group.title).font(.system(size: 13, weight: .medium))
                Spacer(minLength: 12)
                Text(Fmt.size(group.bytes)).font(.system(size: 13, weight: .medium)).monospacedDigit()
                NightPill(text: state.text, tone: state.tone)
            }
            .padding(.top, 12).padding(.bottom, 2)
            HStack(spacing: 6) {
                Text(line(for: group))
                Button(open ? "Hide items" : "See \(group.items.count == 1 ? "item" : "items")") {
                    if open { expanded.remove(group.id) } else { expanded.insert(group.id) }
                }
                .buttonStyle(.plain).foregroundStyle(Brand.deepBlue)
                .accessibilityLabel("\(open ? "Hide" : "Show") items in \(group.title)")
            }
            .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
            .padding(.leading, 32).padding(.bottom, open ? 6 : 12)
            if open {
                ForEach(group.items) { itemRow($0, groupStatus: state.text) }
                    .padding(.bottom, 2)
                Spacer().frame(height: 8)
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.wash(0.06)).frame(height: 1) }
    }

    private func itemRow(_ item: ScanItem, groupStatus: String) -> some View {
        let state = status(of: [item])
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent).font(.system(size: 12.5)).foregroundStyle(Brand.textSecondary).lineLimit(1)
                Text(detail(item)).font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    .help(item.resolvedURL.path)
            }
            Spacer(minLength: 8)
            if state.text != groupStatus { NightPill(text: state.text, tone: state.tone) }
            Text(item.allocatedSize > 0 ? Fmt.size(item.allocatedSize) : "—")
                .font(.system(size: 12)).foregroundStyle(Brand.textSecondary).monospacedDigit()
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.leading, 32).padding(.vertical, 5)
    }

    /// One plain sentence: how much, and how it comes back or where it goes.
    private func line(for group: ReviewGroup) -> String {
        let n = group.items.count
        let what = "\(n) \(n == 1 ? "item" : "items")"
        if group.items.allSatisfy({ $0.cleanMethod.isPaid }) { return "\(what), cleaned with the tool's own command." }
        if group.items.allSatisfy({ $0.cleanMethod == .emptyTrash }) { return "\(what) emptied from the Trash for good." }
        if !group.items.contains(where: freesNow) {
            return "\(what), moved to the Trash so you can put \(n == 1 ? "it" : "them") back."
        }
        if group.items.allSatisfy(\.isRegenerable) { return "\(what). Your tools make them again when needed." }
        if group.items.contains(where: { !$0.isRegenerable && !freesNow($0) }) {
            return "\(what). Your own files among them go to the Trash."
        }
        return "\(what), including your own files, deleted for good."
    }

    /// One short line: the tool's own command, where it goes, or the path.
    private func detail(_ item: ScanItem) -> String {
        if case .tool(let command) = item.cleanMethod { return "Cleaned by the tool: \(command.display)" }
        if !freesNow(item), item.cleanMethod == .trash { return "Moves to Trash · \(item.resolvedURL.path)" }
        return item.resolvedURL.path
    }

    /// Three states only: Ready, Close app first, Needs you.
    private func status(of items: [ScanItem]) -> (text: String, tone: NightPill.Tone) {
        let running = RunningApps.displayNames(for: RunningApps.running(amongst: Array(Set(items.flatMap(\.requiresQuitBundleIDs)))))
        if let app = running.first { return ("Close \(app) first", .warn) }
        if items.contains(where: { !$0.isRegenerable || $0.severity != .safe }) { return ("Needs you", .neutral) }
        return ("Ready", .ok)
    }

    /// Shown only when they apply, as single quiet lines.
    private var noteLines: [(text: String, tint: Color)] {
        var lines: [(text: String, tint: Color)] = []
        // The button is never greyed out without a reason on screen.
        if !cleaning {
            if store.isScanning { lines.append(("A scan is running. Freeing starts once it finishes.", Brand.amber)) }
            else if store.isCleaning { lines.append(("Another clean is still running. Try again when it finishes.", Brand.amber)) }
            else if runnable.isEmpty { lines.append(("Nothing here can be removed by Cairn.", Brand.amber)) }
        }
        if hasPersonalFilesToDelete {
            lines.append(("Delete now is picked, so your own files here are deleted for good, not sent to the Trash.", Brand.amber))
        }
        if !skipped.isEmpty {
            lines.append(("\(skipped.count) advice-only \(skipped.count == 1 ? "item is" : "items are") left alone.", Brand.textMuted))
        }
        if let goalPlan { lines.append(("Aim: \(Fmt.size(goalPlan.target)) available", Brand.textMuted)) }
        return lines
    }
    @ViewBuilder private var notes: some View {
        if !noteLines.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(noteLines.indices, id: \.self) { i in
                    Text(noteLines[i].text).foregroundStyle(noteLines[i].tint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.system(size: 12))
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield").font(.system(size: 12))
                Text(runningBlockers.isEmpty
                     ? "Passwords, your emails, Photos, your code history and AI chats are never included."
                     : "Items from \(runningBlockers.joined(separator: ", ")) are skipped while it is open.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
            Spacer(minLength: 12)
            // No blue macOS focus ring when the sheet opens: these look like
            // every other button in Cairn. Escape still cancels.
            Button("Cancel") { dismiss() }
                .buttonStyle(ControlPanelButtonStyle(size: .large))
                .focusEffectDisabled()
                .keyboardShortcut(.cancelAction).disabled(cleaning)
            Button {
                Task { await runClean() }
            } label: {
                HStack(spacing: 8) {
                    if cleaning { ProgressView().controlSize(.small) }
                    Text(cleaning ? "Freeing…" : title)
                }
            }
            .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
            .focusEffectDisabled()
            // Deliberately no Return shortcut: removing files takes a click, never a stray key press.
            .disabled(!canClean)
        }
    }

    private var canClean: Bool {
        !cleaning && !store.isScanning && !store.isCleaning && !runnable.isEmpty
            && (!hasPersonalFilesToDelete || acknowledgedPermanentDeletion)
    }

    private func runClean() async {
        guard canClean else { return }
        guard sample == nil, !CommandLine.arguments.contains("--preview-ui") else { dismiss(); return }
        cleaning = true
        let summary = await store.clean(items, proEnabled: proEnabled, reviewedPlan: goalPlan, removal: mode)
        cleaning = false
        onDone(summary)
        dismiss()
    }
}

/// The review sheet's showcase contents: the website story's 38.6 GB, by tool.
struct ReviewSample {
    let items: [ScanItem]
    let titles: [String: String]
    var mode: RemovalMode = .smart

    /// Inert long review, including the personal-file acknowledgement.
    static var stress: ReviewSample {
        let items = (0..<12).map { index in
            ScanItem(url: URL(fileURLWithPath: "/Sample/Downloads/Personal archive \(index).zip"),
                     allocatedSize: 1_000_000_000, categoryID: "fixture-\(index)",
                     severity: .review, isRegenerable: false)
        }
        return ReviewSample(items: items,
            titles: Dictionary(uniqueKeysWithValues: (0..<12).map { ("fixture-\($0)", "Personal archive \($0)") }),
            mode: .delete)
    }

    static var showcase: ReviewSample {
        let home = FileScan.home
        func item(_ path: String, _ gigabytes: Double, _ category: String) -> ScanItem {
            ScanItem(url: home.appendingPathComponent(path), allocatedSize: Int64(gigabytes * 1_000_000_000),
                     categoryID: category, severity: .safe)
        }
        return ReviewSample(items: [
            item("Library/Developer/Xcode/DerivedData", 14.2, "xcode"),
            item("Library/Containers/com.docker.docker/Data/build-cache", 9.8, "docker"),
            item("Developer/storefront-web/node_modules", 5.2, "dev-projects"),
            item("Developer/design-system/node_modules", 2.5, "dev-projects"),
            item("Developer/marketing-site/node_modules", 1.8, "dev-projects"),
            item(".npm/_cacache", 5.1, "npm"),
        ], titles: ["xcode": "Xcode build files", "docker": "Docker build cache",
                    "dev-projects": "node_modules", "npm": "npm cache"])
    }
}
