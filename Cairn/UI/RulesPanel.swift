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

    @State private var editing: CleaningRule.Kind?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Approve once. Rules only clear files that rebuild themselves, skip anything in use, and leave a receipt in Activity.")
                .font(.system(size: 13.5)).foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 16)
            lowSpace
            ForEach(runner.rules) { rule in row(rule) }
        }
    }

    private var freeNow: Int64? { StorageControl.shared.capacity.last?.available }

    /// One warning when space runs low, shared with Monitoring. The small
    /// gauge shows free space now against the line you set.
    private var lowSpace: some View {
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 15))
                .foregroundStyle(Brand.amber).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Warn me when space runs low").font(.system(size: 13.5, weight: .medium))
                (Text("One alert when free space drops under ")
                 + Text("\(settings.reserveGB) GB").foregroundStyle(Brand.room)
                 + Text(", then quiet until it recovers. The same setting as Monitoring."))
                    .font(.system(size: 12)).foregroundStyle(Brand.textMuted).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let free = freeNow, settings.reserveEnabled { gauge(free: free) }
            Stepper("\(settings.reserveGB) GB", value: $settings.reserveGB, in: 5...500, step: 5)
                .font(.system(size: 12)).fixedSize().disabled(!settings.reserveEnabled)
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
        .padding(.horizontal, 4)
        .nightRow()
    }

    /// Free space now (amber when under the line) against the warning line in ice.
    private func gauge(free: Int64) -> some View {
        let scale = Double(max(Int64(settings.reserveGB) * 5, 1)) * 1_000_000_000
        let low = free < Int64(settings.reserveGB) * 1_000_000_000
        return VStack(alignment: .trailing, spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Brand.wash(0.08))
                    Capsule().fill(low ? Brand.amber : Brand.wash(0.4))
                        .frame(width: geo.size.width * CGFloat(min(1, Double(free) / scale)))
                    Rectangle().fill(Brand.room).frame(width: 1, height: 12)
                        .offset(x: geo.size.width * 0.2)
                }
            }
            .frame(width: 120, height: 4)
            Text("\(Fmt.size(free)) free now").font(.system(size: 11)).foregroundStyle(Brand.textMuted).monospacedDigit()
        }
    }

    private func icon(_ kind: CleaningRule.Kind) -> String {
        switch kind {
        case .xcodeBuild: return "hammer"
        case .packageCaches: return "shippingbox"
        case .idleProjects: return "folder"
        case .browserCaches: return "globe"
        case .appCaches: return "macwindow"
        case .logs: return "doc.text"
        }
    }

    private func row(_ rule: CleaningRule) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon(rule.kind)).font(.system(size: 14, weight: .light))
                .foregroundStyle(Brand.textMuted).frame(width: 22).padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.kind.title).font(.system(size: 13.5, weight: .medium))
                Text(rule.kind.detail).font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if pendingApproval == rule.kind { approval(rule) }
                else if rule.approved { summary(rule) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(rule.kind.title, isOn: Binding(get: { rule.approved || pendingApproval == rule.kind }, set: { on in
                if on { startApproval(rule) } else { pendingApproval = nil; editing = nil; var next = rule; next.approved = false; runner.update(next) }
            }))
            .labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.horizontal, 4)
        .nightRow()
    }

    /// An approved rule's settings read as one line; "Change" opens the controls.
    @ViewBuilder private func summary(_ rule: CleaningRule) -> some View {
        HStack(spacing: 14) {
            chip(rule.paused ? "Paused" : rule.schedule.title)
            if rule.kind != .browserCaches && rule.kind != .appCaches {
                chip(rule.kind.ageLabel.lowercased(), "\(rule.minAgeDays) days")
            }
            chip("up to", "\(rule.capGB) GB a run")
            Text(lastLine(rule)).font(.system(size: 12)).foregroundStyle(Brand.textMuted).lineLimit(1)
            NightLink(title: runner.running == rule.kind ? "Running…" : "Run now") { Task { await runner.run(rule.kind) } }
                .disabled(runner.running != nil || rule.paused || preview)
            NightLink(title: editing == rule.kind ? "Done" : "Change") { editing = editing == rule.kind ? nil : rule.kind }
        }
        .padding(.top, 6)
        if editing == rule.kind {
            VStack(alignment: .leading, spacing: 10) {
                settingsLine(rule)
                NightLink(title: rule.paused ? "Resume this rule" : "Pause this rule") { var next = rule; next.paused.toggle(); runner.update(next) }
            }
            .padding(.top, 10)
        }
    }

    private func chip(_ text: String, _ value: String? = nil) -> some View {
        Group {
            if let value { Text(text + " ").foregroundStyle(Brand.textSecondary) + Text(value).foregroundStyle(Brand.room) }
            else { Text(text).foregroundStyle(Brand.room) }
        }
        .font(.system(size: 12)).lineLimit(1).fixedSize()
    }

    private func lastLine(_ rule: CleaningRule) -> String {
        if runner.running == rule.kind { return "Running now" }
        guard let last = rule.lastRun else { return "First run within the hour" }
        return "Last ran " + last.formatted(.relative(presentation: .named)) + (rule.lastResult.isEmpty ? "" : " · " + rule.lastResult)
    }

    /// Before approving: what the rule would clear today, measured now.
    @ViewBuilder private func approval(_ rule: CleaningRule) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            settingsLine(rule)
            if checking == rule.kind {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Measuring what this rule would clear today…").font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                }
            } else if let items = previews[rule.kind] {
                let total = items.reduce(Int64(0)) { $0 + $1.allocatedSize }
                NightNote(strong: items.isEmpty ? "" : "Today this rule would clear \(Fmt.size(total))",
                          text: items.isEmpty ? "Today this rule would clear nothing. It will check again on its schedule."
                              : "in \(items.count) item\(items.count == 1 ? "" : "s"), for example \(items.prefix(3).map { $0.resolvedURL.lastPathComponent }.joined(separator: ", ")).") {
                    NightLink(title: "Cancel") { pendingApproval = nil }
                    Button("Approve rule") {
                        var next = rule
                        next.approved = true
                        next.paused = false
                        runner.update(next)
                        pendingApproval = nil
                    }.buttonStyle(ControlPanelButtonStyle(primary: true))
                }
            }
        }
        .padding(.top, 10)
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
