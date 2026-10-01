import Foundation

/// `Cairn --safetycheck` — a release gate. Asserts the SafePaths chokepoint still
/// refuses every irreplaceable location (AI agent conversation history, iCloud
/// mirrors, Keychains, ssh keys, Documents) while normal caches stay cleanable.
/// Run before shipping; a failure here means a data-loss regression.
enum SafetyCheck {
    static func run() {
        // Verify the AI-history denylist really blocks these paths.
        let home = FileScan.home
        let mustBlock = [
            ".claude", ".claude/projects", ".claude/projects/foo/bar.jsonl",
            ".codex", ".codex/sessions", ".cursor",
            "Library/Application Support/Claude",
            "Library/Application Support/Codex",
            "Library/Application Support/chatgpt-mac",
            "Library/Application Support/Codex Web GPT/sessions",
            "Library/Application Support/OpenAI",
            "Library/Application Support/com.openai.codex",
            "Library/Application Support/com.openai.chat",
            "Library/Group Containers/2DC432GLL2.com.openai.codex.notifications",
            "Library/Group Containers/group.com.openai.chat",
            "Library/Containers/com.openai.codex/Data",
            "Library/Caches/Codex",
            "Library/Caches/com.openai.codex",
            "Library/Mobile Documents", "Library/CloudStorage/Dropbox",
            "Library/Keychains", ".ssh/id_rsa", "Documents/tax.pdf",
        ]
        var fails = 0
        for rel in mustBlock {
            let u = home.appendingPathComponent(rel)
            let v = SafePaths.evaluate(u, allowedRoots: [home])
            if v.isAllowed { print("❌ ALLOWED (should be blocked): \(rel)"); fails += 1 }
            else { print("✅ blocked: \(rel)") }
        }
        // sanity: a real cache target must still be cleanable
        let ok = home.appendingPathComponent("Library/Caches/some-app")
        if SafePaths.evaluate(ok, allowedRoots: [home]).isAllowed {
            print("✅ unrelated cache still cleanable")
        } else {
            print("❌ unrelated cache wrongly blocked")
            fails += 1
        }
        let agentApp = URL(fileURLWithPath: "/Applications/ChatGPT.app")
        if AppInventoryStore.isUninstallSafe(agentApp) {
            print("❌ protected app can be uninstalled")
            fails += 1
        } else { print("✅ protected app uninstall blocked") }

        // A generic cache parent can hide a protected session directory. This
        // must fail immediately before Trash, not merely at scan-item creation.
        let nestedFixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("cairn-nested-safety-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: nestedFixture, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: nestedFixture) }
            let nested = nestedFixture.appendingPathComponent("generic/subfolder/chatgpt-mac", isDirectory: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            if SafePaths.evaluateContents(nestedFixture).isAllowed {
                print("❌ nested conversation data was not protected")
                fails += 1
            } else { print("✅ nested conversation data blocked") }
        } catch {
            print("❌ nested safety fixture failed: \(error.localizedDescription)")
            fails += 1
        }

        // A stale scan or crafted review item must not bypass the executor's
        // tool/cache policy. Only disposable paths are used for the command
        // fixture; the npm URL is a string and is never read or modified.
        let toolFixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("cairn-tool-safety-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: toolFixture, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: toolFixture) }
            let marker = toolFixture.appendingPathComponent("must-not-be-created")
            let toolItem = ScanItem(
                url: toolFixture, resolvedURL: toolFixture, allocatedSize: 1024,
                categoryID: "fixture", severity: .safe,
                cleanMethod: .tool(ToolCommand(tool: "touch", arguments: [marker.path], display: "touch fixture")),
                selected: true
            )
            let toolResult = Cleaner.clean(toolItem, allowedRoots: [toolFixture], proEnabled: true)
            if !toolResult.ok && !toolResult.usedTool && toolResult.bytesAffected == 0 &&
                toolResult.error?.contains("review-only") == true && !FileManager.default.fileExists(atPath: marker.path) {
                print("✅ broad tool action blocked in executor")
            } else {
                print("❌ broad tool action escaped executor guard")
                fails += 1
            }

            for rel in [".npm/_cacache", ".gradle/caches", "Library/Caches/Homebrew"] {
                let cacheURL = home.appendingPathComponent(rel)
                let staleCacheItem = ScanItem(
                    url: cacheURL, resolvedURL: cacheURL, allocatedSize: 1024,
                    categoryID: "dev-caches", severity: .safe,
                    cleanMethod: .trash, selected: true,
                    sourceIdentity: SourceIdentity(device: 0, inode: 0)
                )
                let result = Cleaner.clean(staleCacheItem, allowedRoots: [home], proEnabled: true)
                if !result.ok && result.bytesAffected == 0 && result.error?.contains("review-only") == true {
                    print("✅ stale tool-cache Trash item blocked: \(rel)")
                } else {
                    print("❌ stale tool-cache Trash item escaped executor guard: \(rel)")
                    fails += 1
                }
            }
        } catch {
            print("❌ tool safety fixture failed: \(error.localizedDescription)")
            fails += 1
        }

        // Exercise the CLI installer policy against isolated temporary fixtures.
        // A regular file or someone else's symlink must never be replaced.
        let fm = FileManager.default
        let fixture = fm.temporaryDirectory.appendingPathComponent("cairn-cli-safety-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: fixture, withIntermediateDirectories: false)
            defer { try? fm.removeItem(at: fixture) }
            let binary = fixture.appendingPathComponent("app-binary")
            let target = fixture.appendingPathComponent("cairn")
            try Data("binary".utf8).write(to: binary)

            func expect(_ expected: CLIInstallPolicy.TargetState, _ label: String) {
                if CLIInstallPolicy.state(at: target, for: binary) == expected {
                    print("✅ CLI \(label)")
                } else {
                    print("❌ CLI \(label)")
                    fails += 1
                }
            }

            expect(.absent, "absent path")
            try Data("keep me".utf8).write(to: target)
            expect(.conflict, "regular file protected")
            try fm.removeItem(at: target)
            try fm.createSymbolicLink(at: target, withDestinationURL: binary)
            expect(.ownedLink, "own symlink recognized")
            try fm.removeItem(at: target)
            try fm.createSymbolicLink(atPath: target.path, withDestinationPath: "missing-binary")
            expect(.conflict, "dangling symlink protected")
            try fm.removeItem(at: target)
            let foreign = fixture.appendingPathComponent("foreign-binary")
            try Data("foreign".utf8).write(to: foreign)
            try fm.createSymbolicLink(at: target, withDestinationURL: foreign)
            expect(.conflict, "foreign symlink protected")
        } catch {
            print("❌ CLI policy fixture failed: \(error.localizedDescription)")
            fails += 1
        }

        // A build with the local Pro unlock still switched on must never ship —
        // it would hand every customer Pro without a key.
        if LicenseConfig.devProUnlock {
            print("❌ DEV PRO UNLOCK IS ON — run: defaults delete com.emotiveimpact.cairn cairn.devPro")
            fails += 1
        } else {
            print("✅ dev Pro unlock off")
        }

        print(fails == 0 ? "\nALL SAFETY CHECKS PASSED" : "\n\(fails) SAFETY FAILURES")
        if fails > 0 { exit(1) }
    }
}
