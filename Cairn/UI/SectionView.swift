import SwiftUI

/// A nav section that shows a filtered slice of the scan as expandable category
/// groups (Developer / AI / Creative / Large Files / Apps).
struct SectionView: View {
    let store: ScanStore
    let section: NavSection
    var onReview: () -> Void

    private var buckets: [ScanStore.Bucket] { section.buckets(store) }

    var body: some View {
        ScrollView {
            CategoryResults(store: store, buckets: buckets, title: section.title, onReview: onReview)
                .padding(28)
        }
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
