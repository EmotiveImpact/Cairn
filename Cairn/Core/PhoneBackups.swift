import Foundation

/// One iPhone or iPad backup made by Finder. Only the small summary files are
/// read (device, model, iOS version, date, whether it has a password); the
/// backup's contents are never opened.
struct PhoneBackup: Identifiable, Sendable {
    let id: String
    let url: URL
    var deviceName: String
    var model: String
    var iosVersion: String
    var lastBackup: Date?
    var passwordProtected: Bool
    var bytes: Int64

    /// Not backed up for six months: usually an old device.
    var isOld: Bool { (lastBackup.map { Date().timeIntervalSince($0) } ?? .infinity) > 180 * 86_400 }

    /// "Edem's iPhone · iPhone 12 · backed up 3 March 2025"
    var line: String {
        var parts = [model]
        if let lastBackup { parts.append("backed up " + lastBackup.formatted(.dateTime.day().month(.wide).year())) }
        if passwordProtected { parts.append("password protected") }
        return parts.joined(separator: " · ")
    }

    /// Moved and kept on the drive as an archive, never linked: Apple warns
    /// against moving the live Backup folder. Bring back puts it exactly
    /// where Finder looks, ready to restore a phone.
    var target: RelocationTarget {
        let safeName = deviceName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return RelocationTarget(id: "iphone-backup:" + id, title: "\(deviceName) backup", url: url, mode: .archive,
                                closeFirst: "Finder's backup or restore", processNames: ["AppleMobileBackup", "MobileDeviceUpdater"],
                                whileDisconnected: "Plug the drive in and bring it back to restore a phone from it.",
                                privateFiles: !passwordProtected, driveFolder: "iPhone backups/\(safeName) \(String(id.prefix(8)))")
    }
}

enum PhoneBackups {
    static let root = FileScan.home.appendingPathComponent("Library/Application Support/MobileSync/Backup")

    struct Listing: Sendable {
        var backups: [PhoneBackup] = []
        /// macOS hides this folder from apps without Full Disk Access.
        var needsFullDiskAccess = false
    }

    static func list(root: URL = root, measure: Bool = true) -> Listing {
        var listing = Listing()
        guard FileManager.default.fileExists(atPath: root.path) else { return listing }
        let names: [String]
        do { names = try FileManager.default.contentsOfDirectory(atPath: root.path) }
        catch { listing.needsFullDiskAccess = true; return listing }
        for name in names.sorted() where !name.hasPrefix(".") {
            let folder = root.appendingPathComponent(name)
            guard Relocation.isRealDirectory(folder) else { continue }
            let info = plist(folder.appendingPathComponent("Info.plist"))
            let manifest = plist(folder.appendingPathComponent("Manifest.plist"))
            guard info != nil || manifest != nil else { continue }
            let product = info?["Product Type"] as? String ?? ""
            let backup = PhoneBackup(
                id: name, url: folder,
                deviceName: (info?["Device Name"] as? String) ?? (info?["Display Name"] as? String) ?? "iPhone",
                model: friendlyModel(product),
                iosVersion: info?["Product Version"] as? String ?? "",
                lastBackup: info?["Last Backup Date"] as? Date,
                passwordProtected: manifest?["IsEncrypted"] as? Bool ?? false,
                bytes: measure ? FileScan.measure(folder).allocatedSize : 0)
            listing.backups.append(backup)
        }
        listing.backups.sort { ($0.lastBackup ?? .distantPast) < ($1.lastBackup ?? .distantPast) }
        return listing
    }

    private static func plist(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url), data.count < 8 << 20 else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    enum BinError: LocalizedError {
        case busy, notABackup
        var errorDescription: String? {
            switch self {
            case .busy: "A backup or restore is running. Try again when it finishes."
            case .notABackup: "This is not a Finder backup folder, so Cairn left it alone."
            }
        }
    }

    /// Puts one backup in the Bin, where it can still be put back until the
    /// Bin is emptied. Only a real backup folder directly inside `root` is
    /// accepted; the Backup folder itself never is.
    @discardableResult
    static func moveToBin(_ backup: PhoneBackup, root: URL = root, isBusy: () -> Bool = PhoneBackups.busy) throws -> URL? {
        let folder = backup.url.standardizedFileURL
        guard folder.deletingLastPathComponent().path == root.standardizedFileURL.path,
              folder.lastPathComponent == backup.id, !backup.id.isEmpty, !backup.id.hasPrefix("."),
              Relocation.isRealDirectory(folder),
              Relocation.exists(folder.appendingPathComponent("Info.plist")) || Relocation.exists(folder.appendingPathComponent("Manifest.plist"))
        else { throw BinError.notABackup }
        guard !isBusy() else { throw BinError.busy }
        var landed: NSURL?
        try FileManager.default.trashItem(at: folder, resultingItemURL: &landed)
        return landed as URL?
    }

    /// A backup or restore in progress must not be moved.
    static func busy() -> Bool {
        ["AppleMobileBackup", "MobileDeviceUpdater"].contains { name in
            (try? ToolRunner.runExecutable("/usr/bin/pgrep", ["-x", name], timeout: 3))?.ok == true
        }
    }

    /// Plain names for the model codes in Info.plist. Unknown codes show as
    /// "iPhone" or "iPad" rather than a code.
    static func friendlyModel(_ code: String) -> String {
        let known: [String: String] = [
            "iPhone10,1": "iPhone 8", "iPhone10,4": "iPhone 8", "iPhone10,2": "iPhone 8 Plus", "iPhone10,5": "iPhone 8 Plus",
            "iPhone10,3": "iPhone X", "iPhone10,6": "iPhone X", "iPhone11,2": "iPhone XS", "iPhone11,4": "iPhone XS Max",
            "iPhone11,6": "iPhone XS Max", "iPhone11,8": "iPhone XR", "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro",
            "iPhone12,5": "iPhone 11 Pro Max", "iPhone12,8": "iPhone SE", "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12",
            "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max", "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13",
            "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max", "iPhone14,6": "iPhone SE", "iPhone14,7": "iPhone 14",
            "iPhone14,8": "iPhone 14 Plus", "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max", "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus", "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max", "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus", "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max", "iPhone17,5": "iPhone 16e",
        ]
        if let name = known[code] { return name }
        if code.hasPrefix("iPad") { return "iPad" }
        if code.hasPrefix("iPod") { return "iPod touch" }
        return "iPhone"
    }
}
