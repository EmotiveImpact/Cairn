import SwiftUI

/// A clean donut breakdown with a center total. Used on the Developer Cleanup
/// summary panel.
struct DonutChart: View {
    struct Slice: Identifiable { let id = UUID(); let label: String; let value: Int64; let color: Color }
    let slices: [Slice]
    var lineWidth: CGFloat = 22
    var centerTop: String = ""
    var centerValue: String = ""

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var total: Int64 { max(1, slices.reduce(0) { $0 + $1.value }) }

    var body: some View {
        ZStack {
            Circle().stroke(Brand.border, lineWidth: lineWidth)
            ForEach(Array(boundaries.enumerated()), id: \.offset) { _, b in
                Circle()
                    .trim(from: b.start, to: (appeared || reduceMotion) ? b.end : b.start)
                    .stroke(b.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: appeared)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: total)
            }
            VStack(spacing: 1) {
                if !centerTop.isEmpty { Text(centerTop).font(.system(size: 11)).foregroundStyle(Brand.textMuted) }
                Text(centerValue).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Brand.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.4, dampingFraction: 0.9), value: centerValue)
            }
        }
        .onAppear { appeared = true }
    }

    private var boundaries: [(start: CGFloat, end: CGFloat, color: Color)] {
        var acc: CGFloat = 0
        var out: [(CGFloat, CGFloat, Color)] = []
        for s in slices {
            let frac = CGFloat(s.value) / CGFloat(total)
            let gap: CGFloat = frac > 0.02 ? 0.004 : 0
            out.append((acc + gap, acc + frac - gap, s.color))
            acc += frac
        }
        return out.map { (start: $0.0, end: max($0.0, $0.1), color: $0.2) }
    }
}

/// Legend rows for a donut.
struct DonutLegend: View {
    let slices: [DonutChart.Slice]
    var body: some View {
        VStack(spacing: 7) {
            ForEach(slices) { s in
                HStack(spacing: 8) {
                    Circle().fill(s.color).frame(width: 8, height: 8)
                    Text(s.label).font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
                    Spacer()
                    Text(Fmt.size(s.value)).font(.system(size: 12, weight: .medium)).foregroundStyle(Brand.textPrimary)
                }
            }
        }
    }
}
