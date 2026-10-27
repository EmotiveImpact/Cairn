import Foundation

/// The startup disk's capacity, for the CLI and the AI tools link.
enum DeviceInfo {
    // Volume info is a synchronous filesystem hit. Cache it and refresh at most
    // once a second, and protect the cache so a detached task cannot race a
    // main-thread read.
    private static let volumeLock = NSLock()
    private static var _bootVolume: Volumes.Info?
    private static var _bootVolumeAt: TimeInterval = 0
    private static let volumeTTL: TimeInterval = 1.0

    static var bootVolume: Volumes.Info? {
        volumeLock.lock()
        defer { volumeLock.unlock() }
        let now = Date().timeIntervalSinceReferenceDate
        if let cached = _bootVolume, now - _bootVolumeAt < volumeTTL { return cached }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let info = Volumes.info(for: FileScan.volumeURL(of: home))
        _bootVolume = info
        _bootVolumeAt = now
        return info
    }

    static var totalCapacity: Int64 { bootVolume?.totalCapacity ?? 0 }
}
