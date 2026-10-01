import SwiftUI
import Charts
import AppKit

/// Dedicated evidence screen. Candidate changes never claim to explain all
/// capacity movement or identify which process wrote the files.
struct ChangesWorkspace: View {
    let control: StorageControl
    let store: ScanStore
    var search: String
    var onOpen: (NavSection) -> Void
    @State private var period = 7
    @State private var selectedDate: Date?
    @State private var legacyReadings: [StorageHistory.Sample] = []
    private let preview = CommandLine.arguments.contains("--preview-ui")

    private var readings: [CapacityReading] {
        let all = preview ? Self.samples : control.latestCapacity
        let start = Date().addingTimeInterval(-Double(period) * 86_400)
        return all.filter { $0.date >= start }.sorted { $0.date < $1.date }
    }
    private var plot: CapacityPlot {
        let maxGap: TimeInterval = preview ? 2 * 86_400 : period == 30 ? 36 * 3_600 : 8 * 3_600
        return CapacityPlot(readings: readings, maximumInterval: maxGap)
    }
    private var changes: [CandidateChange] {
        let all = preview ? Self.sampleChanges : control.changes
        return all.filter { search.isEmpty || $0.category.title.localizedCaseInsensitiveContains(search) }
    }
    private var selected: CapacityReading? {
        guard let selectedDate else { return nil }
        return plot.reading(near: selectedDate)
    }
    private var selectedDetail: String? {
        guard let selectedDate else { return nil }
        if let gap = plot.gap(at: selectedDate) { return gap.detail }
        guard let selected else { return nil }
        return "\(selected.date.formatted(date: .abbreviated, time: .shortened)) · \(Fmt.size(selected.available)) available"
    }
    private var scopeMessage: String {
        if preview { return "Sample readings · two compatible scans" }
        if store.isScanning { return "A scan is in progress. Its measurements will appear when complete." }
        if let latest = control.candidates.last {
            let covered = latest.categories.filter(\.complete).count
            return "\(covered) of \(latest.categories.count) candidate categories measured · \(latest.date.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Complete two scans to compare cleanup candidates. Other storage can change between scans."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Changes").font(.system(size: 28, weight: .semibold))
                        Text("What Cairn observed on this Mac. Measurements are local and dated.")
                            .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                    }
                    Spacer()
                    CairnSegmentedControl(label: "Period", selection: $period, options: [("24 hours", 1), ("7 days", 7), ("30 days", 30)]).frame(width: 228, height: 32)
                }
                history.padding(.top, 26)
                if !suggestions.isEmpty { suggestionSection.padding(.top, 28) }
                locationSection.padding(.top, 28)
                if !legacyReadings.isEmpty {
                    DisclosureGroup("Earlier daily readings · volume unverified") {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("These readings predate volume identity tracking. They are kept separately and are not joined to the chart or candidate changes.")
                                .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                            ForEach(Array(legacyReadings.suffix(7).reversed()), id: \.date) { entry in
                                HStack {
                                    Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                    Spacer()
                                    Text(Fmt.size(entry.freeBytes)).monospacedDigit()
                                }.font(.system(size: 11)).foregroundStyle(Brand.textSecondary)
                            }
                        }.padding(.top, 8)
                    }.font(.system(size: 11)).foregroundStyle(Brand.textMuted).padding(.top, 18)
                }
                Rectangle().fill(Brand.separator).frame(height: 0.5).padding(.vertical, 26)
                HStack {
                    Text("OBSERVED CANDIDATES").font(.system(size: 11)).tracking(0.7).foregroundStyle(Brand.textMuted)
                    Spacer()
                    if !preview, let first = control.candidates.suffix(2).first, let last = control.candidates.last, first.id != last.id {
                        Text("\(first.date.formatted(date: .abbreviated, time: .omitted)) – \(last.date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                    }
                }
                Text(scopeMessage).font(.system(size: 12)).foregroundStyle(Brand.textMuted).padding(.top, 9)
                if let error = control.error, !preview {
                    Text(error).font(.system(size: 12)).foregroundStyle(Brand.amber).padding(.top, 10)
                }
                if changes.isEmpty {
                    CairnStateView(kind: .empty, title: store.isScanning ? "Measuring changes" : "No comparable change yet",
                        message: search.isEmpty ? "Two completed measurements with matching scope reveal changes in known locations. Cairn does not guess at the rest of the disk." : "No measured category matches this filter.")
                        .padding(.top, 20)
                } else {
                    VStack(spacing: 0) {
                        ForEach(changes) { change in
                            Button { onOpen(route(change.category)) } label: {
                                HStack(spacing: 15) {
                                    Image(systemName: change.category.icon).font(.system(size: 19, weight: .light))
                                        .foregroundStyle(Brand.textSecondary).frame(width: 30)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(change.category.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.textPrimary)
                                        Text("Measured cleanup candidates · \(change.delta > 0 ? "grew" : "shrunk") between scans")
                                            .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                                    }
                                    Spacer()
                                    Text("\(change.delta > 0 ? "+" : "−")\(Fmt.size(abs(change.delta)))")
                                        .font(.system(size: 14, weight: .regular)).monospacedDigit()
                                        .foregroundStyle(change.delta > 0 ? Brand.textPrimary : Brand.safeCyan)
                                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Brand.textMuted)
                                }.frame(minHeight: 64).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Rectangle().fill(Brand.separator).frame(height: 0.5)
                        }
                    }.padding(.top, 12)
                }
                Text("Changes in these cleanup candidates do not account for every change in available space. Browser activity, app data and macOS-managed files may lie outside this coverage.")
                    .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 18)
            }.padding(30).frame(maxWidth: .infinity, alignment: .leading)
        }.background(Brand.background).foregroundStyle(Brand.textPrimary)
            .onChange(of: period) { _, _ in selectedDate = nil }
            .task {
                if !preview {
                    await control.refreshCapacity()
                    legacyReadings = StorageHistory.load()
                }
            }
    }

    private var visibleLocations: [LocationReading] {
        (preview ? Self.sampleLocations : control.latestLocations).filter {
            search.isEmpty || $0.root.title.localizedCaseInsensitiveContains(search)
        }
    }
    private var suggestions: [GrowthSuggestion] {
        preview ? GrowthSuggestions.evaluate(LocationComparison.changes(Self.sampleLocationHistory),
            selectedIDs: GrowthSuggestions.defaultIDs, minimumBytes: 1_000_000_000) : control.growthSuggestions
    }
    private var suggestionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SUGGESTED INSPECTIONS").font(.system(size: 11)).tracking(0.7).foregroundStyle(Brand.textMuted)
            ForEach(suggestions) { suggestion in
                HStack(spacing: 14) {
                    Image(systemName: suggestion.change.after.root.icon)
                        .font(.system(size: 18)).foregroundStyle(Brand.blue).frame(width: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(suggestion.change.after.root.title).font(.system(size: 13, weight: .medium))
                        Text("Grew \(Fmt.size(suggestion.change.delta)) · \(suggestion.change.interval)")
                            .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                    }
                    Spacer()
                    Button("Inspect") { onOpen(suggestion.change.id == "downloads" ? .largeFiles :
                        (suggestion.change.id == "chrome-cache" || suggestion.change.id == "safari-cache" ? .browsers : .developer)) }
                        .buttonStyle(ControlPanelButtonStyle())
                }.padding(.vertical, 9)
                Rectangle().fill(Brand.separator).frame(height: 0.5)
            }
            Text("Suggestions use measured growth, not a claim that these bytes can be freed. Review individual files and the owning app before any action.")
                .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
        }
    }
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("KNOWN LOCATIONS").font(.system(size: 11)).tracking(0.7).foregroundStyle(Brand.textMuted)
                Spacer()
                Button(control.measuringLocations ? "Stop measuring" : "Measure locations") {
                    if control.measuringLocations { control.cancelLocationMeasurement() }
                    else { control.measureLocations() }
                }.buttonStyle(ControlPanelButtonStyle()).disabled(preview)
            }
            Text(control.measuringLocations ? control.measurementStatus : "Folder sizes from metadata only. These observations do not grant permission to remove anything.")
                .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
            if visibleLocations.isEmpty {
                Text(search.isEmpty ? "Measure known locations to start a baseline. A second compatible reading shows growth or decline." : "No observed location matches this filter.")
                    .font(.system(size: 12)).foregroundStyle(Brand.textSecondary).padding(.vertical, 12)
            }
            ForEach(visibleLocations) { reading in
                let change = (preview ? LocationComparison.changes(Self.sampleLocationHistory) : control.locationChanges).first { $0.id == reading.root.id }
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(reading.root.path).textSelection(.enabled)
                        Text("Observed \(reading.ended.formatted(date: .abbreviated, time: .shortened)) · \(reading.entries) entries checked")
                        if let change {
                            Text("\(change.interval) · \(Fmt.size(change.before.allocated ?? 0)) → \(Fmt.size(change.after.allocated ?? 0)) allocated")
                        } else {
                            Text("A second complete reading with matching location, volume and scope is needed for a comparison.")
                        }
                        Text(reading.root.observationOnly ? "Observation only. This location is not added to cleanup candidates." : "Open the relevant cleanup screen to review separately eligible items.")
                        Text("Hard links are counted once within this folder. APFS clones and snapshots can share or retain blocks; folder sizes are not guaranteed space savings.")
                        Button("Show location") { NSWorkspace.shared.activateFileViewerSelecting([reading.root.url]) }
                            .buttonStyle(.plain).foregroundStyle(Brand.deepBlue).disabled(preview || reading.coverage == .absent)
                    }.font(.system(size: 11)).foregroundStyle(Brand.textMuted).padding(.vertical, 8)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: reading.root.icon).frame(width: 24).foregroundStyle(Brand.textSecondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(reading.root.title).font(.system(size: 13)).foregroundStyle(Brand.textPrimary)
                            Text(reading.coverage.label).font(.system(size: 11)).foregroundStyle(reading.coverage.comparable ? Brand.textMuted : Brand.amber)
                        }
                        Spacer()
                        if let change {
                            Text(change.delta == 0 ? "Unchanged" : "\(change.delta > 0 ? "+" : "−")\(Fmt.size(abs(change.delta)))")
                                .font(.system(size: 12)).monospacedDigit().foregroundStyle(Brand.textSecondary)
                        }
                        Text(reading.allocated.map { (reading.coverage.comparable ? "" : "Partial · ") + Fmt.size($0) } ?? "Unavailable")
                            .font(.system(size: 13)).monospacedDigit().frame(minWidth: 92, alignment: .trailing)
                    }.frame(minHeight: 52)
                }
                Rectangle().fill(Brand.separator).frame(height: 0.5)
            }
            Text("Each location has its own measured interval. These sizes are not added together to explain the whole disk.")
                .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
        }
    }
    private static var sampleLocationHistory: [LocationReading] {
        sampleChanges.flatMap { change -> [LocationReading] in
            let root = ObservedRoot(id: change.id, title: change.category.title, path: "/Sample/" + change.category.title, icon: change.category.icon, observationOnly: false)
            return [(change.before, change.category.bytes - change.delta), (change.after, change.category.bytes)].map { date, bytes in
                LocationReading(id: UUID(), root: root, started: date.addingTimeInterval(-1), ended: date, volumeID: PreviewStorageScenario.volumeID, identity: .init(device: 1, inode: 2), parentIdentity: .init(device: 1, inode: 1), scope: "sample", coverage: .complete, allocated: bytes, logical: bytes, entries: 25, hardLinksSkipped: 0, source: "sample", metric: "allocated-and-logical-v1", adapterVersion: 1)
            }
        }
    }
    private static var sampleLocations: [LocationReading] { LocationComparison.latest(sampleLocationHistory) }

    private var history: some View {
        let shownReserve: Int64? = preview ? PreviewStorageScenario.reserveBytes :
            (AppSettings.shared.reserveEnabled ? control.reserveBytes : nil)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("AVAILABLE SPACE").font(.system(size: 11, weight: .medium))
                        .tracking(0.7).foregroundStyle(Brand.textMuted)
                    if let last = readings.last {
                        Text(Fmt.size(last.available)).font(.system(size: 34, weight: .regular))
                            .monospacedDigit().foregroundStyle(Brand.textPrimary)
                    } else {
                        Text("No readings yet").font(.system(size: 21, weight: .regular))
                    }
                }
                Spacer()
                if let shownReserve {
                    Label("\(Fmt.size(shownReserve)) reserve", systemImage: "line.diagonal")
                        .font(.system(size: 11)).foregroundStyle(Brand.textSecondary)
                }
            }
            if readings.count >= 2, let first = readings.first, let last = readings.last {
                let observedLow = readings.map(\.available).min()!
                let low = max(0, min(observedLow, shownReserve ?? observedLow) - 3_000_000_000)
                let high = readings.map(\.available).max()! + 3_000_000_000
                let upper = shownReserve.map { max(high, $0 + 2_000_000_000) } ?? high
                Chart {
                    ForEach(plot.points) { point in
                        AreaMark(x: .value("Date", point.reading.date), yStart: .value("GB", Double(low) / 1e9), yEnd: .value("GB", Double(point.reading.available) / 1e9), series: .value("Observation segment", point.segment))
                            .foregroundStyle(LinearGradient(colors: [Brand.blue.opacity(0.20), Brand.blue.opacity(0)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Date", point.reading.date), y: .value("GB", Double(point.reading.available) / 1e9), series: .value("Observation segment", point.segment))
                            .foregroundStyle(Brand.blue).lineStyle(StrokeStyle(lineWidth: 1.8))
                    }
                    if let shownReserve {
                        RuleMark(y: .value("Chosen reserve", Double(shownReserve) / 1e9))
                            .foregroundStyle(Brand.amber.opacity(0.55)).lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    }
                    if let selected {
                        RuleMark(x: .value("Selected", selected.date)).foregroundStyle(Brand.textMuted.opacity(0.6))
                        PointMark(x: .value("Reading", selected.date), y: .value("GB", Double(selected.available) / 1e9))
                            .foregroundStyle(Brand.blue).symbolSize(35)
                    }
                }
                .chartOverlay { proxy in
                    CapacityGapOverlay(gaps: plot.gaps, proxy: proxy)
                }
                .chartXSelection(value: $selectedDate)
                .chartXScale(range: .plotDimension(padding: 7))
                .chartYScale(domain: (Double(low) / 1e9)...(Double(upper) / 1e9))
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { axis in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                            .foregroundStyle(Brand.separator)
                        if let gb = axis.as(Double.self) {
                            AxisValueLabel { Text("\(Int(gb)) GB") }
                                .foregroundStyle(Brand.textMuted)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            .foregroundStyle(Brand.textMuted)
                    }
                }
                .frame(height: 218)
                .accessibilityLabel("Available space changed from \(Fmt.size(first.available)) to \(Fmt.size(last.available))")
                CapacityChartReadout(text: selectedDetail)
                HStack {
                    readingLabel(first)
                    Spacer()
                    readingLabel(last)
                }.font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                let delta = last.available - first.available
                Text("\(Fmt.size(abs(delta))) \(delta < 0 ? "less" : "more") available over this measured interval")
                    .font(.system(size: 12)).foregroundStyle(Brand.textSecondary).padding(.top, 6)
            } else {
                CairnStateView(kind: .empty, title: "History starts here",
                    message: "Cairn needs two readings on this volume before drawing a trend. It will never invent earlier readings.")
                    .frame(minHeight: 160)
            }
            DisclosureGroup("Readings as text") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(readings.suffix(100).reversed())) { reading in
                        HStack {
                            Text(reading.date.formatted(date: .abbreviated, time: .shortened))
                            Spacer()
                            Text(Fmt.size(reading.available)).monospacedDigit()
                        }.accessibilityElement(children: .combine)
                    }
                }.font(.system(size: 11)).padding(.top, 8)
            }.font(.system(size: 11)).foregroundStyle(Brand.textMuted)
            if preview {
                Text("Sample data · no disk actions")
                    .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
            }
        }
    }
    private func readingLabel(_ reading: CapacityReading) -> some View {
        Text("\(reading.date.formatted(.dateTime.day().month(.abbreviated).hour().minute())) · \(Fmt.size(reading.available))").monospacedDigit()
    }
    private func route(_ category: CandidateReading.Category) -> NavSection {
        if category.id == "browser-caches" { return .browsers }
        if ["large-old", "installers"].contains(category.id) { return .largeFiles }
        switch category.group {
        case .developer: return .developer
        case .ai: return .ai
        case .creative: return .creative
        case .general: return .general
        }
    }
    private static let samples = PreviewStorageScenario.capacityHistory
    private static let sampleChanges: [CandidateChange] = [
        CandidateChange(category: .init(id: "xcode", title: "Build output", icon: "hammer", group: .developer, bytes: 6_400_000_000, complete: true), delta: 4_200_000_000, before: Date().addingTimeInterval(-86400), after: Date()),
        CandidateChange(category: .init(id: "browser-caches", title: "Browser caches", icon: "globe", group: .general, bytes: 2_700_000_000, complete: true), delta: 1_100_000_000, before: Date().addingTimeInterval(-86400), after: Date())
    ]
}
