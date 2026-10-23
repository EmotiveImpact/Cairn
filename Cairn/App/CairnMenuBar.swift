import AppKit
import SwiftUI
import Observation

/// Routes menu actions to the existing window. The menu never owns a scanner.
@MainActor @Observable final class MenuBarRoute {
    enum Action: Equatable { case overview, changes, makeRoom, projects, scan, stop, results, activity, storage(String?), preferences(String) }
    struct Request: Equatable { let id = UUID(); let action: Action }
    static let shared = MenuBarRoute()
    var pending: Request?
    @ObservationIgnored var openWindow: (() -> Void)?
    func send(_ action: Action) {
        pending = Request(action: action)
        openWindow?()
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// A small value snapshot, read only when the menu opens or an action fires.
struct MenuScanStatus {
    var scanning = false
    var operationBusy = false
    var otherScanBusy = false
    var categoryCount = 0
    var scanDate: Date?
    var partial = false
    var operationText: String?
    /// Safe, rebuildable and actionable bytes in the latest results.
    var readyBytes: Int64 = 0
    /// The latest project build-output findings, grouped off the main thread.
    var projectItems: [ScanItem] = []
    var canStart: Bool { !scanning && !operationBusy && !otherScanBusy }
}

/// What the menu offers to free, built from saved results only. A nudge
/// opens a review page; it never selects or removes anything by itself.
enum MenuGuardian {
    static let idleDays = 30

    static func readyTitle(_ bytes: Int64) -> String? {
        bytes >= 100_000_000 ? "Review \(Fmt.size(bytes)) ready to free" : nil
    }

    static func idleProjectsTitle(_ projects: [ProjectSummary], now: Date = Date()) -> String? {
        let idle = projects.filter { ($0.idleDays(now: now) ?? 0) >= idleDays && $0.rebuildableBytes > 0 }
        guard !idle.isEmpty else { return nil }
        let bytes = idle.reduce(Int64(0)) { $0 + $1.rebuildableBytes }
        return "\(idle.count) idle project\(idle.count == 1 ? "" : "s") · \(Fmt.size(bytes)) rebuildable"
    }

    static func growthTitle(_ suggestion: GrowthSuggestion?) -> String? {
        guard let suggestion else { return nil }
        return "\(suggestion.change.after.root.title) grew \(Fmt.size(suggestion.change.delta))"
    }

    /// One quiet line for things moved to a drive that is not plugged in,
    /// e.g. "Studio SSD holds Ollama models and 2 more".
    static func awayTitle(_ away: [(title: String, drive: String)]) -> String? {
        guard let first = away.first else { return nil }
        let drives = Set(away.map(\.drive))
        let holder = drives.count == 1 ? first.drive : "Unplugged drives"
        let more = away.count > 1 ? " and \(away.count - 1) more" : ""
        return "\(holder) \(drives.count == 1 ? "holds" : "hold") \(first.title)\(more)"
    }
}

enum MenuStorageSummary {
    static func change(current: Int64?, volumeID: String?, readings: [CapacityReading], now: Date = Date()) -> String {
        guard let current, let volumeID, !volumeID.isEmpty,
              let previous = readings.filter({ $0.volumeID == volumeID && $0.date < Calendar.current.startOfDay(for: now) })
                .max(by: { $0.date < $1.date }) else { return "Volume-aware history is still building" }
        let delta = current - previous.available
        let from = previous.date.formatted(date: .abbreviated, time: .omitted)
        if abs(delta) < 1_000_000 { return "Available space is steady since \(from)" }
        return "\(Fmt.size(abs(delta))) \(delta < 0 ? "less" : "more") available since \(from)"
    }

    static func change(current: Int64?, samples: [StorageHistory.Sample], now: Date = Date()) -> String {
        guard let current, let previous = samples.filter({ $0.date < Calendar.current.startOfDay(for: now) }).max(by: { $0.date < $1.date }) else {
            return "Daily history is still building"
        }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: previous.date), to: Calendar.current.startOfDay(for: now)).day ?? 0
        guard days > 0 else { return "Daily history is still building" }
        let delta = current - previous.freeBytes
        let period = days == 1 ? "since yesterday" : "since \(previous.date.formatted(.dateTime.day().month(.abbreviated)))"
        if abs(delta) < 1_000_000 { return "Available space is steady \(period)" }
        return "\(Fmt.size(abs(delta))) \(delta < 0 ? "less" : "more") \(period)"
    }
}

enum MenuAvailableSpace {
    static func title(_ bytes: Int64?, checked: Bool) -> String {
        guard let bytes, bytes >= 0 else { return checked ? "—" : "…" }
        return Fmt.size(bytes)
    }
}

/// AppKit supplies real menu tracking, keyboard navigation, submenus and material.
/// No scene binding, scan stores or synchronous filesystem work on open.
@MainActor final class CairnMenuBar: NSObject, NSMenuDelegate {
    static let shared = CairnMenuBar()
    var scanStatus: () -> MenuScanStatus = { MenuScanStatus() }
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private var refreshTask: Task<Void, Never>?
    private var badgeRefreshLoop: Task<Void, Never>?
    private var visibilityGeneration: UInt64 = 0
    private var available: Int64?
    private var change = "Reading storage…"
    private var readAt: Date?
    private var drives: [Drive] = []
    private var drivesRead = false
    private var capacityRow: NSMenuItem?
    private var changeRow: NSMenuItem?
    private var reserveRow: NSMenuItem?
    private var pauseRow: NSMenuItem?
    private var drivesRow: NSMenuItem?
    private var projectsRow: NSMenuItem?
    private var idleProjectsTitle: String?
    private var awayRow: NSMenuItem?
    private var awayTitle: String?
    private var preview: Bool { CommandLine.arguments.contains("--preview-ui") }

    private struct Drive: Sendable {
        var id: String
        var name: String
        var available: Int64?
        var readOnly: Bool
    }
    private struct Reading: Sendable {
        var available: Int64?
        var change: String
        var drives: [Drive]
        var idleProjects: String?
        var away: String?
    }

    func setVisible(_ visible: Bool) {
        let enabled = preview ? CommandLine.arguments.contains("--preview-menu") : visible
        guard enabled != (statusItem != nil) else { return }
        visibilityGeneration &+= 1
        if !enabled {
            badgeRefreshLoop?.cancel()
            badgeRefreshLoop = nil
            refreshTask?.cancel()
            refreshTask = nil
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        if !preview { available = nil; readAt = nil }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let renderer = ImageRenderer(content: CairnLogo(size: 22, monochrome: true))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "mountain.2.fill", accessibilityDescription: "Cairn")
        image?.isTemplate = true
        image?.size = NSSize(width: 20, height: 20)
        item.button?.image = image
        item.button?.imagePosition = .imageLeading
        item.button?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        menu.delegate = self
        menu.autoenablesItems = false
        menu.minimumWidth = 290
        item.menu = menu
        statusItem = item
        if preview {
            available = PreviewStorageScenario.availableBytes
            change = "3.5 GB more available since yesterday"
            drives = CommandLine.arguments.contains("--preview-empty-storage") ? [] : [.init(id: "SAMPLE-DRIVE-IDENTITY", name: "Studio SSD", available: 186_000_000_000, readOnly: false)]
            drivesRead = true
            readAt = Date()
        }
        rebuild()
        if !preview { startBadgeRefreshLoop() }
    }

    /// The visible number is a fresh internal-volume capacity reading, never a
    /// scan estimate. A minute-level metadata check keeps it useful even when
    /// reserve monitoring is off and the menu stays closed.
    private func startBadgeRefreshLoop() {
        badgeRefreshLoop?.cancel()
        badgeRefreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                let reading = await Task.detached(priority: .utility) { CapacityProbe.read() }.value
                guard !Task.isCancelled, let self, self.statusItem != nil else { return }
                self.available = reading?.available
                self.readAt = Date()
                self.updateStorageRows()
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        rebuild()
        refresh()
        #if DEBUG
        if preview, let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--capture-menu=") }) {
            let folder = URL(fileURLWithPath: String(argument.dropFirst("--capture-menu=".count)))
            let timer = Timer(timeInterval: 0.3, repeats: false) { _ in
                MainActor.assumeIsolated {
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    for window in NSApp.windows where window.level.rawValue >= NSWindow.Level.popUpMenu.rawValue && window.frame.width > 150 {
                        guard let view = window.contentView?.superview ?? window.contentView,
                              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        if let data = bitmap.representation(using: .png, properties: [:]) {
                            try? data.write(to: folder.appendingPathComponent("menu-\(window.windowNumber).png"))
                        }
                    }
                }
            }
            RunLoop.main.add(timer, forMode: .eventTracking)
        }
        #endif
    }

    /// Sample-only inspection of the actual NSMenu, inside the preview window.
    /// This also works when macOS hides status items behind a display notch.
    func presentPreviewMenu() {
        guard preview, let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }), let view = window.contentView else { return }
        let top = view.isFlipped ? CGFloat(50) : view.bounds.height - 50
        menu.popUp(positioning: nil, at: NSPoint(x: max(0, view.bounds.width - 320), y: top), in: view)
    }

    private func refresh() {
        guard !preview, refreshTask == nil else { return }
        let generation = visibilityGeneration
        let history = StorageControl.shared.latestCapacity
        let projectItems = scanStatus().projectItems
        RelocationStore.shared.load()
        let moves = RelocationStore.shared.records
        // Only volume metadata and Cairn's small saved history; no directory walks
        // or diskutil processes. One in-flight task even after repeated menu opens.
        refreshTask = Task {
            let reading = await Task.detached(priority: .utility) {
                let internalCapacity = CapacityProbe.read()
                let free = internalCapacity?.available
                let keys: Set<URLResourceKey> = [.volumeUUIDStringKey, .volumeNameKey, .volumeIsLocalKey, .volumeIsInternalKey, .volumeIsReadOnlyKey, .volumeAvailableCapacityForImportantUsageKey]
                let locality: Set<URLResourceKey> = [.volumeIsLocalKey, .volumeIsInternalKey]
                let mounts = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(locality), options: [.skipHiddenVolumes]) ?? []
                let drives = mounts.compactMap { url -> Drive? in
                    guard let location = try? url.resourceValues(forKeys: locality), location.volumeIsLocal == true, location.volumeIsInternal == false,
                          let values = try? url.resourceValues(forKeys: keys) else { return nil }
                    return Drive(id: values.volumeUUIDString ?? url.path, name: values.volumeName ?? url.lastPathComponent,
                                 available: values.volumeAvailableCapacityForImportantUsage, readOnly: values.volumeIsReadOnly != false)
                }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                let idle = projectItems.isEmpty ? nil : MenuGuardian.idleProjectsTitle(ProjectIndex.build(from: projectItems))
                let away = MenuGuardian.awayTitle(RelocationStore.away(moves))
                return Reading(available: free, change: MenuStorageSummary.change(current: free, volumeID: internalCapacity?.volumeID, readings: history), drives: drives, idleProjects: idle, away: away)
            }.value
            guard !Task.isCancelled, generation == visibilityGeneration, statusItem != nil else { return }
            available = reading.available
            change = reading.change
            drives = reading.drives
            idleProjectsTitle = reading.idleProjects
            awayTitle = reading.away
            drivesRead = true
            readAt = Date()
            updateStorageRows()
            refreshTask = nil
        }
    }

    private func rebuild() {
        menu.removeAllItems()
        heading(preview ? "STORAGE · SAMPLE DATA" : "STORAGE")
        capacityRow = info("Reading storage…")
        changeRow = info(change)
        reserveRow = AppSettings.shared.reserveEnabled ? info("Reading your chosen reserve…") : nil
        let status = scanStatus()
        let ready = preview ? MenuGuardian.readyTitle(8_500_000_000) : MenuGuardian.readyTitle(status.readyBytes)
        let growth = preview ? nil : MenuGuardian.growthTitle(StorageControl.shared.growthSuggestions.first)
        if ready != nil || growth != nil || !status.projectItems.isEmpty || preview {
            menu.addItem(.separator())
            heading("READY TO FREE")
            if let ready { action(ready, symbol: "sparkles", route: .results, enabled: !status.operationBusy) }
            projectsRow = NSMenuItem(title: "", action: #selector(performAction(_:)), keyEquivalent: "")
            projectsRow?.target = self
            projectsRow?.representedObject = RouteBox(.projects)
            projectsRow?.image = symbol("folder.badge.gearshape")
            if let projectsRow { menu.addItem(projectsRow) }
            if let growth { action(growth, symbol: "chart.line.uptrend.xyaxis", route: .changes) }
        } else {
            projectsRow = nil
        }
        menu.addItem(.separator())
        if let text = status.operationText { info(text) }
        action(status.scanning ? "Stop scan" : "Scan Mac", symbol: status.scanning ? "stop.circle" : "magnifyingglass", key: "r", route: status.scanning ? .stop : .scan,
               enabled: !preview && (status.scanning || status.canStart))
        let review = status.categoryCount > 0 ? "Review latest results (\(status.categoryCount))" : "Review latest results"
        action(review, symbol: "checklist", route: .results, enabled: status.scanDate != nil || status.scanning || preview)
        if let date = status.scanDate {
            info("\(status.partial ? "Partial scan" : "Last scan"): \(date.formatted(.dateTime.day().month(.abbreviated).hour().minute()))")
        } else if !preview { info("No saved scan yet") }
        if status.operationBusy { info("An operation is in progress") }
        else if status.otherScanBusy { info("Another scan is running") }
        action("Recent activity", symbol: "clock.arrow.circlepath", route: .activity)
        action("Changes…", symbol: "chart.xyaxis.line", route: .changes)
        action("Make room…", symbol: "plus.circle", route: .makeRoom)
        if AppSettings.shared.reserveEnabled {
            pauseRow = NSMenuItem(title: "", action: #selector(toggleReservePause), keyEquivalent: "")
            pauseRow?.target = self
            pauseRow?.isEnabled = !preview
            if let pauseRow { menu.addItem(pauseRow) }
        } else {
            pauseRow = nil
            action("Set up space alerts…", symbol: "bell", route: .preferences("Monitoring"))
        }
        menu.addItem(.separator())
        drivesRow = NSMenuItem(title: "External drives", action: nil, keyEquivalent: "")
        drivesRow?.image = symbol("externaldrive")
        if let drivesRow { menu.addItem(drivesRow) }
        awayRow = NSMenuItem(title: "", action: #selector(performAction(_:)), keyEquivalent: "")
        awayRow?.target = self
        awayRow?.representedObject = RouteBox(.makeRoom)
        awayRow?.image = symbol("externaldrive.badge.exclamationmark")
        awayRow?.toolTip = "Plug the drive in to use them."
        if let awayRow { menu.addItem(awayRow) }
        let protection = NSMenuItem(title: "Protected locations", action: nil, keyEquivalent: "")
        protection.image = symbol("shield")
        let protected = NSMenu()
        protected.autoenablesItems = false
        for title in ["Known Codex & ChatGPT sessions", "Source, Git & recovery data", "System files & credentials"] {
            let row = NSMenuItem(title: title, action: nil, keyEquivalent: ""); row.isEnabled = false; protected.addItem(row)
        }
        protected.addItem(.separator())
        action("View protections…", route: .preferences("Protection"), in: protected)
        action("Excluded locations…", route: .preferences("Excluded locations"), in: protected)
        protection.submenu = protected
        menu.addItem(protection)
        menu.addItem(.separator())
        action("Open Cairn", key: "o", route: .overview)
        action("Settings…", key: ",", route: .preferences("General"))
        let quit = NSMenuItem(title: "Quit Cairn", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        quit.isEnabled = !status.operationBusy
        menu.addItem(quit)
        updateStorageRows()
    }

    private func updateStorageRows() {
        if let available {
            let low = available < 15_000_000_000
            capacityRow?.title = "\(Fmt.size(available)) available\(low ? " · Low" : "")"
            capacityRow?.image = symbol(low ? "circle.fill" : "checkmark.circle.fill", color: low ? .systemOrange : .systemGreen)
        } else {
            capacityRow?.title = readAt == nil ? "Reading storage…" : "Storage reading unavailable"
            capacityRow?.image = nil
        }
        if let capacityRow {
            // Information is not clickable, but the primary reading should not
            // look like an unavailable command. Dynamic color follows macOS.
            capacityRow.attributedTitle = NSAttributedString(string: capacityRow.title, attributes: [
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.menuFont(ofSize: 13)
            ])
        }
        changeRow?.title = change
        if let projectsRow {
            let title = preview ? "3 idle projects · 6.2 GB rebuildable" : idleProjectsTitle
            projectsRow.title = title ?? "Projects"
            projectsRow.isHidden = title == nil
        }
        if let awayRow {
            let title = preview ? "Studio SSD holds Ollama models and 2 more" : awayTitle
            awayRow.title = title ?? ""
            awayRow.isHidden = title == nil || (preview && !drives.isEmpty)
        }
        if let reserveRow {
            let settings = AppSettings.shared
            if settings.reservePaused { reserveRow.title = "Space alerts paused · target \(settings.reserveGB) GB" }
            else if let available {
                let gap = max(0, Int64(settings.reserveGB) * 1_000_000_000 - available)
                reserveRow.title = gap == 0 ? "Chosen reserve met · \(settings.reserveGB) GB" : "\(Fmt.size(gap)) below chosen reserve"
            } else { reserveRow.title = "Chosen reserve · \(settings.reserveGB) GB · reading unavailable" }
        }
        pauseRow?.title = AppSettings.shared.reservePaused ? "Resume space alerts" : "Pause space alerts"
        capacityRow?.toolTip = "Available capacity includes space macOS may reclaim.\(readAt.map { " Read at \($0.formatted(date: .omitted, time: .shortened))." } ?? "")"
        updateBadge()
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        drivesRow?.title = drives.count == 1 ? drives[0].name : "External drives\(drives.isEmpty ? "" : " (\(drives.count))")"
        if drives.isEmpty {
            let row = NSMenuItem(title: drivesRead ? "No external drives connected" : "Reading connected drives…", action: nil, keyEquivalent: "")
            row.isEnabled = false; submenu.addItem(row)
        }
        for drive in drives {
            let title = "\(drive.name) · \(drive.available.map(Fmt.size) ?? "Capacity unavailable")\(drive.available == nil ? "" : " available")"
            let row = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            row.image = symbol("circle.fill", color: .systemGreen); row.isEnabled = false; submenu.addItem(row)
            if drive.readOnly { let row = NSMenuItem(title: "Read-only or access unknown", action: nil, keyEquivalent: ""); row.isEnabled = false; submenu.addItem(row) }
            action("View \(drive.name) in Storage…", route: .storage(drive.id), in: submenu)
        }
        if !drives.isEmpty { submenu.addItem(.separator()) }
        action("Storage options…", route: .storage(nil), in: submenu)
        drivesRow?.submenu = submenu
    }

    private func updateBadge() {
        guard let button = statusItem?.button else { return }
        button.title = MenuAvailableSpace.title(available, checked: readAt != nil)
        if let available, let image = gauge(available: available) { button.image = image }
        let state: String
        if let available {
            state = "\(Fmt.size(available)) available on this Mac"
        } else {
            state = readAt == nil ? "Checking available storage" : "Available storage could not be read"
        }
        button.setAccessibilityLabel(preview ? "Cairn preview, \(state), sample data" : "Cairn, \(state)")
        button.toolTip = preview
            ? "Cairn Preview · sample data"
            : "\(state). Includes space macOS may reclaim.\(readAt.map { " Checked at \($0.formatted(date: .omitted, time: .shortened))." } ?? "")"
    }

    /// A small gauge that fills as the disk fills, amber when it is nearly full.
    /// Drawn as a template so it follows the menu bar's colour, except when amber.
    private func gauge(available: Int64) -> NSImage? {
        let total = preview ? PreviewStorageScenario.totalBytes
            : (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey]))?.volumeTotalCapacity.map(Int64.init)
        guard let total, total > 0 else { return nil }
        let used = min(1, max(0, 1 - Double(available) / Double(total)))
        let nearlyFull = used >= 0.95
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let outline = NSBezierPath(roundedRect: NSRect(x: 2.15, y: 2.65, width: 13.7, height: 12.7), xRadius: 2.7, yRadius: 2.7)
            outline.lineWidth = 1.3
            (nearlyFull ? NSColor.labelColor : NSColor.black).setStroke()
            outline.stroke()
            // Fill rises from the bottom, inside a 1.5 pt margin.
            let inner = NSRect(x: 3.5, y: 4, width: 11, height: 10)
            let height = max(1.6, inner.height * used)
            let fill = NSBezierPath(roundedRect: NSRect(x: inner.minX, y: inner.maxY - height, width: inner.width, height: height),
                                    xRadius: 1.4, yRadius: 1.4)
            (nearlyFull ? NSColor.systemOrange : NSColor.black.withAlphaComponent(0.85)).setFill()
            fill.fill()
            return true
        }
        image.isTemplate = !nearlyFull
        image.accessibilityDescription = "Disk \(Int((used * 100).rounded()))% full"
        return image
    }

    @discardableResult private func info(_ title: String) -> NSMenuItem {
        let row = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        row.isEnabled = false
        menu.addItem(row)
        return row
    }
    private func heading(_ title: String) { menu.addItem(NSMenuItem.sectionHeader(title: title)) }
    private final class RouteBox: NSObject { let action: MenuBarRoute.Action; init(_ action: MenuBarRoute.Action) { self.action = action } }
    private func action(_ title: String, symbol name: String? = nil, key: String = "", route: MenuBarRoute.Action, enabled: Bool = true, in targetMenu: NSMenu? = nil) {
        let row = NSMenuItem(title: title, action: #selector(performAction(_:)), keyEquivalent: key)
        row.target = self; row.isEnabled = enabled; row.representedObject = RouteBox(route)
        if let name { row.image = symbol(name) }
        (targetMenu ?? menu).addItem(row)
    }
    private func symbol(_ name: String, color: NSColor? = nil) -> NSImage? {
        var image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        if let color { image = image?.withSymbolConfiguration(.init(paletteColors: [color])) }
        image?.size = NSSize(width: 15, height: 15)
        return image
    }
    @objc private func performAction(_ sender: NSMenuItem) {
        guard let route = (sender.representedObject as? RouteBox)?.action else { return }
        // Validate again after menu tracking, not just when the menu was opened.
        let status = scanStatus()
        if route == .scan && (preview || !status.canStart) { return }
        if route == .stop && (preview || !status.scanning) { return }
        MenuBarRoute.shared.send(route)
    }
    @objc private func quitApp() {
        let status = scanStatus()
        guard !status.operationBusy else { return }
        NSApp.terminate(nil)
    }
    @objc private func toggleReservePause() {
        guard !preview, AppSettings.shared.reserveEnabled else { return }
        if AppSettings.shared.reservePaused { StorageControl.shared.resumeMonitoring() }
        else { StorageControl.shared.pauseMonitoring(until: nil) }
        updateStorageRows()
    }
}
