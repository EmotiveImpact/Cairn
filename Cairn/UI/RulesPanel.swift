import SwiftUI

/// Settings › Rules: cleanups approved once, then run by Cairn on its own.
/// Every rule starts off. Turning one on shows exactly what it would clear
/// today before it is approved.
struct RulesPanel: View {
    @Bindable private var settings = AppSettings.shared
    @State private var previews: [CleaningRule.Kind: [ScanItem]] = [:]
    @State private var checking: CleaningRule.Kind?
    @State private var pendingApproval: CleaningRule.Kind?
    private var runner: RuleRunner { .shared }
    private let preview = CommandLine.arguments.contains("--preview-ui")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Approve a rule once and Cairn runs it on its own while it is open. Rules only clear caches and build files that rebuild themselves, stop at the size limit you set, skip anything in use, and leave a receipt in Activity.")
                .font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 18)
            lowSpace
            ForEach(runner.rules) { rule in row(rule) }
        }
    }

    /// One warning when space runs low, shared with Monitoring.
    private var lowSpace: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Warn me when space runs low").font(.system(size: 13, weight: .medium))
                Text("One alert when free space stays under \(settings.reserveGB) GB, and nothing more until it recovers. The same setting as Monitoring.")
                    .font(.system(size: 12)).foregroundStyle(Brand.textMuted).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Stepper("\(settings.reserveGB) GB", value: $settings.reserveGB, in: 5...500, step: 5)
                .frame(width: 120).disabled(!settings.reserveEnabled)
            Toggle("Warn me when space runs low", isOn: $settings.reserveEnabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                .onChange(of: settings.reserveEnabled) { _, enabled in
                    guard !preview else { return }
                    if enabled {
                        settings.reservePaused = false
                        Notify.requestAuth()
                        StorageControl.shared.start()
                        Task { await StorageControl.shared.refreshCapacity(); await StorageControl.shared.refreshNotificationStatus() }
                    }
                    StorageControl.shared.configureMonitoring()
                }
        }
        .nightRow()
    }

    private func row(_ rule: CleaningRule) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.kind.title).font(.system(size: 13, weight: .medium))
                    Text(rule.kind.detail).font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(status(rule)).font(.system(size: 11.5))
                        .foregroundStyle(rule.active ? Brand.room : Brand.textMuted)
                        .padding(.top, 3)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Toggle(rule.kind.title, isOn: Binding(get: { rule.approved || pendingApproval == rule.kind }, set: { on in
                    if on { startApproval(rule) } else { pendingApproval = nil; var next = rule; next.approved = false; runner.update(next) }
                }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            if pendingApproval == rule.kind { approval(rule) }
            else if rule.approved { controls(rule) }
        }
        .nightRow()
    }

    /// Before approving: what the rule would clear today, measured now.
    @ViewBuilder private func approval(_ rule: CleaningRule) -> some View {
        settingsLine(rule)
        if checking == rule.kind {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Measuring what this rule would clear today…").font(.system(size: 12)).foregroundStyle(Brand.textMuted)
            }
        } else if let items = previews[rule.kind] {
            let total = items.reduce(Int64(0)) { $0 + $1.allocatedSize }
            Text(items.isEmpty ? "Today this rule would clear nothing. It will check again on its schedule."
                               : "Today this rule would clear \(Fmt.size(total)) in \(items.count) item\(items.count == 1 ? "" : "s"), for example \(items.prefix(3).map { $0.resolvedURL.lastPathComponent }.joined(separator: ", ")).")
                .font(.system(size: 12)).foregroundStyle(Brand.textSecondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Approve rule") {
                    var next = rule
                    next.approved = true
                    next.paused = false
                    runner.update(next)
                    pendingApproval = nil
                }.buttonStyle(ControlPanelButtonStyle(primary: true))
                Button("Cancel") { pendingApproval = nil }.buttonStyle(ControlPanelButtonStyle())
            }
        }
    }

    @ViewBuilder private func controls(_ rule: CleaningRule) -> some View {
        settingsLine(rule)
        HStack(spacing: 10) {
            Button(runner.running == rule.kind ? "Running…" : "Run now") { Task { await runner.run(rule.kind) } }
                .buttonStyle(ControlPanelButtonStyle(size: .small))
                .disabled(runner.running != nil || rule.paused || preview)
            Button(rule.paused ? "Resume" : "Pause") { var next = rule; next.paused.toggle(); runner.update(next) }
                .buttonStyle(ControlPanelButtonStyle(size: .small))
        }
    }

    private func settingsLine(_ rule: CleaningRule) -> some View {
        HStack(spacing: 18) {
            CairnSegmentedControl(label: "How often", selection: Binding(get: { rule.schedule }, set: { var next = rule; next.schedule = $0; runner.update(next) }),
                                  options: CleaningRule.Schedule.allCases.map { ($0.title, $0) })
                .frame(width: 220)
            if rule.kind != .browserCaches && rule.kind != .appCaches {
                Stepper("\(rule.kind.ageLabel) \(rule.minAgeDays) days", value: Binding(get: { rule.minAgeDays }, set: { var next = rule; next.minAgeDays = $0; runner.update(next); previews[rule.kind] = nil }),
                        in: rule.kind == .idleProjects ? 7...365 : 1...365, step: rule.kind == .idleProjects ? 7 : 1)
                    .font(.system(size: 12))
            }
            Stepper("Up to \(rule.capGB) GB a run", value: Binding(get: { rule.capGB }, set: { var next = rule; next.capGB = $0; runner.update(next); previews[rule.kind] = nil }),
                    in: 1...200)
                .font(.system(size: 12))
        }
    }

    private func status(_ rule: CleaningRule) -> String {
        if runner.running == rule.kind { return "Running now" }
        guard rule.approved else { return "Off" }
        if rule.paused { return "Paused" }
        var parts = [rule.schedule.title]
        if let last = rule.lastRun { parts.append("last ran \(last.formatted(.relative(presentation: .named)))" + (rule.lastResult.isEmpty ? "" : ": \(rule.lastResult)")) }
        else { parts.append("first run within the hour") }
        return parts.joined(separator: " · ")
    }

    private func startApproval(_ rule: CleaningRule) {
        pendingApproval = rule.kind
        guard !preview else { previews[rule.kind] = []; return }
        checking = rule.kind
        Task {
            let items = await runner.preview(rule) ?? []
            previews[rule.kind] = items
            if checking == rule.kind { checking = nil }
        }
    }
}
