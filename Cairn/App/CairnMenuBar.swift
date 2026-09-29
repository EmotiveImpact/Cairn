import AppKit
import SwiftUI
import Observation

/// Routes menu actions to the existing window. The menu never owns a scanner.
@MainActor @Observable final class MenuBarRoute {
    enum Action: Equatable { case overview, scan, stop, results, activity, storage(String?), preferences(String) }
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
    var canStart: Bool { !scanning && !operationBusy && !otherScanBusy }
}

enum MenuStorageSummary {
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

/// AppKit supplies real menu tracking, keyboard navigation, submenus and material.
/// No scene binding, timers, scan stores or synchronous filesystem work on open.
@MainActor final class CairnMenuBar: NSObject, NSMenuDelegate {
    static let shared = CairnMenuBar()
    var scanStatus: () -> MenuScanStatus = { MenuScanStatus() }
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private var refreshTask: Task<Void, Never>?
    private var available: Int64?
    private var change = "Reading storage…"
    private var readAt: Date?
    private var drives: [Drive] = []
    private var drivesRead = false
    private var capacityRow: NSMenuItem?
    private var changeRow: NSMenuItem?
    private var drivesRow: NSMenuItem?
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
    }

    func setVisible(_ visible: Bool) {
        let enabled = preview ? CommandLine.arguments.contains("--preview-menu") : visible
        guard enabled != (statusItem != nil) else { return }
        if !enabled {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let renderer = ImageRenderer(content: CairnLogo(size: 22, monochrome: true))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "mountain.2.fill", accessibilityDescription: "Cairn")
        image?.isTemplate = true
        image?.size = NSSize(width: 20, height: 20)
        item.button?.image = image
        item.button?.toolTip = preview ? "Cairn Preview · sample data" : "Cairn · Storage & maintenance"
        item.button?.setAccessibilityLabel(preview ? "Cairn Preview" : "Cairn")
        menu.delegate = self
        menu.autoenablesItems = false
        menu.minimumWidth = 290
        item.menu = menu
        statusItem = item
        if preview {
            available = 9_900_000_000
            change = "4.2 GB less since yesterday"
            drives = CommandLine.arguments.contains("--preview-empty-storage") ? [] : [.init(id: "SAMPLE-DRIVE-IDENTITY", name: "Studio SSD", available: 186_000_000_000, readOnly: false)]
            drivesRead = true
            readAt = Date()
        }
        rebuild()
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
        // Only volume metadata and Cairn's small saved history; no directory walks
        // or diskutil processes. One in-flight task even after repeated menu opens.
        refreshTask = Task {
            let reading = await Task.detached(priority: .utility) {
                let home = FileManager.default.homeDirectoryForCurrentUser
                let info = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                let free = info?.volumeAvailableCapacityForImportantUsage
                let keys: Set<URLResourceKey> = [.volumeUUIDStringKey, .volumeNameKey, .volumeIsLocalKey, .volumeIsInternalKey, .volumeIsReadOnlyKey, .volumeAvailableCapacityForImportantUsageKey]
                let locality: Set<URLResourceKey> = [.volumeIsLocalKey, .volumeIsInternalKey]
                let mounts = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(locality), options: [.skipHiddenVolumes]) ?? []
                let drives = mounts.compactMap { url -> Drive? in
                    guard let location = try? url.resourceValues(forKeys: locality), location.volumeIsLocal == true, location.volumeIsInternal == false,
                          let values = try? url.resourceValues(forKeys: keys) else { return nil }
                    return Drive(id: values.volumeUUIDString ?? url.path, name: values.volumeName ?? url.lastPathComponent,
                                 available: values.volumeAvailableCapacityForImportantUsage, readOnly: values.volumeIsReadOnly != false)
                }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                return Reading(available: free, change: MenuStorageSummary.change(current: free, samples: StorageHistory.load()), drives: drives)
            }.value
            available = reading.available
            change = reading.change
            drives = reading.drives
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
        menu.addItem(.separator())
        let status = scanStatus()
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
        menu.addItem(.separator())
        drivesRow = NSMenuItem(title: "External drives", action: nil, keyEquivalent: "")
        drivesRow?.image = symbol("externaldrive")
        if let drivesRow { menu.addItem(drivesRow) }
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
        quit.isEnabled = !status.operationBusy && !status.scanning && !status.otherScanBusy
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
        capacityRow?.toolTip = "Available capacity includes space macOS may reclaim.\(readAt.map { " Read at \($0.formatted(date: .omitted, time: .shortened))." } ?? "")"
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
        guard !status.operationBusy && !status.scanning && !status.otherScanBusy else { return }
        NSApp.terminate(nil)
    }
}
