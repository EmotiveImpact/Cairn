import Foundation

/// Photos, videos and files sent and received in Messages. Cairn only measures
/// them: deleting the files by hand leaves holes in chats, and with Messages in
/// iCloud a delete reaches every device. Apple's own Storage review removes
/// them properly, so Cairn sends people there.
struct MessagesAttachments: Sendable {
    let url: URL
    var bytes: Int64 = 0
    var videos: Int64 = 0
    var photos: Int64 = 0
    var other: Int64 = 0
    var count = 0
    /// Bytes in files not changed for over a year.
    var oldBytes: Int64 = 0
    var partial = false

    /// System Settings › General › Storage, where Messages lists large attachments.
    static let reviewURL = URL(string: "x-apple.systempreferences:com.apple.settings.Storage")!

    static func folder(home: URL = FileScan.home) -> URL {
        home.appendingPathComponent("Library/Messages/Attachments")
    }

    private static let videoTypes: Set<String> = ["mov", "mp4", "m4v", "3gp", "avi", "hevc"]
    private static let photoTypes: Set<String> = ["jpg", "jpeg", "heic", "heif", "png", "gif", "webp", "tiff", "dng"]

    /// Nil when the folder is missing or Cairn cannot read it (no Full Disk Access).
    static func measure(_ url: URL = folder(), now: Date = Date(), maxFiles: Int = 200_000) -> MessagesAttachments? {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey]
        guard Relocation.isRealDirectory(url),
              (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil,
              let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]) else { return nil }
        var result = MessagesAttachments(url: url)
        let yearAgo = now.addingTimeInterval(-365 * 86_400)
        for case let file as URL in walker {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            if result.count >= maxFiles { result.partial = true; break }
            let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            let type = file.pathExtension.lowercased()
            result.count += 1
            result.bytes += size
            if videoTypes.contains(type) { result.videos += size }
            else if photoTypes.contains(type) { result.photos += size }
            else { result.other += size }
            if let modified = values.contentModificationDate, modified < yearAgo { result.oldBytes += size }
        }
        return result
    }

    /// "Videos 3.1 GB · photos 1.2 GB · other 200 MB", biggest first, empty parts left out.
    var breakdown: String {
        [("Videos", videos), ("Photos", photos), ("Other files", other)]
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .enumerated()
            .map { index, part in "\(index == 0 ? part.0 : part.0.lowercased()) \(Fmt.size(part.1))" }
            .joined(separator: " · ")
    }

    var line: String {
        let old = oldBytes > 0 ? " · \(Fmt.size(oldBytes)) over a year old" : ""
        return "\(Fmt.grouped(count)) files sent in chats\(old)"
    }
}
