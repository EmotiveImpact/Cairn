import SwiftUI
import Charts

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
    private struct PlotPoint: Identifiable {
        let reading: CapacityReading
        let segment: Int
        var id: UUID { reading.id }
    }
    private var plotPoints: [PlotPoint] {
        let maxGap: TimeInterval = preview ? 2 * 86_400 : period == 30 ? 36 * 3_600 : 8 * 3_600
        var segment = 0
        var previous: Date?
        return readings.map { reading in
            if let previous, reading.date.timeIntervalSince(previous) > maxGap { segment += 1 }
            previous = reading.date
            return PlotPoint(reading: reading, segment: segment)
        }
    }
    private var changes: [CandidateChange] {
        let all = preview ? Self.sampleChanges : control.changes
        return all.filter { search.isEmpty || $0.category.title.localizedCaseInsensitiveContains(search) }
    }
    private var selected: CapacityReading? {
        guard let selectedDate else { return nil }
        return readings.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
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
                        Text("Changes").font(.system(size: 24, weight: .regular))
                        Text("What Cairn observed on this Mac. Measurements are local and dated.")
                            .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                    }
                    Spacer()
                    Picker("Period", selection: $period) {
                        Text("24 hours").tag(1)
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                    }.pickerStyle(.segmented).frame(width: 250)
                }
                history.padding(.top, 28)
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
            }.padding(30).frame(maxWidth: 980, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Brand.background).foregroundStyle(Brand.textPrimary)
            .onChange(of: period) { _, _ in selectedDate = nil }
            .task {
                if !preview {
                    await control.refreshCapacity()
                    legacyReadings = StorageHistory.load()
                }
            }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Available space").font(.system(size: 15, weight: .medium))
                Spacer()
                if let last = readings.last {
                    Text(Fmt.size(last.available)).font(.system(size: 18, weight: .regular)).monospacedDigit()
                }
            }
            if readings.count >= 2, let first = readings.first, let last = readings.last {
                let low = max(0, readings.map(\.available).min()! - 3_000_000_000)
                let high = readings.map(\.available).max()! + 3_000_000_000
                Chart {
                    ForEach(plotPoints) { point in
                        AreaMark(x: .value("Date", point.reading.date), yStart: .value("Bytes", low), yEnd: .value("Bytes", point.reading.available), series: .value("Observation segment", point.segment))
                            .foregroundStyle(LinearGradient(colors: [Brand.blue.opacity(0.20), Brand.blue.opacity(0)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Date", point.reading.date), y: .value("Bytes", point.reading.available), series: .value("Observation segment", point.segment))
                            .foregroundStyle(Brand.blue).lineStyle(StrokeStyle(lineWidth: 1.8))
                    }
                    if AppSettings.shared.reserveEnabled {
                        RuleMark(y: .value("Chosen reserve", control.reserveBytes))
                            .foregroundStyle(Brand.amber.opacity(0.55)).lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    }
                    if let selected {
                        RuleMark(x: .value("Selected", selected.date)).foregroundStyle(Brand.textMuted.opacity(0.6))
                        PointMark(x: .value("Reading", selected.date), y: .value("Bytes", selected.available))
                            .foregroundStyle(Brand.blue).symbolSize(35)
                    }
                }
                .chartXSelection(value: $selectedDate)
                .chartXScale(range: .plotDimension(padding: 7))
                .chartYScale(domain: low...(AppSettings.shared.reserveEnabled ? max(high, control.reserveBytes + 2_000_000_000) : high))
                .chartYAxis(.hidden).chartXAxis(.hidden).frame(height: 185)
                .accessibilityLabel("Available space changed from \(Fmt.size(first.available)) to \(Fmt.size(last.available))")
                HStack {
                    readingLabel(first)
                    Spacer()
                    if let selected { readingLabel(selected).foregroundStyle(Brand.textPrimary); Spacer() }
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
            Text(preview ? "Sample data · no disk actions" : "Readings are collected while Cairn runs. Long gaps are left open because it was not observing.")
                .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
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
    private static let samples: [CapacityReading] = [28.4, 26.8, 23.2, 24.1, 18.6, 14.3, 9.9].enumerated().map { index, gb in
        CapacityReading(date: Date().addingTimeInterval(Double(index - 6) * 86_400), volumeID: "SAMPLE", available: Int64(gb * 1e9), total: 500_000_000_000)
    }
    private static let sampleChanges: [CandidateChange] = [
        CandidateChange(category: .init(id: "xcode", title: "Build output", icon: "hammer", group: .developer, bytes: 6_400_000_000, complete: true), delta: 4_200_000_000, before: Date().addingTimeInterval(-86400), after: Date()),
        CandidateChange(category: .init(id: "browser-caches", title: "Browser caches", icon: "globe", group: .general, bytes: 2_700_000_000, complete: true), delta: 1_100_000_000, before: Date().addingTimeInterval(-86400), after: Date())
    ]
}
