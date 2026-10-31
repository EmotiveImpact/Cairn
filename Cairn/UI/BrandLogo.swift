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
        case "docker", "docker-disk": return "docker"
        case "simulators": return "xcode"
        case "ollama-models": return "ollama"
        case "claude-data": return "claude"
        case "cursor-worktrees": return "cursor"
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

    /// Colourless mark for a scan category: the company logo where there is
    /// one, otherwise a thin outline symbol.
    static func forCategory(_ id: String, size: CGFloat = 22) -> BrandLogo {
        let logo: String? = ["xcode": "xcode", "docker": "docker", "npm": "npm"][id]
        let symbol: String
        switch id {
        case "ide-caches": symbol = "chevron.left.forwardslash.chevron.right"
        case "android": symbol = "candybarphone"
        case "dev-projects": symbol = "folder"
        case "runtimes": symbol = "cube"
        case "git-bloat": symbol = "arrow.triangle.branch"
        case "ai-models": symbol = "brain.head.profile"
        case "creative": symbol = "film"
        case "app-caches": symbol = "macwindow"
        case "browser-caches": symbol = "globe"
        case "comm-caches": symbol = "bubble.left.and.bubble.right"
        case "logs": symbol = "doc.text"
        case "installers": symbol = "arrow.down.app"
        case "trash": symbol = "trash"
        case "orphaned": symbol = "folder.badge.questionmark"
        case "large-old": symbol = "doc"
        case "tm-snapshots": symbol = "clock.arrow.circlepath"
        case "messages-attachments": symbol = "message"
        case "simulators": symbol = "iphone"
        default: symbol = "shippingbox"
        }
        return BrandLogo(name: logo, fallback: symbol, size: size)
    }
}
