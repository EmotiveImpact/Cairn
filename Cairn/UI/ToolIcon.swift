import SwiftUI
import AppKit

/// A soft rounded tinted tile holding an SF symbol — the premium "app-icon-ish"
/// treatment used across headers, rows, and cards.
struct IconTile: View {
    var systemImage: String
    var tint: Color = Brand.blue
    var size: CGFloat = 40
    var glyphScale: CGFloat = 0.46

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(tint.opacity(0.12))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: size * glyphScale, weight: .semibold))
                    .foregroundStyle(tint)
            )
    }
}

/// Resolves the best available icon for a tool/category: a real installed-app
/// icon (Xcode, Docker, VS Code…) → a real file icon → a tasteful tinted SF tile.
struct ToolIcon: View {
    var bundleID: String? = nil
    var bundledAsset: String? = nil
    var fileURL: URL? = nil
    var systemImage: String = "shippingbox.fill"
    var tint: Color = Brand.blue
    var size: CGFloat = 34

    @State private var resolved: NSImage?

    var body: some View {
        Group {
            if let img = resolved {
                Image(nsImage: img).resizable().interpolation(.high)
                    .frame(width: size, height: size)
            } else {
                IconTile(systemImage: systemImage, tint: tint, size: size)
            }
        }
        .task(id: bundleID ?? fileURL?.path ?? systemImage) { resolve() }
    }

    private func resolve() {
        if let name = bundledAsset, let url = Bundle.main.url(forResource: name, withExtension: "svg"), let icon = NSImage(contentsOf: url) {
            resolved = icon; return
        }
        if let b = bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b) {
            resolved = IconCache.shared.icon(for: url); return
        }
        if let f = fileURL, FileManager.default.fileExists(atPath: f.path) {
            resolved = IconCache.shared.icon(for: f); return
        }
        resolved = nil
    }
}

/// Per-category icon spec — real app icon where one exists, else a brand-tinted tile.
extension ToolIcon {
    static func forCategory(_ id: String, size: CGFloat = 34) -> ToolIcon {
        switch id {
        case "xcode":        return ToolIcon(bundleID: "com.apple.dt.Xcode", systemImage: "hammer.fill", tint: Brand.blue, size: size)
        case "docker":       return ToolIcon(bundleID: "com.docker.docker", bundledAsset: "tool-docker", systemImage: "shippingbox.fill", tint: Color(hex: 0x2496ED), size: size)
        case "ide-caches":   return ToolIcon(bundleID: "com.microsoft.VSCode", systemImage: "chevron.left.forwardslash.chevron.right", tint: Color(hex: 0x2496ED), size: size)
        case "android":      return ToolIcon(bundleID: "com.google.android.studio", bundledAsset: "tool-android", systemImage: "candybarphone", tint: Color(hex: 0x3DDC84), size: size)
        case "npm": return ToolIcon(bundledAsset: "tool-npm", systemImage: "shippingbox.fill", tint: Color(hex: 0xCB3837), size: size)
        case "dev-caches":   return ToolIcon(systemImage: "shippingbox.fill", tint: Color(hex: 0xCB3837), size: size)
        case "dev-projects": return ToolIcon(systemImage: "folder.fill", tint: Brand.blue, size: size)
        case "runtimes":     return ToolIcon(systemImage: "cube.fill", tint: Color(hex: 0x3776AB), size: size)
        case "git-bloat":    return ToolIcon(systemImage: "arrow.triangle.branch", tint: Color(hex: 0xF05133), size: size)
        case "ai-models":    return ToolIcon(bundleID: "com.electron.ollama", systemImage: "brain.head.profile", tint: Brand.purple, size: size)
        case "creative":     return ToolIcon(systemImage: "film.fill", tint: Brand.cyan, size: size)
        case "app-caches":   return ToolIcon(systemImage: "macwindow", tint: Brand.blue, size: size)
        case "browser-caches": return ToolIcon(systemImage: "globe", tint: Brand.blue, size: size)
        case "comm-caches":  return ToolIcon(systemImage: "bubble.left.and.bubble.right.fill", tint: Brand.blue, size: size)
        case "logs":         return ToolIcon(systemImage: "doc.text.fill", tint: Brand.textMuted, size: size)
        case "installers":   return ToolIcon(systemImage: "arrow.down.app.fill", tint: Brand.blue, size: size)
        case "trash":        return ToolIcon(systemImage: "trash.fill", tint: Brand.textMuted, size: size)
        case "orphaned":     return ToolIcon(systemImage: "folder.badge.questionmark", tint: Brand.amber, size: size)
        case "large-old":    return ToolIcon(systemImage: "doc.fill", tint: Brand.blue, size: size)
        case "tm-snapshots": return ToolIcon(systemImage: "clock.arrow.circlepath", tint: Brand.blue, size: size)
        case "messages-attachments": return ToolIcon(systemImage: "message.fill", tint: Brand.blue, size: size)
        default:             return ToolIcon(systemImage: "shippingbox.fill", tint: Brand.blue, size: size)
        }
    }
}
