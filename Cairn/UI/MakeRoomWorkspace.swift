import SwiftUI
import AppKit

/// The planner ranks only candidates that can actually reach the existing
/// reviewed Trash executor. Filtering precedes the display cap so a long list
/// of blocked findings cannot hide a valid option farther down the scan.
enum MakeRoomCandidates {
    static func select(_ items: [ScanItem], isExcluded: (URL) -> Bool, limit: Int = 60) -> [ScanItem] {
        var seen: [String] = []
        var identities = Set<String>()
        var options: [ScanItem] = []
        let ranked = items.sorted { a, b in
            if a.severity != b.severity { return a.severity < b.severity }
            if a.allocatedSize != b.allocatedSize { return a.allocatedSize > b.allocatedSize }
            return a.resolvedURL.path < b.resolvedURL.path
        }
        for item in ranked {
            if options.count >= limit { break }
            guard SpaceActionCapability.forItem(item).executableAfterReview,
                  item.sourceIdentity != nil, !isExcluded(item.resolvedURL),
                  SafePaths.protectedSessionReason(item.resolvedURL) == nil else { continue }
            guard case .trash = item.cleanMethod else { continue }
            let path = item.resolvedURL.standardizedFileURL.path
            guard !seen.contains(where: { path == $0 || path.hasPrefix($0 + "/") || $0.hasPrefix(path + "/") }) else { continue }
            if let identity = item.sourceIdentity {
                guard identities.insert("\(identity.device):\(identity.inode)").inserted else { continue }
            }
            seen.append(path)
            options.append(item)
        }
        return options
    }
}

/// Where one thing goes to make room: the Bin, an SSD, or online only.
enum MakeRoomWay: String, CaseIterable, Hashable, Sendable {
    case bin = "Bin", ssd = "SSD", cloud = "Cloud"
}

/// One row of the Make room page. `ways` are the choices that make sense for
/// it; anything else is never offered (app data never goes to the cloud).
struct MakeRoomRow: Identifiable {
    enum Kind {
        case scan(ScanItem)
        case move(RelocationTarget)
        case phone(PhoneBackup)
        case online(CloudFolder)
    }
    let id: String
    let symbol: String
    let title: String
    let line: String
    var peek: [String] = []
    var note: String = ""
    var folder: URL?
    let bytes: Int64
    let ways: [MakeRoomWay]
    let suggested: MakeRoomWay?
    let kind: Kind
    /// A scan finding that is the same folder as a move target: Bin uses it.
    var scanItem: ScanItem?
}

/// Builds the rows from what Cairn already knows. Pure, so it can be checked
/// without a Mac full of data.
enum MakeRoomPlan {
    static let minimum: Int64 = 100_000_000

    static func rows(scan: [ScanItem], targets: [RelocationTarget], measured: [String: Int64], offloaded: Set<String>,
                     backups: [PhoneBackup], clouds: [CloudFolder], driveReady: Bool, cloudReady: Bool,
                     home: URL = FileScan.home) -> [MakeRoomRow] {
        var rows: [MakeRoomRow] = []
        var used = Set<String>()
        for target in targets where !offloaded.contains(target.id) && !target.id.hasPrefix("own:") && !target.id.hasPrefix("iphone-backup:") {
            guard let bytes = measured[target.id], bytes >= minimum else { continue }
            let path = target.url.standardizedFileURL.path
            let twin = scan.first { $0.resolvedURL.standardizedFileURL.path == path }
            if twin != nil { used.insert(path) }
            let rebuildable = target.mode == .freshOnDrive
            rows.append(MakeRoomRow(
                id: "move:" + target.id, symbol: symbol(for: target.id), title: target.title,
                line: rebuildable ? "They rebuild on their own next time you build"
                    : target.id == RelocationTarget.docker.id ? "Images and containers · Docker keeps working while the drive is plugged in"
                    : "Keeps working while the drive is plugged in",
                note: target.id == RelocationTarget.docker.id ? "Cairn closes Docker, moves it and points Docker at the drive"
                    : target.closeFirst.isEmpty ? "" : "Cairn asks you to close \(target.closeFirst) first",
                folder: target.url, bytes: bytes, ways: twin != nil ? [.bin, .ssd] : [.ssd],
                suggested: rebuildable && twin != nil ? .bin : (driveReady ? .ssd : nil),
                kind: .move(target), scanItem: twin))
        }
        for backup in backups where backup.bytes >= minimum {
            rows.append(MakeRoomRow(
                id: "phone:" + backup.id, symbol: "iphone", title: "\(backup.deviceName) backup", line: backup.line,
                note: "Moved and kept on the drive. Bring it back any time to restore a phone.", folder: backup.url,
                bytes: backup.bytes, ways: [.bin, .ssd], suggested: backup.isOld && driveReady ? .ssd : nil, kind: .phone(backup)))
        }
        for cloud in clouds where cloud.candidateBytes >= minimum {
            rows.append(MakeRoomRow(
                id: "online:" + cloud.id, symbol: "cloud", title: "\(cloud.name) downloads",
                line: "Copies already safe in \(cloud.name) · not opened in 3 months",
                peek: cloud.candidates.prefix(3).map { $0.url.deletingPathExtension().lastPathComponent },
                folder: cloud.url, bytes: cloud.candidateBytes, ways: [.cloud], suggested: .cloud, kind: .online(cloud)))
        }
        for item in scan where !used.contains(item.resolvedURL.standardizedFileURL.path) && item.allocatedSize >= minimum {
            let own = RelocationTarget.own(item.resolvedURL, home: home) != nil && !item.isRegenerable
            var ways: [MakeRoomWay] = [.bin]
            if own { ways += [.ssd] + (cloudReady ? [.cloud] : []) }
            rows.append(MakeRoomRow(
                id: "scan:" + item.id.uuidString, symbol: own ? "doc" : "arrow.triangle.2.circlepath",
                title: item.url.lastPathComponent,
                line: item.isRegenerable ? "Rebuilt or downloaded again when needed" : "Last changed \(item.latestModified.formatted(.dateTime.month(.wide).year()))",
                folder: item.resolvedURL, bytes: item.allocatedSize, ways: ways,
                suggested: item.isRegenerable ? .bin : nil, kind: .scan(item), scanItem: item))
        }
        return rows.sorted { $0.bytes > $1.bytes }
    }

    static func symbol(for id: String) -> String {
        switch id {
        case "ios-simulators", "android-emulators": return "iphone.gen3"
        case "xcode-derived-data": return "hammer"
        case "xcode-archives": return "archivebox"
        case "android-sdk": return "wrench.and.screwdriver"
        case RelocationTarget.docker.id: return "shippingbox"
        default: return "cpu"
        }
    }

    /// "70.4 GB chosen · 47.9 GB to Studio SSD, 16.3 GB to the Bin, 6.2 GB online only"
    static func summary(_ totals: [MakeRoomWay: Int64], drive: String) -> (strong: String, rest: String)? {
        let total = totals.values.reduce(0, +)
        guard total > 0 else { return nil }
        var parts: [String] = []
        if let ssd = totals[.ssd], ssd > 0 { parts.append("\(Fmt.size(ssd)) to \(drive)") }
        if let bin = totals[.bin], bin > 0 { parts.append("\(Fmt.size(bin)) to the Bin") }
        if let cloud = totals[.cloud], cloud > 0 { parts.append("\(Fmt.size(cloud)) online only") }
        return (Fmt.size(total), "chosen · " + parts.joined(separator: ", "))
    }
}

/// Make room: everything Cairn can free, with one choice each. Bin goes
/// through the reviewed cleaner; SSD and Cloud copy and check first.
struct MakeRoomWorkspace: View {
    let store: ScanStore
    let control: StorageControl
    let receiptRunID: UUID?
    var onBack: () -> Void
    var onScan: () -> Void
    var onReview: (ReviewedSpacePlan) -> Void
    var onOpen: (NavSection) -> Void
    @State private var drives = StorageTransferStore()
    @State private var choices: [String: MakeRoomWay] = [:]
    @State private var touched = Set<String>()
    @State private var backups: [PhoneBackup] = []
    @State private var clouds: [CloudFolder] = []
    @State private var loading = true
    @State private var confirming = false
    @State private var message = ""
    private var moves: RelocationStore { .shared }
    private let preview = CommandLine.arguments.contains("--preview-ui")

    private var drive: StorageDrive? {
        if preview { return StorageDrive(url: URL(fileURLWithPath: "/Volumes/Studio SSD"), name: "Studio SSD", uuid: "SAMPLE", capacity: 1_000_000_000_000,
                                         available: 412_000_000_000, external: true, writable: true, encrypted: true, format: "apfs") }
        return drives.drives.first { $0.acceptsMove() }
    }
    /// The first cloud folder on this Mac, found once when the page loads.
    @State private var cloudTarget: (id: String, name: String, url: URL)?
    private var rows: [MakeRoomRow] {
        if preview { return Self.sampleRows }
        let scan = store.phase == .finished && !store.includeExternalVolumes
            ? MakeRoomCandidates.select(store.buckets.flatMap(\.items), isExcluded: AppSettings.shared.isExcluded) : []
        let measured = moves.states.compactMapValues(\.bytes)
        let offloaded = Set(moves.records.filter { $0.status == .offloaded }.map(\.targetID))
        return MakeRoomPlan.rows(scan: scan, targets: moves.targets, measured: measured, offloaded: offloaded,
                                 backups: backups, clouds: clouds, driveReady: drive != nil, cloudReady: cloudTarget != nil)
    }
    private func choice(_ row: MakeRoomRow) -> MakeRoomWay? {
        touched.contains(row.id) ? choices[row.id] : row.suggested
    }
    private func available(_ way: MakeRoomWay, _ row: MakeRoomRow) -> Bool {
        switch way {
        case .ssd: return drive != nil
        case .cloud: if case .online = row.kind { return true } else { return cloudTarget != nil }
        case .bin: return true
        }
    }
    private var totals: [MakeRoomWay: Int64] {
        rows.reduce(into: [:]) { result, row in
            if let way = choice(row), available(way, row) { result[way, default: 0] += row.bytes }
        }
    }

    var body: some View {
        let rows = rows
        let free = rows.reduce(Int64(0)) { $0 + $1.bytes }
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 0) {
                    Text("Make room · ").nightEyebrow()
                    driveLine
                }.lineLimit(1)
                Spacer(minLength: 12)
                Button { rescan() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                    .buttonStyle(ControlPanelButtonStyle(size: .small))
                    .disabled(preview || store.isScanning)
            }
            .frame(height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(loading && rows.isEmpty ? "Looking for room" : "\(Fmt.size(free)) you can free")
                    .font(.system(size: 40, weight: .light)).tracking(-0.8).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("Choose Bin, SSD or Cloud for each. Nothing leaves this Mac until its copy has been checked, and anything moved can be brought back.")
                    .font(.system(size: 13)).foregroundStyle(Brand.textMuted)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            if rows.isEmpty {
                NightEmpty(title: loading ? "Measuring" : store.hasScanned ? "Nothing big to free right now" : "Scan to see what can go",
                           message: loading ? "Checking drives, iPhone backups and cloud folders." : store.hasScanned
                               ? "Cairn found nothing over 100 MB that it can move or remove." : "Rescan and Cairn lists what you can free here.",
                           busy: loading || store.isScanning)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            rowView(row, first: index == 0)
                        }
                    }
                }
                .scrollIndicators(.automatic)
                .overlay(alignment: .top) { Rectangle().fill(Brand.wash(0.07)).frame(height: 1) }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if moves.busyTarget != nil || !message.isEmpty || !moves.message.isEmpty {
                progressLine
            }
            HStack(alignment: .center, spacing: 10) {
                if let summary = MakeRoomPlan.summary(totals, drive: drive?.name ?? "the SSD") {
                    NightTotal(strong: summary.strong, rest: summary.rest)
                } else {
                    Text("Choose where each one goes").font(.system(size: 13)).foregroundStyle(Brand.textMuted)
                }
                Spacer(minLength: 12)
                Button("Choose none") { chooseNone(rows) }
                    .buttonStyle(ControlPanelButtonStyle())
                    .disabled(totals.isEmpty)
                Button("Review and make room") { confirming = true }
                    .buttonStyle(ControlPanelButtonStyle(primary: true))
                    .disabled(preview || totals.isEmpty || moves.busyTarget != nil || store.isScanning || store.isCleaning)
            }
            .padding(.top, 14)
            .overlay(alignment: .top) { Rectangle().fill(Brand.wash(0.07)).frame(height: 1) }
        }
        .padding(.top, 22).padding(.horizontal, 40).padding(.bottom, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(Brand.textPrimary)
        .task { await load() }
        .sheet(isPresented: $confirming) {
            WorkspaceConfirmation(title: "Make room?", explanation: confirmation(rows),
                                  entries: plannedLines(rows), actionTitle: "Make room") { run(rows) }
        }
    }

    @ViewBuilder private var driveLine: some View {
        if let drive {
            HStack(spacing: 7) {
                Circle().fill(Brand.room).frame(width: 6, height: 6).shadow(color: Brand.room, radius: 4)
                Text("\(drive.name) plugged in · \(Fmt.size(drive.available)) free").nightEyebrow()
            }
        } else {
            Text("No SSD plugged in").nightEyebrow()
        }
    }

    private func rowView(_ row: MakeRoomRow, first: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: row.symbol).font(.system(size: 16, weight: .light))
                .foregroundStyle(Brand.textMuted).frame(width: 22, height: 22).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Brand.textPrimary)
                    .lineLimit(1).truncationMode(.middle)
                Text(row.line).font(.system(size: 12.5)).foregroundStyle(Brand.textMuted).lineLimit(1)
                if !row.peek.isEmpty || !row.note.isEmpty {
                    HStack(spacing: 6) {
                        Text(row.peek.isEmpty ? row.note : row.peek.joined(separator: " · "))
                            .font(.system(size: 12)).foregroundStyle(Self.faint).lineLimit(1)
                        if !row.peek.isEmpty, let folder = row.folder {
                            Button("See all") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Brand.deepBlue)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 8) {
                Text(Fmt.size(row.bytes)).font(.system(size: 14, weight: .medium)).monospacedDigit()
                HStack(spacing: 0) {
                    ForEach(MakeRoomWay.allCases, id: \.self) { way in wayButton(way, row) }
                }
                .padding(.trailing, -8)
            }
            .frame(width: 230, alignment: .trailing)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { if !first { Rectangle().fill(Brand.wash(0.06)).frame(height: 1) } }
    }

    @ViewBuilder private func wayButton(_ way: MakeRoomWay, _ row: MakeRoomRow) -> some View {
        let offered = row.ways.contains(way)
        let enabled = offered && available(way, row)
        let on = enabled && choice(row) == way
        Button {
            touched.insert(row.id)
            choices[row.id] = choice(row) == way ? nil : way
        } label: {
            Text(way.rawValue).font(.system(size: 12))
                .foregroundStyle(on ? Brand.room : Brand.textMuted.opacity(enabled ? 1 : 0.4))
                .frame(width: 64).padding(.vertical, 3)
                .background(Capsule().fill(on ? Brand.room.opacity(0.06) : .clear))
                .overlay(Capsule().strokeBorder(on ? Brand.room.opacity(0.4) : .clear, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(offered ? 1 : 0)
        .disabled(!enabled || preview)
        .help(offered && !enabled ? (way == .ssd ? "Plug in an SSD to move this" : "Set up a cloud folder to use this") : "")
        .accessibilityHidden(!offered)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var progressLine: some View {
        HStack(spacing: 10) {
            if moves.busyTarget != nil {
                ProgressView().controlSize(.small)
                Text("\(Fmt.size(moves.copied)) of \(Fmt.size(moves.total)) copied and checked\(moves.queued.isEmpty ? "" : " · \(moves.queued.count) more waiting")")
                    .font(.system(size: 12)).monospacedDigit()
                Spacer()
                Button("Stop") { moves.cancel() }.buttonStyle(ControlPanelButtonStyle(size: .small))
            } else {
                Text(message.isEmpty ? moves.message : message).font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
        }
    }

    private static let faint = Color(light: 0x8A949E, dark: 0x5F6B77)

    private func chooseNone(_ rows: [MakeRoomRow]) {
        for row in rows { touched.insert(row.id); choices[row.id] = nil }
    }

    private func chosen(_ rows: [MakeRoomRow], _ way: MakeRoomWay) -> [MakeRoomRow] {
        rows.filter { choice($0) == way && available(way, $0) }
    }

    private func confirmation(_ rows: [MakeRoomRow]) -> String {
        var parts = ["Things going to the SSD or the cloud are copied and checked before the Mac's copy is removed, and can be brought back."]
        if !chosen(rows, .bin).isEmpty { parts.append("Things going to the Bin are shown in a review first.") }
        if chosen(rows, .ssd).contains(where: { if case .move(let target) = $0.kind { return target.id == RelocationTarget.docker.id } else { return false } }) {
            parts.append("Cairn will close Docker, move its disk to \(drive?.name ?? "the SSD") and start it again.")
        }
        let privateRows = chosen(rows, .ssd).contains { row in
            switch row.kind { case .phone(let backup): return !backup.passwordProtected; case .scan: return true; default: return false }
        }
        if let warning = drive?.passwordWarning(privateFiles: privateRows) { parts.append(warning) }
        return parts.joined(separator: " ")
    }

    private func plannedLines(_ rows: [MakeRoomRow]) -> [String] {
        MakeRoomWay.allCases.flatMap { way in
            chosen(rows, way).map { row in
                switch way {
                case .ssd: return "\(row.title) → \(drive?.name ?? "SSD") · \(Fmt.size(row.bytes))"
                case .bin: return "\(row.title) → Bin · \(Fmt.size(row.bytes))"
                case .cloud:
                    if case .online = row.kind { return "\(row.title) → online only · \(Fmt.size(row.bytes))" }
                    return "\(row.title) → \(cloudTarget?.name ?? "cloud") · \(Fmt.size(row.bytes))"
                }
            }
        }
    }

    private func load() async {
        guard !preview else { loading = false; return }
        loading = true
        await drives.refresh()
        await moves.refresh()
        let found = await Task.detached(priority: .utility) { () -> ([PhoneBackup], [CloudFolder]) in
            let backups = PhoneBackups.list().backups
            let clouds = CloudSpace.folders().map { CloudSpace.measure($0.0, $0.1, $0.2) }
            return (backups, clouds)
        }.value
        backups = found.0; clouds = found.1
        cloudTarget = found.1.first.map { (id: $0.id, name: $0.name, url: $0.url) }
        loading = false
    }

    private func rescan() {
        guard !preview else { return }
        onScan()
        Task { await load() }
    }

    private func run(_ rows: [MakeRoomRow]) {
        guard !preview else { return }
        message = ""
        if let drive {
            for row in chosen(rows, .ssd) {
                switch row.kind {
                case .move(let target): moves.move(target, to: drive)
                case .phone(let backup): moves.move(backup.target, to: drive)
                case .scan(let item): if let target = RelocationTarget.own(item.resolvedURL) { moves.move(target, to: drive) }
                case .online: break
                }
            }
        }
        let cloudRows = chosen(rows, .cloud)
        let online = cloudRows.flatMap { row -> [URL] in if case .online(let folder) = row.kind { return folder.candidates.map(\.url) } else { return [] } }
        let ownToCloud = cloudRows.compactMap { row -> URL? in if case .scan(let item) = row.kind { return item.resolvedURL } else { return nil } }
        if !online.isEmpty {
            Task {
                let result = await Task.detached(priority: .utility) { CloudSpace.keepOnlineOnly(online) }.value
                message = "\(Fmt.size(result.freed)) is now online only." + (result.skipped.isEmpty ? "" : " \(result.skipped.count) files were left as they were.")
                await load()
            }
        }
        if !ownToCloud.isEmpty, let cloudTarget {
            Task { await CloudMoveStore.shared.move(ownToCloud, to: cloudTarget) }
        }
        let binRows = chosen(rows, .bin)
        for row in binRows {
            if case .phone(let backup) = row.kind {
                do { try PhoneBackups.moveToBin(backup) } catch { message = error.localizedDescription }
            }
        }
        let binItems = binRows.compactMap(\.scanItem)
        if !binItems.isEmpty { prepareReview(binItems) }
        for row in rows { touched.insert(row.id); choices[row.id] = nil }
    }

    private func prepareReview(_ chosen: [ScanItem]) {
        guard let scanStarted = store.scanStartedAt else { message = "Rescan before putting things in the Bin."; return }
        let settings = AppSettings.shared
        let exclusions = settings.excludedPaths, fda = store.fdaGranted
        let developer = settings.includeDeveloperCaches, simulators = settings.includeSimulators
        let binBytes = chosen.reduce(Int64(0)) { $0 + $1.allocatedSize }
        Task {
            await control.refreshCapacity(force: true)
            guard let capacity = control.current else { message = "Available space could not be checked."; return }
            let target = min(capacity.total, max(1, capacity.available + binBytes))
            let plan = await Task.detached(priority: .utility) {
                ReviewedSpacePlan.capture(items: chosen, capacity: capacity, target: target, scanStarted: scanStarted,
                    exclusions: exclusions, fullDiskAccess: fda, developerCaches: developer, simulators: simulators)
            }.value
            guard let plan, store.comparisonScopeStable, store.scanStartedAt == scanStarted else {
                message = "The scan changed since these were found. Rescan and try again."
                return
            }
            onReview(plan)
        }
    }

    /// The approved picture, row for row. Preview only; never acted on.
    private static let sampleRows: [MakeRoomRow] = {
        func row(_ id: String, _ symbol: String, _ title: String, _ line: String, peek: [String] = [], note: String = "",
                 _ gb: Double, _ ways: [MakeRoomWay], _ pick: MakeRoomWay?) -> MakeRoomRow {
            let item = ScanItem(url: URL(fileURLWithPath: "/Sample/" + id), allocatedSize: Int64(gb * 1_000_000_000), categoryID: "sample", severity: .review)
            return MakeRoomRow(id: id, symbol: symbol, title: title, line: line, peek: peek, note: note,
                               folder: URL(fileURLWithPath: "/Sample/" + id), bytes: Int64(gb * 1_000_000_000), ways: ways, suggested: pick, kind: .scan(item))
        }
        return [
            row("phone", "iphone", "iPhone backups", "Edem's iPhone 12 · last backed up March 2024",
                note: "Moved and kept on the drive. Bring it back any time to restore a phone.", 14.6, [.bin, .ssd], .ssd),
            row("docker", "shippingbox", "Docker's disk", "Images and containers · Docker keeps working while the drive is plugged in",
                note: "Cairn closes Docker, moves it and points Docker at the drive", 12.8, [.bin, .ssd], .ssd),
            row("videos", "film", "Old videos in Movies", "105 videos · almost all unopened for over a year",
                peek: ["720p.h264.mp4", "01-Main.mp4", "Madison Morgan audition"], 12.1, [.bin, .ssd, .cloud], .ssd),
            row("simulators", "iphone.gen3", "iPhone simulators", "9 simulators · Xcode finds them while the drive is plugged in",
                peek: ["iPhone 15 Pro", "iPad Air", "iPhone SE"], 9.8, [.bin, .ssd], nil),
            row("zips", "doc.zipper", "Zip files in Downloads", "60 archives · most over a year old",
                peek: ["Cymatics Equinox", "3260 free effects", "Text messaging titles"], 9.1, [.bin, .ssd, .cloud], .bin),
            row("ollama", "cpu", "Ollama models", "3 models · Ollama finds them while the drive is plugged in",
                note: "llama3.1 · qwen2.5-coder · nomic-embed-text", 8.4, [.bin, .ssd], .ssd),
            row("xcode", "hammer", "Xcode build files", "They rebuild on their own next time you build",
                peek: ["12 projects"], 7.2, [.bin, .ssd], .bin),
            row("gdrive", "cloud", "Google Drive downloads", "Copies already safe in Google Drive · not opened in 3 months",
                peek: ["Brand assets", "Client videos", "Old exports"], 6.2, [.cloud], .cloud),
        ]
    }()
}
