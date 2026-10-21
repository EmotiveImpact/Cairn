import SwiftUI

/// The cairn as a picture of the Mac: one stone per thing that can be freed,
/// smallest on top, each sized by how much room it takes. Widths follow the
/// square root of size so large items read as large without swamping the rest.
struct StoneStack: View {
    struct Stone: Identifiable {
        let title: String
        let bytes: Int64
        var id: String { title }
    }

    let stones: [Stone]
    /// Show size and name beside each stone.
    var labelled = true
    /// Ready stones are tinted with the "room" colour; settled ones stay neutral.
    var ready = true
    var maxWidth: CGFloat = 150
    var minWidth: CGFloat = 58

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var placed = false

    /// Largest at the base.
    private var ordered: [Stone] { stones.sorted { $0.bytes < $1.bytes } }
    private var largest: Int64 { max(1, stones.map(\.bytes).max() ?? 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: -5) {
            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, stone in
                let width = stoneWidth(stone)
                HStack(spacing: 10) {
                    stoneShape
                        .frame(width: width, height: width * 0.36)
                        .offset(x: index.isMultiple(of: 2) ? -CGFloat(min(8, index * 2)) : CGFloat(min(8, index * 2)))
                        .frame(width: maxWidth)
                    if labelled {
                        HStack(spacing: 6) {
                            Text(Fmt.size(stone.bytes)).font(.system(size: 11.5, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(Brand.textPrimary)
                            Text(stone.title).font(.system(size: 11.5)).foregroundStyle(Brand.textSecondary).lineLimit(1)
                        }
                    }
                }
                .zIndex(Double(index))
                .opacity(placed ? 1 : 0)
                .offset(y: placed ? 0 : -14)
                .animation(reduceMotion ? nil : Animation.spring(response: 0.5, dampingFraction: 0.72)
                    .delay(Double(ordered.count - 1 - index) * 0.06), value: placed)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stones.map { "\($0.title) \(Fmt.size($0.bytes))" }.joined(separator: ", "))
        .onAppear { placed = true }
    }

    private func stoneWidth(_ stone: Stone) -> CGFloat {
        minWidth + (maxWidth - minWidth) * CGFloat((Double(stone.bytes) / Double(largest)).squareRoot())
    }

    private var stoneShape: some View {
        Ellipse()
            .fill(ready
                  ? AnyShapeStyle(LinearGradient(colors: [Brand.room.opacity(0.85), Brand.room.opacity(0.45)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                  : AnyShapeStyle(LinearGradient(colors: [Brand.stoneTop, Brand.stoneBase],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(Ellipse().strokeBorder(Brand.wash(0.08), lineWidth: 0.5))
            .shadow(color: Brand.cardShadow, radius: 4, y: 3)
    }
}
