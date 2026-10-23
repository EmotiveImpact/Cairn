import Foundation

/// Isolated fixtures only; no real user data, drives or settings are changed.
enum WorkspaceCheck {
    static func run() {
        var failures = 0
        func check(_ good: Bool, _ label: String) { print("\(good ? "PASS" : "FAIL") \(label)"); if !good { failures += 1 } }
        // Projects grouping: a monorepo's packages collapse to the repository,
        // a loose folder stands alone, and build output never dates activity.
        do {
            let fm = FileManager.default
            let root = fm.temporaryDirectory.appendingPathComponent("cairn-projects-\(UUID().uuidString)").standardizedFileURL
            defer { try? fm.removeItem(at: root) }
            let repo = root.appendingPathComponent("mono")
            let loose = root.appendingPathComponent("loose")
            try fm.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
            try fm.createDirectory(at: repo.appendingPathComponent("packages/web/node_modules"), withIntermediateDirectories: true)
            try fm.createDirectory(at: repo.appendingPathComponent("packages/api/node_modules"), withIntermediateDirectories: true)
            try fm.createDirectory(at: loose.appendingPathComponent(".venv"), withIntermediateDirectories: true)
            let old = Date(timeIntervalSinceNow: -120 * 86_400)
            fm.createFile(atPath: repo.appendingPathComponent(".git/HEAD").path, contents: Data("ref: refs/heads/main\n".utf8))
            try fm.setAttributes([.modificationDate: old], ofItemAtPath: repo.appendingPathComponent(".git/HEAD").path)
            fm.createFile(atPath: loose.appendingPathComponent("requirements.txt").path, contents: Data())
            let items = [
                ScanItem(url: repo.appendingPathComponent("packages/web/node_modules"), allocatedSize: 300, categoryID: ProjectIndex.categoryID, severity: .safe),
                ScanItem(url: repo.appendingPathComponent("packages/api/node_modules"), allocatedSize: 200, categoryID: ProjectIndex.categoryID, severity: .safe),
                ScanItem(url: loose.appendingPathComponent(".venv"), allocatedSize: 50, categoryID: ProjectIndex.categoryID, severity: .review, isRegenerable: false),
                ScanItem(url: root.appendingPathComponent("elsewhere/cache"), allocatedSize: 999, categoryID: "app-caches", severity: .safe),
            ]
            let projects = ProjectIndex.build(from: items, stopAt: root)
            let mono = projects.first { $0.url.path == repo.path }
            let single = projects.first { $0.url.path == loose.path }
            check(projects.count == 2, "Projects only group project build output")
            check(mono?.isRepository == true && mono?.items.count == 2 && mono?.rebuildableBytes == 500,
                  "Monorepo packages group under their repository")
            check(single?.isRepository == false && single?.rebuildableBytes == 0 && single?.measuredBytes == 50,
                  "A virtual environment without proof of rebuild is not counted as rebuildable")
            check((mono?.idleDays() ?? 0) >= 119, "Project activity comes from git metadata, not build output")
        } catch {
            check(false, "Projects fixture could not be created: \(error)")
        }
        // MCP: protocol shape and read-only tool surface, without scanning.
        let initialize = MCPServer.handle(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-06-18"]])
        check((initialize?["result"] as? [String: Any])?["protocolVersion"] as? String == "2025-06-18", "MCP initialize echoes the requested protocol")
        check(MCPServer.handle(["jsonrpc": "2.0", "method": "notifications/initialized"]) == nil, "MCP notifications get no response")
        let listed = ((MCPServer.handle(["jsonrpc": "2.0", "id": 2, "method": "tools/list"])?["result"] as? [String: Any])?["tools"] as? [[String: Any]]) ?? []
        let names = Set(listed.compactMap { $0["name"] as? String })
        check(names == ["storage_status", "list_projects", "find_reclaimable", "list_categories", "open_cairn"], "MCP lists only measuring and opening tools")
        check(!names.contains { $0.contains("clean") || $0.contains("delete") || $0.contains("remove") }, "MCP exposes no removal tool")
        let unknownTool = MCPServer.handle(["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": "empty_trash"]])?["result"] as? [String: Any]
        check(unknownTool?["isError"] as? Bool == true, "MCP refuses tools it does not offer")
        let badCategory = MCPServer.handle(["jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": ["name": "find_reclaimable", "arguments": ["category": "__no_such_category__"]] as [String: Any]])?["result"] as? [String: Any]
        check(badCategory?["isError"] as? Bool == true, "MCP rejects an unknown category before scanning")
        check(MCPServer.handle(["jsonrpc": "2.0", "id": 5, "method": "nope"])?["error"] != nil, "MCP reports unknown methods")
        check(CLI.readOnlyCommands == ["status", "scan", "categories", "projects", "mcp", "help", "--help", "-h"], "Only read-only CLI commands run beside the app")
        check(!CLI.readOnlyCommands.contains("clean"), "The clean command never runs beside the app")
        // Moves: copy, read back, link, remove; bring back; crash recovery; refusals.
        do {
            let fm = FileManager.default
            let root = fm.temporaryDirectory.appendingPathComponent("cairn-offload-\(UUID().uuidString)").standardizedFileURL
            defer { try? fm.removeItem(at: root) }
            let source = root.appendingPathComponent("home/models")
            let drive = root.appendingPathComponent("drive")
            let destination = drive.appendingPathComponent("Cairn Offload/models")
            try fm.createDirectory(at: source.appendingPathComponent("blobs"), withIntermediateDirectories: true)
            try fm.createDirectory(at: source.appendingPathComponent("snapshots/abc"), withIntermediateDirectories: true)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 7, count: 300_000).write(to: source.appendingPathComponent("blobs/sha256-a"))
            try Data("manifest".utf8).write(to: source.appendingPathComponent("manifest.json"))
            // A Hugging Face style link that stays inside the folder.
            try fm.createSymbolicLink(atPath: source.appendingPathComponent("snapshots/abc/weights").path, withDestinationPath: "../../blobs/sha256-a")
            try fm.setAttributes([.posixPermissions: 0o640], ofItemAtPath: source.appendingPathComponent("manifest.json").path)
            let cancel = CancelBox()
            let moved = try Relocation.offload(source: source, destination: destination, cancel: cancel, destinationValid: { true })
            check(moved.files.count == 2 && moved.bytes == 300_008 && moved.links.count == 1, "Move copies every file and inner link")
            check(Relocation.linkDestination(source) == destination.path, "Move leaves a link to the drive copy")
            check(!Relocation.exists(URL(fileURLWithPath: source.path + Relocation.movingSuffix)), "Move removes the original after the link checks out")
            check((try? Data(contentsOf: source.appendingPathComponent("manifest.json"))) == Data("manifest".utf8), "Apps still read moved files through the link")
            check((try? Data(contentsOf: source.appendingPathComponent("snapshots/abc/weights")))?.count == 300_000, "Links inside a moved folder still work")
            let perms = (try? fm.attributesOfItem(atPath: destination.appendingPathComponent("manifest.json").path))?[.posixPermissions] as? Int
            check(perms == 0o640, "Moves keep file permissions")
            check(!Relocation.exists(URL(fileURLWithPath: destination.path + Relocation.partialSuffix)), "No unfinished copy is left behind")
            let restored = try Relocation.restore(source: source, destination: destination, cancel: cancel, destinationValid: { true })
            check(Relocation.isRealDirectory(source) && restored.files.count == 2, "Bring back puts a real folder back")
            check(!Relocation.exists(destination), "Bring back removes the drive copy once the Mac copy matches")
            check(Relocation.linkDestination(source.appendingPathComponent("snapshots/abc/weights")) == "../../blobs/sha256-a", "Bring back keeps inner links as they were")
            // A crash after setting the original aside but before linking.
            let moving = URL(fileURLWithPath: source.path + Relocation.movingSuffix)
            try fm.moveItem(at: source, to: moving)
            check(Relocation.reconcile(source: source) == .interrupted && Relocation.isRealDirectory(source), "Recovery puts an interrupted original back")
            // A crash after the link, before removing the original: finish the move.
            _ = try Relocation.copyTree(from: source, to: destination, cancel: cancel, destinationValid: { true })
            try fm.moveItem(at: source, to: moving)
            try fm.createSymbolicLink(atPath: source.path, withDestinationPath: destination.path)
            check(Relocation.reconcile(source: source, destination: destination) == .offloaded && !Relocation.exists(moving)
                  && Relocation.linkDestination(source) == destination.path, "Recovery finishes a move whose drive copy matches")
            // Same crash, but the drive is gone: put the original back.
            _ = try Relocation.restore(source: source, destination: destination, cancel: cancel, destinationValid: { true })
            _ = try Relocation.copyTree(from: source, to: destination, cancel: cancel, destinationValid: { true })
            try fm.moveItem(at: source, to: moving)
            try fm.createSymbolicLink(atPath: source.path, withDestinationPath: destination.path)
            try fm.moveItem(at: destination, to: drive.appendingPathComponent("unplugged"))
            check(Relocation.reconcile(source: source, destination: destination) == .interrupted && Relocation.isRealDirectory(source),
                  "Recovery puts the original back when the drive copy cannot be checked")
            try fm.removeItem(at: drive.appendingPathComponent("unplugged"))
            // A second move must not replace an existing drive copy.
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            var refusedExisting = false
            do { _ = try Relocation.offload(source: source, destination: destination, cancel: cancel, destinationValid: { true }) }
            catch { refusedExisting = true }
            check(refusedExisting && Relocation.isRealDirectory(source), "A move never replaces an existing drive copy")
            try fm.removeItem(at: destination)
            // Links that point outside the folder are refused.
            try fm.createSymbolicLink(at: source.appendingPathComponent("escape"), withDestinationURL: root)
            var refusedLink = false
            do { _ = try Relocation.offload(source: source, destination: drive.appendingPathComponent("other"), cancel: cancel, destinationValid: { true }) }
            catch { refusedLink = true }
            check(refusedLink && Relocation.isRealDirectory(source) && !Relocation.exists(drive.appendingPathComponent("other")), "Moves refuse links that point outside")
            try fm.removeItem(at: source.appendingPathComponent("escape"))
            // Hard links would be split in two, so they are refused.
            try fm.linkItem(at: source.appendingPathComponent("manifest.json"), to: source.appendingPathComponent("twin.json"))
            var refusedHard = false
            do { _ = try Relocation.offload(source: source, destination: drive.appendingPathComponent("hard"), cancel: cancel, destinationValid: { true }) }
            catch { refusedHard = true }
            check(refusedHard && Relocation.isRealDirectory(source), "Moves refuse hard-linked files")
            try fm.removeItem(at: source.appendingPathComponent("twin.json"))
            var refusedMissing = false
            do { _ = try Relocation.offload(source: source, destination: drive.appendingPathComponent("gone"), cancel: cancel, destinationValid: { false }) }
            catch { refusedMissing = true }
            check(refusedMissing && Relocation.isRealDirectory(source) && !Relocation.exists(drive.appendingPathComponent("gone.partial")),
                  "A move stops when the drive disappears and leaves nothing half done")
            // The drive goes away part way through: the original stays, the partial is cleared.
            var calls = 0
            var refusedMidway = false
            do { _ = try Relocation.offload(source: source, destination: drive.appendingPathComponent("mid"), cancel: cancel,
                                            destinationValid: { calls += 1; return calls < 3 }) }
            catch { refusedMidway = true }
            check(refusedMidway && Relocation.isRealDirectory(source) && !Relocation.exists(drive.appendingPathComponent("mid"))
                  && !Relocation.exists(drive.appendingPathComponent("mid.partial")), "A drive pulled mid-move leaves the original and no partial")
            // A file written during the copy stops the move.
            let busyFile = source.appendingPathComponent("blobs/sha256-a")
            var refusedChange = false
            do { _ = try Relocation.offload(source: source, destination: drive.appendingPathComponent("changed"), cancel: cancel, destinationValid: {
                if let handle = try? FileHandle(forWritingTo: busyFile) { handle.seekToEndOfFile(); handle.write(Data([1])); try? handle.close() }
                return true
            }) } catch { refusedChange = true }
            check(refusedChange && Relocation.isRealDirectory(source) && !Relocation.exists(drive.appendingPathComponent("changed")),
                  "A file changing during the copy stops the move")
            // Your own single file: moved without a link, brought back.
            let video = root.appendingPathComponent("home/Movies/Trip.mov")
            try fm.createDirectory(at: video.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 3, count: 50_000).write(to: video)
            let videoCopy = drive.appendingPathComponent("Cairn Offload/From this Mac/Movies/Trip.mov")
            try fm.createDirectory(at: videoCopy.deletingLastPathComponent(), withIntermediateDirectories: true)
            _ = try Relocation.offload(source: video, destination: videoCopy, mode: .archive, cancel: cancel, destinationValid: { true })
            check(!Relocation.exists(video) && Relocation.isRegularFile(videoCopy), "Your own files move without a link")
            _ = try Relocation.restore(source: video, destination: videoCopy, mode: .archive, cancel: cancel, destinationValid: { true })
            check(Relocation.isRegularFile(video) && !Relocation.exists(videoCopy), "Your own files come back")
            check(RelocationTarget.own(video, home: root.appendingPathComponent("home"))?.driveFolder == "From this Mac/Movies/Trip.mov",
                  "Own files keep their folder layout on the drive")
            check(RelocationTarget.own(root.appendingPathComponent("home/Library/Mail"), home: root.appendingPathComponent("home")) == nil,
                  "Library folders are never offered as your own files")
            // A mostly empty disk image stays small on the drive.
            let disk = root.appendingPathComponent("home/Docker.raw")
            fm.createFile(atPath: disk.path, contents: nil)
            if let handle = try? FileHandle(forWritingTo: disk) { try handle.truncate(atOffset: 64 << 20); try handle.seek(toOffset: 8 << 20); handle.write(Data(repeating: 9, count: 4096)); try handle.close() }
            let diskCopy = drive.appendingPathComponent("Docker.raw")
            let digest = try Relocation.copyFile(disk, diskCopy, expected: nil, cancel: cancel)
            let allocated = (try? diskCopy.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? Int.max
            check(Relocation.readBackDigest(diskCopy, cancel: cancel) == digest && allocated < 16 << 20, "Mostly empty disk images stay small and match")
            // Rebuildable build files: nothing copied, future files go to the drive.
            let derived = root.appendingPathComponent("home/DerivedData")
            try fm.createDirectory(at: derived.appendingPathComponent("App-abc"), withIntermediateDirectories: true)
            let derivedOnDrive = drive.appendingPathComponent("Cairn Offload/xcode-derived-data")
            try Relocation.redirect(source: derived, destination: derivedOnDrive, destinationValid: { true })
            check(Relocation.linkDestination(derived) == derivedOnDrive.path && (try? fm.contentsOfDirectory(atPath: derivedOnDrive.path))?.isEmpty == true,
                  "Build files point at the drive without copying")
            try Relocation.unredirect(source: derived, destination: derivedOnDrive, destinationValid: { true })
            check(Relocation.isRealDirectory(derived) && !Relocation.exists(derivedOnDrive), "Build files come back to the Mac")
            check(Relocation.staysInside(link: "a/b/c", target: "../d") && !Relocation.staysInside(link: "a", target: "../x")
                  && !Relocation.staysInside(link: "a", target: "/etc"), "Inner links are judged correctly")
        } catch {
            check(false, "Move fixture failed: \(error)")
        }
        // iPhone backups: summary files only; old cloud copies compared by name and size.
        do {
            let fm = FileManager.default
            let root = fm.temporaryDirectory.appendingPathComponent("cairn-phone-\(UUID().uuidString)").standardizedFileURL
            defer { try? fm.removeItem(at: root) }
            let backup = root.appendingPathComponent("Backup/00008030-001A2B3C4D5E6F70")
            try fm.createDirectory(at: backup, withIntermediateDirectories: true)
            let info: [String: Any] = ["Device Name": "Edem's iPhone", "Product Type": "iPhone13,2", "Product Version": "17.4",
                                       "Last Backup Date": Date(timeIntervalSinceNow: -400 * 86_400)]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: backup.appendingPathComponent("Info.plist"))
            try PropertyListSerialization.data(fromPropertyList: ["IsEncrypted": true], format: .xml, options: 0).write(to: backup.appendingPathComponent("Manifest.plist"))
            try fm.createDirectory(at: root.appendingPathComponent("Backup/not-a-backup"), withIntermediateDirectories: true)
            let listing = PhoneBackups.list(root: root.appendingPathComponent("Backup"))
            let found = listing.backups.first
            check(listing.backups.count == 1 && found?.deviceName == "Edem's iPhone" && found?.model == "iPhone 12"
                  && found?.passwordProtected == true && found?.isOld == true, "iPhone backups show device, model, date and password")
            check(found?.target.mode == .archive && found?.target.privateFiles == false, "Password-protected backups move as archives without a warning")
            check(PhoneBackups.friendlyModel("iPad13,1") == "iPad" && PhoneBackups.friendlyModel("x") == "iPhone", "Unknown models read as plain names")
            let old = root.appendingPathComponent("home/Dropbox (Old)")
            let live = root.appendingPathComponent("home/Library/CloudStorage/Dropbox")
            try fm.createDirectory(at: old.appendingPathComponent("Work"), withIntermediateDirectories: true)
            try fm.createDirectory(at: live.appendingPathComponent("Work"), withIntermediateDirectories: true)
            try Data(repeating: 1, count: 100).write(to: old.appendingPathComponent("Work/a.txt"))
            try Data(repeating: 1, count: 100).write(to: live.appendingPathComponent("Work/a.txt"))
            try Data(repeating: 2, count: 50).write(to: old.appendingPathComponent("Work/only-here.txt"))
            let spares = CloudSpace.oldSyncFolders(home: root.appendingPathComponent("home"), live: [("Dropbox", "Dropbox", live)])
            check(spares.count == 1 && spares.first?.onlyHere == 1, "Old sync folders count files that exist only there")
            check(CloudSpace.providerName("GoogleDrive-me@example.com") == "Google Drive" && CloudSpace.providerName("OneDrive-Personal") == "OneDrive",
                  "Cloud folders get plain names")
            let gone = root.appendingPathComponent("Volumes/Studio SSD/Cairn Offload/models").path
            func moved(_ id: String, _ title: String, _ status: RelocationRecord.Status, _ mode: Relocation.Mode, _ destination: String) -> RelocationRecord {
                RelocationRecord(targetID: id, source: "/x/\(id)", destination: destination, volumeID: "V", volumeName: "Studio SSD",
                                 status: status, detail: "", mode: mode, title: title)
            }
            let away = RelocationStore.away([
                moved("ollama-models", "Ollama models", .offloaded, .linkBack, gone),
                moved("ollama-models", "Ollama models", .restored, .linkBack, gone),
                moved("xcode-derived-data", "Xcode build files", .offloaded, .freshOnDrive, gone),
                moved("own:a", "Films", .offloaded, .archive, gone),
                moved("lmstudio-models", "LM Studio models", .offloaded, .linkBack, root.path),
            ])
            check(away.map(\.title) == ["Ollama models", "Xcode build files"], "Menu counts only linked moves whose drive is away")
            check(MenuGuardian.awayTitle(away) == "Studio SSD holds Ollama models and 1 more" && MenuGuardian.awayTitle([]) == nil,
                  "Menu names the drive to plug in")
        } catch {
            check(false, "Phone and cloud fixture failed: \(error)")
        }
        // AI tool connections: only the cairn entry changes, and unreadable files are left alone.
        do {
            let fm = FileManager.default
            let home = fm.temporaryDirectory.appendingPathComponent("cairn-agents-\(UUID().uuidString)").standardizedFileURL
            defer { try? fm.removeItem(at: home) }
            let tools = AgentTool.all(home: home)
            func tool(_ id: String) -> AgentTool { tools.first { $0.id == id }! }
            let command = "/Applications/Cairn.app/Contents/MacOS/Cairn"
            check(AgentConnections.state(tool("cursor"), command: command) == .notInstalled, "Missing AI tools show as not installed")
            let cursor = tool("cursor")
            try fm.createDirectory(at: cursor.marker, withIntermediateDirectories: true)
            try Data(#"{"mcpServers":{"other":{"command":"x"}},"theme":"dark"}"#.utf8).write(to: cursor.config)
            check(AgentConnections.state(cursor, command: command) == .available, "An installed AI tool can be connected")
            try AgentConnections.connect(cursor, command: command)
            let written = AgentConnections.readJSON(cursor.config) ?? [:]
            let servers = written["mcpServers"] as? [String: Any] ?? [:]
            check(servers["other"] != nil && written["theme"] as? String == "dark", "Connecting keeps the tool's other settings")
            check((servers["cairn"] as? [String: Any])?["args"] as? [String] == ["mcp"], "Connecting adds the cairn mcp entry")
            check(fm.fileExists(atPath: cursor.config.path + AgentConnections.backupSuffix), "Connecting keeps a backup of the original file")
            check(AgentConnections.state(cursor, command: command) == .connected(current: true), "A connected tool reads as connected")
            check(AgentConnections.state(cursor, command: "/elsewhere/Cairn") == .connected(current: false), "An entry for another copy reads as out of date")
            try AgentConnections.disconnect(cursor)
            let after = AgentConnections.readJSON(cursor.config) ?? [:]
            check((after["mcpServers"] as? [String: Any])?["cairn"] == nil && (after["mcpServers"] as? [String: Any])?["other"] != nil, "Disconnecting removes only the cairn entry")
            let vscode = tool("vscode")
            try fm.createDirectory(at: vscode.marker, withIntermediateDirectories: true)
            try AgentConnections.connect(vscode, command: command)
            let vsEntry = (AgentConnections.readJSON(vscode.config)?["servers"] as? [String: Any])?["cairn"] as? [String: Any]
            check(vsEntry?["type"] as? String == "stdio", "VS Code gets its servers key and stdio type")
            let gemini = tool("gemini")
            try fm.createDirectory(at: gemini.marker, withIntermediateDirectories: true)
            let commented = Data("// my settings\n{\"a\": 1}".utf8)
            try commented.write(to: gemini.config)
            var refusedComments = false
            do { try AgentConnections.connect(gemini, command: command) } catch { refusedComments = true }
            check(refusedComments && (try? Data(contentsOf: gemini.config)) == commented, "Settings with comments are left untouched")
            if case .unreadable = AgentConnections.state(gemini, command: command) { check(true, "Unparseable settings are reported, not edited") }
            else { check(false, "Unparseable settings are reported, not edited") }
            let codex = tool("codex")
            try fm.createDirectory(at: codex.marker, withIntermediateDirectories: true)
            let toml = "model = \"o4\"\n\n[mcp_servers.other]\ncommand = \"x\"\n"
            try Data(toml.utf8).write(to: codex.config)
            try AgentConnections.connect(codex, command: command)
            try AgentConnections.connect(codex, command: command)
            let codexText = (try? String(contentsOf: codex.config, encoding: .utf8)) ?? ""
            check(codexText.components(separatedBy: "[mcp_servers.cairn]").count == 2 && codexText.contains("[mcp_servers.other]"), "Codex gets one cairn table beside its others")
            check(AgentConnections.state(codex, command: command) == .connected(current: true), "Codex reads as connected")
            try AgentConnections.disconnect(codex)
            check((try? String(contentsOf: codex.config, encoding: .utf8)) == toml, "Disconnecting Codex restores its settings exactly")
            var refusedClaude = false
            do { try AgentConnections.connect(tool("claude-code"), command: command, claudeBinary: nil) } catch { refusedClaude = true }
            check(refusedClaude && !fm.fileExists(atPath: tool("claude-code").config.path), "Claude Code settings are never written directly")
        } catch {
            check(false, "AI tool connection fixture failed: \(error)")
        }
        let today = Calendar.current.startOfDay(for: Date())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let oldDay = Calendar.current.date(byAdding: .day, value: -8, to: today)!
        let history = [StorageHistory.Sample(date: yesterday, freeBytes: 20_000_000_000)]
        check(MenuStorageSummary.change(current: nil, samples: history).contains("still building"), "Missing capacity does not become zero space")
        check(MenuStorageSummary.change(current: 10_000_000_000, samples: history).contains("less since yesterday"), "Menu growth uses a prior calendar day")
        check(MenuStorageSummary.change(current: 30_000_000_000, samples: history).contains("more since yesterday"), "Menu free-space increase keeps its direction")
        check(!MenuStorageSummary.change(current: 10_000_000_000, samples: [.init(date: oldDay, freeBytes: 20_000_000_000)]).contains("yesterday"), "Older history is not labelled yesterday")
        check(MenuStorageSummary.change(current: 10_000_000_000, samples: [.init(date: today, freeBytes: 20_000_000_000)]).contains("still building"), "Same-day history does not invent a daily change")
        let identifiedHistory = [CapacityReading(date: yesterday, volumeID: "internal-A", available: 20_000_000_000, total: 500_000_000_000)]
        check(MenuStorageSummary.change(current: 10_000_000_000, volumeID: "internal-A", readings: identifiedHistory).contains("less"), "Menu compares matching-volume capacity")
        check(MenuStorageSummary.change(current: 10_000_000_000, volumeID: "internal-B", readings: identifiedHistory).contains("still building"), "Menu refuses a replacement volume's history")
        check(MenuAvailableSpace.title(nil, checked: false) == "…" && MenuAvailableSpace.title(nil, checked: true) == "—",
              "Menu bar does not turn an unavailable capacity reading into zero")
        check(MenuAvailableSpace.title(42_600_000_000, checked: true).contains("GB"),
              "Menu bar labels measured available capacity with a size unit")
        check(MenuScanStatus().canStart, "Idle menu allows an explicit scan")
        check(MenuGuardian.readyTitle(50_000_000) == nil && MenuGuardian.readyTitle(2_000_000_000)?.contains("ready to free") == true,
              "Menu offers a review only when the latest results hold meaningful rebuildable space")
        check(MenuGuardian.growthTitle(nil) == nil, "Menu shows no growth nudge without an opted-in suggestion")
        check(MenuGuardian.idleProjectsTitle([]) == nil, "Menu shows no project nudge without idle projects")
        check(!MenuScanStatus(scanning: true).canStart && !MenuScanStatus(operationBusy: true).canStart && !MenuScanStatus(otherScanBusy: true).canStart, "Menu blocks overlapping operations")
        let chartStart = Date(timeIntervalSince1970: 100)
        let chartReadings = [0.0, 3600.0, 28 * 3600.0, 29 * 3600.0].map {
            CapacityReading(date: chartStart.addingTimeInterval($0), volumeID: "chart-fixture", available: 1_000, total: 10_000)
        }
        let chart = CapacityPlot(readings: chartReadings, maximumInterval: 8 * 3600)
        check(chart.points.map(\.segment) == [0, 0, 1, 1] && chart.gaps.count == 1,
              "Capacity chart retains a missing interval as separate measured segments")
        check(chart.reading(near: chartStart.addingTimeInterval(12 * 3600)) == nil && chart.gap(at: chartStart.addingTimeInterval(12 * 3600)) != nil,
              "Hovering an unmeasured gap cannot claim a distant sample")
        check(chart.reading(near: chartReadings[1].date)?.id == chartReadings[1].id && chart.reading(near: chartReadings[2].date)?.id == chartReadings[2].id,
              "Capacity readings at both gap boundaries remain inspectable")
        check(chart.gaps.first?.before.id == chartReadings[1].id && chart.gaps.first?.after.id == chartReadings[2].id && chart.points.count == chartReadings.count,
              "Gap connectors use saved endpoints without adding synthetic readings")
        // Scan comparison must never turn missing or incompatible data into savings.
        let scope = ScanComparison.Scope(categories: ["a"], exclusions: [], developerCaches: true,
                                         simulators: true, fullDiskAccess: true, externalVolumes: false)
        let baseline = ScanComparison.Reading(date: Date(timeIntervalSince1970: 100), scope: scope, complete: true,
            buckets: [.init(id: "a", title: "Build output", icon: "hammer", group: .developer, bytes: 100)])
        var later = baseline; later.date = Date(timeIntervalSince1970: 200); later.buckets[0].bytes = 175
        check(ScanComparison.compare([baseline, later]).changes.first?.delta == 75, "Compatible scan growth is measured")
        later.buckets[0].bytes = 60
        check(ScanComparison.compare([baseline, later]).changes.first?.delta == -40, "Category decreases retain their sign")
        later.buckets[0].bytes = 100
        check(ScanComparison.compare([baseline, later]).comparable && ScanComparison.compare([baseline, later]).changes.isEmpty, "Unchanged categories are not invented changes")
        check(!ScanComparison.compare([baseline]).comparable, "First scan waits for a baseline pair")
        later.complete = false
        check(!ScanComparison.compare([baseline, later]).comparable, "Incomplete scans cannot be compared")
        later.complete = true; later.scope.exclusions = ["/example"]
        check(!ScanComparison.compare([baseline, later]).comparable, "Different exclusions block comparison")
        later.scope = scope; later.buckets = []
        check(!ScanComparison.compare([baseline, later]).comparable, "Missing category is not zero bytes")
        later = baseline; later.date = Date(timeIntervalSince1970: 200); later.buckets.append(later.buckets[0])
        check(!ScanComparison.compare([baseline, later]).comparable, "Duplicate saved category IDs are rejected without a crash")
        var limited = baseline; limited.scope.fullDiskAccess = false
        later = limited; later.date = Date(timeIntervalSince1970: 200)
        check(!ScanComparison.compare([limited, later]).comparable, "Limited-access scans do not imply complete coverage")
        var external = baseline; external.scope.externalVolumes = true
        later = external; later.date = Date(timeIntervalSince1970: 200)
        check(!ScanComparison.compare([external, later]).comparable, "External-drive comparisons withheld until drive scope is tracked")
        check(!ScanComparison.compare([baseline, baseline]).comparable, "Equal measurement times cannot be compared")
        let candidateA = CandidateReading.Category(id: "a", title: "Build output", icon: "hammer", group: .developer, bytes: 100, complete: true)
        let candidateB = CandidateReading.Category(id: "b", title: "Browser caches", icon: "globe", group: .general, bytes: 200, complete: false)
        let candidateScope = ScanComparison.Scope(categories: ["a", "b"], exclusions: [], developerCaches: true, simulators: true, fullDiskAccess: false, externalVolumes: false)
        let candidateBefore = CandidateReading(date: Date(timeIntervalSince1970: 100), volumeID: "internal-A", scope: candidateScope, categories: [candidateA, candidateB])
        let candidateAfter = CandidateReading(date: Date(timeIntervalSince1970: 200), volumeID: "internal-A", scope: candidateScope, categories: [
            .init(id: "a", title: "Build output", icon: "hammer", group: .developer, bytes: 175, complete: true),
            .init(id: "b", title: "Browser caches", icon: "globe", group: .general, bytes: 500, complete: false)
        ])
        check(CandidateComparison.changes([candidateBefore, candidateAfter]).map(\.delta) == [75], "Partial candidate scan compares only complete categories")
        check(CandidateComparison.changes([candidateBefore, .init(date: Date(timeIntervalSince1970: 200), volumeID: "internal-B", scope: candidateScope, categories: candidateAfter.categories)]).isEmpty, "Candidate comparison refuses another volume")
        var changedScope = candidateScope; changedScope.exclusions = ["/example"]
        check(CandidateComparison.changes([candidateBefore, .init(date: Date(timeIntervalSince1970: 200), volumeID: "internal-A", scope: changedScope, categories: candidateAfter.categories)]).isEmpty, "Candidate comparison refuses changed exclusions")
        check(SpaceGoal.shortfall(available: 12_000_000_000, target: 30_000_000_000) == 18_000_000_000, "Goal calculates measured shortfall")
        check(SpaceGoal.shortfall(available: nil, target: 30_000_000_000) == nil && !SpaceGoal.reached(available: nil, target: 30_000_000_000), "Unknown capacity never meets a goal")
        check(SpaceGoal.shortfall(available: 12_000_000_000, target: 30_000_000_000) == 18_000_000_000 && !SpaceGoal.reached(available: 12_000_000_000, target: 30_000_000_000), "Candidate or Trash file sizes never credit an unmeasured goal")
        check(SpaceGoal.reached(available: 31_000_000_000, target: 30_000_000_000), "Already-met goal needs no cleanup")
        let beforeManual = CapacityReading(date: Date(timeIntervalSince1970: 100), volumeID: "internal-A", available: 12_000_000_000, total: 500_000_000_000)
        let afterManual = CapacityReading(date: Date(timeIntervalSince1970: 200), volumeID: "internal-A", available: 18_000_000_000, total: 500_000_000_000)
        check(SpaceGoal.observedChange(from: beforeManual, to: afterManual) == 6_000_000_000 &&
              SpaceGoal.shortfall(available: afterManual.available, target: 30_000_000_000) == 12_000_000_000,
              "A manual capacity increase updates the remaining goal without attributing the cause")
        check(SpaceGoal.observedChange(from: beforeManual, to: .init(date: Date(timeIntervalSince1970: 200), volumeID: "internal-B", available: 18_000_000_000, total: 500_000_000_000)) == nil,
              "A replacement volume cannot create false manual progress")
        check(SpaceGoal.observedChange(from: beforeManual, to: .init(date: Date(timeIntervalSince1970: 200), volumeID: "internal-A", available: 8_000_000_000, total: 500_000_000_000)) == -4_000_000_000,
              "A capacity decrease remains negative after a manual recheck")
        check(SpaceGoal.observedChange(from: afterManual, to: beforeManual) == nil,
              "An older reading cannot reverse the manual progress baseline")
        check(CapacitySeries.visible(stored: [beforeManual], current: afterManual).map(\.available) == [12_000_000_000, 18_000_000_000],
              "A fresh Finder return reading appears before the five-minute archive interval")
        check(CapacitySeries.visible(stored: [beforeManual], current: .init(date: Date(timeIntervalSince1970: 200), volumeID: "internal-B", available: 18_000_000_000, total: 500_000_000_000)).count == 1,
              "Visible capacity history does not connect different internal volumes")
        let firstLow = CapacityReading(date: Date(timeIntervalSince1970: 100), volumeID: "internal-A", available: 12_000_000_000, total: 500_000_000_000)
        let secondLow = CapacityReading(date: Date(timeIntervalSince1970: 500), volumeID: "internal-A", available: 11_000_000_000, total: 500_000_000_000)
        check(ReserveAlertPolicy.decide(current: secondLow, previous: firstLow, target: 30_000_000_000, alreadyAlerted: false) == .alert,
              "Reserve alert needs two spaced low readings")
        check(ReserveAlertPolicy.decide(current: secondLow, previous: firstLow, target: 30_000_000_000, alreadyAlerted: true) == .unchanged,
              "Already-sent reserve alert does not repeat")
        check(ReserveAlertPolicy.decide(current: secondLow, previous: .init(date: Date(timeIntervalSince1970: 300), volumeID: "internal-A", available: 12_000_000_000, total: 500_000_000_000), target: 30_000_000_000, alreadyAlerted: false) == .unchanged,
              "Rapid low readings do not trigger an alert storm")
        check(ReserveAlertPolicy.decide(current: secondLow, previous: .init(date: Date(timeIntervalSince1970: 100), volumeID: "internal-B", available: 12_000_000_000, total: 500_000_000_000), target: 30_000_000_000, alreadyAlerted: false) == .unchanged,
              "Another volume cannot confirm a reserve alert")
        check(ReserveAlertPolicy.decide(current: .init(date: Date(timeIntervalSince1970: 900), volumeID: "internal-A", available: 33_000_000_000, total: 500_000_000_000), previous: secondLow, target: 30_000_000_000, alreadyAlerted: true) == .clear,
              "Reserve alert re-arms only after hysteresis")
        let growthNow = Date(timeIntervalSince1970: 2_000_000)
        let growthRoot = ObservedRoot(id: "npm-cache", title: "npm package cache", path: "/fixture/.npm/_cacache", icon: "shippingbox", observationOnly: false)
        func growthReading(_ size: Int64, at date: Date, coverage: LocationCoverage = .complete, volume: String = "internal-A") -> LocationReading {
            LocationReading(id: UUID(), root: growthRoot, started: date.addingTimeInterval(-2), ended: date,
                volumeID: volume, identity: .init(device: 1, inode: 2), parentIdentity: .init(device: 1, inode: 1),
                scope: "fixture-scope", coverage: coverage, allocated: size, logical: size, entries: 2,
                hardLinksSkipped: 0, source: "fixture", metric: "allocated-and-logical-v1", adapterVersion: 1)
        }
        let growthBefore = growthReading(1_000_000_000, at: growthNow.addingTimeInterval(-3_600))
        let growthAfter = growthReading(2_500_000_000, at: growthNow)
        let growthPair = LocationComparison.changes([growthBefore, growthAfter])
        check(GrowthSuggestions.evaluate(growthPair, selectedIDs: ["npm-cache"], minimumBytes: 1_000_000_000, now: growthNow).map(\.id) == ["npm-cache"],
              "Selected, recent compatible growth produces an inspection suggestion")
        check(GrowthSuggestions.evaluate(growthPair, selectedIDs: [], minimumBytes: 1_000_000_000, now: growthNow).isEmpty &&
              GrowthSuggestions.evaluate(growthPair, selectedIDs: ["npm-cache"], minimumBytes: 2_000_000_000, now: growthNow).isEmpty,
              "Unselected or below-threshold growth produces no suggestion")
        check(GrowthSuggestions.evaluate(growthPair, selectedIDs: ["npm-cache"], minimumBytes: 1_000_000_000, now: growthNow.addingTimeInterval(8 * 86_400)).isEmpty,
              "Stale growth is not presented as a current suggestion")
        check(LocationComparison.changes([growthBefore, growthReading(3_000_000_000, at: growthNow, coverage: .partial)]).isEmpty &&
              LocationComparison.changes([growthBefore, growthReading(3_000_000_000, at: growthNow, volume: "internal-B")]).isEmpty,
              "Incomplete or replacement-volume readings cannot arm a rule")
        check(StorageDrive.uniqueIdentity("drive-A", mountedIDs: ["drive-A", "drive-B"]) &&
              !StorageDrive.uniqueIdentity("drive-A", mountedIDs: ["drive-A", "drive-A"]) &&
              !StorageDrive.uniqueIdentity("", mountedIDs: [""]),
              "Missing and duplicate external-drive identities are ineligible")
        var ambiguousDrive = StorageDrive(url: URL(fileURLWithPath: "/fixture/drive"), name: "Fixture", uuid: "drive-A",
            capacity: 10_000, available: 5_000, external: true, writable: true, encrypted: true, format: "apfs")
        ambiguousDrive.identityAmbiguous = true
        check(!ambiguousDrive.acceptsCopy && ambiguousDrive.exportStatus.contains("Duplicate"),
              "Ambiguous mounted drive cannot be presented as export-ready")
        check(NpmCacheInspection.parse("/Users/fixture/.npm\n") == "/Users/fixture/.npm" &&
              NpmCacheInspection.parse("undefined\n") == nil &&
              NpmCacheInspection.parse("/one\n/two\n") == nil &&
              NpmCacheInspection.parse("/tmp/../other") == nil,
              "npm cache inspection accepts one canonical absolute path only")
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("cairn-workspace-check-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: false)
            defer { try? fm.removeItem(at: root) }
            let source = root.appendingPathComponent("export.zip")
            let original = Data((0..<(3 * 1024 * 1024)).map { UInt8($0 % 251) })
            try original.write(to: source)
            let eligiblePlanItem = ScanItem(url: source, allocatedSize: 1, categoryID: "fixture", severity: .safe)
            let blockedPlanItems = (0..<120).map { index in
                ScanItem(url: root.appendingPathComponent("missing-\(index)"), allocatedSize: 1_000_000,
                         categoryID: "fixture", severity: .safe)
            }
            let planOptions = MakeRoomCandidates.select(blockedPlanItems + [eligiblePlanItem], isExcluded: { _ in false })
            check(planOptions.map(\.id) == [eligiblePlanItem.id],
                  "Blocked large findings cannot hide a valid plan option beyond the old display cap")
            let cancel = CancelBox()
            let result = try ArchiveCopy.copy(source: source, directory: root.appendingPathComponent("complete"), cancel: cancel, destinationValid: { true }, progress: { _ in })
            check(try Data(contentsOf: result.0) == original, "Full copy content matches")
            check(try Data(contentsOf: source) == original, "Original retained unchanged")
            check(result.1 == original.count && result.2.count == 64, "Byte count and SHA-256 recorded")
            let permissions = try fm.attributesOfItem(atPath: result.0.path)[.posixPermissions] as? NSNumber
            check(permissions?.intValue == 0o600, "Export has private file permissions")
            let stopped = CancelBox(); stopped.cancel()
            do { _ = try ArchiveCopy.copy(source: source, directory: root.appendingPathComponent("cancelled"), cancel: stopped, destinationValid: { true }, progress: { _ in }); check(false, "Cancelled copy rejected") }
            catch { check(!fm.fileExists(atPath: root.appendingPathComponent("cancelled").path), "Cancelled copy creates no destination") }
            do { _ = try ArchiveCopy.copy(source: source, directory: root.appendingPathComponent("missing-drive"), cancel: cancel, destinationValid: { false }, progress: { _ in }); check(false, "Missing drive rejected") }
            catch { check(true, "Missing or different drive rejected") }
            let link = root.appendingPathComponent("link.zip")
            try fm.createSymbolicLink(at: link, withDestinationURL: source)
            do { try ArchiveCopy.validateSource(link); check(false, "Symbolic link rejected") } catch { check(true, "Symbolic link rejected") }
            let database = root.appendingPathComponent("live.sqlite")
            try Data("database".utf8).write(to: database)
            do { try ArchiveCopy.validateSource(database); check(false, "Database rejected") } catch { check(true, "Database rejected") }
            do { try ArchiveCopy.validateSource(root); check(false, "Directory rejected") } catch { check(true, "Directory rejected") }
            let interrupted = CancelBox()
            let partialDir = root.appendingPathComponent("interrupted")
            do { _ = try ArchiveCopy.copy(source: source, directory: partialDir, cancel: interrupted, destinationValid: { true }, progress: { _ in interrupted.cancel() }); check(false, "Mid-copy cancellation rejected") }
            catch { check(!fm.fileExists(atPath: partialDir.appendingPathComponent("export.zip").path), "Interrupted copy is never marked complete") }
            check(try Data(contentsOf: source) == original, "Cancellation preserves original")
            do { _ = try ArchiveCopy.copy(source: source, directory: root.appendingPathComponent("complete"), cancel: cancel, destinationValid: { true }, progress: { _ in }); check(false, "Existing destination protected") }
            catch { check(try Data(contentsOf: result.0) == original, "Existing destination is never overwritten") }
        } catch { check(false, "Fixture error: \(error.localizedDescription)") }
        print("Workspace checks: \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
