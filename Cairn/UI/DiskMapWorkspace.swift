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

/// Files › Disk map: the whole internal disk as one wide bar, each kind of
/// space a clear step of blue (design/new-pages/diskmap2.png). The list
/// below names every part; choosing one shows what is inside it beside the
/// list. Nothing slides: hover and choice only change light.
struct DiskMapWorkspace: View {
    private var map: DiskMapStore { .shared }
    @State private var path: [String] = []
    @State private var chosen: String?
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
    /// The part whose insides show beside the list: the one clicked, else the
    /// largest part that has something inside (System Data on most Macs).
    private var opened: DiskArea? {
        if let chosen, let area = shown.first(where: { $0.id == chosen }), !area.children.isEmpty { return area }
        return shown.first { $0.kind == .systemData && !$0.children.isEmpty }
            ?? shown.filter { !$0.children.isEmpty }.max { $0.bytes < $1.bytes }
    }

    var body: some View {
        NightNumberPage(eyebrow: path.isEmpty ? "Files · Disk map" : "Disk map · " + breadcrumb,
                        number: number, phrase: phrase, lead: lead) {
            HStack(spacing: 8) {
                if !path.isEmpty {
                    Button { path.removeLast(); chosen = nil } label: { Label("Back", systemImage: "chevron.left") }
                        .buttonStyle(ControlPanelButtonStyle(size: .small))
                }
                Button { measure() } label: {
                    Label(map.measuring ? "Measuring…" : reading == nil ? "Map my disk" : "Measure again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(ControlPanelButtonStyle(size: .small))
                .disabled(map.measuring)
            }
        } content: {
            if reading != nil {
                VStack(alignment: .leading, spacing: 26) {
                    diskBar
                    HStack(alignment: .top, spacing: 36) {
                        legend.frame(maxWidth: .infinity)
                        inside.frame(maxWidth: .infinity, alignment: .topLeading)
                    }
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

    private var number: String {
        guard let reading else { return "Disk map" }
        if let focus { return (focus.partial ? "≥ " : "") + Fmt.size(focus.bytes) }
        return Fmt.size(reading.used)
    }

    private var phrase: String {
        guard let reading else { return "" }
        if let focus { return "in \(focus.title)" }
        return "used of \(Fmt.size(reading.total))"
    }

    private var lead: String {
        if let focus { return focus.note.isEmpty ? "Choose a part to see what is inside it." : focus.note }
        return reading == nil ? "A picture of everything on this Mac's disk, System Data included."
                              : "Everything on this disk, System Data included. Choose a part to look inside."
    }

    private func measure() {
        guard !preview else { map.showSample(); return }
        path = []
        chosen = nil
        map.measure()
    }

    // MARK: - Colour

    /// Blues only: each kind of space is its own clear step, so the bar and
    /// the list match at a glance. Free space is a faint track.
    static func tone(_ kind: DiskArea.Kind) -> Color {
        switch kind {
        case .macOS: return Color(light: 0x8DA4BD, dark: 0x3D5A7A)
        case .systemData: return Brand.room
        case .apps: return Color(light: 0x4F86C6, dark: 0x5D8FC4)
        case .developer: return Color(light: 0x6E9FD9, dark: 0x7FB0E8)
        case .files, .other: return Color(light: 0xA3C3E6, dark: 0xA9CDF4)
        case .free: return Brand.wash(0.07)
        }
    }

    private func tone(_ area: DiskArea, index: Int) -> Color {
        focus == nil ? Self.tone(area.kind) : Self.step(index)
    }

    /// Steps of ice for the parts inside one area, largest first.
    static func step(_ index: Int) -> Color {
        Brand.room.opacity([1, 0.78, 0.6, 0.46, 0.34, 0.24, 0.18][min(index, 6)])
    }

    // MARK: - Bar

    private var diskBar: some View {
        let areas = shown
        let total = Double(max(1, areas.reduce(Int64(0)) { $0 + $1.bytes }))
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let gaps = CGFloat(max(0, areas.count - 1)) * 3
                HStack(spacing: 3) {
                    ForEach(Array(areas.enumerated()), id: \.element.id) { index, area in
                        let width = max(4, (geo.size.width - gaps) * CGFloat(Double(area.bytes) / total))
                        let lit = opened?.id == area.id || hovered == area.id
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(tone(area, index: index))
                            .opacity(hovered == nil || hovered == area.id || area.kind == .free ? 1 : 0.8)
                            .shadow(color: lit && area.kind != .free ? Brand.room.opacity(0.45) : .clear, radius: 9)
                            .overlay(alignment: .leading) {
                                if width > 74 {
                                    Text(area.kind == .free ? "Free · " + Fmt.size(area.bytes) : area.title)
                                        .font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                                        .foregroundStyle(area.kind == .free ? Brand.textMuted : Brand.onRoom)
                                        .padding(.leading, 10)
                                }
                            }
                            .frame(width: width)
                            .onHover { inside in
                                if inside { hovered = area.id } else if hovered == area.id { hovered = nil }
                            }
                            .onTapGesture { open(area) }
                            .help("\(area.title): \(Fmt.size(area.bytes))")
                            .accessibilityLabel("\(area.title), \(Fmt.size(area.bytes))")
                    }
                }
            }
            .frame(height: 44)
            HStack {
                Text("0")
                Spacer()
                Text(Fmt.size(Int64(total)))
            }
            .font(.system(size: 11)).foregroundStyle(Brand.textMuted).monospacedDigit()
        }
        .animation(.easeOut(duration: 0.15), value: hovered)
    }

    // MARK: - List

    private var legend: some View {
        NightList {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, area in
                Button { open(area) } label: {
                    HStack(spacing: 12) {
                        Circle().fill(area.kind == .free && focus == nil ? Brand.wash(0.14) : tone(area, index: index))
                            .frame(width: 9, height: 9)
                        Text(area.title).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text((area.partial ? "≥ " : "") + Fmt.size(area.bytes))
                            .font(.system(size: 13, weight: .medium)).monospacedDigit()
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(area.children.isEmpty ? Color.clear : Brand.textMuted)
                    }
                    .padding(.horizontal, 6)
                }
                .buttonStyle(.plain)
                .nightRow()
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(opened?.id == area.id || hovered == area.id ? Brand.room.opacity(0.05) : Color.clear))
                .onHover { inside in
                    if inside { hovered = area.id } else if hovered == area.id { hovered = nil }
                }
                .help(area.note)
                .contextMenu {
                    if let url = area.url { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                }
            }
        }
    }

    /// What is inside the opened part: its own small bar and list.
    @ViewBuilder private var inside: some View {
        if let area = opened {
            let parts = area.children.sorted { $0.bytes > $1.bytes }
            let total = Double(max(1, parts.reduce(Int64(0)) { $0 + $1.bytes }))
            VStack(alignment: .leading, spacing: 12) {
                Text("Inside \(area.title) · \(Fmt.size(area.bytes))").nightEyebrow().lineLimit(1)
                GeometryReader { geo in
                    let gaps = CGFloat(max(0, parts.count - 1)) * 2
                    HStack(spacing: 2) {
                        ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Self.step(index))
                                .frame(width: max(3, (geo.size.width - gaps) * CGFloat(Double(part.bytes) / total)))
                        }
                    }
                }
                .frame(height: 10)
                NightList {
                    ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                        Button { open(part) } label: {
                            HStack(spacing: 12) {
                                Circle().fill(Self.step(index)).frame(width: 9, height: 9)
                                Text(part.title).font(.system(size: 13)).lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text((part.partial ? "≥ " : "") + Fmt.size(part.bytes))
                                    .font(.system(size: 13, weight: .medium)).monospacedDigit()
                            }
                            .padding(.horizontal, 4)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, -4)
                        .nightRow()
                        .help(part.note.isEmpty ? part.title : part.note)
                    }
                }
                if !area.note.isEmpty {
                    Text(area.note).font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Choosing a part shows its insides; a part inside the opened one drills
    /// down when it has parts of its own, otherwise shows it in Finder.
    private func open(_ area: DiskArea) {
        if shown.contains(where: { $0.id == area.id }) {
            chosen = area.id
            if area.children.isEmpty, area.kind != .free, let url = area.url, !preview {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        } else if !area.children.isEmpty, let parent = opened {
            path.append(parent.id)
            path.append(area.id)
            chosen = nil
            hovered = nil
        } else if let url = area.url, !preview {
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
