import SwiftUI
import AppKit

/// Keeps the latest disk map while the app runs, so leaving the page and
/// coming back does not walk the disk again.
@MainActor @Observable final class DiskMapStore {
    static let shared = DiskMapStore()
    private(set) var reading: DiskMap.Reading?
    private(set) var measuring = false
    private(set) var status = ""

    func measure() {
        guard !measuring else { return }
        measuring = true
        status = "Measuring…"
        Task {
            let result = await Task.detached(priority: .utility) {
                DiskMap.read(progress: { line in Task { @MainActor in DiskMapStore.shared.status = "Measuring " + line } })
            }.value
            reading = result ?? reading
            status = result == nil ? "Cairn could not read this disk's capacity." : ""
            measuring = false
        }
    }

    func showSample() { reading = DiskMapWorkspace.sample }
}

/// Files › Disk map: the whole internal disk as two rings. The inner ring
/// is macOS, System Data, apps, coding, your files and free space; the outer
/// ring is what is inside each. Click a slice to look inside it.
struct DiskMapWorkspace: View {
    private var map: DiskMapStore { .shared }
    @State private var path: [String] = []
    @State private var hovered: String?
    private let preview = CommandLine.arguments.contains("--preview-ui")

    private var reading: DiskMap.Reading? { map.reading }

    /// The area being looked at; nil is the whole disk.
    private var focus: DiskArea? {
        var current: DiskArea?
        var level = reading?.areas ?? []
        for id in path {
            guard let next = level.first(where: { $0.id == id }) else { break }
            current = next
            level = next.children
        }
        return current
    }
    private var shown: [DiskArea] { focus?.children ?? reading?.areas ?? [] }
    private var hoveredArea: DiskArea? {
        guard let hovered else { return nil }
        return shown.first { $0.id == hovered } ?? shown.flatMap(\.children).first { $0.id == hovered }
    }

    var body: some View {
        NightPage(eyebrow: path.isEmpty ? "Disk map" : "Disk map · " + breadcrumb,
                  title: title, subtitle: subtitle) {
            HStack(spacing: 8) {
                if !path.isEmpty {
                    Button { path.removeLast() } label: { Label("Back", systemImage: "chevron.left") }
                        .buttonStyle(ControlPanelButtonStyle(size: .small))
                }
                Button { measure() } label: {
                    Label(map.measuring ? "Measuring…" : reading == nil ? "Map my disk" : "Measure again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(ControlPanelButtonStyle(size: .small))
                .disabled(map.measuring)
            }
        } content: {
            if let reading {
                HStack(alignment: .top, spacing: 36) {
                    rings(reading).frame(width: 340, height: 340)
                    legend.frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                NightEmpty(title: map.measuring ? "Mapping your disk" : "Not mapped yet",
                           message: map.measuring ? map.status
                               : "Cairn measures macOS, System Data, apps and your files. It only reads sizes and takes up to two minutes.",
                           busy: map.measuring)
            }
        } footer: {
            if let reading {
                NightTotal(strong: Fmt.size(reading.free), rest: "free of \(Fmt.size(reading.total))")
                Spacer()
                Text(map.measuring ? map.status : "Measured " + reading.date.formatted(.relative(presentation: .named)))
                    .font(.system(size: 12)).foregroundStyle(Brand.textMuted).lineLimit(1)
            }
        }
        .task { if preview && reading == nil { map.showSample() } }
    }

    private var breadcrumb: String {
        var names: [String] = []
        var level = reading?.areas ?? []
        for id in path {
            guard let next = level.first(where: { $0.id == id }) else { break }
            names.append(next.title)
            level = next.children
        }
        return names.joined(separator: " › ")
    }

    private var title: String {
        guard let reading else { return "Disk map" }
        if let focus { return "\(focus.partial ? "≥ " : "")\(Fmt.size(focus.bytes)) in \(focus.title)" }
        return "\(Fmt.size(reading.used)) used of \(Fmt.size(reading.total))"
    }

    private var subtitle: String {
        if let focus { return focus.note.isEmpty ? "Click a slice to look inside it." : focus.note }
        return reading == nil ? "A picture of everything on this Mac's disk, System Data included."
                              : "Click a slice to look inside it. Sizes marked ≥ hit a measuring limit."
    }

    private func measure() {
        guard !preview else { map.showSample(); return }
        path = []
        map.measure()
    }

    // MARK: - Rings

    private struct Slice: Identifiable {
        let area: DiskArea
        let start: Double
        let end: Double
        let outer: Bool
        let tint: Color
        var id: String { area.id }
    }

    private func slices(_ areas: [DiskArea]) -> [Slice] {
        let total = max(1, areas.reduce(Int64(0)) { $0 + $1.bytes })
        var result: [Slice] = []
        var cursor = -90.0
        for (index, area) in areas.enumerated() {
            let span = 360 * Double(area.bytes) / Double(total)
            let tint = tint(area, index: index)
            result.append(Slice(area: area, start: cursor, end: cursor + span, outer: false, tint: tint))
            var inner = cursor
            let childTotal = max(1, area.children.reduce(Int64(0)) { $0 + $1.bytes })
            for (childIndex, child) in area.children.enumerated() {
                let childSpan = span * Double(child.bytes) / Double(max(childTotal, area.bytes))
                if childSpan >= 0.5 {
                    result.append(Slice(area: child, start: inner, end: inner + childSpan, outer: true,
                                        tint: tint.opacity(childIndex % 2 == 0 ? 0.72 : 0.5)))
                }
                inner += childSpan
            }
            cursor += span
        }
        return result
    }

    /// Blues only: each kind is one step of the same blue, free space a faint track.
    private func tint(_ area: DiskArea, index: Int) -> Color {
        if focus != nil { return Brand.room.opacity([0.95, 0.8, 0.65, 0.5, 0.38][index % 5]) }
        switch area.kind {
        case .free: return Brand.wash(0.10)
        case .macOS: return Brand.room.opacity(0.32)
        case .systemData: return Brand.room.opacity(0.5)
        case .apps: return Brand.room.opacity(0.66)
        case .developer: return Brand.room.opacity(0.82)
        case .files, .other: return Brand.room.opacity(0.96)
        }
    }

    private func rings(_ reading: DiskMap.Reading) -> some View {
        GeometryReader { geo in
            let radius = min(geo.size.width, geo.size.height) / 2 - 4
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let all = slices(shown)
            ZStack {
                ForEach(all) { slice in
                    let gap = slice.end - slice.start > 1.2 ? 0.35 : 0
                    DiskMapArc(start: .degrees(slice.start + gap), end: .degrees(max(slice.start + gap, slice.end - gap)),
                               inner: radius * (slice.outer ? 0.70 : 0.44), outer: radius * (slice.outer ? 0.98 : 0.68), center: center)
                        .fill(slice.tint.opacity(hovered == nil || hovered == slice.id ? 1 : 0.55))
                        .onHover { inside in
                            if inside { hovered = slice.id } else if hovered == slice.id { hovered = nil }
                        }
                        .onTapGesture { open(slice.area) }
                        .accessibilityLabel("\(slice.area.title), \(Fmt.size(slice.area.bytes))")
                }
                VStack(spacing: 3) {
                    let area = hoveredArea
                    Text(Fmt.size(area?.bytes ?? focus?.bytes ?? reading.used))
                        .font(.system(size: 26, weight: .light)).monospacedDigit()
                        .foregroundStyle(Brand.textPrimary)
                    Text(area?.title ?? focus?.title ?? "used")
                        .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                        .lineLimit(2).multilineTextAlignment(.center)
                        .frame(maxWidth: radius * 0.75)
                }
                .allowsHitTesting(false)
            }
            .animation(.easeOut(duration: 0.15), value: hovered)
        }
    }

    // MARK: - Legend

    private var legend: some View {
        let areas = shown
        let largest = max(1, areas.map(\.bytes).max() ?? 1)
        return NightList {
            ForEach(Array(areas.enumerated()), id: \.element.id) { index, area in
                Button { open(area) } label: {
                    HStack(spacing: 12) {
                        Circle().fill(tint(area, index: index)).frame(width: 9, height: 9)
                        NightName(logo: nil, title: area.title, subtitle: area.note)
                        NightMeter(share: Double(area.bytes) / Double(largest))
                        Text((area.partial ? "≥ " : "") + Fmt.size(area.bytes)).font(.system(size: 13, weight: .medium)).monospacedDigit()
                            .frame(width: 90, alignment: .trailing)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(area.children.isEmpty ? Color.clear : Brand.textMuted)
                    }
                }
                .buttonStyle(.plain)
                .nightRow()
                .onHover { inside in
                    if inside { hovered = area.id } else if hovered == area.id { hovered = nil }
                }
                .contextMenu {
                    if let url = area.url { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                }
            }
        }
    }

    /// Opens an area with something inside it; otherwise shows it in Finder.
    private func open(_ area: DiskArea) {
        if !area.children.isEmpty {
            // An outer slice belongs to an inner one; open the path down to it.
            if let parent = shown.first(where: { $0.children.contains { $0.id == area.id } }) {
                path.append(parent.id)
            }
            path.append(area.id)
            hovered = nil
        } else if area.kind != .free, let url = area.url, !preview {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    /// Sample map for `--preview-ui` screenshots. Nothing on disk is read.
    static let sample: DiskMap.Reading = {
        let gb: Int64 = 1_000_000_000
        func a(_ id: String, _ title: String, _ kind: DiskArea.Kind, _ size: Int64, _ children: [DiskArea] = [], _ note: String = "") -> DiskArea {
            DiskArea(id: id, title: title, kind: kind, bytes: size * gb, children: children, note: note)
        }
        let system = [a("sys/dev", "Xcode and simulators", .systemData, 38), a("sys/support", "App support data", .systemData, 21),
                      a("sys/caches", "App caches", .systemData, 14), a("sys/containers", "App containers", .systemData, 11),
                      a("sys/vm", "Swap and sleep image", .systemData, 6), a("sys/unseen", "Not measured", .systemData, 9)]
        let files = [a("f/dl", "Downloads", .files, 42), a("f/docs", "Documents", .files, 30), a("f/pics", "Pictures", .files, 24),
                     a("f/movies", "Movies", .files, 18), a("f/desk", "Desktop", .files, 6)]
        let dev = [a("d/dev", "Developer", .developer, 64), a("d/hidden", "Hidden tool folders", .developer, 31)]
        let apps = [a("a/xcode", "Xcode", .apps, 12), a("a/logic", "Logic Pro", .apps, 7), a("a/rest", "48 smaller items", .apps, 19)]
        return DiskMap.Reading(total: 994 * gb, free: 412 * gb, areas: [
            a("macos", "macOS", .macOS, 16, [], "macOS and the files it needs to start. Read-only."),
            a("sys", "System Data", .systemData, 99, system, "What Finder calls System Data, broken into its parts."),
            a("apps", "Apps", .apps, 38, apps), a("dev", "Coding", .developer, 95, dev),
            a("files", "Your files", .files, 120, files), a("free", "Free", .free, 412),
        ], date: Date())
    }()
}

/// A filled ring segment between two radii.
struct DiskMapArc: Shape {
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
