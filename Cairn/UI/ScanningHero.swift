import SwiftUI

/// The animated scan visualization — rotating gradient rings + a pulsing core
/// with the live "Reclaimable: X GB and counting…" counter (SPEC §4.1).
struct ScanningHero: View {
    let total: Int64
    let itemCount: Int
    let progressText: String
    let isScanning: Bool
    var onStop: () -> Void

    @State private var spin = false
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 30) {
            ZStack {
                // Outer rotating ring
                ring(diameter: 230, lineWidth: 3, colors: [Brand.blue, Brand.cyan, .clear, Brand.blue])
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .opacity(0.9)
                // Inner counter-rotating ring
                ring(diameter: 176, lineWidth: 2, colors: [Brand.cyan, .clear, Brand.blue, .clear, Brand.cyan])
                    .rotationEffect(.degrees(spin ? -360 : 0))
                    .opacity(0.7)
                // Pulsing glow core
                Circle()
                    .fill(Brand.blue.opacity(0.20))
                    .frame(width: 150, height: 150)
                    .blur(radius: 28)
                    .scaleEffect(pulse ? 1.12 : 0.9)
                // Cairn mark
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 50, weight: .semibold))
                    .foregroundStyle(Brand.brand)
                    .scaleEffect(pulse ? 1.04 : 0.98)
            }
            .frame(height: 240)

            VStack(spacing: 8) {
                Text(Fmt.size(total))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.textGradient)
                    .contentTransition(.numericText(value: Double(total)))
                    .animation(.snappy, value: total)
                Text(isScanning ? "reclaimable — and counting…" : "reclaimable")
                    .font(.title3)
                    .foregroundStyle(Brand.textSecondary)
                Text(isScanning ? (progressText.isEmpty ? "Scanning…" : progressText)
                                : "\(itemCount) items found across your Mac")
                    .font(.footnote)
                    .foregroundStyle(Brand.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 460)
                    .padding(.top, 2)
            }

            if isScanning {
                Button(action: onStop) { Label("Stop", systemImage: "stop.fill") }
                    .buttonStyle(GhostButtonStyle())
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { startAnimating() }
        .onChange(of: isScanning) { _, now in if now { startAnimating() } }
    }

    private func ring(diameter: CGFloat, lineWidth: CGFloat, colors: [Color]) -> some View {
        Circle()
            .stroke(
                AngularGradient(colors: colors, center: .center),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .frame(width: diameter, height: diameter)
    }

    private func startAnimating() {
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: 7).repeatForever(autoreverses: false)) { spin = true }
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { pulse = true }
    }
}
