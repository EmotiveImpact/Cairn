import SwiftUI
import AppKit

/// Native selection, keyboard handling and accessibility with Cairn's quiet surface.
struct CairnSegmentedControl<Value: Hashable>: NSViewRepresentable {
    let label: String
    @Binding var selection: Value
    let options: [(String, Value)]
    @Environment(\.isEnabled) private var isEnabled
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: QuietSegments, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? CGFloat(options.count) * 86, height: 32)
    }
    func makeNSView(context: Context) -> QuietSegments {
        let view = QuietSegments()
        view.trackingMode = .selectOne
        view.target = context.coordinator
        view.action = #selector(Coordinator.changed(_:))
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }
    func updateNSView(_ view: QuietSegments, context: Context) {
        context.coordinator.parent = self
        view.segmentCount = options.count
        for (index, option) in options.enumerated() {
            view.setLabel(option.0, forSegment: index)
        }
        view.selectedSegment = options.firstIndex { $0.1 == selection } ?? -1
        view.isEnabled = isEnabled
        view.setAccessibilityLabel(label)
        view.needsDisplay = true
    }
    final class Coordinator: NSObject {
        var parent: CairnSegmentedControl
        init(_ parent: CairnSegmentedControl) { self.parent = parent }
        @objc func changed(_ sender: NSSegmentedControl) {
            guard parent.options.indices.contains(sender.selectedSegment) else { return }
            parent.selection = parent.options[sender.selectedSegment].1
            sender.needsDisplay = true
        }
    }
}

final class QuietSegments: NSSegmentedControl {
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 32) }
    override func layout() {
        super.layout()
        guard segmentCount > 0 else { return }
        let target = max(1, (bounds.width - 4) / CGFloat(segmentCount))
        for index in 0..<segmentCount where abs(width(forSegment: index) - target) > 0.1 {
            setWidth(target, forSegment: index)
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        guard segmentCount > 0 else { return }
        let area = bounds.insetBy(dx: 1, dy: 1)
        NSColor.labelColor.withAlphaComponent(0.035).setFill()
        NSBezierPath(roundedRect: area, xRadius: 8, yRadius: 8).fill()
        let width = (area.width - 4) / CGFloat(segmentCount)
        for index in 0..<segmentCount {
            let rect = NSRect(x: area.minX + 2 + CGFloat(index) * width, y: area.minY + 2, width: width, height: area.height - 4)
            let selected = selectedSegment == index
            if selected {
                NSColor.labelColor.withAlphaComponent(isEnabled ? 0.095 : 0.05).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
                if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
                    NSColor.secondaryLabelColor.setStroke()
                    NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6).stroke()
                }
            }
            let text = label(forSegment: index) ?? ""
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: selected ? .medium : .regular),
                .foregroundColor: (selected ? NSColor.labelColor : NSColor.secondaryLabelColor).withAlphaComponent(isEnabled ? 1 : 0.45)
            ]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
        }
    }
}
