import Foundation
import Darwin

/// Real facts about this Mac for the sidebar device card.
enum DeviceInfo {
    // Hardware facts never change while we run — compute once (they were being
    // recomputed via Host.current()/sysctl on every SwiftUI redraw).
    static let name: String = Host.current().localizedName ?? "This Mac"

    /// e.g. "Apple M3 Pro" (Apple silicon) or the Intel brand string.
    static let chip: String = sysctlString("machdep.cpu.brand_string") ?? "Mac"

    /// Physical RAM in whole GB.
    static let ramGB: Int = Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())

    // Volume info is a synchronous filesystem hit. SwiftUI reads these from view
    // bodies (sidebar card, dashboard, status rows) on EVERY redraw — during a
    // live scan that was hundreds of disk calls per second on the main thread,
    // which showed up as UI lag. Cache it and refresh at most once a second.
    // The dashboard also reads these from a detached task; protect the shared
    // cache so that task cannot race SwiftUI's main-thread reads or invalidation.
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

    /// Force the next read to re-measure (call after a clean reclaims space).
    static func invalidateVolumeCache() {
        volumeLock.lock()
        _bootVolumeAt = 0
        volumeLock.unlock()
    }

    static var totalCapacity: Int64 { bootVolume?.totalCapacity ?? 0 }
    static var available: Int64 { bootVolume?.availableImportant ?? 0 }
    static var used: Int64 { max(0, totalCapacity - available) }
    static var usedFraction: Double {
        totalCapacity == 0 ? 0 : Double(used) / Double(totalCapacity)
    }

    /// The SF Symbol that best matches THIS Mac's model — so a Mac mini shows a
    /// Mac mini, a MacBook shows a laptop, etc. Detected from the device name and
    /// (on Intel) the model identifier; falls back to a desktop.
    static let deviceSymbol: String = {
        let n = name.lowercased()
        if n.contains("mac mini") || n.contains("macmini") { return "macmini" }
        if n.contains("mac studio") { return "macstudio" }
        if n.contains("mac pro") { return "macpro.gen3" }
        if n.contains("imac") { return "desktopcomputer" }
        if n.contains("macbook") || n.contains("laptop") { return "laptopcomputer" }
        let m = (sysctlString("hw.model") ?? "").lowercased()
        if m.hasPrefix("macmini") { return "macmini" }
        if m.hasPrefix("macbook") { return "laptopcomputer" }
        if m.hasPrefix("imac") { return "desktopcomputer" }
        if m.hasPrefix("macpro") { return "macpro.gen3" }
        if m.hasPrefix("macstudio") { return "macstudio" }
        return "desktopcomputer"
    }()

    /// "Apple M3 Pro · 32 GB RAM"
    static let specLine: String = "\(chip) · \(ramGB) GB RAM"
    /// "2 TB SSD"
    static var storageLine: String { Fmt.size(totalCapacity) + " SSD" }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
