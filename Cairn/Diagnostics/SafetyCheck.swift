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
            if SafePaths.evaluate(u, allowedRoots: [home], rebuildable: true).isAllowed {
                print("❌ ALLOWED as rebuildable (should be blocked): \(rel)"); fails += 1
            }
        }
        // Rebuildable project output may be deleted even where personal files may not.
        let mustBlockRebuildable = [
            ".claude/plugins/x/node_modules", ".codex/x/node_modules", ".cursor/extensions/x/node_modules",
            "Code/app/.git/node_modules", "Documents", "Documents/Taxes", "Library/Application Support/Claude/Cache",
            "Library/Caches/Codex", "Library/Caches/com.openai.chat",
        ]
        for rel in mustBlockRebuildable {
            if SafePaths.evaluate(home.appendingPathComponent(rel), allowedRoots: [home], rebuildable: true).isAllowed {
                print("❌ rebuildable ALLOWED (should be blocked): \(rel)"); fails += 1
            } else { print("✅ blocked even as rebuildable: \(rel)") }
        }
        for rel in ["Documents/site/node_modules", "Code/claude-app/node_modules", "Code/sessions-api/target", "Library/Caches/com.example.app"] {
            if SafePaths.evaluate(home.appendingPathComponent(rel), allowedRoots: [home], rebuildable: true).isAllowed {
                print("✅ rebuildable output cleanable: \(rel)")
            } else { print("❌ rebuildable output wrongly blocked: \(rel)"); fails += 1 }
        }
        let personal = ScanItem(url: home.appendingPathComponent("Documents/site/notes.txt"), allocatedSize: 1,
                                categoryID: "large-old", severity: .review, isRegenerable: false)
        let reviewModules = ScanItem(url: home.appendingPathComponent("Code/app/node_modules"), allocatedSize: 1,
                                     categoryID: "dev-projects", severity: .review, isRegenerable: false)
        if !personal.isRebuildable && reviewModules.isRebuildable && !RemovalMode.smart.deletesImmediately(personal)
            && RemovalMode.smart.deletesImmediately(reviewModules) {
            print("✅ Smart mode deletes rebuildable output and sends personal files to Trash")
        } else { print("❌ rebuildable classification wrong"); fails += 1 }
        // sanity: a real cache target must still be cleanable
        let ok = home.appendingPathComponent("Library/Caches/some-app")
        if SafePaths.evaluate(ok, allowedRoots: [home]).isAllowed {
            print("✅ unrelated cache still cleanable")
        } else {
            print("❌ unrelated cache wrongly blocked")
            fails += 1
        }
        // Apple's own caches stay off limits unless known safe; a macOS update in
        // progress and parts of Ollama's shared store are never cleanable.
        let appleBlocked = [
            "Library/Caches/com.apple.e5rt.e5bundlecache", "Library/Caches/com.apple.e5rt.e5bundlecache/x",
            "Library/Caches/com.apple.Photos", "Library/Caches/com.apple.Safari.SafeBrowsing",
            "Library/Caches/GeoServices", "Library/Caches/CloudKit/x",
            ".ollama/models/blobs/sha256-1", ".ollama/models/manifests",
        ]
        for rel in appleBlocked {
            let u = home.appendingPathComponent(rel)
            if SafePaths.evaluate(u, allowedRoots: [home]).isAllowed
                || SafePaths.evaluate(u, allowedRoots: [home], rebuildable: true).isAllowed {
                print("❌ ALLOWED (should be blocked): \(rel)"); fails += 1
            } else { print("✅ blocked: \(rel)") }
        }
        for path in ["/macOS Install Data/x", "/System/Volumes/Data/macOS Install Data/x"] {
            if SafePaths.evaluate(URL(fileURLWithPath: path), allowedRoots: [URL(fileURLWithPath: "/")]).isAllowed {
                print("❌ ALLOWED (should be blocked): \(path)"); fails += 1
            } else { print("✅ blocked: \(path)") }
        }
        let neuralTemp = FileManager.default.temporaryDirectory.appendingPathComponent("com.apple.e5rt.e5bundlecache")
        if SafePaths.evaluate(neuralTemp, allowedRoots: [FileManager.default.temporaryDirectory]).isAllowed {
            print("❌ Neural Engine cache in temp folder ALLOWED"); fails += 1
        } else { print("✅ blocked: Neural Engine cache in temp folder") }
        for rel in ["Library/Caches/com.apple.Safari", "Library/Caches/com.apple.FinalCut",
                    "Library/Caches/com.apple.dt.Xcode", "Library/Caches/com.spotify.client", ".ollama/models"] {
            if SafePaths.evaluate(home.appendingPathComponent(rel), allowedRoots: [home]).isAllowed {
                print("✅ known-safe cache still cleanable: \(rel)")
            } else { print("❌ known-safe cache wrongly blocked: \(rel)"); fails += 1 }
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
            // A rebuildable tree is not refused for SDK-named folders or .db files inside...
            try Data().write(to: nested.appendingPathComponent("cache.sqlite"))
            if SafePaths.evaluateContents(nestedFixture, rebuildable: true).isAllowed {
                print("✅ rebuildable tree with .db files and SDK-named folders cleanable")
            } else { print("❌ rebuildable tree wrongly blocked"); fails += 1 }
            // ...but a Settings exclusion inside it still wins.
            let saved = SafePaths.userExcluded
            SafePaths.userExcluded = [nested.path]
            if SafePaths.evaluateContents(nestedFixture, rebuildable: true).isAllowed {
                print("❌ exclusion inside rebuildable tree ignored"); fails += 1
            } else { print("✅ exclusion inside rebuildable tree blocks it") }
            SafePaths.userExcluded = saved
        } catch {
            print("❌ nested safety fixture failed: \(error.localizedDescription)")
            fails += 1
        }

        // Tool commands run only with an explicit argument array; commands that
        // destroy data never run. A stale review item for a real cache path must
        // fail the identity check without touching it.
        let toolFixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("cairn-tool-safety-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: toolFixture, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: toolFixture) }
            let destroyMarker = toolFixture.appendingPathComponent("must-not-be-created")
            let destructive = ScanItem(
                url: toolFixture, resolvedURL: toolFixture, allocatedSize: 1024,
                categoryID: "fixture", severity: .review,
                cleanMethod: .tool(ToolCommand(tool: "touch", arguments: [destroyMarker.path], display: "touch fixture", destroysData: true)),
                selected: true
            )
            let destructiveResult = Cleaner.clean(destructive, allowedRoots: [toolFixture], proEnabled: true)
            if !destructiveResult.ok && destructiveResult.bytesAffected == 0 && !FileManager.default.fileExists(atPath: destroyMarker.path) {
                print("✅ data-destroying tool command blocked in executor")
            } else {
                print("❌ data-destroying tool command escaped executor guard")
                fails += 1
            }

            let runMarker = toolFixture.appendingPathComponent("tool-ran")
            let supported = ScanItem(
                url: toolFixture, resolvedURL: toolFixture, allocatedSize: 2048,
                categoryID: "fixture", severity: .safe,
                cleanMethod: .tool(ToolCommand(tool: "touch", arguments: [runMarker.path], display: "touch fixture")),
                selected: true
            )
            let supportedResult = Cleaner.clean(supported, allowedRoots: [toolFixture], proEnabled: true)
            if supportedResult.ok && supportedResult.usedTool && supportedResult.deleted && supportedResult.bytesAffected == 2048
                && FileManager.default.fileExists(atPath: runMarker.path) {
                print("✅ reviewed tool command runs with its argument array")
            } else {
                print("❌ reviewed tool command did not run: \(supportedResult.error ?? "unknown")")
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
                let result = Cleaner.clean(staleCacheItem, allowedRoots: [home], proEnabled: true,
                                           moveToTrash: { _ in throw CocoaError(.featureUnsupported) })
                if !result.ok && result.bytesAffected == 0 && result.error?.contains("changed since scanning") == true {
                    print("✅ stale cache review item blocked by identity check: \(rel)")
                } else {
                    print("❌ stale cache review item escaped identity check: \(rel)")
                    fails += 1
                }
            }

            // Delete-now: the item is moved (here into a fixture Trash) and then
            // removed, so nothing is left to occupy space.
            let deleteRoot = toolFixture.appendingPathComponent("delete-root")
            let fixtureTrash = toolFixture.appendingPathComponent("fixture-trash")
            try FileManager.default.createDirectory(at: deleteRoot, withIntermediateDirectories: false)
            try FileManager.default.createDirectory(at: fixtureTrash, withIntermediateDirectories: false)
            let doomed = deleteRoot.appendingPathComponent("cache-dir")
            try FileManager.default.createDirectory(at: doomed, withIntermediateDirectories: false)
            try Data(repeating: 1, count: 4096).write(to: doomed.appendingPathComponent("blob"))
            var deleteItem = ScanItem(url: doomed, allocatedSize: 4096, categoryID: "fixture", severity: .safe, selected: true)
            deleteItem.deleteImmediately = true
            let moved = fixtureTrash.appendingPathComponent("cache-dir")
            let deleteResult = Cleaner.clean(deleteItem, allowedRoots: [deleteRoot], proEnabled: true, moveToTrash: { url in
                try FileManager.default.moveItem(at: url, to: moved); return moved
            })
            if deleteResult.ok && deleteResult.deleted && deleteResult.movedToTrashURL == nil
                && !FileManager.default.fileExists(atPath: doomed.path) && !FileManager.default.fileExists(atPath: moved.path) {
                print("✅ delete-now removes the item instead of parking it in Trash")
            } else {
                print("❌ delete-now left data behind: \(deleteResult.error ?? "unknown")")
                fails += 1
            }

            // End to end: a review-level node_modules holding a .sqlite file and an
            // SDK folder named "openai" is deleted outright in Smart mode.
            let modules = deleteRoot.appendingPathComponent("web/node_modules")
            try FileManager.default.createDirectory(at: modules.appendingPathComponent("openai/sessions"), withIntermediateDirectories: true)
            try Data(repeating: 2, count: 4096).write(to: modules.appendingPathComponent("openai/sessions/test.sqlite"))
            var moduleItem = ScanItem(url: modules, allocatedSize: 4096, categoryID: "dev-projects", severity: .review,
                                      isRegenerable: false, selected: true)
            moduleItem.deleteImmediately = RemovalMode.smart.deletesImmediately(moduleItem)
            let movedModules = fixtureTrash.appendingPathComponent("node_modules")
            let moduleResult = Cleaner.clean(moduleItem, allowedRoots: [deleteRoot], proEnabled: false, moveToTrash: { url in
                try FileManager.default.moveItem(at: url, to: movedModules); return movedModules
            })
            if moduleResult.ok && moduleResult.deleted && !FileManager.default.fileExists(atPath: modules.path)
                && !FileManager.default.fileExists(atPath: movedModules.path) {
                print("✅ node_modules with databases inside is deleted and its space freed")
            } else {
                print("❌ node_modules was not deleted: \(moduleResult.error ?? "unknown")")
                fails += 1
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

        // Cleaning-coverage rules: matching, version order and simctl parsing.
        func rule(_ ok: Bool, _ label: String) {
            if ok { print("✅ \(label)") } else { print("❌ \(label)"); fails += 1 }
        }
        let apps = ["docker": "Docker", "notion": "Notion", "visualstudiocode": "Visual Studio Code"]
        rule(InstallersScanner.installedApp(matching: "Docker-4.34.2-arm64", in: apps) == "Docker", "installer matches its installed app")
        rule(InstallersScanner.installedApp(matching: "Notion Calendar", in: apps) == nil, "installer for a different app does not match")
        rule(InstallersScanner.installedApp(matching: "tax-return-2024", in: apps) == nil, "unrelated disk image does not match")
        rule(AndroidSDKScanner.versionLess("25.1.8937393", "26.3.11579264")
             && !AndroidSDKScanner.versionLess("27.0.1", "26.9"), "NDK versions order numerically")
        let runtimesJSON = """
        {"A":{"identifier":"A","version":"17.5","platformIdentifier":"com.apple.platform.iphonesimulator","sizeBytes":7000000000,"deletable":true},
         "B":{"identifier":"B","version":"18.2","platformIdentifier":"com.apple.platform.iphonesimulator","sizeBytes":8000000000,"deletable":true},
         "C":{"identifier":"C","version":"10.5","platformIdentifier":"com.apple.platform.watchsimulator","sizeBytes":4000000000,"deletable":true},
         "D":{"identifier":"D","version":"16.4","platformIdentifier":"com.apple.platform.iphonesimulator","sizeBytes":6000000000,"deletable":false}}
        """
        let old = XcodeScanner.supersededRuntimes(XcodeScanner.parseRuntimes(runtimesJSON)).map(\.identifier)
        rule(old == ["A"], "only superseded, deletable simulator runtimes are offered")

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
