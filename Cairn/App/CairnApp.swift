import SwiftUI
import AppKit

/// Entry point. A thin wrapper so we can support headless CLI flags
/// (`--snapshot` for screenshots, `--selftest` later) before handing off to the
/// SwiftUI App lifecycle.
@main
struct CairnMain {
    static func main() {
        let isolated = ["--evidencecheck", "--hashmemorycheck", "--loadcheck", "--reliabilitycheck", "--workspacecheck", "--safetycheck", "--lifecyclecheck", "--native-reliability-check", "--lease-probe", "--recovery-child"]
        let command = CommandLine.arguments.dropFirst().first ?? ""
        // Diagnostic flags bypass live-store ownership only when unambiguous.
        // In particular, --readonlycheck must not borrow --safetycheck's bypass.
        let modes = isolated + ["--readonlycheck", "--selftest"]
        let selectedModes = modes.filter { CommandLine.arguments.contains($0) }
        guard selectedModes.count <= 1,
              !(CLI.commands.contains(command) && !selectedModes.isEmpty) else {
            fputs("Choose one Cairn command or diagnostic mode at a time. No operation started.\n", stderr)
            exit(64)
        }
        let visualPreview = CommandLine.arguments.contains("--preview-ui") && !CLI.commands.contains(command)
            && !CommandLine.arguments.contains("--readonlycheck") && !CommandLine.arguments.contains("--selftest")
        if visualPreview && CommandLine.arguments.contains("--component-showcase") && selectedModes.isEmpty {
            ComponentShowcaseRunner.run()
            return
        }
        if !visualPreview, !CommandLine.arguments.contains(where: isolated.contains), !InstanceLease.claimApplication() {
            if CLI.commands.contains(command) { exit(75) }
            return
        }
        if CommandLine.arguments.contains("--native-reliability-check") {
            Task { @MainActor in await LifecycleCheck.nativeCheck() }
            RunLoop.main.run(); return
        }
        if CommandLine.arguments.contains("--lifecyclecheck") {
            Task { @MainActor in await LifecycleCheck.run() }
            RunLoop.main.run(); return
        }
        if CommandLine.arguments.contains("--lease-probe") { LifecycleCheck.leaseProbe(); return }
        if CommandLine.arguments.contains("--recovery-child") {
            Task { @MainActor in await LifecycleCheck.recoveryChild() }
            RunLoop.main.run(); return
        }
        if CommandLine.arguments.contains("--evidencecheck") {
            Task.detached { await EvidenceCheck.run() }
            RunLoop.main.run()
            return
        }
        if CommandLine.arguments.contains("--hashmemorycheck") {
            Task { await HashMemoryCheck.run() }
            RunLoop.main.run()
            return
        }
        if CommandLine.arguments.contains("--readonlycheck") {
            Task { @MainActor in await ReadOnlyScanCheck.run() }
            RunLoop.main.run()
            return
        }
        if CommandLine.arguments.contains("--loadcheck") {
            Task { @MainActor in await LoadCheck.run() }
            RunLoop.main.run()
            return
        }
        if CommandLine.arguments.contains("--reliabilitycheck") {
            Task { @MainActor in await ReliabilityCheck.run() }
            RunLoop.main.run()
            return
        }
        if CommandLine.arguments.contains("--workspacecheck") {
            WorkspaceCheck.run()
            return
        }
        if CommandLine.arguments.contains("--safetycheck") {
            SafetyCheck.run()
            return
        }
        if CommandLine.arguments.contains("--selftest") {
            SelfTest.run()
            return
        }
        // `cairn status|scan|clean|categories` — the CLI. Checked before the
        // SwiftUI lifecycle so no window server is ever touched.
        let args = Array(CommandLine.arguments.dropFirst())
        if let first = args.first, CLI.commands.contains(first) {
            CLI.run(args)
            return
        }
        CairnApp.main()
    }
}

struct CairnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage(CairnAppearance.key) private var appearance = CairnAppearance.dark.rawValue
    var body: some Scene {
        // Single `Window` (not `WindowGroup`): one AppShell, one set of stores/
        // scans/caches. A second window would mean a second full scan + duplicate
        // caches — a direct multiplier on memory.
        Window("Cairn", id: "main") {
            AppShell()
                .background(Brand.chrome)
                .onAppear { CairnAppearance(rawValue: appearance)?.apply() }
                .onChange(of: appearance) { _, next in CairnAppearance(rawValue: next)?.apply() }
        }
        .windowStyle(.hiddenTitleBar)
        // CRITICAL: do NOT use `.contentMinSize` together with a `.frame(minWidth:
        // minHeight:)` on the content. That makes AppKit re-derive the WINDOW's
        // minimum size from SwiftUI's content layout on every pass: the content
        // measures, the window constraint re-solves, which re-measures the
        // content… When the content is wider than the window can give it (the
        // dashboard's card row at small widths) the two never agree and it spins
        // forever — 100% main thread, RSS climbing ~45 MB/s, navigation frozen
        // app-wide. The size floor is set ONCE on the NSWindow in AppDelegate
        // instead, which cannot feed back into layout.
        .windowResizability(.automatic)
        .defaultSize(width: 1120, height: 740)
        .commands {
            CairnFindCommands()
            CommandGroup(after: .toolbar) {
                if CommandLine.arguments.contains("--preview-ui") && CommandLine.arguments.contains("--preview-menu") {
                    Button("Preview status menu") { CairnMenuBar.shared.presentPreviewMenu() }
                }
            }
            CommandGroup(replacing: .newItem) {}   // no "New Window"
        }

    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { MenuBarRoute.shared.openWindow?() }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard CairnMenuBar.shared.scanStatus().operationBusy else { return .terminateNow }
        MenuBarRoute.shared.openWindow?()
        let alert = NSAlert()
        alert.messageText = "An operation is still in progress"
        alert.informativeText = "Finish or cancel the operation in Cairn before quitting. Your files and recovery records need time to finish safely."
        alert.addButton(withTitle: "Return to Cairn")
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }), window.attachedSheet == nil {
            alert.beginSheetModal(for: window)
        }
        return .terminateCancel
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        CairnMenuBar.shared.setVisible(AppSettings.shared.showMenuBarItem)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // The window's size floor, set once. See the note in `body` — deriving it
        // from content layout (`.contentMinSize`) is what caused the render loop.
        for window in NSApp.windows where window.styleMask.contains(.titled) {
            let preview = CommandLine.arguments.contains("--preview-ui")
            let minimumPreview = preview && CommandLine.arguments.contains("--preview-min-window")
            let widePreview = preview && CommandLine.arguments.contains("--preview-wide-window")
            let visible = (window.screen ?? NSScreen.main)?.visibleFrame
            window.minSize = NSSize(width: min(1024, visible?.width ?? 1024), height: min(680, visible?.height ?? 680))
            // Restore once, outside SwiftUI layout. Preview never overwrites the live frame.
            let restored = !preview && window.setFrameUsingName("CairnMainWindow.v2")
            if !restored {
                let target = NSSize(width: minimumPreview ? 1024 : widePreview ? 1280 : 1120,
                                    height: minimumPreview ? 680 : widePreview ? 800 : 740)
                window.setContentSize(NSSize(width: min(target.width, visible?.width ?? target.width),
                                             height: min(target.height, visible?.height ?? target.height)))
                window.center()
            }
            if let visible {
                var frame = window.frame
                frame.size.width = min(frame.width, visible.width)
                frame.size.height = min(frame.height, visible.height)
                frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.width))
                frame.origin.y = max(visible.minY, min(frame.origin.y, visible.maxY - frame.height))
                window.setFrame(frame, display: true)
            }
            if !preview { window.setFrameAutosaveName("CairnMainWindow.v2") }

        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        if CommandLine.arguments.contains("--preview-ui") { return !CommandLine.arguments.contains("--preview-menu") }
        // Stay alive in the menu bar when the user keeps the menu bar item on.
        return !AppSettings.shared.showMenuBarItem
    }
}

private struct CairnFindKey: FocusedValueKey {
    typealias Value = () -> Void
}
extension FocusedValues {
    var cairnFind: (() -> Void)? {
        get { self[CairnFindKey.self] }
        set { self[CairnFindKey.self] = newValue }
    }
}
private struct CairnFindCommands: Commands {
    @FocusedValue(\.cairnFind) private var find
    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("Find in Results") { find?() }
                .keyboardShortcut("f", modifiers: .command).disabled(find == nil)
        }
    }
}

/// Window appearance. Dark is Cairn's default; Light and System use the same
/// tokens, which carry a value for each (see `Brand`).
enum CairnAppearance: String, CaseIterable {
    case dark, light, system
    static let key = "cairn.appearance"
    var title: String {
        switch self { case .dark: return "Dark"; case .light: return "Light"; case .system: return "Match System" }
    }
    func apply() {
        switch self {
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .system: NSApp.appearance = nil
        }
    }
}
