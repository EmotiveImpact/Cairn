import SwiftUI
import Charts

struct OverviewWorkspace: View {
    let store: ScanStore
    let storage: StorageTransferStore
    let control: StorageControl
    var search: String
    var onOpen: (NavSection) -> Void
    @State private var period = 7
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
        return history.filter { $0.date >= start && $0.date <= Date() }.sorted { $0.date < $1.date }
    }
    private var plot: CapacityPlot {
        let maxGap: TimeInterval = preview ? 2 * 86_400 : period == 30 ? 36 * 3_600 : 8 * 3_600
        return CapacityPlot(readings: points, maximumInterval: maxGap)
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
    private var externalDrive: StorageDrive? { preview ? (CommandLine.arguments.contains("--preview-empty-overview") ? nil : Self.sampleDrive) : storage.drives.first(where: \.external) }
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
        return lowSpace ? "Your Mac needs more room." : "Room for what’s next."
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                historySection.padding(.top, 22)
                HStack { Spacer(); Button("View history") { showHistory = true }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Brand.deepBlue)
                }.padding(.top, 9)
                divider.padding(.top, 19).padding(.bottom, 17)
                suggestionSection
                divider.padding(.top, 15).padding(.bottom, 16)
                supportingSections
            }.padding(.horizontal, 30).padding(.top, 24).padding(.bottom, 18)
                .frame(maxWidth: 1200, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Color(hex: 0x191D21)).foregroundStyle(Brand.textPrimary)
        .font(.system(size: 13, weight: .regular))
        .task { if !preview { await control.refreshCapacity(); await storage.refresh() } }
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
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("THIS MAC").font(.system(size: 11, weight: .regular)).tracking(0.7).foregroundStyle(Brand.textMuted)
                    Text("Available space").font(.system(size: 24, weight: .semibold))
                }
                Spacer()
                HStack(spacing: 8) {
                    Button { scan() } label: {
                        Label(store.isScanning ? "Stop scan" : (store.lastScanDate != nil || preview ? "Rescan" : "Scan this Mac"), systemImage: store.isScanning ? "stop.circle" : "arrow.clockwise")
                    }.buttonStyle(ControlPanelButtonStyle())
                        .keyboardShortcut("r", modifiers: .command)
                        .disabled(preview || store.isCleaning)
                        .help(preview ? "Scanning is disabled in this sample preview." : "Scan this Mac (⌘R)")
                    if canOpenScanResults {
                        Button(store.phase == .cancelled ? "See partial results" : "See results") { onOpen(.smartScan) }
                            .buttonStyle(ControlPanelButtonStyle())
                            .help(preview ? "Open sample results; no disk action is available" : store.phase == .cancelled ? "Review the items found before the scan stopped" : "Review this scan's findings")
                            .transition(.opacity)
                    }
                    Button("Make room") { onOpen(.makeRoom) }
                        .buttonStyle(ControlPanelButtonStyle(primary: true))
                        .help("Choose an available-space target and review your options")
                }.animation(.easeInOut(duration: 0.22), value: store.phase)
            }
            HStack(alignment: .center, spacing: 24) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(displayedCapacity.map { Fmt.size($0.available) } ?? "—")
                        .font(.system(size: 48, weight: .regular)).tracking(-1.6).monospacedDigit()
                    if let total = displayedCapacity?.total {
                        Text("of \(Fmt.size(total))").font(.system(size: 17)).foregroundStyle(Brand.textMuted)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if let reserve = shownReserve, let available = displayedCapacity?.available {
                    Rectangle().fill(Brand.separator).frame(width: 1, height: 60)
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(available >= reserve ? Brand.safeCyan : Brand.amber).frame(width: 9, height: 9).padding(.top, 6)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(available >= reserve ? "Above your \(Fmt.size(reserve)) reserve" : "Below your \(Fmt.size(reserve)) reserve")
                                .font(.system(size: 13, weight: .semibold))
                            Text(available >= reserve ? "\(Fmt.size(available - reserve)) above your chosen reserve." : "\(Fmt.size(reserve - available)) needed to meet your reserve.")
                                .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(.top, 14)
            if !preview, let date = store.lastScanDate {
                HStack(spacing: 6) {
                    Image(systemName: store.phase == .cancelled ? "pause.circle" : "clock")
                    Text(store.phase == .cancelled ? "Scan stopped · results may be incomplete" : "Last scan \(date.formatted(date: .abbreviated, time: .shortened))")
                }.font(.system(size: 11)).foregroundStyle(Brand.textMuted).padding(.top, 8)
            }
        }
    }
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let first = points.first, let last = points.last, points.count >= 2 {
                let observedLow = Double(points.map(\.available).min() ?? 0) / 1e9
                let observedHigh = Double(points.map(\.available).max() ?? 0) / 1e9
                let chosenReserve = Double(shownReserve ?? 0) / 1e9
                let chartLow = preview ? 0 : max(0, min(observedLow, shownReserve == nil ? observedLow : chosenReserve) - 3)
                let chartHigh = preview ? 120 : max(observedHigh, shownReserve == nil ? observedHigh : chosenReserve) + 3
                Chart {
                    ForEach(plot.points) { point in
                        let sample = point.reading
                        AreaMark(x: .value("Date", sample.date), yStart: .value("GB", chartLow), yEnd: .value("GB", Double(sample.available) / 1e9), series: .value("Observation segment", point.segment))
                            .foregroundStyle(LinearGradient(colors: [Brand.blue.opacity(0.17), Brand.blue.opacity(0)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Date", sample.date), y: .value("GB", Double(sample.available) / 1e9), series: .value("Observation segment", point.segment))
                            .foregroundStyle(Brand.blue).lineStyle(StrokeStyle(lineWidth: 1.7))
                        if sample.date == last.date { PointMark(x: .value("Date", sample.date), y: .value("GB", Double(sample.available) / 1e9)).foregroundStyle(Brand.blue).symbolSize(25) }
                    }
                    if shownReserve != nil {
                        RuleMark(y: .value("Chosen reserve", chosenReserve))
                            .foregroundStyle(Brand.amber.opacity(0.55)).lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    }
                    if let sample = selectedSample {
                        RuleMark(x: .value("Reading", sample.date)).foregroundStyle(Brand.textMuted.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        PointMark(x: .value("Date", sample.date), y: .value("GB", Double(sample.available) / 1e9)).foregroundStyle(Brand.blue).symbolSize(35)
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
                    AxisValueLabel { if let gb = value.as(Double.self) { Text("\(Int(gb)) GB") } }
                } }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                .frame(height: 178)
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
    private var suggestionSection: some View {
        let observed = control.locationChanges.filter { $0.delta > 0 && (search.isEmpty || $0.after.root.title.localizedCaseInsensitiveContains(search)) }
            .sorted { $0.delta > $1.delta }.prefix(2)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("WHAT CHANGED").font(.system(size: 11)).tracking(0.7).foregroundStyle(Brand.textMuted)
                Spacer()
                Button("See all changes") { onOpen(.changes) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Brand.deepBlue)
            }.padding(.bottom, 8)
            if preview {
                growthRow(title: "Xcode build output", detail: "DerivedData and build intermediates grew.", icon: "hammer", amount: "+4.2 GB")
                divider
                growthRow(title: "Downloads", detail: "Downloaded files grew over the measured interval.", icon: "arrow.down.circle", amount: "+1.3 GB")
            } else if observed.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "chart.xyaxis.line").foregroundStyle(Brand.textSecondary)
                    Text(control.measuringLocations ? control.measurementStatus : "Two comparable folder measurements reveal where known locations grew.")
                        .foregroundStyle(Brand.textMuted)
                    Spacer()
                    Button("Open Changes") { onOpen(.changes) }.buttonStyle(ControlPanelButtonStyle())
                }.font(.system(size: 12)).padding(.vertical, 18)
            } else {
                ForEach(Array(observed), id: \.id) { change in
                    growthRow(title: change.after.root.title, detail: "Measured folder growth · \(change.interval)",
                              icon: change.after.root.icon, amount: "+\(Fmt.size(change.delta))")
                    divider
                }
            }
        }
    }
    private func growthRow(title: String, detail: String, icon: String, amount: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 19)).foregroundStyle(Brand.blue)
                .frame(width: 40, height: 40).background(Brand.surfaceElevated, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(Brand.textMuted).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(amount).font(.system(size: 12, weight: .medium)).monospacedDigit()
            Button("Inspect") { onOpen(.changes) }.buttonStyle(ControlPanelButtonStyle())
        }.padding(.vertical, 10)
    }
    private var supportingSections: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DRIVE").font(.system(size: 11)).tracking(0.7).foregroundStyle(Brand.textMuted)
            Button { onOpen(.storage) } label: {
                HStack(spacing: 14) {
                    Image(systemName: "externaldrive").font(.system(size: 23)).foregroundStyle(Brand.textSecondary).frame(width: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(externalDrive?.name ?? "External storage").font(.system(size: 13, weight: .medium))
                        if let drive = externalDrive {
                            Text("\(Fmt.size(drive.available)) available · \(drive.encrypted ? "Encrypted" : "Encryption unconfirmed")")
                                .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                        } else {
                            Text("Connect a drive to explore supported storage options.")
                                .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }
    private static let sampleDrive = StorageDrive(url: URL(fileURLWithPath: "/Volumes/Studio SSD"), name: "Studio SSD", uuid: "SAMPLE-DRIVE", capacity: 1_000_000_000_000, available: 186_000_000_000, external: true, writable: true, encrypted: true, format: "apfs")
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
