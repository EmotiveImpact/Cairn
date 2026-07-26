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

    var body: some Scene {
        // Single `Window` (not `WindowGroup`): one AppShell, one set of stores/
        // scans/caches. A second window would mean a second full scan + duplicate
        // caches — a direct multiplier on memory.
        Window("Cairn", id: "main") {
            AppShell()
                .frame(minWidth: 1040, minHeight: 720)
                .background(Brand.background)
                .preferredColorScheme(.light)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1240, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}   // no "New Window"
        }

        // Honors Settings → "Show menu bar item": quick access to Cairn from the
        // menu bar; the toggle inserts/removes it live.
        MenuBarExtra("Cairn", systemImage: "mountain.2.fill", isInserted: $showMenuBarItem) {
            MenuBarContent()
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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Stay alive in the menu bar when the user keeps the menu bar item on.
        !AppSettings.shared.showMenuBarItem
    }
}
