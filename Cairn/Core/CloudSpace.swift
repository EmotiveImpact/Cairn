import Foundation
import Darwin

/// Cloud folders on this Mac: iCloud Drive, Google Drive, Dropbox, OneDrive
/// and any other File Provider folder. Cairn only ever removes the Mac's copy
/// of a file macOS reports as fully uploaded; the file stays online and
/// downloads again when it is opened. Never used for app data.
struct CloudFolder: Identifiable, Sendable {
    let id: String
    let name: String
    let url: URL
    /// Bytes downloaded on this Mac.
    var localBytes: Int64 = 0
    /// Downloaded, uploaded, not kept downloaded on purpose, not opened lately.
    var candidates: [CloudFile] = []
    var candidateBytes: Int64 { candidates.reduce(0) { $0 + $1.bytes } }
    /// Files marked "Keep Downloaded"; left alone.
    var pinnedBytes: Int64 = 0
    /// Downloaded but not yet uploaded; never touched.
    var waitingBytes: Int64 = 0
}

struct CloudFile: Identifiable, Sendable {
    var id: String { url.path }
    let url: URL
    let bytes: Int64
    let lastOpened: Date?
}

/// An old copy left behind when a cloud app moved to Apple's newer cloud
/// folders, e.g. "~/Dropbox (Old)".
struct OldSyncFolder: Identifiable, Sendable {
    var id: String { url.path }
    let url: URL
    let provider: String
    let bytes: Int64
    /// Files that are not in the live cloud folder with the same size. When
    /// this is zero the old folder is a spare copy; -1 means it could not be compared.
    let onlyHere: Int
}

enum CloudSpace {
    static let iCloudDrive = FileScan.home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
    static let cloudStorage = FileScan.home.appendingPathComponent("Library/CloudStorage")
    static let driveCache = FileScan.home.appendingPathComponent("Library/Application Support/Google/DriveFS")

    static func folders(home: URL = FileScan.home) -> [(String, String, URL)] {
        var result: [(String, String, URL)] = []
        let icloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if Relocation.isRealDirectory(icloud) { result.append(("icloud", "iCloud Drive", icloud)) }
        let storage = home.appendingPathComponent("Library/CloudStorage")
        for name in ((try? FileManager.default.contentsOfDirectory(atPath: storage.path)) ?? []).sorted() where !name.hasPrefix(".") {
            let url = storage.appendingPathComponent(name)
            guard Relocation.isRealDirectory(url) else { continue }
            result.append((name, providerName(name), url))
        }
        return result
    }

    /// "GoogleDrive-me@example.com" → "Google Drive".
    static func providerName(_ folder: String) -> String {
        let lowered = folder.lowercased()
        if lowered.hasPrefix("googledrive") { return "Google Drive" }
        if lowered.hasPrefix("dropbox") { return "Dropbox" }
        if lowered.hasPrefix("onedrive") { return "OneDrive" }
        if lowered.hasPrefix("box") { return "Box" }
        return folder.components(separatedBy: "-").first ?? folder
    }

    private static let keys: Set<URLResourceKey> = [
        .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .totalFileAllocatedSizeKey, .contentAccessDateKey,
        .isUbiquitousItemKey, .ubiquitousItemIsUploadedKey, .ubiquitousItemDownloadingStatusKey,
    ]

    /// Kept downloaded on purpose ("Keep Downloaded" in Finder).
    static func pinned(_ url: URL) -> Bool {
        let size = listxattr(url.path, nil, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return false }
        var buffer = [CChar](repeating: 0, count: size)
        guard listxattr(url.path, &buffer, size, XATTR_NOFOLLOW) == size else { return false }
        let names = buffer.split(separator: 0).map { String(decoding: $0.map { UInt8(bitPattern: $0) }, as: UTF8.self) }
        return names.contains { $0.hasPrefix("com.apple.fileprovider.pinned") }
    }

    /// Measures what a cloud folder keeps on this Mac. Files of at least
    /// `minimum` bytes not opened for `idleDays` are offered.
    static func measure(_ id: String, _ name: String, _ root: URL, minimum: Int64 = 20_000_000, idleDays: Double = 90,
                        cancel: CancelBox = CancelBox()) -> CloudFolder {
        var folder = CloudFolder(id: id, name: name, url: root)
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants]) else { return folder }
        let cutoff = Date().addingTimeInterval(-idleDays * 86_400)
        for case let url as URL in walker {
            if cancel.isCancelled { break }
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            let allocated = Int64(values.totalFileAllocatedSize ?? 0)
            guard allocated > 0 else { continue } // already online only
            folder.localBytes += allocated
            if values.ubiquitousItemIsUploaded != true { folder.waitingBytes += allocated; continue }
            if pinned(url) { folder.pinnedBytes += allocated; continue }
            let opened = values.contentAccessDate
            if allocated >= minimum, (opened ?? .distantPast) < cutoff {
                folder.candidates.append(CloudFile(url: url, bytes: allocated, lastOpened: opened))
            }
        }
        folder.candidates.sort { $0.bytes > $1.bytes }
        return folder
    }

    /// Removes the Mac's copy of each file that is uploaded and not kept
    /// downloaded on purpose, the same way Finder's "Remove Download" does.
    /// Returns the bytes released and any files left alone, with why.
    static func keepOnlineOnly(_ files: [URL]) -> (freed: Int64, skipped: [(URL, String)]) {
        var freed: Int64 = 0
        var skipped: [(URL, String)] = []
        for url in files {
            guard let values = try? url.resourceValues(forKeys: keys), values.isUbiquitousItem == true else {
                skipped.append((url, "Not in a cloud folder")); continue
            }
            guard values.ubiquitousItemIsUploaded == true else { skipped.append((url, "Not uploaded yet")); continue }
            guard !pinned(url) else { skipped.append((url, "Marked Keep Downloaded")); continue }
            let before = Int64(values.totalFileAllocatedSize ?? 0)
            do {
                try FileManager.default.evictUbiquitousItem(at: url)
                freed += before
            } catch {
                skipped.append((url, "The cloud app said no: \(error.localizedDescription)"))
            }
        }
        return (freed, skipped)
    }

    /// Google Drive's own cache, per account. Cleared only with Google Drive quit.
    static func googleDriveCacheBytes() -> Int64 {
        guard let accounts = try? FileManager.default.contentsOfDirectory(atPath: driveCache.path) else { return 0 }
        return accounts.reduce(0) { total, account in
            let cache = driveCache.appendingPathComponent(account).appendingPathComponent("content_cache")
            return total + (Relocation.isRealDirectory(cache) ? FileScan.measure(cache).allocatedSize : 0)
        }
    }

    /// Old full copies left in the home folder by older versions of the
    /// cloud apps, compared with the live cloud folder by name and size.
    static func oldSyncFolders(home: URL = FileScan.home, live: [(String, String, URL)]? = nil, cancel: CancelBox = CancelBox()) -> [OldSyncFolder] {
        let live = live ?? folders(home: home)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? []).sorted()
        var result: [OldSyncFolder] = []
        for name in names {
            let lowered = name.lowercased()
            let provider: String
            if lowered.hasPrefix("dropbox") { provider = "Dropbox" }
            else if lowered.hasPrefix("google drive") { provider = "Google Drive" }
            else if lowered.hasPrefix("onedrive") { provider = "OneDrive" }
            else { continue }
            let url = home.appendingPathComponent(name)
            // The live folder is often linked from the home folder; skip links.
            guard Relocation.isRealDirectory(url) else { continue }
            let current = live.first { $0.1 == provider }?.2
            // -1: no live folder to compare with, so nothing is offered for the Bin.
            let onlyHere = current.map { countOnlyHere(old: url, live: $0, cancel: cancel) } ?? -1
            result.append(OldSyncFolder(url: url, provider: provider, bytes: FileScan.measure(url).allocatedSize, onlyHere: onlyHere))
        }
        return result
    }

    /// Files in `old` with no file of the same relative path and size in
    /// `live`. A cloud-only file in `live` still has its full size, so it counts.
    static func countOnlyHere(old: URL, live: URL, cancel: CancelBox) -> Int {
        guard let walker = FileManager.default.enumerator(at: old, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return -1 }
        var missing = 0
        let base = old.standardizedFileURL.path
        for case let url as URL in walker {
            if cancel.isCancelled { return -1 }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true else { continue }
            if url.lastPathComponent == ".DS_Store" { continue }
            let relative = String(url.standardizedFileURL.path.dropFirst(base.count + 1))
            let twin = live.appendingPathComponent(relative)
            let size = (try? twin.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
            if size != values.fileSize { missing += 1 }
        }
        return missing
    }
}
