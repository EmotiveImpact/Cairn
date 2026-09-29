import SwiftUI
import Charts

struct OverviewWorkspace: View {
    let store: ScanStore
    let storage: StorageTransferStore
    let control: StorageControl
    var search: String
    var onOpen: (NavSection) -> Void
    @State private var volume: Volumes.Info?
    @State private var period = 7
    @State private var showHistory = false
    @State private var selectedDate: Date?
    private var selectedSample: CapacityReading? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }
    private let preview = CommandLine.arguments.contains("--preview-ui")
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
    private var lowSpace: Bool { volume.map { $0.totalCapacity > 0 && Double($0.availableImportant) / Double($0.totalCapacity) < 0.05 } ?? false }
    private var storageHeadline: String {
        guard volume != nil else { return "Checking available storage." }
        return lowSpace ? "Your Mac needs more room." : "Room for what’s next."
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                historySection.padding(.top, 18)
                HStack(spacing: 15) {
                    if AppSettings.shared.reserveEnabled, let shortfall = control.reserveShortfall {
                        Text(shortfall == 0 ? "Your chosen \(AppSettings.shared.reserveGB) GB reserve is met" : "\(Fmt.size(shortfall)) below your chosen reserve")
                            .font(.system(size: 12)).foregroundStyle(shortfall == 0 ? Brand.textMuted : Brand.amber)
                    } else {
                        Text("Make room for what you need next").font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                    }
                    Spacer()
                    Button("Make room") { onOpen(.makeRoom) }.buttonStyle(ControlPanelButtonStyle(primary: store.hasScanned))
                }.padding(.top, 20)
                divider.padding(.top, 26).padding(.bottom, 22)
                suggestionSection
                divider.padding(.top, 26).padding(.bottom, 22)
                supportingSections
            }.padding(30).frame(maxWidth: 980, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Color(hex: 0x191D21)).foregroundStyle(Brand.textPrimary)
        .font(.system(size: 13, weight: .regular))
        .task { if !preview { await control.refreshCapacity() }; await refreshMeasurements(); if !preview { await storage.refresh() } }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in if !preview { Task { await storage.refresh() } } }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in if !preview { Task { await storage.refresh() } } }
        .onChange(of: store.isScanning) { _, running in if !running { Task { await refreshMeasurements() } } }
        .sheet(isPresented: $showHistory) {
            CairnDialog(title: "Available-space history", subtitle: "Daily readings · collected when Cairn opens", height: 540) {
                VStack(alignment: .leading, spacing: 18) {
                Picker("Period", selection: $period) { Text("7 days").tag(7); Text("30 days").tag(30) }.pickerStyle(.segmented).frame(width: 180)
                historySection
                if let delta = historyDelta { Text("\(Fmt.size(abs(delta))) \(delta < 0 ? "less" : "more") available over \(historyDays) days").font(.system(size: 14)) }
                Text("Daily readings collected when Cairn opens. Category scans do not explain every change in disk space.").font(.system(size: 12)).foregroundStyle(Brand.textMuted)
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
                VStack(alignment: .leading, spacing: 7) {
                    Text("THIS MAC").font(.system(size: 11, weight: .regular)).tracking(0.7).foregroundStyle(Brand.textMuted)
                    Text(storageHeadline)
                        .font(.system(size: 24, weight: .regular))
                    Text(volume == nil ? "Reading your internal drive…" : lowSpace ? "Internal storage is running low" : "Available space on your internal drive")
                        .font(.system(size: 12, weight: .regular)).foregroundStyle(lowSpace ? Brand.amber : Brand.textMuted)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button("History") { showHistory = true }.buttonStyle(ControlPanelButtonStyle())
                    Button { scan() } label: {
                        Label(store.isScanning ? "Stop scan" : (store.lastScanDate != nil || preview ? "Rescan" : "Scan this Mac"), systemImage: store.isScanning ? "stop.circle" : "arrow.clockwise")
                    }.buttonStyle(ControlPanelButtonStyle(primary: suggestion == nil))
                        .keyboardShortcut("r", modifiers: .command)
                        .disabled(preview || store.isCleaning)
                        .help(preview ? "Scanning is disabled in this sample preview." : "Scan this Mac (⌘R)")
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(volume.map { Fmt.size($0.availableImportant) } ?? "—").font(.system(size: 46, weight: .regular)).tracking(-1.6).monospacedDigit()
                Text("available").font(.system(size: 18, weight: .regular)).foregroundStyle(Brand.textMuted)
            }.padding(.top, 22)
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
                let chosenReserve = Double(control.reserveBytes) / 1e9
                let chartLow = max(0, min(observedLow, AppSettings.shared.reserveEnabled ? chosenReserve : observedLow) - 3)
                let chartHigh = max(observedHigh, AppSettings.shared.reserveEnabled ? chosenReserve : observedHigh) + 3
                Chart {
                    ForEach(points, id: \.date) { sample in
                        AreaMark(x: .value("Date", sample.date), yStart: .value("GB", chartLow), yEnd: .value("GB", Double(sample.available) / 1e9))
                            .foregroundStyle(LinearGradient(colors: [Brand.blue.opacity(0.17), Brand.blue.opacity(0)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Date", sample.date), y: .value("GB", Double(sample.available) / 1e9))
                            .foregroundStyle(Brand.blue).lineStyle(StrokeStyle(lineWidth: 1.7))
                        if sample.date == last.date { PointMark(x: .value("Date", sample.date), y: .value("GB", Double(sample.available) / 1e9)).foregroundStyle(Brand.blue).symbolSize(25) }
                    }
                    if AppSettings.shared.reserveEnabled {
                        RuleMark(y: .value("Chosen reserve", Double(control.reserveBytes) / 1e9))
                            .foregroundStyle(Brand.amber.opacity(0.55)).lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    }
                    if let sample = selectedSample {
                        RuleMark(x: .value("Reading", sample.date)).foregroundStyle(Brand.textMuted.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        PointMark(x: .value("Date", sample.date), y: .value("GB", Double(sample.available) / 1e9)).foregroundStyle(Brand.blue).symbolSize(35)
                    }
                }
                .chartXSelection(value: $selectedDate)
                .onChange(of: period) { _, _ in selectedDate = nil }
                .chartXScale(range: .plotDimension(padding: 5))
                .chartYScale(domain: chartLow...chartHigh)
                .chartYAxis(.hidden).chartXAxis(.hidden).frame(height: 104)
                .accessibilityLabel("Available space from \(Fmt.size(first.available)) to \(Fmt.size(last.available))")
                HStack {
                    readingLabel(first)
                    Spacer()
                    if let selectedSample { readingLabel(selectedSample).foregroundStyle(Brand.textPrimary); Spacer() }
                    readingLabel(last)
                }.font(.system(size: 11, weight: .regular)).foregroundStyle(Brand.textMuted)
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
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("START HERE").font(.system(size: 11, weight: .regular)).tracking(0.7).foregroundStyle(Brand.textMuted)
                Spacer()
                Button("What changed?") { onOpen(.changes) }.buttonStyle(.plain).font(.system(size: 12, weight: .regular)).foregroundStyle(Brand.deepBlue)
            }
            HStack(spacing: 16) {
                Image(systemName: suggestion?.category.icon ?? "magnifyingglass").font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Brand.textSecondary).frame(width: 46, height: 46)
                    .background(Brand.surfaceSubtle, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 5) {
                    Text(suggestion.map { "\($0.category.title) candidates grew" } ?? (store.isScanning ? "Scan in progress" : !search.isEmpty ? "No matching category growth" : "See what’s taking up space"))
                        .font(.system(size: 15, weight: .medium))
                    Text(suggestion.map { "\(Fmt.size($0.delta)) more in measured cleanup candidates since the previous compatible scan.\nReview files before removing anything." } ?? (store.isScanning ? store.progressText : !search.isEmpty ? "This filter searches measured categories, not files. Try a category such as build output, or press Escape to clear." : comparisonUnavailable ?? "No category growth measured. Review current files or scan again."))
                        .font(.system(size: 12, weight: .regular)).foregroundStyle(Brand.textMuted).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if let suggestion {
                    Button("Review files") { onOpen(route(suggestion.category)) }.buttonStyle(ControlPanelButtonStyle())
                } else {
                    if store.isScanning { ProgressView().controlSize(.small).accessibilityLabel("Scan in progress") }
                    else { Button("Open cleanup") { onOpen(.smartScan) }.buttonStyle(ControlPanelButtonStyle()) }
                }
            }
        }
    }
    private var supportingSections: some View {
        HStack(alignment: .top, spacing: 36) {
            VStack(alignment: .leading, spacing: 12) {
                Label(externalDrive?.name ?? "External storage", systemImage: "externaldrive").font(.system(size: 14, weight: .medium))
                if let drive = externalDrive, drive.capacity > 0 {
                    let fraction = max(0, min(1, 1 - Double(drive.available) / Double(drive.capacity)))
                    GeometryReader { proxy in
                        Capsule().fill(Brand.surfaceSubtle)
                        Capsule().fill(Brand.blue).frame(width: proxy.size.width * fraction)
                    }.frame(height: 5)
                    HStack {
                        Text("\(Fmt.size(drive.available)) available")
                        Spacer(minLength: 4)
                        Text(drive.encrypted ? "Encrypted" : "Encryption unconfirmed").foregroundStyle(Brand.textMuted)
                    }.font(.system(size: 11, weight: .regular))
                } else { Text("Connect a drive to explore your options.").font(.system(size: 12)).foregroundStyle(Brand.textMuted) }
                Button("Storage options →") { onOpen(.storage) }.buttonStyle(.plain).font(.system(size: 12, weight: .regular)).foregroundStyle(Brand.deepBlue)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(Brand.separator).frame(width: 0.5, height: 96)
            VStack(alignment: .leading, spacing: 12) {
                Label("Recent activity", systemImage: "clock.arrow.circlepath").font(.system(size: 14, weight: .medium))
                Text(preview || store.removalLog.isEmpty ? "No recorded cleanup activity." : "\(store.removalLog.count) recorded removal\(store.removalLog.count == 1 ? "" : "s").")
                    .font(.system(size: 12, weight: .regular)).foregroundStyle(Brand.textMuted)
                Label("Known session locations protected", systemImage: "lock.shield").font(.system(size: 11, weight: .regular)).foregroundStyle(Brand.textMuted)
                Button("Activity & recovery →") { onOpen(.activity) }.buttonStyle(.plain).font(.system(size: 12, weight: .regular)).foregroundStyle(Brand.deepBlue)
            }.frame(maxWidth: .infinity, alignment: .leading)
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
    private func refreshMeasurements() async {
        if preview {
            volume = Volumes.Info(url: URL(fileURLWithPath: "/"), name: "Macintosh HD", totalCapacity: 500_000_000_000, availableImportant: 9_900_000_000)
        } else {
            volume = await Task.detached { Volumes.info(for: FileScan.volumeURL(of: FileScan.home)) }.value
        }
    }
    private static let sampleHistory: [CapacityReading] = [28.4, 26.8, 23.2, 24.1, 18.6, 14.3, 9.9].enumerated().map { index, gb in
        CapacityReading(date: Date().addingTimeInterval(Double(index - 6) * 86_400), volumeID: "SAMPLE", available: Int64(gb * 1e9), total: 500_000_000_000)
    }
    private static let sampleChanges: [CandidateChange] = [
        .init(category: .init(id: "xcode", title: "Build output", icon: "hammer", group: .developer, bytes: 6_400_000_000, complete: true), delta: 4_200_000_000, before: Date().addingTimeInterval(-86400), after: Date()),
        .init(category: .init(id: "browser-caches", title: "Browser caches", icon: "globe", group: .general, bytes: 2_700_000_000, complete: true), delta: 1_100_000_000, before: Date().addingTimeInterval(-86400), after: Date()),
        .init(category: .init(id: "large-old", title: "Large downloads", icon: "folder", group: .general, bytes: 4_800_000_000, complete: true), delta: 850_000_000, before: Date().addingTimeInterval(-86400), after: Date())
    ]
}
