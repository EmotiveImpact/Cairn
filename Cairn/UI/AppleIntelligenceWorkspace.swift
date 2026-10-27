import SwiftUI
import AppKit

/// Apple Intelligence: its models measured, an opt-in turn-off that lists what
/// stops working, and one Undo. Changes happen only through a profile the
/// person approves in System Settings and macOS's own asset service; Cairn
/// never touches a file under /System.
struct AppleIntelligenceWorkspace: View {
    private enum Phase: Equatable { case idle, approving, removing, undoing }

    private let preview = CommandLine.arguments.contains("--preview-ui")
    @State private var sizes: [String: Int64]?
    @State private var measuring = false
    @State private var chosen: Set<String>?
    @State private var installed = AppleIntelligence.Profile.Installed()
    @State private var phase: Phase = .idle
    @State private var confirming = false
    @State private var waiting: Task<Void, Never>?
    @State private var note: String?

    private var features: [AppleIntelligence.Feature] { preview ? AppleIntelligence.features : AppleIntelligence.availableFeatures }
    private var supported: Bool { preview || AppleIntelligence.supportedMac }
    private var choice: Set<String> { chosen ?? (preview ? AppleIntelligence.defaultChoice(among: features) : []) }
    private var shownSizes: [String: Int64]? { preview ? Self.sample : sizes }
    /// What goes: the choice before the profile is in, what the profile holds after.
    private var removing: [String] {
        installed.on ? AppleIntelligence.sets.map(\.id).filter { installed.sets.contains($0) }
                     : AppleIntelligence.setsToRemove(chosen: choice, among: features)
    }
    private var busy: Bool { phase != .idle }

    private func bytes(_ set: AppleIntelligence.ModelSet) -> Int64? { shownSizes.map { $0[set.assetType] ?? 0 } }
    private func total(_ ids: [String]) -> Int64? {
        guard let sizes = shownSizes else { return nil }
        return AppleIntelligence.sets.filter { ids.contains($0.id) }.reduce(0) { $0 + (sizes[$1.assetType] ?? 0) }
    }

    var body: some View {
        let sets = supported ? AppleIntelligence.available(among: features) : []
        let all = total(sets.map(\.id))
        let going = total(removing)
        let largest = max(1, sets.compactMap(bytes).max() ?? 1)
        NightHeroPage(eyebrow: "Clean · Apple Intelligence", lead: lead) {
            NightHeroNumber(number: all.map(Fmt.size) ?? (measuring ? "…" : "–"), label: "of Apple Intelligence models")
        } trailing: {
            Button { Task { await measure() } } label: { Label("Look again", systemImage: "arrow.clockwise") }
                .buttonStyle(ControlPanelButtonStyle(size: .small))
                .disabled(preview || measuring || busy || !supported)
        } content: {
            if !supported {
                NightEmpty(title: "Apple Intelligence isn't on this Mac",
                           message: "It needs a Mac with Apple silicon and macOS 15.1 or later, so there are no models here to remove.")
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    NightList { ForEach(sets) { row($0, largest: largest) } }
                        .frame(maxHeight: CGFloat(sets.count) * 62)
                    explain
                    if let note {
                        Text(note).font(.system(size: 12.5)).foregroundStyle(Brand.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } footer: {
            if supported { footer(going: going) }
        }
        .sheet(isPresented: $confirming) {
            TurnOffSheet(features: AppleIntelligence.featuresOff(removing: Set(removing), among: features),
                         bytes: going, onCancel: { confirming = false },
                         onConfirm: { confirming = false; turnOff() })
        }
        .task { await measure() }
        .onDisappear { waiting?.cancel(); waiting = nil; phase = .idle }
    }

    private var lead: String {
        installed.on
            ? "Apple Intelligence is off through Cairn's profile. Undo turns it back on, and macOS downloads the models again when a feature needs them."
            : "macOS downloads these on its own and has no single off switch. Cairn can turn the features off and have macOS remove the models. Undo brings them back."
    }

    // MARK: Rows

    private func row(_ set: AppleIntelligence.ModelSet, largest: Int64) -> some View {
        let size = bytes(set)
        let goes = removing.contains(set.id)
        let follows = goes && !installed.on && !choice.contains(set.id)
        return HStack(spacing: 16) {
            if !installed.on {
                NightCheck(on: goes, enabled: !follows && !busy) { toggle(set.id) }
            }
            NightName(logo: nil, title: set.title, subtitle: set.line, symbol: "sparkle", titleSize: 13.5)
            NightMeter(share: Double(size ?? 0) / Double(largest), width: 140)
            Text(size.map(Fmt.size) ?? "–").font(.system(size: 13.5, weight: .medium)).monospacedDigit()
                .frame(width: 70, alignment: .trailing)
            pill(goes: goes, follows: follows, size: size).frame(width: 170, alignment: .leading)
        }
        .nightHeroRow()
    }

    @ViewBuilder private func pill(goes: Bool, follows: Bool, size: Int64?) -> some View {
        if installed.on {
            if !goes { NightPill(text: "Kept on") }
            else if (size ?? 0) > 0 { NightPill(text: "Still here", tone: .warn) }
            else { NightPill(text: "Removed", tone: .ok) }
        } else if follows {
            NightPill(text: "Goes with main models", tone: .ok)
        } else {
            NightPill(text: goes ? "Turns off" : "Stays on", tone: goes ? .ok : .neutral)
        }
    }

    private func toggle(_ id: String) {
        var next = choice
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        chosen = next
        note = nil
    }

    @ViewBuilder private var explain: some View {
        if installed.on {
            NightExplain(strong: "Off through Cairn's profile. ",
                         rest: "To turn it back on, press Undo and remove the profile in System Settings. macOS downloads the models again the first time a feature needs them.")
        } else if !removing.isEmpty {
            let off = AppleIntelligence.featuresOff(removing: Set(removing), among: features).map(\.title)
            NightExplain(strong: "Stops working: ",
                         rest: Self.list(off) + ". Cairn never deletes files in /\u{2060}System; macOS removes the models itself, and Undo brings everything back.")
        }
    }

    // MARK: Footer

    @ViewBuilder private func footer(going: Int64?) -> some View {
        switch phase {
        case .approving:
            NightTotal(strong: "Waiting", rest: "for you in System Settings: open Cairn's profile and click Install", large: true)
            Spacer()
            Button("Cancel") { stopWaiting() }.buttonStyle(ControlPanelButtonStyle(size: .large))
            Button("Open System Settings") { AppleIntelligence.Profile.openSettings() }
                .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
        case .removing:
            ProgressView().controlSize(.small)
            NightTotal(strong: "Removing", rest: "macOS is taking the models off this Mac", large: true)
            Spacer()
        case .undoing:
            NightTotal(strong: "Waiting", rest: "for you in System Settings: select Cairn's profile and click Remove", large: true)
            Spacer()
            Button("Cancel") { stopWaiting() }.buttonStyle(ControlPanelButtonStyle(size: .large))
            Button("Open System Settings") { AppleIntelligence.Profile.openSettings() }
                .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
        case .idle:
            if installed.on {
                let left = going ?? 0
                NightTotal(strong: left > 0 ? Fmt.size(left) : "Off", rest: left > 0 ? "of models still here" : "Apple Intelligence is off", large: true)
                Spacer()
                if left > 0 {
                    Button("Remove the models") { Task { await removeModels() } }
                        .buttonStyle(ControlPanelButtonStyle(size: .large))
                        .disabled(preview)
                }
                Button("Undo") { undo() }
                    .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
                    .disabled(preview)
            } else {
                let count = AppleIntelligence.featuresOff(removing: Set(removing), among: features).count
                NightTotal(strong: going.map(Fmt.size) ?? "–", rest: "comes back · \(count) \(count == 1 ? "feature turns" : "features turn") off", large: true)
                Spacer()
                Button((going ?? 0) > 0 ? "Turn off and free \(Fmt.size(going ?? 0))" : "Turn off") { if !preview { confirming = true } }
                    .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
                    .disabled(removing.isEmpty || (!preview && measuring))
            }
        }
    }

    // MARK: Actions

    private func measure() async {
        guard !preview, supported else { return }
        if chosen == nil { chosen = AppleIntelligence.defaultChoice(among: features) }
        measuring = true
        sizes = await Task.detached(priority: .utility) { AppleIntelligence.AssetService.inventory() }.value
        installed = AppleIntelligence.Profile.installed()
        measuring = false
    }

    /// Step 1: the profile, which only the person can install. Step 2: macOS removes the models.
    private func turnOff() {
        let sets = Set(removing)
        guard !preview, !sets.isEmpty else { return }
        do { try AppleIntelligence.Profile.present(removing: sets) } catch {
            note = "Cairn couldn't write its profile, so nothing has changed. \(error.localizedDescription)"
            return
        }
        note = nil
        phase = .approving
        waiting?.cancel()
        waiting = Task { @MainActor in
            let approved = await Self.wait { AppleIntelligence.Profile.installed().sets == sets }
            guard !Task.isCancelled else { return }
            installed = AppleIntelligence.Profile.installed()
            phase = .idle
            if approved { await removeModels() }
            else { note = "The profile wasn't installed, so nothing has changed." }
        }
    }

    private func removeModels() async {
        let targets = removing
        guard !preview, installed.on, !targets.isEmpty else { return }
        phase = .removing
        let stayed = await Task.detached(priority: .userInitiated) { await AppleIntelligence.AssetService.remove(targets) }.value
        phase = .idle
        await measure()
        if stayed.isEmpty {
            note = "macOS is removing the models. Storage in System Settings can keep counting them for a while before the space shows."
        } else {
            note = stayed.map { item in
                "\(AppleIntelligence.sets.first { $0.id == item.set }?.title ?? item.set) stayed: \(item.reason)"
            }.joined(separator: " ") + " The features are still off and won't download again."
        }
    }

    private func undo() {
        guard !preview else { return }
        AppleIntelligence.Profile.openSettings()
        note = nil
        phase = .undoing
        waiting?.cancel()
        waiting = Task { @MainActor in
            let removed = await Self.wait { !AppleIntelligence.Profile.installed().on }
            guard !Task.isCancelled else { return }
            installed = AppleIntelligence.Profile.installed()
            phase = .idle
            note = removed
                ? "Apple Intelligence is back on. macOS downloads the models again the first time a feature needs them."
                : "The profile is still installed, so Apple Intelligence stays off."
        }
    }

    private func stopWaiting() {
        waiting?.cancel()
        waiting = nil
        installed = AppleIntelligence.Profile.installed()
        phase = .idle
    }

    /// Checks once a second for up to ten minutes while the person is in System Settings.
    private static func wait(until done: @escaping () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(600)
        while Date() < end {
            if Task.isCancelled { return false }
            if done() { return true }
            try? await Task.sleep(for: .seconds(1))
        }
        return done()
    }

    static func list(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
    }

    /// The approved System Data picture's 22 GB. Preview only; never acted on.
    private static let sample: [String: Int64] = [
        "com.apple.MobileAsset.UAF.FM.GenerativeModels": 16_800_000_000,
        AppleIntelligence.visual: 3_100_000_000,
        AppleIntelligence.code: 1_400_000_000,
        AppleIntelligence.cleanUp: 500_000_000,
        AppleIntelligence.spatial: 200_000_000,
    ]
}

/// What stops working, how it happens and how to undo it, before anything changes.
private struct TurnOffSheet: View {
    let features: [AppleIntelligence.Feature]
    let bytes: Int64?
    var onCancel: () -> Void
    var onConfirm: () -> Void

    var body: some View {
        CairnDialog(title: "Turn off Apple Intelligence?",
                    subtitle: bytes.map { "About \(Fmt.size($0)) comes back once macOS removes the models." } ?? "",
                    height: 520) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("These stop working").nightEyebrow()
                    ForEach(features) { feature in
                        Label(feature.title, systemImage: "minus.circle")
                            .font(.system(size: 12.5)).foregroundStyle(Brand.textSecondary)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("What happens").nightEyebrow()
                    ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(index + 1)").font(.system(size: 12, weight: .medium)).foregroundStyle(Brand.textMuted)
                            Text(step).font(.system(size: 12.5)).foregroundStyle(Brand.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        } actions: {
            Button("Cancel", action: onCancel).buttonStyle(ControlPanelButtonStyle(size: .large))
                .keyboardShortcut(.cancelAction)
            Button("Turn off", action: onConfirm).buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
        }
    }

    static let steps = [
        "System Settings asks you to approve Cairn's profile. It turns these features off and stops their models downloading again.",
        "Cairn asks macOS to remove the models. Cairn itself never deletes a file in /\u{2060}System.",
        "Undo on this page, or removing the profile in System Settings, turns everything back on. macOS downloads the models again when a feature needs them.",
    ]
}
