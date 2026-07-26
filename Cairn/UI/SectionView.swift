import SwiftUI

/// A nav section that shows a filtered slice of the scan as expandable category
/// groups (Developer / AI / Creative / Large Files / Apps).
struct SectionView: View {
    let store: ScanStore
    let section: NavSection
    var onReview: () -> Void

    private var buckets: [ScanStore.Bucket] { section.buckets(store) }
    private var shown: [ScanStore.Bucket] {
        buckets.filter { !$0.items.isEmpty }.sorted { $0.totalSize > $1.totalSize }
    }
    private var total: Int64 { buckets.reduce(0) { $0 + $1.totalSize } }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PageHero(title: section.title,
                         subtitle: subtitle,
                         progress: total > 0 ? 1 : 0.02,
                         value: total,
                         caption: "Reclaimable",
                         footnote: shown.isEmpty ? "\(buckets.count) categories" : "\(shown.count) with results") {
                    Button { for b in buckets { store.selectAllSafe(in: b.id) } } label: {
                        Label("Select all safe", systemImage: "checklist")
                    }
                    .buttonStyle(WhiteButtonStyle())
                    .disabled(shown.isEmpty)
                    Button { store.rescan() } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(WhiteButtonStyle())
                }
                content.heroPageContent()
            }
        }
    }

    /// Says what this pillar actually covers, so the page explains itself.
    private var subtitle: String {
        switch section {
        case .ai:
            return "Model weights, embeddings and agent caches. Large, rebuildable, and re-downloaded on demand — your conversations are never touched."
        case .creative:
            return "Render caches, previews, proxies and scratch files left behind by your creative tools."
        default:
            return "Reclaimable space in this category."
        }
    }

    @ViewBuilder private var content: some View {
        if store.isScanning && shown.isEmpty {
            LoadingState(label: "Scanning \(section.title.lowercased())…")
                .cairnCard(0)
        } else if !store.hasScanned {
            EmptyState(icon: section.icon,
                       title: "No scan yet",
                       caption: "Run a scan to see what \(section.title) is holding on to.",
                       tint: Brand.blue)
                .cairnCard(0)
        } else if shown.isEmpty {
            EmptyState(icon: "checkmark.circle.fill",
                       title: "Nothing to clean here",
                       caption: "Cairn found no reclaimable space in \(section.title). You're tidy.",
                       tint: Brand.safeCyan)
                .cairnCard(0)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(shown) { bucket in
                    CategoryDisclosure(store: store, bucketID: bucket.id)
                }
                cleanBar
            }
        }
    }

    /// The one primary action on the page, anchored under the list.
    private var cleanBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.selectedCount > 0
                     ? "\(store.selectedCount) selected · \(Fmt.size(store.selectedTotal))"
                     : "Nothing selected")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.textPrimary)
                Text("Everything goes to the Trash — you can put it back.")
                    .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
            }
            Spacer()
            Button("Select none") { for b in buckets { store.selectNone(in: b.id) } }
                .buttonStyle(GhostButtonStyle())
                .disabled(store.selectedCount == 0)
            Button(action: onReview) {
                Text(store.selectedCount > 0 ? "Review & Clean \(Fmt.size(store.selectedTotal))" : "Review & Clean")
            }
            .buttonStyle(BrandButtonStyle(enabled: store.selectedCount > 0))
            .disabled(store.selectedCount == 0)
        }
        .padding(14)
        .background(CardBackground(level: .low))
    }
}

/// Header + expandable category disclosures + a sticky clean action.
struct CategoryResults: View {
    let store: ScanStore
    let buckets: [ScanStore.Bucket]
    let title: String
    var onReview: () -> Void

    private var shown: [ScanStore.Bucket] {
        buckets.filter { !$0.items.isEmpty }.sorted { $0.totalSize > $1.totalSize }
    }
    private var total: Int64 { buckets.reduce(0) { $0 + $1.totalSize } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(Brand.textPrimary)
                    Text("\(Fmt.size(total)) reclaimable across \(shown.count) categories")
                        .font(.system(size: 13)).foregroundStyle(Brand.textSecondary)
                }
                Spacer()
                Button("Select safe") { for b in buckets { store.selectAllSafe(in: b.id) } }
                    .buttonStyle(GhostButtonStyle())
                Button {
                    onReview()
                } label: { Text(store.selectedCount > 0 ? "Review & Clean \(Fmt.size(store.selectedTotal))" : "Review & Clean") }
                    .buttonStyle(BrandButtonStyle(enabled: store.selectedCount > 0))
                    .disabled(store.selectedCount == 0)
            }

            if store.isScanning && shown.isEmpty {
                loading
            } else if shown.isEmpty {
                empty
            } else {
                ForEach(shown) { bucket in
                    CategoryDisclosure(store: store, bucketID: bucket.id)
                }
            }
        }
    }

    private var loading: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Scanning…").font(.system(size: 13)).foregroundStyle(Brand.textMuted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle").font(.system(size: 30)).foregroundStyle(Brand.safeCyan)
            Text("Nothing to clean here — you're tidy.").font(.system(size: 13)).foregroundStyle(Brand.textMuted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 50)
    }
}

/// One collapsible category card.
struct CategoryDisclosure: View {
    let store: ScanStore
    let bucketID: String
    @State private var expanded = false

    private var bucket: ScanStore.Bucket? { store.buckets.first { $0.id == bucketID } }

    var body: some View {
        if let bucket {
            VStack(spacing: 0) {
                Button { withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: bucket.info.systemImage).font(.system(size: 15)).foregroundStyle(Brand.blue).frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(bucket.info.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Brand.textPrimary)
                            Text(bucket.info.subtitle).font(.system(size: 11)).foregroundStyle(Brand.textMuted).lineLimit(1)
                        }
                        Spacer()
                        if bucket.selectedSize > 0 {
                            Text(Fmt.size(bucket.selectedSize)).font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.blue)
                        }
                        Text("\(bucket.items.count) · \(Fmt.size(bucket.totalSize))")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Brand.textSecondary)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Brand.textMuted).rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).pointerCursor()

                if expanded {
                    Divider().overlay(Brand.border)
                    HStack(spacing: 8) {
                        Button("Select safe") { store.selectAllSafe(in: bucket.id) }.buttonStyle(GhostButtonStyle())
                        Button("None") { store.selectNone(in: bucket.id) }.buttonStyle(GhostButtonStyle())
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    LazyVStack(spacing: 2) {
                        ForEach(bucket.items) { item in
                            ItemRow(store: store, item: item)
                        }
                    }
                    .padding(.horizontal, 6).padding(.bottom, 8)
                }
            }
            .background(CardBackground())
        }
    }
}
