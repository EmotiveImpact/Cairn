import SwiftUI
import AppKit

/// A company's own logo (Claude, Codex, Cursor, Xcode, Docker, npm), drawn
/// colourless in the text tone, with no tile behind it. Falls back to an SF Symbol
/// when the logo is not bundled, for example under `swift run`.
struct BrandLogo: View {
    let name: String?
    var fallback: String = "shippingbox"
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let image = name.flatMap({ Self.image($0) }) {
                Image(nsImage: image).renderingMode(.template).resizable().interpolation(.high)
                    .frame(width: size * 0.72, height: size * 0.72)
            } else {
                Image(systemName: fallback).font(.system(size: size * 0.62, weight: .light))
            }
        }
        .foregroundStyle(Brand.textSecondary)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @MainActor private static var cache: [String: NSImage] = [:]
    @MainActor private static func image(_ name: String) -> NSImage? {
        if let hit = cache[name] { return hit }
        guard let url = Bundle.main.url(forResource: "logo-\(name)", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        cache[name] = image
        return image
    }

    /// Logo for an observed folder, by its catalogue id.
    static func forRoot(_ id: String) -> String? {
        switch id {
        case "xcode-build": return "xcode"
        case "npm-cache": return "npm"
        case "codex-state": return "codex"
        case "docker": return "docker"
        default: return nil
        }
    }

    /// Logo for an AI coding tool, by its `AgentTool` id.
    static func forAgent(_ id: String) -> String? {
        switch id {
        case "claude-code", "claude-desktop": return "claude"
        case "codex": return "codex"
        case "cursor": return "cursor"
        default: return nil
        }
    }
}
