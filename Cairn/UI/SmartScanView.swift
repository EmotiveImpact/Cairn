import SwiftUI

struct SmartScanView: View {
    let store: ScanStore
    var onReview: () -> Void
    var onMissionReview: () -> Void
    @State private var showMap = false
    /// Stable anchor for the elapsed-time TimelineView (see note below).
    @State private var timelineAnchor = Date()

    var body: some View {
        if store.isScanning {
            scanning
        } else if store.hasScanned {
            results
        } else {
            idle
        }
    }

    // MARK: - Idle state (land here on launch; show last scan if cached)

    private var idle: some View {
        let s = Fmt.split(store.displayGrandTotal)
        return VStack(spacing: 18) {
            Spacer()
            ScanRing(progress: store.displayGrandTotal > 0 ? 1 : 0.02,
                     value: s.value, unit: s.unit,
                     caption1: "Reclaimable",
                     caption2: store.showingCachedResults ? "Last scan" : "Not scanned yet")
                .frame(width: 300, height: 300)
            Text(store.showingCachedResults
                 ? "Showing your last scan. Run a fresh scan to review and clean."
                 : "Run a Smart Scan to find reclaimable space across your Mac.")
                .font(.system(size: 13)).foregroundStyle(Brand.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
            Button { store.startScan(includeExternalVolumes: !AppSettings.shared.ignoreExternalDrives) } label: {
                Label(store.showingCachedResults ? "Rescan" : "Start Smart Scan", systemImage: "scope").frame(maxWidth: 280)
            }
            .buttonStyle(BrandButtonStyle(prominent: false))
            if !FullDiskAccess.isGranted() {
                Label("Grant Full Disk Access for complete results", systemImage: "lock.shield")
                    .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    // MARK: - Scanning state (matches the mockup)

    private var scanning: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Smart Scan").font(.system(size: 15, weight: .semibold)).foregroundStyle(Brand.textPrimary)
                Spacer()
                // `from: .now` re-evaluated per render created a NEW schedule every
                // frame, which invalidated the view, which re-rendered… an infinite
                // loop that pinned the main thread during scans. Anchor the start.
                TimelineView(.periodic(from: timelineAnchor, by: 1)) { _ in
                    HStack(spacing: 10) {
                        metaStat("ELAPSED", elapsed)
                        metaStat("PROGRESS", "\(Int(store.scanProgress * 100))%")
                    }
                }
            }
            .padding(28)

            // The signature animated scan visual (counter-rotating gradient rings,
            // pulsing core, live "and counting…" total + Stop).
            ScanningHero(total: store.grandTotal,
                         itemCount: store.buckets.reduce(0) { $0 + $1.items.count },
                         progressText: store.progressText,
                         isScanning: true) { store.cancel() }

            statCards.padding(.horizontal, 28).padding(.bottom, 24)
        }
    }

    private func metaStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(label).eyebrow()
            Text(value).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(Brand.textPrimary).contentTransition(.numericText())
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .cairnCard(0, radius: 10, level: .low)
    }

    private var statCards: some View {
        HStack(spacing: 12) {
            ForEach(Array(store.buckets.filter { $0.totalSize > 0 }.sorted { $0.totalSize > $1.totalSize }.prefix(5))) { b in
                VStack(spacing: 8) {
                    ToolIcon.forCategory(b.id, size: 24)
                    Text(b.info.title).font(.system(size: 11, weight: .medium)).foregroundStyle(Brand.textSecondary)
                        .lineLimit(1)
                    Text(Fmt.size(b.totalSize)).font(.system(size: 14, weight: .bold)).foregroundStyle(Brand.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .cairnCard(14)
            }
        }
    }

    private var cancelledBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.amber).font(.system(size: 14))
            Text("Scan stopped — these are partial results.").font(.system(size: 12, weight: .medium)).foregroundStyle(Brand.textPrimary)
            Spacer()
            Button("Rescan") { store.startScan(includeExternalVolumes: !AppSettings.shared.ignoreExternalDrives) }.buttonStyle(GhostButtonStyle())
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).fill(Brand.amber.opacity(0.10))
            .overlay(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).stroke(Brand.amber.opacity(0.3), lineWidth: 1)))
    }

    private var elapsed: String {
        guard let start = store.scanStartedAt else { return "00:00" }
        let t = max(0, Int(Date().timeIntervalSince(start)))
        return String(format: "%02d:%02d", t / 60, t % 60)
    }

    // MARK: - Results state

    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if store.phase == .cancelled { cancelledBanner }
                MissionsBar(store: store) { mission in
                    mission.apply(store)
                    if store.selectedCount > 0 { onMissionReview() }
                }
                HStack {
                    Text("Results").font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.textMuted)
                    Spacer()
                    Picker("", selection: $showMap) {
                        Image(systemName: "list.bullet").tag(false)
                        Image(systemName: "chart.pie.fill").tag(true)
                    }
                    .pickerStyle(.segmented).frame(width: 92)
                }
                if showMap {
                    DiskMapView(store: store) { _ in }
                        .frame(height: 340)
                        .cairnCard(16)
                } else {
                    CategoryResults(store: store, buckets: store.buckets, title: "Smart Scan", onReview: onReview)
                }
            }
            .padding(28)
        }
    }
}

/// The light progress ring — value / unit / caption stacked, matching the mockup.
struct ScanRing: View {
    var progress: Double
    var topLabel: String = ""
    var value: String
    var unit: String
    var caption1: String
    var caption2: String = ""

    var body: some View {
        ZStack {
            // Solid white centre so the value reads clearly over the hero artwork.
            Circle().fill(Brand.surfaceElevated).padding(5.5)
                .shadow(color: Brand.blue.opacity(0.10), radius: 14, y: 3)
            Circle().stroke(Brand.border, lineWidth: 11)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(Brand.ring, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // Springs so a clean makes the arc visibly fall back, rather than
                // the number changing with no sense of space being returned.
                .animation(.spring(response: 0.7, dampingFraction: 0.78), value: progress)
            VStack(spacing: 1) {
                if !topLabel.isEmpty {
                    Text(topLabel).font(.system(size: 13)).foregroundStyle(Brand.textSecondary).padding(.bottom, 2)
                }
                Text(value).font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Brand.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text(unit).font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(Brand.textSecondary)
                Text(caption1).font(.system(size: 12.5)).foregroundStyle(Brand.textSecondary).padding(.top, 4)
                if !caption2.isEmpty {
                    Text(caption2).font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 26)
        }
    }
}
