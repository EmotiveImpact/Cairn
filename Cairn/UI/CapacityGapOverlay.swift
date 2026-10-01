import SwiftUI
import Charts

/// A visual bridge between saved endpoints, deliberately outside the measured
/// chart series: no interpolated sample, area fill or selectable numeric value.
struct CapacityGapOverlay: View {
    let gaps: [CapacityPlot.Gap]
    let proxy: ChartProxy

    var body: some View {
        GeometryReader { geometry in
            if let plotFrame = proxy.plotFrame {
                let bounds = geometry[plotFrame]
                ForEach(gaps) { gap in
                    if let startX = proxy.position(forX: gap.start),
                       let endX = proxy.position(forX: gap.end),
                       let startY = proxy.position(forY: Double(gap.before.available) / 1e9),
                       let endY = proxy.position(forY: Double(gap.after.available) / 1e9) {
                        let width = endX - startX
                        let center = CGPoint(x: bounds.minX + (startX + endX) / 2,
                                             y: bounds.minY + (startY + endY) / 2)
                        Path { path in
                            path.move(to: CGPoint(x: bounds.minX + startX, y: bounds.minY + startY))
                            path.addLine(to: CGPoint(x: bounds.minX + endX, y: bounds.minY + endY))
                        }
                        .stroke(Brand.blue, style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                        .accessibilityHidden(true)

                        // Tight intervals retain the dashed bridge and hover
                        // explanation without a label covering measured data.
                        if width >= 132 {
                            Text("No saved readings")
                                .font(.system(size: 11))
                                .foregroundStyle(Brand.textMuted)
                                .fixedSize()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Brand.background, in: RoundedRectangle(cornerRadius: 4))
                                .position(center)
                                .accessibilityLabel(gap.detail)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
