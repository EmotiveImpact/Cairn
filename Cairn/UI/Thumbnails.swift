import SwiftUI
import AppKit
import QuickLookThumbnailing

// MARK: - Thumbnail (QuickLook content preview, FileIcon fallback)

/// Caches QuickLook thumbnails (images/video/PDF) keyed by path+mtime so the list
/// scrolls smoothly. Falls back to the real Finder icon while loading / for
/// non-previewable types via the existing `IconCache`.
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let store = NSCache<NSString, NSImage>()   // auto-evicting, thread-safe
    init() {
        store.countLimit = 400
        // A selected large file can request a much larger preview than a list
        // row. Bound decoded image memory by cost as well as entry count.
        store.totalCostLimit = 48 * 1024 * 1024
    }

    // QLThumbnailGenerator applies NO concurrency limit of its own. With a few
    // hundred visible rows every one fired a request at once and each completion
    // decoded an image and hopped to the main queue — that storm is what hung the
    // main thread on the Duplicates page. Requests are now queued, at most
    // `maxInFlight` at a time, and duplicate requests for the same key coalesce.
    private let lock = NSLock()
    private var inFlight = 0
    private var pendingKeys = Set<String>()
    private var queue: [(key: String, url: URL, side: CGFloat, scale: CGFloat, done: (NSImage) -> Void)] = []
    private let maxInFlight = 3
    private let maxQueued = 60          // don't hoard work for rows scrolled past

    func cached(_ key: String) -> NSImage? { store.object(forKey: key as NSString) }
    func set(_ image: NSImage, for key: String, cost: Int) {
        store.setObject(image, forKey: key as NSString, cost: cost)
    }

    /// Cancel queued (not yet started) work — call when a view goes away.
    func drainQueue() {
        lock.lock(); queue.removeAll(); pendingKeys.removeAll(); lock.unlock()
    }

    private func enqueue(key: String, url: URL, side: CGFloat, scale: CGFloat,
                         done: @escaping (NSImage) -> Void) {
        lock.lock()
        guard !pendingKeys.contains(key) else { lock.unlock(); return }
        pendingKeys.insert(key)
        queue.append((key, url, side, scale, done))
        if queue.count > maxQueued {
            let dropped = queue.removeFirst()
            pendingKeys.remove(dropped.key)
        }
        lock.unlock()
        pump()
    }

    private func pump() {
        lock.lock()
        guard inFlight < maxInFlight, !queue.isEmpty else { lock.unlock(); return }
        let job = queue.removeLast()          // newest first — that's what's on screen
        pendingKeys.remove(job.key)
        inFlight += 1
        lock.unlock()

        let size = CGSize(width: job.side, height: job.side)
        let req = QLThumbnailGenerator.Request(fileAt: job.url, size: size, scale: job.scale,
                                              representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
            guard let self else { return }
            if let rep {
                // Quick Look can return a wide video frame for a square request.
                // Giving NSImage the requested square size distorts that frame
                // even when the view later uses scaledToFit or scaledToFill.
                let pixels = rep.cgImage
                let imageSize = CGSize(width: CGFloat(pixels.width) / job.scale,
                                       height: CGFloat(pixels.height) / job.scale)
                let img = NSImage(cgImage: pixels, size: imageSize)
                self.set(img, for: job.key,
                         cost: rep.cgImage.bytesPerRow * rep.cgImage.height)
                DispatchQueue.main.async { job.done(img) }
            }
            self.lock.lock(); self.inFlight -= 1; self.lock.unlock()
            self.pump()                        // start the next one
        }
    }

    func generate(url: URL, side: CGFloat, scale: CGFloat, completion: @escaping (NSImage) -> Void) {
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)#\(side)#\(Int(mtime))"   // include mtime so a changed file re-renders
        if let hit = cached(key) { completion(hit); return }
        enqueue(key: key, url: url, side: side, scale: scale, done: completion)
    }
}

/// Real content thumbnail for a file, with a graceful Finder-icon fallback.
struct ThumbnailView: View {
    let url: URL
    var size: CGFloat = 40
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                Image(nsImage: IconCache.shared.icon(for: url)).resizable().interpolation(.high)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous).stroke(Brand.border, lineWidth: 1))
        .task(id: url.path) {
            image = nil
            ThumbnailCache.shared.generate(url: url, side: size, scale: 2) { img in
                self.image = img
            }
        }
    }
}
