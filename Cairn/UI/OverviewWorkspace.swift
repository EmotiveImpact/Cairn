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
        return lowSpace ? "Your Mac is running low on space" : "This Mac"
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                cleanHero.padding(.top, 22)
                biggestRow.padding(.top, 26)
                graphPanel.padding(.top, 24)
                diskCard.padding(.top, 24)
                nextTiles.padding(.top, 22)
            }.padding(.horizontal, 36).padding(.top, 24).padding(.bottom, 26)
                .frame(maxWidth: 1200, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Brand.glow.ignoresSafeArea()).background(Brand.background).foregroundStyle(Brand.textPrimary)
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

    /// The headline action: what a scan found that can be freed in one go.
    private var recommendedBytes: Int64 { preview ? 18_400_000_000 : store.recommendedBytes }
    private var topCategories: [(String, Int64)] {
        if preview { return [("Xcode", 6_400_000_000), ("Developer caches", 5_200_000_000), ("Browsers", 2_700_000_000), ("Docker", 2_300_000_000)] }
        var totals: [String: Int64] = [:]
        for bucket in store.buckets {
            let bytes = bucket.items.filter { $0.severity == .safe && $0.isRegenerable && $0.isActionable }.reduce(0) { $0 + $1.allocatedSize }
            if bytes > 0 { totals[bucket.info.title, default: 0] += bytes }
        }
        return totals.sorted { $0.value > $1.value }.prefix(6).map { ($0.key, $0.value) }
    }
    @ViewBuilder private var cleanHero: some View {
        if store.isScanning && !preview {
            HStack(spacing: 16) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Scanning · \(Fmt.size(store.grandTotal)) found so far").font(.system(size: 15, weight: .semibold)).monospacedDigit()
                    Text(store.progressText).font(.system(size: 11)).foregroundStyle(Brand.textMuted).lineLimit(1)
                }
                Spacer()
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Brand.rHero).fill(Brand.surfaceElevated))
        } else if recommendedBytes > 0 {
            // One number, one button: what can safely go, and the way to free it.
            HStack(alignment: .center, spacing: 28) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(Fmt.size(recommendedBytes))
                            .font(.system(size: 76, weight: .light)).tracking(-3).monospacedDigit()
                            .contentTransition(.numericText())
                        Text("you can get back").font(.system(size: 21)).foregroundStyle(Brand.textSecondary)
                    }
                    Text("Build files, caches and old simulators that your tools rebuild on their own. Your code, documents and AI conversations are never included.")
                        .font(.system(size: 13)).foregroundStyle(Brand.textSecondary)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 460, alignment: .leading)
                        .padding(.top, 12)
                    HStack(spacing: 10) {
                        Button { onCleanRecommended() } label: {
                            Text("Review and free \(Fmt.size(recommendedBytes))").frame(minWidth: 170)
                        }
                        .buttonStyle(ControlPanelButtonStyle(primary: true))
                        .controlSize(.large)
                        .disabled(preview || store.isCleaning)
                        .help("Check the list once, then free the space")
                        Button("See everything") { onOpen(.smartScan) }
                            .buttonStyle(ControlPanelButtonStyle())
                    }.padding(.top, 20)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if !store.hasLiveResults {
            HStack(spacing: 16) {
                Image(systemName: "sparkle.magnifyingglass").font(.system(size: 26)).foregroundStyle(Brand.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Find out what you can free").font(.system(size: 15, weight: .semibold))
                    Text("A scan takes a minute or two. Nothing is removed until you review it.")
                        .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                }
                Spacer()
                Button("Scan this Mac") { scan() }.buttonStyle(ControlPanelButtonStyle(primary: true)).disabled(preview)
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Brand.rHero).fill(Brand.surfaceElevated))
        } else {
            HStack(spacing: 16) {
                Image(systemName: "checkmark.circle").font(.system(size: 26)).foregroundStyle(Brand.room)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Nothing to free right now").font(.system(size: 15, weight: .semibold))
                    Text("Your caches and build files are already tidy. Cairn will show a number here when they grow.")
                        .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                }
                Spacer()
                Button("See everything") { onOpen(.smartScan) }.buttonStyle(ControlPanelButtonStyle())
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Brand.rHero).fill(Brand.surfaceElevated))
        }
    }

    /// The disk now, and what it will look like once the ready items are freed.
    @ViewBuilder private var diskCard: some View {
        if let capacity = displayedCapacity, capacity.total > 0 {
            let total = Double(capacity.total)
            let used = max(0, capacity.total - capacity.available)
            let ready = min(store.isScanning ? 0 : recommendedBytes, used)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Fmt.size(capacity.available)) free of \(Fmt.size(capacity.total))")
                        .font(.system(size: 14, weight: .semibold)).monospacedDigit()
                    Spacer()
                    if ready > 0 {
                        (Text("After freeing: ").foregroundStyle(Brand.textMuted)
                         + Text("\(Fmt.size(capacity.available + ready)) free").foregroundStyle(Brand.room).fontWeight(.semibold))
                            .font(.system(size: 13)).monospacedDigit()
                    } else if let reserve = shownReserve {
                        Text(capacity.available >= reserve ? "Above your \(Fmt.size(reserve)) reserve" : "\(Fmt.size(reserve - capacity.available)) below your reserve")
                            .font(.system(size: 12)).foregroundStyle(capacity.available >= reserve ? Brand.textMuted : Brand.amber)
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

    /// The next useful thing, never a warning: what grew, the last result, the drive.
    private var nextTiles: some View {
        HStack(alignment: .top, spacing: 14) {
            growthTile
            lastCleanTile
            driveTile
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    private func tile(_ eyebrow: String, _ title: String, _ detail: String, _ link: String, _ action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(eyebrow).eyebrow()
            Text(title).font(.system(size: 13.5, weight: .semibold)).lineLimit(2)
            Text(detail).font(.system(size: 12)).foregroundStyle(Brand.textSecondary).lineLimit(2)
            Spacer(minLength: 2)
            Button(link, action: action).buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Brand.deepBlue)
        }
        .padding(15).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Brand.rHero).fill(Brand.wash(0.02)))
        .overlay(RoundedRectangle(cornerRadius: Brand.rHero).strokeBorder(Brand.separator, lineWidth: 1))
    }
    private var growthTile: some View {
        let grew = control.locationChanges.filter { $0.delta > 0 }.max { $0.delta < $1.delta }
        if preview { return tile("Recently", "Xcode build output grew by 4.2 GB", "DerivedData and build intermediates.", "See what changed") { onOpen(.changes) } }
        if let grew {
            return tile("Recently", "\(grew.after.root.title) grew by \(Fmt.size(grew.delta))", grew.interval, "See what changed") { onOpen(.changes) }
        }
        return tile("Recently", "No growth measured yet", "Cairn compares folder sizes between scans.", "Open Changes") { onOpen(.changes) }
    }
    private var lastCleanTile: some View {
        if preview { return tile("Last clean", "3 October · 23.4 GB freed", "Verified on this Mac.", "See receipt") { onOpen(.activity) } }
        if let run = store.cleanupRuns.first(where: { $0.finished != nil && $0.summary.accounting.completedCount > 0 }) {
            let gains = run.summary.capacityChanges.compactMap(\.delta).filter { $0 > 0 }.reduce(0, +)
            let freed = max(run.summary.accounting.freedBytes, gains)
            let title = "\(run.started.formatted(.dateTime.day().month(.wide))) · " + (freed > 0 ? "\(Fmt.size(freed)) freed" : "\(run.summary.accounting.completedCount) items cleaned")
            let detail = gains > 0 ? "Verified on this Mac." : run.summary.recoverableCount > 0 ? "\(run.summary.recoverableCount) can be put back." : "Recorded in Activity."
            return tile("Last clean", title, detail, "See receipt") { onOpen(.activity) }
        }
        return tile("Last clean", "No cleans yet", "Every clean leaves a receipt in Activity.", "Open Activity") { onOpen(.activity) }
    }
    private var driveTile: some View {
        if let drive = externalDrive {
            return tile("External storage", drive.name, "\(Fmt.size(drive.available)) available\(drive.encrypted ? " · Encrypted" : "")", "Storage options") { onOpen(.storage) }
        }
        return tile("External storage", "No drive connected", "Connect a drive to see storage options.", "Storage options") { onOpen(.storage) }
    }
    /// The biggest things that can go, each with a bar against the largest.
    @ViewBuilder private var biggestRow: some View {
        let top = Array(topCategories.prefix(4))
        if !store.isScanning || preview, let largest = top.first?.1, largest > 0 {
            HStack(alignment: .top, spacing: 22) {
                ForEach(top.indices, id: \.self) { index in
                    let (title, bytes) = top[index]
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).eyebrow().lineLimit(1)
                        Text(Fmt.size(bytes)).font(.system(size: 24, weight: .light)).monospacedDigit()
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Brand.track)
                                Capsule().fill(Brand.room.opacity(0.8))
                                    .frame(width: max(4, geo.size.width * CGFloat(Double(bytes) / Double(largest))))
                            }
                        }.frame(height: 3).padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
                ForEach(top.count..<4, id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
            }
        }
    }
    /// Free space over time, with a ring on the day of each clean.
    private var graphPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("Free space · last \(period) days").eyebrow()
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
        .padding(.horizontal, 18).padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: Brand.rHero).fill(Brand.wash(0.02)))
        .overlay(RoundedRectangle(cornerRadius: Brand.rHero).strokeBorder(Brand.separator, lineWidth: 1))
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
    private var header: some View {
        HStack(alignment: .center) {
            Text(storageHeadline).font(.system(size: 13, weight: .medium))
                .foregroundStyle(lowSpace ? Brand.amber : Brand.textSecondary)
            Spacer()
            HStack(spacing: 8) {
                Button { scan() } label: {
                    Label(store.isScanning ? "Stop scan" : (store.lastScanDate != nil || preview ? "Rescan" : "Scan this Mac"), systemImage: store.isScanning ? "stop.circle" : "arrow.clockwise")
                }.buttonStyle(ControlPanelButtonStyle())
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(preview || store.isCleaning)
                    .help(preview ? "Scanning is disabled in this sample preview." : "Scan this Mac (⌘R)")
                Button("Make room") { onOpen(.makeRoom) }
                    .buttonStyle(ControlPanelButtonStyle())
                    .help("Choose an available-space target and review your options")
                Button("History") { showHistory = true }
                    .buttonStyle(ControlPanelButtonStyle())
                    .help("Available space over the last week or month")
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
                            .foregroundStyle(LinearGradient(colors: [Brand.room.opacity(0.16), Brand.room.opacity(0)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Date", sample.date), y: .value("GB", Double(sample.available) / 1e9), series: .value("Observation segment", point.segment))
                            .foregroundStyle(Brand.room).lineStyle(StrokeStyle(lineWidth: 1.7, lineJoin: .round))
                            .shadow(color: Brand.room.opacity(0.6), radius: 4)
                        if sample.date == last.date { PointMark(x: .value("Date", sample.date), y: .value("GB", Double(sample.available) / 1e9)).foregroundStyle(Brand.room).symbolSize(40) }
                    }
                    ForEach(cleanMarks) { mark in
                        PointMark(x: .value("Date", mark.date), y: .value("GB", mark.available))
                            .symbol { Circle().fill(Brand.background).overlay(Circle().strokeBorder(Brand.room, lineWidth: 1.6)).frame(width: 9, height: 9) }
                    }
                    if shownReserve != nil {
                        RuleMark(y: .value("Chosen reserve", chosenReserve))
                            .foregroundStyle(Brand.amber.opacity(0.55)).lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
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
                    AxisValueLabel { if let gb = value.as(Double.self) { Text("\(Int(gb)) GB") } }
                } }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                .frame(height: 170)
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
