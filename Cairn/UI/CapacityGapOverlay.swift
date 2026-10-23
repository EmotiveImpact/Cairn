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
                        Path { path in
                            path.move(to: CGPoint(x: bounds.minX + startX, y: bounds.minY + startY))
                            path.addLine(to: CGPoint(x: bounds.minX + endX, y: bounds.minY + endY))
                        }
                        // Faint, unlabelled bridge: the hover readout explains it.
                        .stroke(Brand.textMuted.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
                        .accessibilityLabel(gap.detail)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
