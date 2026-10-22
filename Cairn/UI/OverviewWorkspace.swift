import SwiftUI
import Charts

struct OverviewWorkspace: View {
    let store: ScanStore
    let storage: StorageTransferStore
    let control: StorageControl
    var search: String
    var onOpen: (NavSection) -> Void
    var onCleanRecommended: () -> Void = {}
    @State private var period = 30
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Home settles in once: each section fades up a few points in turn, then the graph draws.
    /// Only opacity and offset change, so nothing else on the page moves.
    @State private var appeared = false
    @State private var reveal: CGFloat = 0
    @State private var todayPulse = false
    @State private var showHistory = false
    @State private var selectedDate: Date?
    private var selectedSample: CapacityReading? {
        guard let selectedDate else { return nil }
        return plot.reading(near: selectedDate)
    }
    private var selectedDetail: String? {
        guard let selectedDate else { return nil }
        if let gap = plot.gap(at: selectedDate) { return gap.detail }
        guard let sample = selectedSample else { return nil }
        return "\(sample.date.formatted(date: .abbreviated, time: .shortened)) · \(Fmt.size(sample.available)) available"
    }
    private let preview = CommandLine.arguments.contains("--preview-ui")
    private var canOpenScanResults: Bool {
        if preview { return CommandLine.arguments.contains("--preview-overview-results") }
        return store.hasLiveResults && (store.phase == .finished || store.buckets.contains { !$0.items.isEmpty })
    }
    private var history: [CapacityReading] {
        if preview && !CommandLine.arguments.contains("--preview-empty-overview") { return Self.sampleHistory }
        return preview ? [] : control.latestCapacity
    }
    private var changes: [CandidateChange] {
        let observed = (preview && !CommandLine.arguments.contains("--preview-empty-overview")) ? Self.sampleChanges : control.changes
        return observed.filter { search.isEmpty || $0.category.title.localizedCaseInsensitiveContains(search) }
    }
    private var points: [CapacityReading] {
        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-Double(period - 1) * 86400)
        let inRange = history.filter { $0.date >= start && $0.date <= Date() }.sorted { $0.date < $1.date }
        // Several readings close together draw as a vertical spike at this scale,
        // so keep the latest one per day (30 days) or per hour (7 days).
        let bucket: TimeInterval = period == 30 ? 86_400 : 3_600
        var kept: [CapacityReading] = []
        for reading in inRange {
            if let last = kept.last, floor(last.date.timeIntervalSince1970 / bucket) == floor(reading.date.timeIntervalSince1970 / bucket) {
                kept[kept.count - 1] = reading
            } else { kept.append(reading) }
        }
        return kept
    }
    private var plot: CapacityPlot {
        let maxGap: TimeInterval = preview ? 2 * 86_400 : period == 30 ? 36 * 3_600 : 8 * 3_600
        return CapacityPlot(readings: points, maximumInterval: maxGap)
    }
    /// When free space would reach 5 GB if it keeps falling at the rate seen
    /// on the chart. Nothing is shown when it is rising or the date is far off.
    private struct FillForecast { let days: Int; let date: Date; let floorGB: Double }
    private var fillForecast: FillForecast? {
        let floor: Int64 = 5_000_000_000
        guard let last = points.last else { return nil }
        if preview { return CommandLine.arguments.contains("--preview-empty-overview") ? nil : FillForecast(days: 12, date: last.date.addingTimeInterval(12 * 86_400), floorGB: 5) }
        guard points.count >= 4, let first = points.first else { return nil }
        let xs = points.map { $0.date.timeIntervalSince(first.date) / 86_400 }
        let ys = points.map { Double($0.available) }
        let n = Double(points.count)
        let sx = xs.reduce(0, +), sy = ys.reduce(0, +)
        let sxy = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }, sxx = xs.reduce(0) { $0 + $1 * $1 }
        let denominator = n * sxx - sx * sx
        guard abs(denominator) > .ulpOfOne else { return nil }
        let perDay = -(n * sxy - sx * sy) / denominator
        guard perDay > 0 else { return nil }
        let days = max(0, Double(last.available - floor) / perDay)
        guard days <= 60 else { return nil }
        return FillForecast(days: Int(days.rounded()), date: last.date.addingTimeInterval(days * 86_400), floorGB: Double(floor) / 1e9)
    }
    private var forecastText: String? {
        guard let forecast = fillForecast else { return nil }
        switch forecast.days {
        case 0: return "Your disk is almost full"
        case 1: return "At this rate, full by tomorrow"
        default: return "At this rate, full in about \(forecast.days) days"
        }
    }
    private var historyDelta: Int64? {
        guard points.count >= 2, let first = points.first, let last = points.last else { return nil }
        return last.available - first.available
    }
    private var historyDays: Int {
        guard let first = points.first, let last = points.last else { return 0 }
        return max(1, Calendar.current.dateComponents([.day], from: first.date, to: last.date).day ?? 1)
    }
    private var comparisonUnavailable: String? {
        if store.isScanning { return "Scan in progress. Changes will appear after the scan completes." }
        if store.phase == .cancelled { return "Scan stopped. Complete a scan before comparing categories." }
        return store.comparisonError ?? control.error ?? "Complete two comparable scans to see change in measured cleanup candidates. Other storage may be outside this coverage."
    }
    private var suggestion: CandidateChange? {
        guard comparisonUnavailable == nil else { return nil }
        return changes.filter { $0.delta > 0 }.max { $0.delta < $1.delta }
    }
    private var displayedCapacity: CapacityReading? { preview ? Self.sampleHistory.last : control.current }
    private var shownReserve: Int64? {
        if preview { return PreviewStorageScenario.reserveBytes }
        return AppSettings.shared.reserveEnabled ? control.reserveBytes : nil
    }
    private var lowSpace: Bool {
        displayedCapacity.map { $0.total > 0 && Double($0.available) / Double($0.total) < 0.05 } ?? false
    }
    private var storageHeadline: String {
        guard displayedCapacity != nil else { return "Checking available storage." }
        return lowSpace ? "Your Mac is running low on space" : "This Mac"
    }
    /// Height the chart can take so Home fits the window without scrolling.
    /// Everything else on the page is about 600 pt tall at the default size.
    @State private var chartHeight: CGFloat = 150
    @State private var agentStates: [String: AgentConnections.State] = [:]
    @State private var connecting: String?
    @State private var agentMessage: String?
    private let agentTools = AgentTool.all()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header.modifier(Rise(on: appeared, order: 0, still: reduceMotion))
                cleanHero.padding(.top, 14).modifier(Rise(on: appeared, order: 1, still: reduceMotion))
                graphPanel.padding(.top, 14).modifier(Rise(on: appeared, order: 2, still: reduceMotion))
                diskCard.padding(.top, 14).modifier(Rise(on: appeared, order: 3, still: reduceMotion))
                nextTiles.padding(.top, 14).modifier(Rise(on: appeared, order: 4, still: reduceMotion))
            }.padding(.horizontal, 40).padding(.top, 18).padding(.bottom, 26)
                .frame(maxWidth: 1200, alignment: .leading).frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            chartHeight = min(240, max(110, height - 600))
        }.background(Brand.glow.ignoresSafeArea()).background(Brand.background).foregroundStyle(Brand.textPrimary)
        .font(.system(size: 13, weight: .regular))
        .task { if !preview { await control.refreshCapacity(); await storage.refresh() } }
        .onAppear {
            refreshAgents()
            drawChart()
            // Next run loop, after the first layout, so only the entrance animates.
            DispatchQueue.main.async { appeared = true }
        }
        .onChange(of: period) { _, _ in drawChart() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in if !preview { Task { await storage.refresh() } } }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in if !preview { Task { await storage.refresh() } } }
        .onChange(of: store.isScanning) { _, running in if !running && !preview { Task { await control.refreshCapacity() } } }
        .sheet(isPresented: $showHistory) {
            CairnDialog(title: "Available-space history", subtitle: "Capacity readings collected while Cairn runs", height: 540) {
                VStack(alignment: .leading, spacing: 18) {
                CairnSegmentedControl(label: "Period", selection: $period, options: [("7 days", 7), ("30 days", 30)]).frame(width: 180, height: 32)
                historySection
                if let delta = historyDelta { Text("\(Fmt.size(abs(delta))) \(delta < 0 ? "less" : "more") available over \(historyDays) days").font(.system(size: 14)) }
                Text("Cairn checks available space while it runs and when you return to it. Category scans do not explain every change in disk space.").font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                ScrollView { VStack(spacing: 0) { ForEach(points.reversed(), id: \.date) { point in
                    HStack { Text(point.date, format: .dateTime.day().month(.abbreviated).year()); Spacer(); Text(Fmt.size(point.available)).monospacedDigit() }.font(.system(size: 12)).padding(.vertical, 9)
                } } }
                }
            } actions: { Button("Done") { showHistory = false }.buttonStyle(ControlPanelButtonStyle()).keyboardShortcut(.cancelAction) }
        }
    }
    private var divider: some View { Rectangle().fill(Brand.separator).frame(height: 0.5) }

    /// The headline action: what a scan found that can be freed in one go.
    private var recommendedBytes: Int64 { preview ? 18_400_000_000 : store.recommendedBytes }
    @ViewBuilder private var cleanHero: some View {
        if store.isScanning && !preview {
            // Same big number as the result, counting up while the scan runs.
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    CountingBytes(bytes: store.grandTotal, duration: 0.3, still: reduceMotion)
                        .font(.system(size: 58, weight: .light)).tracking(-2.3)
                    Text("found so far").font(.system(size: 20)).foregroundStyle(Brand.textMuted)
                }
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Scanning · \(store.progressText)").font(.system(size: 13)).foregroundStyle(Brand.textSecondary).lineLimit(1)
                }.padding(.top, 8)
                Text("Nothing is removed until you review it.")
                    .font(.system(size: 13)).foregroundStyle(Brand.textMuted).padding(.top, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if recommendedBytes > 0 {
            // One number, one button: what can safely go, and the way to free it.
            HStack(alignment: .center, spacing: 28) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        CountingBytes(bytes: recommendedBytes, duration: 0.8, still: reduceMotion)
                            .font(.system(size: 58, weight: .light)).tracking(-2.3)
                        Text("you can get back").font(.system(size: 20)).foregroundStyle(Brand.textMuted)
                    }
                    Text("Build files, caches and old simulators that your tools rebuild on their own. Your code, documents and AI conversations are never included.")
                        .font(.system(size: 13.5)).foregroundStyle(Brand.textSecondary)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 440, alignment: .leading)
                        .padding(.top, 8)
                    HStack(spacing: 10) {
                        Button { onCleanRecommended() } label: {
                            Text("Review and free \(Fmt.size(recommendedBytes))").frame(minWidth: 170)
                        }
                        .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
                        .disabled(preview || store.isCleaning)
                        .help("Check the list once, then free the space")
                        Button("See everything") { onOpen(.smartScan) }
                            .buttonStyle(ControlPanelButtonStyle(size: .large))
                    }.padding(.top, 14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if !store.hasLiveResults || store.phase == .cancelled {
            // Same big, open type as the result. No box: just say what is missing and offer the scan.
            VStack(alignment: .leading, spacing: 0) {
                Text(store.phase == .cancelled ? "Finish the scan" : "Find what you can get back")
                    .font(.system(size: 44, weight: .light)).tracking(-1.8)
                Text(store.phase == .cancelled
                     ? "The last scan was stopped early, so Cairn can't give you a number yet. A full scan takes a minute or two."
                     : "A scan takes a minute or two. Nothing is removed until you review it.")
                    .font(.system(size: 13.5)).foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 440, alignment: .leading)
                    .padding(.top, 8)
                HStack(spacing: 10) {
                    Button { scan() } label: { Text("Scan this Mac").frame(minWidth: 140) }
                        .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
                        .disabled(preview || store.isCleaning)
                    Button("See everything") { onOpen(.smartScan) }.buttonStyle(ControlPanelButtonStyle(size: .large))
                }.padding(.top, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("All tidy").font(.system(size: 58, weight: .light)).tracking(-2.3)
                    Text("nothing to get back right now").font(.system(size: 20)).foregroundStyle(Brand.textMuted)
                }
                Text("Your caches and build files are already small. Cairn will show a number here when they grow.")
                    .font(.system(size: 13.5)).foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 440, alignment: .leading)
                    .padding(.top, 8)
                Button("See everything") { onOpen(.smartScan) }.buttonStyle(ControlPanelButtonStyle(size: .large)).padding(.top, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The disk now, and what it will look like once the ready items are freed.
    @ViewBuilder private var diskCard: some View {
        if let capacity = displayedCapacity, capacity.total > 0 {
            let total = Double(capacity.total)
            let used = max(0, capacity.total - capacity.available)
            let ready = min(store.isScanning ? 0 : recommendedBytes, used)
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    (Text(Fmt.size(capacity.available)).fontWeight(.medium).foregroundStyle(Brand.textPrimary)
                     + Text(" free of \(Fmt.size(capacity.total))").foregroundStyle(Brand.textMuted))
                        .font(.system(size: 12.5)).monospacedDigit()
                    Spacer()
                    if ready > 0 {
                        (Text("After freeing: ").foregroundStyle(Brand.textMuted)
                         + Text("\(Fmt.size(capacity.available + ready)) free").foregroundStyle(Brand.room).fontWeight(.medium))
                            .font(.system(size: 12.5)).monospacedDigit()
                    } else if let reserve = shownReserve {
                        Text(capacity.available >= reserve ? "Above your \(Fmt.size(reserve)) reserve" : "\(Fmt.size(reserve - capacity.available)) below your reserve")
                            .font(.system(size: 12.5)).foregroundStyle(capacity.available >= reserve ? Brand.textMuted : Brand.amber)
                    }
                }
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Capsule().fill(Brand.inUse)
                            .frame(width: geo.size.width * CGFloat(Double(used - ready) / total))
                        if ready > 0 {
                            Capsule().fill(Brand.room)
                                .frame(width: geo.size.width * CGFloat(Double(ready) / total))
                                .shadow(color: Brand.room.opacity(0.55), radius: 7)
                        }
                        Spacer(minLength: 0)
                    }
                    .background(Capsule().fill(Brand.track))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.7), value: ready)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.7), value: capacity.available)
                }
                .frame(height: 6)
                .accessibilityLabel("\(Fmt.size(capacity.available)) free, \(Fmt.size(ready)) ready to free")
                HStack(spacing: 18) {
                    legend(Brand.inUse, "In use")
                    if ready > 0 { legend(Brand.room, "Ready to free") }
                    legend(Brand.track, "Free now")
                    Spacer()
                    if let date = store.lastScanDate, !preview {
                        Text(store.phase == .cancelled ? "Scan stopped · results may be incomplete" : "Scanned \(date.formatted(.relative(presentation: .named)))")
                            .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                    }
                }
            }
        }
    }
    private func legend(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2.5).fill(color).frame(width: 9, height: 9)
            Text(title).font(.system(size: 11.5)).foregroundStyle(Brand.textSecondary)
        }
    }

    /// The next useful thing, never a warning: what grew, the last result, your AI tools.
    private var nextTiles: some View {
        HStack(alignment: .top, spacing: 32) {
            growthTile
            lastCleanTile
            agentsTile
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    private func card<Content: View>(_ eyebrow: String, _ link: String?, _ action: @escaping () -> Void, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow).eyebrow()
            content()
            if let link { Button(link, action: action).buttonStyle(QuietLinkStyle()).font(.system(size: 12)).padding(.top, 4) }
        }
        .padding(.top, 12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .top) { Rectangle().fill(Brand.separator).frame(height: 1) }
    }
    private func tile(_ eyebrow: String, _ title: String, _ detail: String, _ link: String, _ action: @escaping () -> Void) -> some View {
        card(eyebrow, link, action) {
            Text(title).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
            Text(detail).font(.system(size: 12)).foregroundStyle(Brand.textMuted).lineLimit(2)
        }
    }
    private func logoRow<Trailing: View>(_ logo: String?, _ fallback: String, _ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            BrandLogo(name: logo, fallback: fallback, size: 24)
            Text(title).font(.system(size: 13)).foregroundStyle(Brand.textPrimary.opacity(0.94)).lineLimit(1)
            Spacer(minLength: 6)
            trailing()
        }.padding(.vertical, 4)
    }

    /// The folders that grew most since the previous measurement.
    private struct Growth: Identifiable { let id: String; let title: String; let delta: Int64; let logo: String?; let icon: String }
    private var growth: [Growth] {
        if preview {
            return [Growth(id: "docker", title: "Docker build cache", delta: 6_100_000_000, logo: "docker", icon: "shippingbox"),
                    Growth(id: "xcode-build", title: "Xcode build output", delta: 4_200_000_000, logo: "xcode", icon: "hammer"),
                    Growth(id: "npm-cache", title: "npm package cache", delta: 1_300_000_000, logo: "npm", icon: "shippingbox")]
        }
        return control.locationChanges.filter { $0.delta > 0 }.sorted { $0.delta > $1.delta }.prefix(3).map {
            Growth(id: $0.id, title: $0.after.root.title, delta: $0.delta, logo: BrandLogo.forRoot($0.id), icon: $0.after.root.icon)
        }
    }
    private var growthTile: some View {
        let rows = growth
        return card("Grew recently", "See what changed", { onOpen(.changes) }) {
            if rows.isEmpty {
                Text("No growth measured yet").font(.system(size: 13.5, weight: .medium))
                Text("Cairn compares folder sizes between scans.").font(.system(size: 12)).foregroundStyle(Brand.textMuted).lineLimit(2)
            } else {
                ForEach(rows) { row in
                    logoRow(row.logo, row.icon, row.title) {
                        Text("+\(Fmt.size(row.delta))").font(.system(size: 13, weight: .medium)).monospacedDigit().foregroundStyle(Brand.room)
                    }
                }
            }
        }
    }
    private var lastCleanTile: some View {
        if preview { return tile("Last clean", "3 October · 23.4 GB freed", "Checked on this Mac.", "See receipt") { onOpen(.activity) } }
        if let run = store.cleanupRuns.first(where: { $0.finished != nil && $0.summary.accounting.completedCount > 0 }) {
            let gains = run.summary.capacityChanges.compactMap(\.delta).filter { $0 > 0 }.reduce(0, +)
            let freed = max(run.summary.accounting.freedBytes, gains)
            let title = "\(run.started.formatted(.dateTime.day().month(.wide))) · " + (freed > 0 ? "\(Fmt.size(freed)) freed" : "\(run.summary.accounting.completedCount) items cleaned")
            let detail = gains > 0 ? "Checked on this Mac." : run.summary.recoverableCount > 0 ? "\(run.summary.recoverableCount) can be put back." : "Recorded in Activity."
            return tile("Last clean", title, detail, "See receipt") { onOpen(.activity) }
        }
        return tile("Last clean", "No cleans yet", "Every clean leaves a receipt in Activity.", "Open Activity") { onOpen(.activity) }
    }

    /// AI coding tools on this Mac, connected ones first, so the agent link
    /// is visible from Home rather than only in Settings.
    private func agentState(_ tool: AgentTool) -> AgentConnections.State {
        if preview { return ["claude-code", "cursor"].contains(tool.id) ? .connected(current: true) : tool.id == "codex" ? .available : .notInstalled }
        return agentStates[tool.id] ?? .notInstalled
    }
    private var shownAgents: [AgentTool] {
        let present = agentTools.filter {
            switch agentState($0) { case .connected, .available: return true; default: return false }
        }
        let connected = present.filter { if case .connected = agentState($0) { return true } else { return false } }
        return Array((connected + present.filter { !connected.contains($0) }).prefix(3))
    }
    private var agentsTile: some View {
        let tools = shownAgents
        return card("Your AI coding tools", tools.isEmpty ? "AI tools settings" : nil, { onOpen(.settings) }) {
            if tools.isEmpty {
                Text("No coding tools found").font(.system(size: 13.5, weight: .medium))
                Text("Claude Code, Codex, Cursor and others can ask Cairn what is using space.").font(.system(size: 12)).foregroundStyle(Brand.textMuted).lineLimit(2)
            } else {
                ForEach(tools) { tool in
                    logoRow(BrandLogo.forAgent(tool.id), "chevron.left.forwardslash.chevron.right", tool.title) {
                        if case .connected = agentState(tool) {
                            HStack(spacing: 5) {
                                Circle().fill(Brand.safeCyan).frame(width: 6, height: 6)
                                Text("Connected").font(.system(size: 12)).foregroundStyle(Brand.safeCyan)
                            }
                        } else {
                            Button(connecting == tool.id ? "Connecting…" : "Connect") { connect(tool) }
                                .buttonStyle(QuietLinkStyle()).font(.system(size: 12))
                                .disabled(preview || connecting != nil)
                        }
                    }
                }
                Text(agentMessage ?? "Try asking: \u{201C}What\u{2019}s taking up space on my Mac?\u{201D}")
                    .font(.system(size: 12)).foregroundStyle(Brand.textMuted).lineLimit(2).padding(.top, 4)
            }
        }
    }
    private func refreshAgents() {
        guard !preview else { return }
        var next: [String: AgentConnections.State] = [:]
        for tool in agentTools { next[tool.id] = AgentConnections.state(tool) }
        agentStates = next
    }
    private func connect(_ tool: AgentTool) {
        guard !preview else { return }
        connecting = tool.id
        Task.detached {
            let result: String
            do { try AgentConnections.connect(tool); result = "\(tool.title) is connected. Restart it to pick up the change." }
            catch let failure as AgentConnections.Failure { result = failure.message }
            catch { result = "\(tool.title) was not changed: \(error.localizedDescription)" }
            await MainActor.run {
                agentMessage = result
                connecting = nil
                refreshAgents()
            }
        }
    }
    private func drawChart() {
        guard !reduceMotion else { reveal = 1; return }
        reveal = 0
        todayPulse = false
        withAnimation(.easeInOut(duration: 1.1).delay(0.25)) { reveal = 1 }
        withAnimation(.easeOut(duration: 0.9).delay(1.3)) { todayPulse = true }
    }
    /// Free space over time, with a ring on the day of each clean.
    private var graphPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text("Free space · last \(period) days").eyebrow().font(.system(size: 11)).tracking(1.5)
                if let text = forecastText {
                    Text(text).font(.system(size: 12)).foregroundStyle(Brand.amber).padding(.leading, 8)
                }
                Spacer()
                if !cleanMarks.isEmpty {
                    HStack(spacing: 6) {
                        Circle().strokeBorder(Brand.room, lineWidth: 1.5).frame(width: 8, height: 8)
                        Text("Clean").font(.system(size: 11.5)).foregroundStyle(Brand.textMuted)
                    }.padding(.trailing, 8)
                }
                CairnSegmentedControl(label: "Period", selection: $period, options: [("7 days", 7), ("30 days", 30)])
                    .frame(width: 150, height: 28)
            }
            historySection
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.wash(0.02)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Brand.separator, lineWidth: 1))
    }
    /// Cleans that released space inside the chart's period.
    private struct CleanMark: Identifiable { let date: Date; let available: Double; var id: Date { date } }
    private var cleanMarks: [CleanMark] {
        guard let first = points.first?.date else { return [] }
        let runs: [Date] = preview
            ? [first.addingTimeInterval(Double(period) * 86_400 * 0.35)]
            : store.cleanupRuns.filter { RecoveryWorkspace.freed($0.summary) > 0 }.map { $0.finished ?? $0.started }
        return runs.filter { $0 >= first }.compactMap { date in
            guard let reading = points.first(where: { $0.date >= date }) ?? points.last else { return nil }
            return CleanMark(date: date, available: Double(reading.available) / 1e9)
        }
    }
    /// A connected external drive, shown beside the headline only while it is plugged in.
    private var externalDrive: StorageDrive? {
        if preview { return CommandLine.arguments.contains("--preview-empty-overview") ? nil : Self.sampleDrive }
        return storage.drives.first(where: \.external)
    }
    private static let sampleDrive = StorageDrive(url: URL(fileURLWithPath: "/Volumes/Studio SSD"), name: "Studio SSD", uuid: "SAMPLE-DRIVE", capacity: 1_000_000_000_000, available: 186_000_000_000, external: true, writable: true, encrypted: true, format: "apfs")
    private func drivePill(_ drive: StorageDrive) -> some View {
        Button { onOpen(.storage) } label: {
            HStack(spacing: 7) {
                Image(systemName: "externaldrive").font(.system(size: 11, weight: .light))
                Text("\(drive.name) · \(Fmt.size(drive.available)) free").monospacedDigit().lineLimit(1)
                Text("Storage options").foregroundStyle(Brand.deepBlue)
            }
            .font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
            .padding(.horizontal, 10).frame(height: 24)
            .overlay(Capsule().strokeBorder(Brand.separator, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Move large folders to \(drive.name)")
    }
    private var header: some View {
        HStack(alignment: .center) {
            Text("This Mac").font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.textSecondary)
            if let drive = externalDrive { drivePill(drive).padding(.leading, 14) }
            Spacer()
            HStack(spacing: 8) {
                Button { scan() } label: {
                    Label(store.isScanning ? "Stop scan" : (store.lastScanDate != nil || preview ? "Rescan" : "Scan this Mac"), systemImage: store.isScanning ? "stop.circle" : "arrow.clockwise")
                }.buttonStyle(ControlPanelButtonStyle(size: .small))
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(preview || store.isCleaning)
                    .help(preview ? "Scanning is disabled in this sample preview." : "Scan this Mac (⌘R)")
                Button("Make room") { onOpen(.makeRoom) }
                    .buttonStyle(ControlPanelButtonStyle(size: .small))
                    .help("Choose an available-space target and review your options")
                Button("History") { showHistory = true }
                    .buttonStyle(ControlPanelButtonStyle(size: .small))
                    .help("Available space over the last week or month")
            }
        }
    }
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let first = points.first, let last = points.last, points.count >= 2 {
                let observedLow = Double(points.map(\.available).min() ?? 0) / 1e9
                let observedHigh = Double(points.map(\.available).max() ?? 0) / 1e9
                let chosenReserve = Double(shownReserve ?? 0) / 1e9
                let projected = fillForecast.flatMap { $0.days <= 45 ? $0 : nil }
                let lowest = min(observedLow, shownReserve == nil ? observedLow : chosenReserve, projected?.floorGB ?? observedLow)
                let chartLow = preview ? 0 : max(0, lowest - 3)
                let chartHigh = preview ? 120 : max(observedHigh, shownReserve == nil ? observedHigh : chosenReserve) + 3
                Chart {
                    ForEach(plot.points) { point in
                        let sample = point.reading
                        AreaMark(x: .value("Date", sample.date), yStart: .value("GB", chartLow), yEnd: .value("GB", Double(sample.available) / 1e9), series: .value("Observation segment", point.segment))
                            .foregroundStyle(LinearGradient(colors: [Brand.room.opacity(0.16), Brand.room.opacity(0)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Date", sample.date), y: .value("GB", Double(sample.available) / 1e9), series: .value("Observation segment", point.segment))
                            .foregroundStyle(Brand.room).lineStyle(StrokeStyle(lineWidth: 1.7, lineJoin: .round))
                            .shadow(color: Brand.room.opacity(0.6), radius: 4)
                        if sample.date == last.date {
                            PointMark(x: .value("Date", sample.date), y: .value("GB", Double(sample.available) / 1e9))
                                .foregroundStyle(Brand.room.opacity(todayPulse ? 0 : 0.25)).symbolSize(todayPulse ? 420 : 40)
                            PointMark(x: .value("Date", sample.date), y: .value("GB", Double(sample.available) / 1e9)).foregroundStyle(Brand.room).symbolSize(40)
                        }
                    }
                    if let projected {
                        // Its own segment number so it never joins the observed line.
                        LineMark(x: .value("Date", last.date), y: .value("GB", Double(last.available) / 1e9), series: .value("Observation segment", -1))
                            .foregroundStyle(Brand.room.opacity(0.55)).lineStyle(StrokeStyle(lineWidth: 1.3, dash: [3, 5]))
                        LineMark(x: .value("Date", projected.date), y: .value("GB", projected.floorGB), series: .value("Observation segment", -1))
                            .foregroundStyle(Brand.room.opacity(0.55)).lineStyle(StrokeStyle(lineWidth: 1.3, dash: [3, 5]))
                        PointMark(x: .value("Date", projected.date), y: .value("GB", projected.floorGB))
                            .symbol { Circle().strokeBorder(Brand.amber, lineWidth: 1.4).frame(width: 7, height: 7) }
                            .annotation(position: .topLeading, spacing: 2) {
                                Text("Full by \(projected.date.formatted(.dateTime.day().month(.abbreviated)))")
                                    .font(.system(size: 10.5)).foregroundStyle(Brand.amber)
                            }
                    }
                    ForEach(cleanMarks) { mark in
                        PointMark(x: .value("Date", mark.date), y: .value("GB", mark.available))
                            .symbol { Circle().fill(Brand.background).overlay(Circle().strokeBorder(Brand.room, lineWidth: 1.6)).frame(width: 9, height: 9) }
                    }
                    if shownReserve != nil {
                        RuleMark(y: .value("Chosen reserve", chosenReserve))
                            .foregroundStyle(Brand.amber.opacity(0.3)).lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    }
                    if let sample = selectedSample {
                        RuleMark(x: .value("Reading", sample.date)).foregroundStyle(Brand.textMuted.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        PointMark(x: .value("Date", sample.date), y: .value("GB", Double(sample.available) / 1e9)).foregroundStyle(Brand.room).symbolSize(45)
                    }
                }
                .chartOverlay { proxy in
                    CapacityGapOverlay(gaps: plot.gaps, proxy: proxy)
                }
                .chartXSelection(value: $selectedDate)
                .onChange(of: period) { _, _ in selectedDate = nil }
                .chartXScale(range: .plotDimension(padding: 5))
                .chartYScale(domain: chartLow...chartHigh)
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3])).foregroundStyle(Brand.separator)
                    AxisValueLabel { if let gb = value.as(Double.self) { Text("\(Int(gb)) GB").font(.system(size: 10.5)).foregroundStyle(Brand.textMuted.opacity(0.75)) } }
                } }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(.system(size: 10.5)).foregroundStyle(Brand.textMuted.opacity(0.75)) } }
                .frame(height: chartHeight)
                .mask(alignment: .leading) {
                    GeometryReader { geo in Rectangle().frame(width: max(0, geo.size.width * reveal + 12)) }
                }
                .accessibilityLabel("Available space from \(Fmt.size(first.available)) to \(Fmt.size(last.available))")
                CapacityChartReadout(text: selectedDetail)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your history starts here").font(.system(size: 14, weight: .regular))
                    Text("A trend appears after two readings. Cairn records capacity while it runs.").font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                }.frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
            }
        }
    }
    private func readingLabel(_ sample: CapacityReading) -> some View {
        Text("\(sample.date.formatted(.dateTime.day().month(.abbreviated).hour().minute())) · \(Fmt.size(sample.available))").monospacedDigit()
    }
    private func route(_ category: CandidateReading.Category) -> NavSection {
        if category.id == "browser-caches" { return .browsers }
        if ["large-old", "installers"].contains(category.id) { return .largeFiles }
        switch category.group { case .developer: return .developer; case .ai: return .ai; case .creative: return .creative; case .general: return .general }
    }
    private func scan() {
        if store.isScanning { store.cancel() }
        else { store.startScan(includeExternalVolumes: !AppSettings.shared.ignoreExternalDrives) }
    }
    private static let sampleHistory = PreviewStorageScenario.capacityHistory
    private static let sampleChanges: [CandidateChange] = [
        .init(category: .init(id: "xcode", title: "Build output", icon: "hammer", group: .developer, bytes: 6_400_000_000, complete: true), delta: 4_200_000_000, before: Date().addingTimeInterval(-86400), after: Date()),
        .init(category: .init(id: "browser-caches", title: "Browser caches", icon: "globe", group: .general, bytes: 2_700_000_000, complete: true), delta: 1_100_000_000, before: Date().addingTimeInterval(-86400), after: Date()),
        .init(category: .init(id: "large-old", title: "Large downloads", icon: "folder", group: .general, bytes: 4_800_000_000, complete: true), delta: 850_000_000, before: Date().addingTimeInterval(-86400), after: Date())
    ]
}

/// A size that counts smoothly to its new value: fixed-width digits in one unit,
/// so nothing slides or jitters. Counts up from zero the first time it appears.
struct CountingBytes: View {
    let bytes: Int64
    var duration: Double = 0.8
    var still = false
    @State private var shown: Double = 0
    var body: some View {
        CountingBytesText(value: shown, unitOf: bytes)
            .monospacedDigit()
            .onAppear { move(to: bytes) }
            .onChange(of: bytes) { _, new in move(to: new) }
    }
    private func move(to target: Int64) {
        if still { shown = Double(target); return }
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: duration)) { shown = Double(target) }
    }
}
private struct CountingBytesText: View, Animatable {
    var value: Double
    let unitOf: Int64
    var animatableData: Double { get { value } set { value = newValue } }
    var body: some View { Text(value == Double(unitOf) ? Fmt.size(unitOf) : Self.format(value, unitOf: unitOf)) }
    /// Uses the target's unit throughout, so the count never jumps from MB to GB mid-way.
    static func format(_ bytes: Double, unitOf target: Int64) -> String {
        let units: [(Double, String)] = [(1e12, "TB"), (1e9, "GB"), (1e6, "MB"), (1e3, "KB")]
        guard let unit = units.first(where: { Double(target) >= $0.0 }) else { return Fmt.size(Int64(bytes)) }
        let v = max(0, bytes) / unit.0
        return String(format: v >= 100 ? "%.0f %@" : "%.1f %@", v, unit.1)
    }
}

/// One section of Home settling in: a soft fade and a 6 pt rise, each a moment after the last.
/// Offset and opacity never change layout, so neighbouring sections stay put.
private struct Rise: ViewModifier {
    let on: Bool
    let order: Int
    let still: Bool
    func body(content: Content) -> some View {
        content.opacity(on || still ? 1 : 0).offset(y: on || still ? 0 : 6)
            .animation(still ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.55).delay(0.07 * Double(order)), value: on)
    }
}
