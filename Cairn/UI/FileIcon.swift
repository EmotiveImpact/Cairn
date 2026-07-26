import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Caches real Finder icons so lists don't re-fetch per redraw.
final class IconCache {
    static let shared = IconCache()
    // NSCache is thread-safe and auto-evicts under memory pressure + count limit,
    // so icons never grow unbounded across a long session.
    private let byPath = NSCache<NSString, NSImage>()
    private let byExt = NSCache<NSString, NSImage>()
    init() { byPath.countLimit = 600; byExt.countLimit = 120 }

    /// The real macOS icon for a file/folder/app at `url` (Finder icon).
    func icon(for url: URL) -> NSImage {
        let key = url.path as NSString
        if let hit = byPath.object(forKey: key) { return hit }
        let img: NSImage = FileManager.default.fileExists(atPath: url.path)
            ? NSWorkspace.shared.icon(forFile: url.path)
            : genericIcon(forExtension: url.pathExtension)
        byPath.setObject(img, forKey: key)
        return img
    }

    /// A generic document icon for a file extension (no file needed).
    func genericIcon(forExtension ext: String) -> NSImage {
        let key = ext.lowercased() as NSString
        if let hit = byExt.object(forKey: key) { return hit }
        let img = NSWorkspace.shared.icon(for: .init(filenameExtension: ext.lowercased()) ?? .data)
        byExt.setObject(img, forKey: key)
        return img
    }
}

/// Shows the real macOS icon for a file/app/folder URL.
struct FileIcon: View {
    let url: URL
    var size: CGFloat = 20

    var body: some View {
        Image(nsImage: IconCache.shared.icon(for: url))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}
