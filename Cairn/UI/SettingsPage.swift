import SwiftUI
import AppKit

/// Full Settings page (content section), matching the mockup layout — General /
/// Smart Scan / Safety / Notifications on the left; Developer Tools / Ignored
/// Locations / Restore Bin on the right. (Appearance intentionally omitted.)
struct SettingsPage: View {
    let store: ScanStore
    @Bindable private var s = AppSettings.shared
    @ObservedObject var license: LicenseManager
    @State private var showAbout = false
    @State private var cliInstalled = FileManager.default.fileExists(atPath: "/usr/local/bin/cairn")

    /// Symlinks the app's own binary as `cairn`, the way VS Code installs `code`.
    /// /usr/local/bin usually isn't writable without admin rights, so on failure
    /// we hand the user the exact command instead of failing silently.
    private func installCLI() {
        guard let binary = Bundle.main.executableURL else { return }
        let target = URL(fileURLWithPath: "/usr/local/bin/cairn")
        let fm = FileManager.default
        try? fm.removeItem(at: target)
        do {
            try fm.createSymbolicLink(at: target, withDestinationURL: binary)
            cliInstalled = true
        } catch {
            let command = "sudo mkdir -p /usr/local/bin && sudo ln -sf '\(binary.path)' /usr/local/bin/cairn"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            let alert = NSAlert()
            alert.messageText = "Command copied"
            alert.informativeText = "Installing needs admin rights. The install command is on your clipboard — paste it into Terminal."
            alert.runModal()
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Same full-bleed hero every other page wears, so Settings doesn't
                // read as a different app.
                PageHero(title: "Settings",
                         subtitle: "Customize Cairn to keep your Mac clean, safe and fast. Everything saves automatically and stays on this Mac.")

                VStack(alignment: .leading, spacing: 16) {
                    ProStatusCard(license: license)

                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 16) { general; smartScan; safety; notifications }.frame(maxWidth: .infinity)
                        VStack(spacing: 16) { developerTools; ignoredLocations; restoreBin; aboutCard }.frame(maxWidth: .infinity)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                        Text("Your settings are saved automatically and stay on this Mac.")
                            .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                    }
                    .padding(.top, 2)
                }
                .heroPageContent()
            }
        }
    }

    // MARK: - Left column

    private var general: some View {
        card("gearshape.fill", "General") {
            toggleRow("Open at login", "Launch Cairn automatically when you log in.", $s.openAtLogin)
            div
            toggleRow("Show menu bar item", "Access Cairn quickly from the menu bar.", $s.showMenuBarItem)
            div
            dropdownRow("Language", "Choose your preferred language.", current: "System Default", options: ["System Default", "English"]) { _ in }
        }
    }

    private var smartScan: some View {
        card("scope", "Smart Scan") {
            toggleRow("Auto Scan Weekly", "Automatically run Smart Scan every week.", $s.autoScanWeekly)
            div
            toggleRow("Ask Before Deleting", "Ask for confirmation before removing files.", $s.askBeforeDeleting)
            div
            toggleRow("Create Restore Snapshot", "Create a snapshot before major cleanup operations.", $s.createRestoreSnapshot)
            div
            toggleRow("Ignore External Drives", "Skip external and network drives during scans.", $s.ignoreExternalDrives)
        }
    }

    private var safety: some View {
        // These are hard engine guarantees (SafePaths denylist + running-app
        // guard), not options — shown as always-on so the promise is honest.
        card("checkmark.shield.fill", "Safety") {
            alwaysOnRow("Protect System Files", "Critical macOS files and apps can never be selected or removed.")
            div
            alwaysOnRow("Skip Open Files", "Apps that own a cache are quit before it's cleaned.")
            div
            alwaysOnRow("Recoverable Removal", "Everything goes to the Trash first — Put Back anytime.")
        }
    }

    private var notifications: some View {
        card("bell.fill", "Notifications") {
            toggleRow("Scan Notifications", "Receive an alert when a scan completes.", $s.scanNotifications)
        }
    }

    /// A guarantee row — same layout as a toggle row, but with a green "Always on".
    private func alwaysOnRow(_ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.textPrimary)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Brand.textMuted)
            }
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(Brand.safeCyan)
                Text("Always on").font(.system(size: 12, weight: .medium)).foregroundStyle(Brand.textSecondary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    // MARK: - Right column

    private var developerTools: some View {
        card("chevron.left.forwardslash.chevron.right", "Developer Tools") {
            toggleRow("Clean when I quit a dev app",
                      license.isUnlocked
                        ? "When you quit Xcode, Cursor or Android Studio, Cairn sweeps that tool's regenerable caches to the Trash."
                        : "Pro — when you quit Xcode, Cursor or Android Studio, Cairn sweeps that tool's regenerable caches to the Trash.",
                      $s.cleanOnQuitDevApp)
                .disabled(!license.isUnlocked)
                .opacity(license.isUnlocked ? 1 : 0.55)
            div
            toggleRow("Include developer caches", "Clean Xcode, CocoaPods, and other caches.", $s.includeDeveloperCaches)
            div
            toggleRow("Include simulators", "Remove iOS Simulator data.", $s.includeSimulators)
            div
            actionRow("Exclude folders", "Add folders to exclude from scans.", button: "Manage…") { addFolder() }
            div
            actionRow("Command line tool",
                      cliInstalled ? "`cairn` is installed — try `cairn status`."
                                   : "Use Cairn from the terminal: scan, clean, and script it.",
                      button: cliInstalled ? "Reinstall" : "Install…") { installCLI() }
        }
    }

    private var ignoredLocations: some View {
        card("folder.fill", "Ignored Locations") {
            Text("These locations will be skipped during scans.")
                .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
            if s.excludedPaths.isEmpty {
                Text("No ignored locations yet. Sensitive areas (Documents, Keychains, Mail, Photos…) are always protected automatically.")
                    .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                    .padding(.horizontal, 16).padding(.bottom, 12)
            } else {
                ForEach(s.excludedPaths, id: \.self) { path in
                    HStack(spacing: 9) {
                        Image(systemName: "folder.fill").font(.system(size: 12)).foregroundStyle(Brand.blue)
                        Text(pretty(path)).font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button { s.remove(path) } label: { Image(systemName: "minus.circle.fill").foregroundStyle(Brand.textMuted) }
                            .buttonStyle(.plain).pointerCursor()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
            }
            HStack { Spacer(); Button("Manage…") { addFolder() }.buttonStyle(GhostButtonStyle()) }
                .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }

    private var aboutCard: some View {
        card("info.circle.fill", "About Cairn") {
            actionRow("What's New & Changelog", "Version history, bug fixes, and safety notes.", button: "Open") { showAbout = true }
            div
            HStack {
                Text("Version").font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.textPrimary)
                Spacer()
                Text(AppInfo.version).font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
        }
        .sheet(isPresented: $showAbout) { TransparencyPanel() }
    }

    private var restoreBin: some View {
        card("trash.fill", "Restore Bin") {
            dropdownRow("Keep removals listed for", "Recoverable items stay here so you can put them back.",
                        current: "\(s.restoreBinKeepDays) Days", options: ["7 Days", "30 Days", "90 Days"]) { v in
                s.restoreBinKeepDays = Int(v.split(separator: " ").first.map(String.init) ?? "30") ?? 30
                store.pruneRemovalLog()
            }
            div
            if store.removalLog.isEmpty {
                Text("No recent removals. Items you clean appear here so you can Put Back anything moved to the Trash.")
                    .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16).padding(.vertical, 14)
            } else {
                let recent = Array(store.removalLog.prefix(8))
                VStack(spacing: 0) {
                    ForEach(recent) { entry in
                        removalRow(entry)
                        if entry.id != recent.last?.id { div }
                    }
                }
            }
        }
    }

    private func removalRow(_ entry: ScanStore.RemovalLogEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.recoverable ? "arrow.uturn.backward.circle" : "trash.slash")
                .font(.system(size: 14)).foregroundStyle(entry.recoverable ? Brand.blue : Brand.textMuted).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).font(.system(size: 12, weight: .medium)).foregroundStyle(Brand.textPrimary).lineLimit(1)
                Text("\(Fmt.size(entry.bytes)) · \(relative(entry.date))")
                    .font(.system(size: 10)).foregroundStyle(Brand.textMuted)
            }
            Spacer(minLength: 8)
            if entry.recoverable {
                Button("Put Back") { _ = store.restoreFromLog(entry) }.buttonStyle(GhostButtonStyle())
            } else {
                Text("Permanent").font(.system(size: 10, weight: .semibold)).foregroundStyle(Brand.textMuted)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
    }

    private func relative(_ d: Date) -> String {
        return Fmt.relative(d)
    }

    // MARK: - Building blocks

    @ViewBuilder private func card(_ icon: String, _ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.blue)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Brand.blue.opacity(0.10)))
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Brand.textPrimary)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            Divider().overlay(Brand.border)
            content()
        }
        .background(CardBackground())
    }

    private var div: some View { Divider().overlay(Brand.border).padding(.leading, 16) }

    private func toggleRow(_ title: String, _ subtitle: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.textPrimary)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Brand.textMuted)
            }
            Spacer()
            Toggle("", isOn: binding).labelsHidden().toggleStyle(.switch).tint(Brand.blue)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    private func actionRow(_ title: String, _ subtitle: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.textPrimary)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Brand.textMuted)
            }
            Spacer()
            Button(button, action: action).buttonStyle(GhostButtonStyle())
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    private func dropdownRow(_ title: String, _ subtitle: String, current: String, options: [String], onSelect: @escaping (String) -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.textPrimary)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Brand.textMuted)
            }
            Spacer()
            Menu {
                ForEach(options, id: \.self) { opt in Button(opt) { onSelect(opt) } }
            } label: {
                HStack(spacing: 6) {
                    Text(current).font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9)).foregroundStyle(Brand.textMuted)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).stroke(Brand.inputBorder, lineWidth: 1))
            }
            .menuStyle(.borderlessButton).fixedSize()
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true
        panel.prompt = "Exclude"
        if panel.runModal() == .OK { for url in panel.urls { s.add(url) } }
    }

    private func pretty(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
