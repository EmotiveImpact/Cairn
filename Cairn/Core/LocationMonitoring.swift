import Foundation
import CoreServices

/// FSEvents supplies hints, never byte counts or process attribution. State is
/// bounded by the root catalogue; repeated events replace timestamps in place.
struct DirtyLocationSchedule {
    struct Pending { var lastEvent: Date; var revision: UInt64 }
    let rootIDs: Set<String>
    private(set) var pending: [String: Pending] = [:]
    private var lastAttempt: [String: Date] = [:]
    private var backoff: [String: TimeInterval] = [:]
    private var revision: UInt64 = 0
    var quietWindow: TimeInterval = 60
    var minimumInterval: TimeInterval = 15 * 60
    init(rootIDs: Set<String>) { self.rootIDs = Set(rootIDs.sorted().prefix(32)) }
    mutating func mark(_ ids: Set<String>, at date: Date) {
        for id in ids.intersection(rootIDs) {
            revision &+= 1
            pending[id] = Pending(lastEvent: date, revision: revision)
        }
    }
    mutating func reconcile(at date: Date) { mark(rootIDs, at: date) }
    func ready(at date: Date, suspended: Bool) -> [String] {
        guard !suspended else { return [] }
        return pending.keys.filter { id in
            guard let event = pending[id], date.timeIntervalSince(event.lastEvent) >= quietWindow else { return false }
            return date.timeIntervalSince(lastAttempt[id] ?? .distantPast) >= max(minimumInterval, backoff[id] ?? 0)
        }.sorted()
    }
    mutating func begin(_ id: String, at date: Date) -> UInt64? {
        guard let event = pending[id] else { return nil }
        lastAttempt[id] = date
        return event.revision
    }
    mutating func finish(_ id: String, revision expected: UInt64, complete: Bool) {
        if complete {
            backoff[id] = 0
            // A write during traversal must survive completion of that traversal.
            if pending[id]?.revision == expected { pending.removeValue(forKey: id) }
        } else {
            backoff[id] = min(6 * 3_600, max(minimumInterval, (backoff[id] ?? 0) * 2))
        }
    }
}

/// One serial event stream with a bounded mailbox. Paths are consumed inside
/// the callback and discarded; at most one delivery is queued on the main queue.
final class LocationEventWatcher {
    private final class Context: @unchecked Sendable {
        let roots: [ObservedRoot]
        let deliver: @Sendable (Set<String>, Bool) -> Void
        private let lock = NSLock()
        private var pending = Set<String>()
        private var dropped = false
        private var scheduled = false
        private var active = true
        init(roots: [ObservedRoot], deliver: @escaping @Sendable (Set<String>, Bool) -> Void) {
            self.roots = roots; self.deliver = deliver
        }
        func stop() { lock.withLock { active = false; pending.removeAll() } }
        func consume(count: Int, paths: UnsafeMutableRawPointer, flags: UnsafePointer<FSEventStreamEventFlags>) {
            let values = paths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
            let gapFlags = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagEventIdsWrapped | kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagMount | kFSEventStreamEventFlagUnmount)
            var ids = Set<String>()
            var gap = count > 2_048
            if !gap {
                for index in 0..<count {
                    if flags[index] & gapFlags != 0 { gap = true; break }
                    let path = ObservedRoot.lexicalPath(String(cString: values[index]))
                    for root in roots where path == root.path || path.hasPrefix(root.path + "/") || root.path.hasPrefix(path + "/") { ids.insert(root.id) }
                }
            }
            if gap { ids = Set(roots.map(\.id)) }
            guard !ids.isEmpty else { return }
            let enqueue = lock.withLock { () -> Bool in
                guard active else { return false }
                pending.formUnion(ids); dropped = dropped || gap
                guard !scheduled else { return false }
                scheduled = true; return true
            }
            if enqueue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                    let batch = lock.withLock { () -> (Set<String>, Bool) in
                        defer { pending.removeAll(); dropped = false; scheduled = false }
                        return active ? (pending, dropped) : ([], false)
                    }
                    if !batch.0.isEmpty { deliver(batch.0, batch.1) }
                }
            }
        }
    }
    private let queue = DispatchQueue(label: "Cairn.location-events", qos: .utility)
    private var stream: FSEventStreamRef?
    private let context: Context
    init?(roots: [ObservedRoot], deliver: @escaping @Sendable (Set<String>, Bool) -> Void) {
        context = Context(roots: Array(roots.prefix(32)), deliver: deliver)
        guard !context.roots.isEmpty else { return nil }
        var info = FSEventStreamContext(version: 0,
            info: Unmanaged.passUnretained(context).toOpaque(),
            retain: { pointer in
                guard let pointer else { return nil }
                _ = Unmanaged<Context>.fromOpaque(pointer).retain(); return pointer
            }, release: { pointer in
                if let pointer { Unmanaged<Context>.fromOpaque(pointer).release() }
            }, copyDescription: nil)
        // Watch parents too so a missing/replaced root can be discovered. The
        // callback filters events to the finite root catalogue immediately.
        let paths = Array(Set(context.roots.map { $0.url.deletingLastPathComponent().path })) as CFArray
        stream = FSEventStreamCreate(kCFAllocatorDefault, { _, info, count, paths, flags, _ in
            guard let info else { return }
            Unmanaged<Context>.fromOpaque(info).takeUnretainedValue().consume(count: count, paths: paths, flags: flags)
        }, &info, paths, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 5,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagFileEvents))
        guard let stream else { return nil }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream); FSEventStreamRelease(stream); self.stream = nil; return nil
        }
    }
    func stop() {
        context.stop()
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
        stream = nil
    }
    deinit { stop() }
}
