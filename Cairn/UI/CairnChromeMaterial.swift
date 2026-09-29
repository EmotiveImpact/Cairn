import SwiftUI
import AppKit

/// System-owned chrome: no custom tracking areas, timers or layout mutations.
struct CairnChromeMaterial: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        Group {
            if reduceTransparency { Brand.deepPanel }
            else { ZStack { Brand.deepPanel; NativeChromeMaterial().opacity(0.45) } }
        }.allowsHitTesting(false)
    }
}
private struct NativeChromeMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .headerView
        view.blendingMode = .withinWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
