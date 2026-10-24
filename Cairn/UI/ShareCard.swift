import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// "Share your clean" (share.png): a picture of the space a clean gave back,
/// to copy, save or share. It names kinds of things only, never a file or folder.
enum ShareCard {
    /// What the card calls a cleaned item: a short kind, never its name or path.
    static func kind(of item: ScanItem) -> String {
        if item.categoryID == "dev-projects" {
            let folder = item.url.lastPathComponent
            return buildFolders.contains(folder) ? folder : "Project builds"
        }
        return kinds[item.categoryID] ?? "Other files"
    }

    /// Folder names every project of that kind shares, so they say nothing about whose.
    private static let buildFolders: Set<String> = [
        "node_modules", "target", ".build", "Pods", "venv", ".venv", "DerivedData", ".next", ".gradle", ".turbo",
    ]

    private static let kinds: [String: String] = [
        "xcode": "Xcode", "docker": "Docker", "dev-caches": "Developer caches", "browser-caches": "Browser caches",
        "app-caches": "App caches", "comm-caches": "App caches", "ide-caches": "Editor caches", "ai-models": "AI models",
        "android": "Android", "creative": "Creative caches", "installers": "Installers", "large-old": "Old files",
        "logs": "Logs", "orphaned": "App leftovers", "runtimes": "Old runtimes", "tm-snapshots": "Snapshots",
        "tool-downloads": "Test browsers", "trash": "The Bin", "chat-apps": "Chat apps", "games": "Games",
        "git-bloat": "Git history", "rule-spots": "App caches",
    ]

    /// The three biggest kinds, so the line under the number stays one line.
    static func top(_ cleared: [String: Int64]?) -> [(kind: String, bytes: Int64)] {
        (cleared ?? [:]).filter { $0.value > 0 }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(3).map { (kind: $0.key, bytes: $0.value) }
    }

    /// The card as a picture at twice its size, for Retina screens and posts.
    @MainActor static func render(freed: Int64, kinds: [(kind: String, bytes: Int64)]) -> NSImage? {
        let renderer = ImageRenderer(content: ShareCardView(freed: freed, kinds: kinds))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: ShareCardView.size.width, height: ShareCardView.size.height))
    }

    static func png(_ image: NSImage) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    /// A fixed pseudo-random value in 0..<1, so the dots are the same on every card.
    fileprivate static func noise(_ a: Int, _ b: Int) -> Double {
        var h = UInt64(truncatingIfNeeded: (a &* 73_856_093) ^ (b &* 19_349_663))
        h ^= h >> 33; h &*= 0xff51afd7ed558ccd; h ^= h >> 33
        return Double(h % 10_000) / 10_000
    }
}

/// The picture itself. Fixed Night colours, so it looks the same in light mode
/// and wherever it is posted. 572 × 300, as in the mock.
struct ShareCardView: View {
    static let size = CGSize(width: 572, height: 300)
    let freed: Int64
    let kinds: [(kind: String, bytes: Int64)]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(hex: 0x0B0F14)
            // radial-gradient(500px 260px at 25% 10%, rgba(88,168,248,.2), transparent 70%)
            RadialGradient(colors: [Color(hex: 0x58A8F8, opacity: 0.2), Color(hex: 0x58A8F8, opacity: 0)],
                           center: UnitPoint(x: 0.25, y: 0.1), startRadius: 0, endRadius: 350)
                .scaleEffect(x: 1, y: 0.52, anchor: UnitPoint(x: 0.25, y: 0.1))
            dots
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    logo.frame(width: 22, height: 22)
                    Text("Cairn").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(hex: 0xE9EEF4))
                }
                Spacer(minLength: 0)
                Text(Fmt.size(freed))
                    .font(.system(size: 84, weight: .light)).tracking(-3.8)
                    .foregroundStyle(Color(hex: 0xF3F7FB))
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text(ReceiptLine.share(freed: freed))
                    .font(.system(size: 17)).foregroundStyle(Color(hex: 0xA9B4BF))
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .padding(.top, 10)
                HStack(spacing: 20) {
                    ForEach(kinds, id: \.kind) { kind in
                        Text(Fmt.size(kind.bytes)).fontWeight(.medium).foregroundStyle(Color(hex: 0xCFE6FF))
                        + Text(" \(kind.kind)")
                    }
                    Spacer(minLength: 0)
                    Text(LicenseConfig.purchaseURL.host() ?? "getcairn.app")
                }
                .font(.system(size: 12)).foregroundStyle(Color(hex: 0x7F8C99)).lineLimit(1)
                .padding(.top, 18)
            }
            .padding(.horizontal, 30).padding(.vertical, 28)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .environment(\.colorScheme, .dark)
    }

    /// The mock's dot field: 16 rows rising from the bottom edge, thinning as they go.
    private var dots: some View {
        Canvas { context, size in
            for row in 0..<16 {
                let fade = 1 - Double(row) / 16
                for column in 0..<115 where ShareCard.noise(column, row) < 0.05 + 0.8 * fade {
                    let alpha = 0.35 * fade * (0.5 + 0.6 * ShareCard.noise(row, column + 97))
                    let centre = CGPoint(x: 3 + Double(column) * 5, y: size.height - 3 - Double(row) * 5)
                    context.fill(Path(ellipseIn: CGRect(x: centre.x - 0.9, y: centre.y - 0.9, width: 1.8, height: 1.8)),
                                 with: .color(Color(hex: 0x5D9BFF, opacity: alpha)))
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// The four-stone mark in its fixed Night blue.
    private var logo: some View {
        VStack(spacing: 22 * 0.035) {
            ForEach(Array([(0.24, 0.12), (0.40, 0.15), (0.56, 0.18), (0.74, 0.23)].enumerated()), id: \.offset) { _, stone in
                Ellipse()
                    .fill(LinearGradient(colors: [Color(red: 0.57, green: 0.79, blue: 0.98), Color(hex: 0x8CC4FF)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 22 * stone.0, height: 22 * stone.1)
            }
        }
    }
}

/// The sheet over the Done screen: the card, "Show what was cleared", and
/// Copy image, Save and Share. Escape or a click outside closes it.
struct ShareCardSheet: View {
    let freed: Int64
    let cleared: [String: Int64]?
    var onClose: () -> Void
    @State private var showKinds = true
    @State private var image: NSImage?
    @State private var file: URL?
    @State private var copied = false

    private var kinds: [(kind: String, bytes: Int64)] { showKinds ? ShareCard.top(cleared) : [] }

    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: 0x030508, opacity: 0.55)
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)
            sheet.padding(.top, 60)
        }
        .onAppear(perform: render)
        .onChange(of: showKinds) { _, _ in render() }
        .onExitCommand(perform: onClose)
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Share your clean").font(.system(size: 15, weight: .medium))
                Spacer()
                Text("No file names or folders are shown").font(.system(size: 12.5)).foregroundStyle(Brand.textMuted)
            }
            .padding(.bottom, 14)
            ShareCardView(freed: freed, kinds: kinds)
                .accessibilityElement(children: .combine)
            HStack(spacing: 8) {
                if !ShareCard.top(cleared).isEmpty {
                    Text("Show what was cleared").font(.system(size: 12.5)).foregroundStyle(Brand.textMuted)
                    Toggle("Show what was cleared", isOn: $showKinds).labelsHidden()
                        .toggleStyle(ShareSwitchStyle()).padding(.leading, 8)
                }
                Spacer()
                Button(copied ? "Copied" : "Copy image", action: copy)
                    .buttonStyle(ControlPanelButtonStyle(size: .large))
                Button("Save", action: save)
                    .buttonStyle(ControlPanelButtonStyle(size: .large))
                if let file {
                    ShareLink(item: file) { Label("Share…", systemImage: "square.and.arrow.up") }
                        .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
                }
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 24).padding(.vertical, 22)
        .frame(width: 620)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Brand.surfaceElevated))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Brand.wash(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 40, y: 20)
        .foregroundStyle(Brand.textPrimary)
        .background {
            Button("Close", action: onClose).keyboardShortcut(.cancelAction).opacity(0).accessibilityHidden(true)
        }
    }

    /// Renders the picture once per change, and keeps a PNG ready for Share.
    private func render() {
        copied = false
        image = ShareCard.render(freed: freed, kinds: kinds)
        guard let image, let data = ShareCard.png(image) else { file = nil; return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Cairn share", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("My Cairn clean.png")
        file = (try? data.write(to: url, options: .atomic)) == nil ? nil : url
    }

    private func copy() {
        guard let image else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        copied = true
    }

    private func save() {
        guard let image, let data = ShareCard.png(image) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "My Cairn clean.png"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// The mock's small switch: 30 × 18, ice when on with a dark knob.
private struct ShareSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Capsule()
            .fill(configuration.isOn ? Brand.room : Brand.wash(0.12))
            .frame(width: 30, height: 18)
            .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                Circle().fill(configuration.isOn ? Brand.onRoom : Color(light: 0xFFFFFF, dark: 0xC8D0D8))
                    .frame(width: 14, height: 14).padding(2)
            }
            .animation(.easeOut(duration: 0.15), value: configuration.isOn)
            .contentShape(Capsule())
            .onTapGesture { configuration.isOn.toggle() }
            .accessibilityElement()
            .accessibilityLabel("Show what was cleared")
            .accessibilityValue(configuration.isOn ? "On" : "Off")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { configuration.isOn.toggle() }
    }
}
