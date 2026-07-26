import SwiftUI

/// The "Reclaimed X GB" completion moment — subtle reward, with Undo.
struct CelebrationOverlay: View {
    let summary: ScanStore.CleanSummary
    let store: ScanStore
    var onDismiss: () -> Void

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var subtitle: String {
        let rec = summary.recoverableCount, perm = summary.permanentCount
        if perm > 0 && rec == 0 {
            return "\(perm) item\(perm == 1 ? "" : "s") permanently removed"
        } else if perm > 0 {
            return "\(rec) moved to Trash · \(perm) permanently removed"
        }
        return "\(rec) item\(rec == 1 ? "" : "s") moved to the Trash — recoverable"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.32).ignoresSafeArea().onTapGesture { onDismiss() }
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(Brand.cyan.opacity(0.22)).frame(width: 120, height: 120).blur(radius: 22)
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 62)).foregroundStyle(Brand.brand)
                        .symbolEffect(.bounce, value: appeared)
                }
                Text("Reclaimed \(Fmt.size(summary.bytes))")
                    .font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Brand.textPrimary)
                    .contentTransition(.numericText())
                Text(subtitle)
                    .font(.subheadline).foregroundStyle(Brand.textSecondary)
                HStack(spacing: 10) {
                    if !summary.restorable.isEmpty {
                        Button("Undo") { store.undoLast(); onDismiss() }.buttonStyle(GhostButtonStyle())
                    }
                    Button("Done") { onDismiss() }.buttonStyle(BrandButtonStyle())
                }
                .padding(.top, 6)
            }
            .padding(40)
            .cairnCard(0, radius: Brand.rXL, level: .high)
            .padding(40)
            .scaleEffect(appeared ? 1 : 0.9)
            .opacity(appeared ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .onAppear {
            if reduceMotion { appeared = true }
            else { withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { appeared = true } }
        }
    }
}
