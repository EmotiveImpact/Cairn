import SwiftUI
import AppKit

/// Entry point. A thin wrapper so we can support headless CLI flags
/// (`--snapshot` for screenshots, `--selftest` later) before handing off to the
/// SwiftUI App lifecycle.
@main
struct CairnMain {
    static func main() {
        if CommandLine.arguments.contains("--safetycheck") {
            SafetyCheck.run()
            return
        }
        if CommandLine.arguments.contains("--selftest") {
            SelfTest.run()
            return
        }
        CairnApp.main()
    }
}

struct CairnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    // Deliberately @AppStorage, NOT @Bindable AppSettings.shared. Binding the
    // whole settings object here put it in the App's dependency set, so ANY
    // setting change re-evaluated the App body, rebuilt `AppShell`, and reset its
    // @State stores — silently restarting every scan (runaway CPU + memory).
    @AppStorage("cairn.showMenuBarItem") private var showMenuBarItem = true
    @StateObject private var reclaim = ReclaimStats.shared

    /// Writes through only on a REAL change — see the note on MenuBarExtra below.
    private var menuBarInserted: Binding<Bool> {
        Binding(get: { showMenuBarItem },
                set: { if $0 != showMenuBarItem { showMenuBarItem = $0 } })
    }

    var body: some Scene {
        // Single `Window` (not `WindowGroup`): one AppShell, one set of stores/
        // scans/caches. A second window would mean a second full scan + duplicate
        // caches — a direct multiplier on memory.
        Window("Cairn", id: "main") {
            AppShell()
                .background(Brand.background)
                .preferredColorScheme(.light)
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
        .defaultSize(width: 1240, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}   // no "New Window"
        }

        // Honors Settings → "Show menu bar item": quick access to Cairn from the
        // menu bar; the toggle inserts/removes it live.
        // Honors Settings → "Show menu bar item": quick access to Cairn from the
        // menu bar; the toggle inserts/removes it live.
        //
        // CRITICAL: `isInserted` must NOT be bound directly to @AppStorage.
        // MenuBarExtra writes the current value back on every scene update, and
        // @AppStorage treats every write as a change — so the scene re-evaluated,
        // which re-created the MenuBarExtra, which wrote again… an endless loop.
        // It pinned the main thread at 100% CPU and re-constructed AppShell (and
        // therefore all four scan stores) on every pass, so RSS climbed ~45 MB/s
        // into the gigabytes and the whole app froze. No view body ever
        // re-evaluated, which is why it looked like a render bug rather than a
        // scene bug. This binding drops no-op writes, which breaks the cycle.
        // Shows the reclaimable total at a glance, which is what makes a menu bar
        // item worth having. The value comes from `ReclaimStats` rather than the
        // scan engine, so the App scene never depends on a store — reading a
        // rarely-changing published Int is safe here; it was MenuBarExtra WRITING
        // its own binding on every update that caused the freeze, not reading.
        MenuBarExtra(isInserted: menuBarInserted) {
            MenuBarContent()
        } label: {
            Image(systemName: "mountain.2.fill")
            if reclaim.reclaimableBytes > 0 {
                Text(Fmt.size(reclaim.reclaimableBytes))
            }
        }
    }
}

private struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Open Cairn") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        Divider()
        Button("Quit Cairn") { NSApp.terminate(nil) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // The window's size floor, set once. See the note in `body` — deriving it
        // from content layout (`.contentMinSize`) is what caused the render loop.
        for window in NSApp.windows where window.styleMask.contains(.titled) {
            // 250 (fixed sidebar) + 820 (content minWidth). Must stay >= that sum,
            // or the layout constraints are unsatisfiable and AppKit spins
            // re-solving them forever — see the note in AppShell.body.
            window.minSize = NSSize(width: 1070, height: 720)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Stay alive in the menu bar when the user keeps the menu bar item on.
        !AppSettings.shared.showMenuBarItem
    }
}
