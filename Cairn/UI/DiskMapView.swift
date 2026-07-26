import SwiftUI

/// An interactive sunburst of the reclaimable space — inner ring = categories,
/// outer ring = the items inside them. DaisyDisk-style eye candy, built from the
/// scan we already have (no extra disk walk), shown as a toggle on the hero.
struct DiskMapView: View {
    let store: ScanStore
    var onSelectCategory: (String) -> Void

    @State private var hovered: Segment?

    struct Segment: Identifiable, Equatable {
        let id: String
        let label: String
        let size: Int64
        let color: Color
        let start: Angle
        let end: Angle
        let innerFrac: CGFloat
        let outerFrac: CGFloat
        let categoryID: String
        static func == (a: Segment, b: Segment) -> Bool { a.id == b.id }
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = side / 2 - 8
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let segments = buildSegments()

            ZStack {
                ForEach(segments) { seg in
                    ArcShape(start: seg.start, end: seg.end,
                             inner: radius * seg.innerFrac, outer: radius * seg.outerFrac,
                             center: center)
                        .fill(seg.color.opacity(hovered == nil || hovered == seg ? 1 : 0.35))
                        .overlay(
                            ArcShape(start: seg.start, end: seg.end,
                                     inner: radius * seg.innerFrac, outer: radius * seg.outerFrac,
                                     center: center)
                                .stroke(Brand.background.opacity(0.6), lineWidth: 1)
                        )
                        .onHover { if $0 { hovered = seg } else if hovered == seg { hovered = nil } }
                        .onTapGesture { onSelectCategory(seg.categoryID) }
                }

                // Center label
                VStack(spacing: 2) {
                    Text(Fmt.size(hovered?.size ?? store.grandTotal))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.textGradient)
                        .contentTransition(.numericText(value: Double(hovered?.size ?? store.grandTotal)))
                    Text(hovered?.label ?? "reclaimable")
                        .font(.system(size: 12))
                        .foregroundStyle(Brand.textSecondary)
                        .lineLimit(1).frame(maxWidth: radius * 0.8)
                }
            }
            .animation(.easeOut(duration: 0.15), value: hovered)
        }
    }

    private func pillarColor(_ group: CategoryGroup) -> Color {
        switch group {
        case .developer: return Brand.purple
        case .ai: return Brand.blue
        case .creative: return Brand.cyan
        case .general: return Color(hex: 0x6F7487)
        }
    }

    /// Build the two-ring segment list from the buckets that hold actionable space.
    private func buildSegments() -> [Segment] {
        let buckets = store.buckets.filter { $0.totalSize > 0 }
        let grand = max(1, buckets.reduce(Int64(0)) { $0 + $1.totalSize })
        var segs: [Segment] = []
        let gap: Double = 0.6
        var cursor: Double = -90  // start at top

        for bucket in buckets.sorted(by: { $0.totalSize > $1.totalSize }) {
            let span = 360.0 * Double(bucket.totalSize) / Double(grand)
            if span < 0.4 { continue }
            let cStart = cursor + gap / 2
            let cEnd = cursor + span - gap / 2
            let base = pillarColor(bucket.info.group)

            // Inner ring: the category.
            segs.append(Segment(
                id: "cat-\(bucket.id)", label: bucket.info.title, size: bucket.totalSize, color: base,
                start: .degrees(cStart), end: .degrees(max(cStart, cEnd)),
                innerFrac: 0.42, outerFrac: 0.66, categoryID: bucket.id))

            // Outer ring: items, proportional within the category's span.
            let items = bucket.items.filter { $0.allocatedSize > 0 }.sorted { $0.allocatedSize > $1.allocatedSize }
            var iCursor = cStart
            let innerSpan = max(0, cEnd - cStart)
            for (idx, item) in items.enumerated() {
                let iSpan = innerSpan * Double(item.allocatedSize) / Double(bucket.totalSize)
                if iSpan < 0.3 { continue }
                let s = iCursor
                let e = iCursor + iSpan
                iCursor = e
                segs.append(Segment(
                    id: "item-\(item.id)", label: item.url.lastPathComponent, size: item.allocatedSize,
                    color: base.opacity(idx % 2 == 0 ? 0.78 : 0.6),
                    start: .degrees(s), end: .degrees(e),
                    innerFrac: 0.68, outerFrac: 0.98, categoryID: bucket.id))
            }
            cursor += span
        }
        return segs
    }
}

/// A filled ring-arc segment between two radii.
private struct ArcShape: Shape {
    let start: Angle
    let end: Angle
    let inner: CGFloat
    let outer: CGFloat
    let center: CGPoint

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: center, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        p.addArc(center: center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        p.closeSubpath()
        return p
    }
}
