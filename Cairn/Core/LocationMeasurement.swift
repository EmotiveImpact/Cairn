import Foundation
import Darwin

/// Observations never confer permission to clean these locations. In particular,
/// Downloads and Codex state remain review-only/protected in the action catalogue.
struct ObservedRoot: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let path: String
    let icon: String
    let observationOnly: Bool
    var url: URL { URL(fileURLWithPath: path) }

    static func catalogue(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [ObservedRoot] {
        let entries: [(String, String, String, String, Bool)] = [
            ("xcode-build", "Xcode build output", "Library/Developer/Xcode/DerivedData", "hammer", false),
            ("npm-cache", "npm package cache", ".npm/_cacache", "shippingbox", false),
            ("chrome-cache", "Chrome disk cache", "Library/Caches/Google/Chrome", "globe", false),
            ("safari-cache", "Safari disk cache", "Library/Caches/com.apple.Safari", "globe", false),
            ("downloads", "Downloads", "Downloads", "arrow.down.circle", true),
            ("codex-state", "Codex local data", ".codex", "lock.shield", true)
        ]
        return entries.map { ObservedRoot(id: $0.0, title: $0.1, path: home.appendingPathComponent($0.2).path, icon: $0.3, observationOnly: $0.4) }
    }

    static func lexicalPath(_ path: String) -> String {
        var components: [Substring] = []
        for component in path.split(separator: "/") {
            if component == "." { continue }
            if component == ".." { if !components.isEmpty { components.removeLast() }; continue }
            components.append(component)
        }
        return "/" + components.joined(separator: "/")
    }
    static func exclusionScope(_ paths: [String]) -> [String] {
        var output = Set(paths.map(lexicalPath))
        for path in paths {
            if let resolved = realpath(path, nil) {
                output.insert(String(cString: resolved)); free(resolved)
            }
        }
        return output.sorted()
    }

    /// Measure an overlapping tree once; never add a child to its parent's size.
    static func nonOverlapping(_ roots: [ObservedRoot]) -> [ObservedRoot] {
        var ids = Set<String>(), result: [ObservedRoot] = []
        for root in roots.sorted(by: { ($0.path.count, $0.id) < ($1.path.count, $1.id) }) {
            let path = lexicalPath(root.path)
            guard ids.insert(root.id).inserted,
                  !result.contains(where: { path == $0.path || path.hasPrefix($0.path + "/") }) else { continue }
            result.append(root)
        }
        return result
    }
}

struct LocationIdentity: Codable, Equatable, Hashable, Sendable {
    let device: Int64
    let inode: UInt64
    init(device: Int64, inode: UInt64) { self.device = device; self.inode = inode }
    init(_ info: stat) { device = Int64(info.st_dev); inode = UInt64(info.st_ino) }
}

enum LocationCoverage: String, Codable, Sendable {
    case complete, absent, denied, unavailable, partial, limited, cancelled, changing, excluded
    var comparable: Bool { self == .complete || self == .absent }
    var label: String {
        switch self {
        case .complete: return "Measured"
        case .absent: return "Confirmed absent"
        case .denied: return "Access unavailable"
        case .unavailable: return "Location unavailable"
        case .partial: return "Partial measurement"
        case .limited: return "Measurement limit reached"
        case .cancelled: return "Stopped"
        case .changing: return "Changed during measurement"
        case .excluded: return "Excluded from observation"
        }
    }
}

struct LocationReading: Codable, Identifiable, Sendable {
    let id: UUID
    let root: ObservedRoot
    let started: Date
    let ended: Date
    let volumeID: String?
    let identity: LocationIdentity?
    let parentIdentity: LocationIdentity?
    let scope: String
    let coverage: LocationCoverage
    let allocated: Int64?
    let logical: Int64?
    let entries: Int
    let hardLinksSkipped: Int
    let source: String
    let metric: String
    let adapterVersion: Int
    var valid: Bool {
        ended >= started && entries >= 0 && entries <= 100_000 && hardLinksSkipped >= 0 &&
        (allocated == nil || allocated! >= 0) && (logical == nil || logical! >= 0) &&
        (!coverage.comparable || (volumeID?.isEmpty == false && parentIdentity != nil && allocated != nil && logical != nil)) &&
        (coverage != .complete || identity != nil) &&
        (coverage != .absent || (allocated == 0 && logical == 0 && identity == nil)) &&
        metric == "allocated-and-logical-v1" && adapterVersion == 1
    }
}

struct LocationChange: Identifiable {
    let before: LocationReading
    let after: LocationReading
    var id: String { after.root.id }
    var delta: Int64 { after.allocated! - before.allocated! }
    var interval: String {
        "\(before.ended.formatted(date: .abbreviated, time: .shortened)) – \(after.ended.formatted(date: .abbreviated, time: .shortened))"
    }
}

enum LocationComparison {
    static func latest(_ readings: [LocationReading]) -> [LocationReading] {
        Dictionary(grouping: readings, by: { $0.root.id }).values.compactMap {
            $0.max { $0.ended < $1.ended }
        }.sorted { $0.root.title < $1.root.title }
    }
    static func changes(_ readings: [LocationReading]) -> [LocationChange] {
        Dictionary(grouping: readings, by: { $0.root.id }).values.compactMap { group -> LocationChange? in
            let pair = group.sorted { $0.ended < $1.ended }.suffix(2)
            guard pair.count == 2, let before = pair.first, let after = pair.last,
                  before.valid, after.valid, before.coverage.comparable, after.coverage.comparable,
                  before.ended < after.started, before.volumeID == after.volumeID,
                  before.root == after.root, before.scope == after.scope,
                  before.metric == after.metric, before.adapterVersion == after.adapterVersion,
                  before.parentIdentity == after.parentIdentity else { return nil }
            // A proven absence can follow a present root. A replaced present root
            // starts a new baseline; matching the path alone is insufficient.
            guard before.identity == after.identity || after.coverage == .absent || before.coverage == .absent else { return nil }
            return LocationChange(before: before, after: after)
        }.sorted { abs($0.delta) == abs($1.delta) ? $0.id < $1.id : abs($0.delta) > abs($1.delta) }
    }
}

/// The probe walks directory descriptors, never opens file contents, never
/// follows symlinks or mounts, and refuses cloud placeholders. Memory is bounded
/// by the entry limit, recursion by maxDepth, and work by a monotonic deadline.
struct LocationProbe {
    struct Volume: Sendable { let id: String; let internalVolume: Bool }
    var now: () -> Date = Date.init
    var uptime: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    var volume: (URL) -> Volume? = { url in
        guard let values = try? url.resourceValues(forKeys: [.volumeUUIDStringKey, .volumeIsInternalKey]),
              let id = values.volumeUUIDString, !id.isEmpty else { return nil }
        return Volume(id: id, internalVolume: values.volumeIsInternal == true)
    }
    var maxEntries = 100_000
    var maxDepth = 64
    var seconds: TimeInterval = 30

    func measure(_ root: ObservedRoot, exclusions: [String], source: String,
                 cancelled: () -> Bool) -> LocationReading {
        let started = now(), deadline = uptime() + seconds
        let normalizedExclusions = ObservedRoot.exclusionScope(exclusions)
        let scope = "metadata-v1:no-links:no-cloud:no-mounts:" + normalizedExclusions.joined(separator: "\n")
        var state = LocationCoverage.complete
        var allocated: Int64 = 0, logical: Int64 = 0, count = 0, links = 0
        var seen = Set<LocationIdentity>()
        var identity: LocationIdentity?, parentIdentity: LocationIdentity?, volumeID: String?
        func result() -> LocationReading {
            LocationReading(id: UUID(), root: root, started: started, ended: max(started, now()),
                volumeID: volumeID, identity: identity, parentIdentity: parentIdentity, scope: scope,
                coverage: state, allocated: state.comparable || state == .partial || state == .limited || state == .changing ? allocated : nil,
                logical: state.comparable || state == .partial || state == .limited || state == .changing ? logical : nil,
                entries: count, hardLinksSkipped: links, source: source, metric: "allocated-and-logical-v1", adapterVersion: 1)
        }
        func budget() -> Bool {
            if cancelled() { state = .cancelled; return false }
            if count >= min(100_000, maxEntries) || uptime() >= deadline { state = .limited; return false }
            return true
        }
        func excluded(_ path: String) -> Bool {
            normalizedExclusions.contains { path == $0 || path.hasPrefix($0 + "/") }
        }
        guard !excluded(root.path) else { state = .excluded; return result() }
        guard budget() else { return result() }
        // Resolve neither aliases nor symlinks: every ancestor is opened using
        // O_NOFOLLOW, so a replacement cannot redirect this walk outside scope.
        func openDirectory(_ url: URL) -> Int32 {
            var fd = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
            guard fd >= 0 else { return -1 }
            for component in url.pathComponents where component != "/" {
                let next = Darwin.openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                Darwin.close(fd); fd = next
                if fd < 0 { return -1 }
                var value = stat()
                if fstat(fd, &value) != 0 || (value.st_flags & 0x40000000) != 0 {
                    Darwin.close(fd); return -1
                }
            }
            return fd
        }
        let parentURL = root.url.deletingLastPathComponent()
        let parent = openDirectory(parentURL)
        guard parent >= 0 else { state = .unavailable; return result() }
        defer { Darwin.close(parent) }
        var parentStat = stat()
        guard fstat(parent, &parentStat) == 0, let disk = volume(parentURL), disk.internalVolume else {
            state = .unavailable; return result()
        }
        parentIdentity = LocationIdentity(parentStat); volumeID = disk.id
        var rootStat = stat()
        guard fstatat(parent, root.url.lastPathComponent, &rootStat, AT_SYMLINK_NOFOLLOW) == 0 else {
            state = errno == ENOENT ? .absent : errno == EACCES ? .denied : .unavailable
            return result()
        }
        guard (rootStat.st_mode & S_IFMT) == S_IFDIR, rootStat.st_dev == parentStat.st_dev,
              rootStat.st_flags & 0x40000000 == 0 else { state = .unavailable; return result() }
        identity = LocationIdentity(rootStat)
        let rootFD = Darwin.openat(parent, root.url.lastPathComponent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootFD >= 0 else { state = errno == EACCES ? .denied : .unavailable; return result() }
        var openedRoot = stat()
        guard fstat(rootFD, &openedRoot) == 0, LocationIdentity(openedRoot) == identity else {
            Darwin.close(rootFD); state = .changing; return result()
        }
        func add(_ info: stat) {
            let key = LocationIdentity(info)
            guard seen.insert(key).inserted else { links += 1; return }
            let blockBytes = Int64(info.st_blocks).multipliedReportingOverflow(by: 512)
            let a = allocated.addingReportingOverflow(max(0, blockBytes.partialValue))
            let l = logical.addingReportingOverflow(max(0, Int64(info.st_size)))
            guard !blockBytes.overflow, !a.overflow, !l.overflow else { state = .partial; return }
            allocated = a.partialValue; logical = l.partialValue
        }
        func walk(_ fd: Int32, path: String, depth: Int) {
            guard let directory = fdopendir(fd) else { Darwin.close(fd); state = .partial; return }
            defer { closedir(directory) }
            var before = stat()
            guard fstat(fd, &before) == 0 else { state = .partial; return }
            while budget() {
                errno = 0
                guard let entry = readdir(directory) else { if errno != 0 { state = .partial }; break }
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                }
                if name == "." || name == ".." { continue }
                count += 1
                let path = path + "/" + name
                if excluded(path) { state = .partial; continue }
                var info = stat()
                guard fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { state = .partial; continue }
                guard info.st_dev == rootStat.st_dev else { state = .partial; continue }
                let kind = info.st_mode & S_IFMT
                if kind == S_IFLNK { continue } // explicitly excluded by the metric scope
                if info.st_flags & 0x40000000 != 0 || name.hasSuffix(".icloud") { state = .partial; continue }
                if kind == S_IFDIR {
                    guard depth < maxDepth else { state = .limited; break }
                    let child = Darwin.openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                    guard child >= 0 else { state = .partial; continue }
                    var opened = stat()
                    guard fstat(child, &opened) == 0, LocationIdentity(opened) == LocationIdentity(info) else {
                        Darwin.close(child); state = .changing; continue
                    }
                    walk(child, path: path, depth: depth + 1)
                    if state == .limited || state == .cancelled { break }
                } else if kind == S_IFREG { add(info) }
            }
            var after = stat()
            if fstat(fd, &after) != 0 || before.st_mtimespec.tv_sec != after.st_mtimespec.tv_sec ||
                before.st_mtimespec.tv_nsec != after.st_mtimespec.tv_nsec || before.st_ctimespec.tv_sec != after.st_ctimespec.tv_sec ||
                before.st_ctimespec.tv_nsec != after.st_ctimespec.tv_nsec {
                if state == .complete { state = .changing }
            }
        }
        walk(rootFD, path: root.path, depth: 0)
        var finalRoot = stat()
        if fstatat(parent, root.url.lastPathComponent, &finalRoot, AT_SYMLINK_NOFOLLOW) != 0 || LocationIdentity(finalRoot) != identity {
            if state == .complete { state = .changing }
        }
        return result()
    }
}
