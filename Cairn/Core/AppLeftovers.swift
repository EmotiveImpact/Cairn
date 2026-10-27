import Foundation
import AppKit

/// When an app goes in the Bin from Finder, its support files, settings and
/// caches stay behind in ~/Library. Cairn notices the app arrive in the Bin,
/// measures what it left and offers it for review. Nothing is removed here.
enum AppLeftovers {
    struct Part: Identifiable, Equatable, Sendable {
        let url: URL
        let bytes: Int64
        /// Application Support and containers, rather than caches and settings.
        let isSupport: Bool
        var id: String { url.path }
    }

    struct Found: Identifiable, Equatable, Sendable {
        let app: String
        let bundleID: String
        let parts: [Part]
        var id: String { bundleID }
        var total: Int64 { parts.reduce(0) { $0 + $1.bytes } }
        var support: [Part] { parts.filter(\.isSupport) }
        var small: [Part] { parts.filter { !$0.isSupport } }
    }

    /// Less than this is not worth interrupting anyone for.
    static let threshold: Int64 = 20_000_000

    private static let lock = NSLock()
    private static var removedByCairn: [String: Date] = [:]

    /// The Apps page records its own leftovers; the Bin watch skips those apps.
    static func noteRemovedByCairn(_ bundleID: String) {
        lock.lock(); defer { lock.unlock() }
        removedByCairn[bundleID.lowercased()] = Date()
    }

    private static func wasRemovedByCairn(_ bundleID: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let at = removedByCairn[bundleID.lowercased()] else { return false }
        return Date().timeIntervalSince(at) < 300
    }

    /// What one app in the Bin left behind, or nil when there is nothing to offer:
    /// an Apple app, one Cairn removed itself, one still installed elsewhere,
    /// or leftovers too small to mention.
    static func find(trashedApp: URL) -> Found? {
        guard let info = NSDictionary(contentsOf: trashedApp.appendingPathComponent("Contents/Info.plist")),
              let bundleID = (info["CFBundleIdentifier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleID.isEmpty, !bundleID.lowercased().hasPrefix("com.apple"),
              !wasRemovedByCairn(bundleID), !stillInstalled(bundleID) else { return nil }
        let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String)
            ?? trashedApp.deletingPathExtension().lastPathComponent
        let parts = AppInventoryStore.associatedFiles(bundleID: bundleID, appName: name).map { file in
            Part(url: file.url, bytes: FileScan.measure(file.url, maxFiles: 40_000, maxDuration: 2).allocatedSize, isSupport: file.isSupport)
        }
        .filter { $0.bytes > 0 }
        .sorted { $0.bytes > $1.bytes }
        let found = Found(app: name, bundleID: bundleID, parts: parts)
        return found.total >= threshold ? found : nil
    }

    /// Another copy outside the Bin keeps using the same data.
    static func stillInstalled(_ bundleID: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        let path = url.standardizedFileURL.path
        let inBin = path.hasPrefix(FileScan.home.appendingPathComponent(".Trash").path + "/") || path.contains("/.Trashes/")
        return !inBin && FileManager.default.fileExists(atPath: path)
    }

    /// Review items for the normal review: never ticked by a scan, never
    /// rebuildable, so the safety walk checks everything inside before the Bin.
    static func items(_ found: Found) -> [ScanItem] {
        found.parts.map { part in
            ScanItem(url: part.url, allocatedSize: part.bytes, categoryID: "orphaned", severity: .review,
                     isRegenerable: false, cleanMethod: .trash,
                     note: "Left behind by \(found.app), which went in the Bin",
                     volumeURL: FileScan.volumeURL(of: part.url), selected: true)
        }
    }
}

/// Watches the Bin for apps arriving. The Bin needs Full Disk Access to read;
/// without it the watch quietly does nothing.
@MainActor final class TrashWatch {
    static let shared = TrashWatch()
    var onLeftovers: ((AppLeftovers.Found) -> Void)?
    private var source: DispatchSourceFileSystemObject?
    private var known = Set<String>()
    private var pending: Task<Void, Never>?
    private let bin = FileScan.home.appendingPathComponent(".Trash")

    func start() {
        guard source == nil, AppSettings.shared.offerAppLeftovers, FullDiskAccess.isGranted(),
              !CommandLine.arguments.contains("--preview-ui") else { return }
        let descriptor = open(bin.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        known = Set(Self.apps(in: bin))
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .link], queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.changed() } }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    func stop() {
        pending?.cancel()
        pending = nil
        source?.cancel()
        source = nil
    }

    /// Finder writes the Bin in steps; wait for it to settle, then look once.
    private func changed() {
        pending?.cancel()
        pending = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
            guard let self else { return }
            let bin = self.bin
            let now = await Task.detached(priority: .utility) { TrashWatch.apps(in: bin) }.value
            guard !Task.isCancelled else { return }
            let arrived = now.filter { !self.known.contains($0) }
            self.known = Set(now)
            for name in arrived {
                let app = bin.appendingPathComponent(name)
                let found = await Task.detached(priority: .utility) { AppLeftovers.find(trashedApp: app) }.value
                if let found { self.onLeftovers?(found) }
            }
        }
    }

    nonisolated static func apps(in folder: URL) -> [String] {
        (FileScan.children(of: folder) ?? []).filter { $0.pathExtension == "app" }.map(\.lastPathComponent)
    }
}
