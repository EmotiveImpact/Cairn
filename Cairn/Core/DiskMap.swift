import Foundation
import Darwin

/// One slice of the disk map. Areas nest: "System Data" holds swap, your
/// Library's caches and so on. Sizes come from APFS volume counters where
/// macOS keeps them, and from a bounded walk everywhere else.
struct DiskArea: Identifiable, Sendable, Equatable {
    enum Kind: String, Sendable { case macOS, systemData, apps, files, developer, other, free }

    let id: String
    let title: String
    let kind: Kind
    var bytes: Int64
    /// The walk stopped at a limit, so the size is a lower bound.
    var partial = false
    var url: URL?
    var children: [DiskArea] = []
    /// One plain line on what lives here.
    var note = ""
}

/// The whole internal disk as one map: macOS, System Data, apps, your files
/// and free space. Read-only. It never opens files, never hydrates iCloud
/// placeholders, and every walk has a time and file limit.
enum DiskMap {
    struct Reading: Sendable, Equatable {
        let total: Int64
        let free: Int64
        let areas: [DiskArea]
        let date: Date
        var used: Int64 { max(0, total - free) }
    }

    /// Used bytes of one APFS volume, from its own counters (instant, exact).
    static func volumeUsed(_ path: String) -> Int64? {
        var info = statfs()
        guard statfs(path, &info) == 0 else { return nil }
        return Int64(info.f_blocks - info.f_bfree) * Int64(info.f_bsize)
    }

    /// Total and free space as Finder reports them, purgeable space counted as free.
    static func capacity(_ path: String = "/System/Volumes/Data") -> (total: Int64, free: Int64)? {
        let url = URL(fileURLWithPath: FileManager.default.fileExists(atPath: path) ? path : "/")
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = values.volumeTotalCapacity else { return nil }
        return (Int64(total), values.volumeAvailableCapacityForImportantUsage ?? 0)
    }

    /// Builds the map. `progress` gets a short line as each area is measured.
    static func read(home: URL = FileScan.home, deadline: TimeInterval = 120,
                     progress: @Sendable (String) -> Void = { _ in }) -> Reading? {
        guard let space = capacity() else { return nil }
        let total = space.total, free = space.free
        let end = ProcessInfo.processInfo.systemUptime + deadline
        func measure(_ url: URL, _ seconds: TimeInterval = 4) -> (Int64, Bool) {
            guard FileManager.default.fileExists(atPath: url.path) else { return (0, false) }
            let left = end - ProcessInfo.processInfo.systemUptime
            guard left > 0.2 else { return (0, true) }
            let stats = FileScan.measure(url, maxDuration: min(seconds, left))
            return (stats.allocatedSize, stats.truncated || stats.permissionDenied)
        }
        /// A folder measured child by child, so one big folder does not use up
        /// the whole budget of its parent.
        func split(_ url: URL, kind: DiskArea.Kind, title: String, id: String, note: String = "", skip: Set<String> = []) -> DiskArea {
            progress(title)
            var children: [DiskArea] = []
            for child in (FileScan.children(of: url) ?? []).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where !skip.contains(child.lastPathComponent) {
                let (bytes, partial) = measure(child)
                guard bytes > 0 else { continue }
                children.append(DiskArea(id: id + "/" + child.lastPathComponent, title: displayName(child), kind: kind,
                                         bytes: bytes, partial: partial, url: child))
            }
            children.sort { $0.bytes > $1.bytes }
            return DiskArea(id: id, title: title, kind: kind, bytes: children.reduce(0) { $0 + $1.bytes },
                            partial: children.contains(where: \.partial), url: url, children: fold(children, id: id, kind: kind), note: note)
        }
        func area(_ rel: String, _ title: String, kind: DiskArea.Kind, note: String) -> DiskArea? {
            let url = home.appendingPathComponent(rel)
            progress(title)
            let (bytes, partial) = measure(url, 8)
            guard bytes > 0 else { return nil }
            return DiskArea(id: "home/" + rel, title: title, kind: kind, bytes: bytes, partial: partial, url: url, note: note)
        }

        // macOS itself lives on its own sealed volumes, which APFS counts exactly.
        let system = volumeUsed("/") ?? 0
        let preboot = (volumeUsed("/System/Volumes/Preboot") ?? 0) + (volumeUsed("/System/Volumes/Update") ?? 0)
        let vm = volumeUsed("/System/Volumes/VM") ?? 0
        let dataUsed = volumeUsed("/System/Volumes/Data") ?? max(0, total - free - system - preboot - vm)
        let macOS = DiskArea(id: "macos", title: "macOS", kind: .macOS, bytes: system + preboot, children: [
            DiskArea(id: "macos/system", title: "macOS system", kind: .macOS, bytes: system, note: "The sealed system volume. Nothing here can be removed."),
            DiskArea(id: "macos/preboot", title: "Startup and updates", kind: .macOS, bytes: preboot, note: "Files macOS needs to start up and install updates."),
        ].filter { $0.bytes > 0 }, note: "macOS and the files it needs to start. Read-only.")

        // Apps.
        var appChildren = split(URL(fileURLWithPath: "/Applications"), kind: .apps, title: "Applications", id: "apps").children
        if let mine = area("Applications", "Your Applications folder", kind: .apps, note: "Apps installed just for you.") { appChildren.append(mine) }
        let apps = DiskArea(id: "apps", title: "Apps", kind: .apps, bytes: appChildren.reduce(0) { $0 + $1.bytes },
                            partial: appChildren.contains(where: \.partial), url: URL(fileURLWithPath: "/Applications"),
                            children: appChildren.sorted { $0.bytes > $1.bytes }, note: "Everything in Applications.")

        // Your files: the home folder outside Library, with hidden tool folders together.
        var files: [DiskArea] = []
        var hidden: [DiskArea] = []
        var developer: [DiskArea] = []
        for child in (FileScan.children(of: home) ?? []).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = child.lastPathComponent
            guard name != "Library", name != "Applications", name != ".Trash" else { continue }
            progress(name)
            let (bytes, partial) = measure(child, 8)
            guard bytes > 0 else { continue }
            let item = DiskArea(id: "home/" + name, title: displayName(child), kind: name.hasPrefix(".") ? .developer : .files,
                                bytes: bytes, partial: partial, url: child)
            if name.hasPrefix(".") { hidden.append(item) }
            else if ["Developer", "Projects", "Code", "code", "dev", "src", "repos", "git", "GitHub", "workspace"].contains(name) { developer.append(item) }
            else { files.append(item) }
        }
        if let trash = area(".Trash", "Trash", kind: .files, note: "Empty the Trash to get this back.") { files.append(trash) }
        if let icloud = area("Library/Mobile Documents", "iCloud Drive (on this Mac)", kind: .files,
                             note: "Copies of iCloud Drive files kept on this Mac. Optimise Mac Storage can release them.") { files.append(icloud) }
        files.sort { $0.bytes > $1.bytes }
        if !hidden.isEmpty {
            hidden.sort { $0.bytes > $1.bytes }
            developer.append(DiskArea(id: "home/hidden", title: "Hidden tool folders", kind: .developer, bytes: hidden.reduce(0) { $0 + $1.bytes },
                                      partial: hidden.contains(where: \.partial), url: home, children: fold(hidden, id: "home/hidden", kind: .developer),
                                      note: "Folders such as .npm, .cache and .docker that coding tools keep in your home folder."))
        }
        developer.sort { $0.bytes > $1.bytes }

        // System Data: what macOS lumps together. Split into the parts that matter.
        var systemData: [DiskArea] = []
        if vm > 0 { systemData.append(DiskArea(id: "sys/vm", title: "Swap and sleep image", kind: .systemData, bytes: vm,
                                                note: "Memory macOS has moved to disk. It shrinks after a restart.")) }
        let libraryParts: [(String, String, String)] = [
            ("Library/Caches", "App caches", "Rebuilt by apps when needed. Cairn's clean covers the safe ones."),
            ("Library/Application Support", "App support data", "Settings, databases and downloads apps keep for themselves."),
            ("Library/Containers", "App containers", "Data for sandboxed apps, such as Mail attachments and app caches."),
            ("Library/Group Containers", "Shared app data", "Data shared between apps from one developer."),
            ("Library/Developer", "Xcode and simulators", "Simulators, device support and build output. Much of it rebuilds."),
            ("Library/Messages", "Messages", "Message history and attachments."),
            ("Library/Mail", "Mail", "Downloaded mail and attachments."),
            ("Library/Logs", "Logs", "Diagnostic logs."),
        ]
        var libraryMeasured: Int64 = 0
        for (rel, title, note) in libraryParts {
            guard let part = area(rel, title, kind: .systemData, note: note) else { continue }
            libraryMeasured += part.bytes
            systemData.append(part)
        }
        progress("Your Library")
        let (libraryTotal, libraryPartial) = measure(home.appendingPathComponent("Library"), 10)
        let icloudBytes = files.first { $0.id == "home/Library/Mobile Documents" }?.bytes ?? 0
        let libraryRest = libraryTotal - libraryMeasured - icloudBytes
        if libraryRest > 0 && !libraryPartial {
            systemData.append(DiskArea(id: "sys/library-other", title: "Rest of your Library", kind: .systemData, bytes: libraryRest,
                                       url: home.appendingPathComponent("Library"), note: "Preferences, fonts, keychains and smaller app folders."))
        }
        progress("Shared Library")
        let (shared, sharedPartial) = measure(URL(fileURLWithPath: "/Library"), 10)
        if shared > 0 { systemData.append(DiskArea(id: "sys/library", title: "Shared Library", kind: .systemData, bytes: shared, partial: sharedPartial,
                                                   url: URL(fileURLWithPath: "/Library"), note: "Data for all users: drivers, fonts, audio plug-ins, printer software.")) }
        progress("System folders")
        let (privateVar, privatePartial) = measure(URL(fileURLWithPath: "/private/var"), 8)
        if privateVar > 0 { systemData.append(DiskArea(id: "sys/var", title: "System caches and logs", kind: .systemData, bytes: privateVar, partial: privatePartial,
                                                       url: URL(fileURLWithPath: "/private/var"), note: "macOS's own caches, logs and temporary files.")) }
        let (users, usersPartial) = measure(URL(fileURLWithPath: "/Users/Shared"), 6)
        if users > 0 { files.append(DiskArea(id: "users/shared", title: "Shared folder", kind: .files, bytes: users, partial: usersPartial,
                                             url: URL(fileURLWithPath: "/Users/Shared"))) }

        // What the walk could not see: local Time Machine snapshots, other
        // users and files macOS keeps from apps. Counted, never guessed at.
        let seen = apps.bytes + files.reduce(0) { $0 + $1.bytes } + developer.reduce(0) { $0 + $1.bytes }
            + systemData.filter { $0.id != "sys/vm" }.reduce(0) { $0 + $1.bytes }
        let unseen = dataUsed - seen
        if unseen > 512 * 1_024 * 1_024 {
            systemData.append(DiskArea(id: "sys/unseen", title: "Not measured", kind: .systemData, bytes: unseen,
                                       note: "Local Time Machine snapshots, other users' files, and folders Cairn cannot read or ran out of time measuring."))
        }
        systemData.sort { $0.bytes > $1.bytes }

        var areas = [macOS,
                     DiskArea(id: "sys", title: "System Data", kind: .systemData, bytes: systemData.reduce(0) { $0 + $1.bytes },
                              partial: systemData.contains(where: \.partial), children: systemData,
                              note: "What Finder calls System Data, broken into its parts."),
                     apps]
        if !developer.isEmpty {
            areas.append(DiskArea(id: "dev", title: "Coding", kind: .developer, bytes: developer.reduce(0) { $0 + $1.bytes },
                                  partial: developer.contains(where: \.partial), children: developer,
                                  note: "Code folders and the hidden folders coding tools keep."))
        }
        areas.append(DiskArea(id: "files", title: "Your files", kind: .files, bytes: files.reduce(0) { $0 + $1.bytes },
                              partial: files.contains(where: \.partial), url: home, children: fold(files, id: "files", kind: .files),
                              note: "Documents, Downloads, Pictures and the rest of your home folder."))
        areas = areas.filter { $0.bytes > 0 }
        areas.append(DiskArea(id: "free", title: "Free", kind: .free, bytes: free, note: "Available, counting space macOS can release on its own."))
        return Reading(total: total, free: free, areas: areas, date: Date())
    }

    /// Keeps the largest children and puts the small ones together, so the
    /// map stays readable.
    static func fold(_ children: [DiskArea], id: String, kind: DiskArea.Kind, keep: Int = 12) -> [DiskArea] {
        let sorted = children.sorted { $0.bytes > $1.bytes }
        guard sorted.count > keep + 1 else { return sorted }
        let rest = sorted.dropFirst(keep)
        return Array(sorted.prefix(keep)) + [DiskArea(id: id + "/+", title: "\(rest.count) smaller items", kind: kind,
                                                      bytes: rest.reduce(0) { $0 + $1.bytes }, partial: rest.contains(where: \.partial))]
    }

    private static func displayName(_ url: URL) -> String {
        let name = url.lastPathComponent
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
