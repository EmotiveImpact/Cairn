import SwiftUI

/// The readout always occupies one line, including when the pointer leaves.
/// Hover changes its contents, never the position of the workspace below it.
struct CapacityChartReadout: View {
    let text: String?
    var body: some View {
        Text(text ?? " ")
            .font(.system(size: 11, weight: text == nil ? .regular : .medium))
            .monospacedDigit()
            .foregroundStyle(text == nil ? Brand.textMuted : Brand.textPrimary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 18, alignment: .leading)
            .opacity(text == nil ? 0 : 1)
            .accessibilityHidden(text == nil)
            .help(text ?? "Move over the chart to inspect a reading.")
    }
}
