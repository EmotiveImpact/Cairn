import Foundation

/// Games installed by Steam, Epic and CrossOver live outside /Applications, so
/// they stay behind when the launcher is deleted. Mac games from the App Store
/// or a download are listed too, so the page shows every game.
///
/// While the launcher is installed, a game is advice only: the launcher's own
/// uninstall also forgets the game, where moving the folder would leave the
/// launcher thinking it is still there. A game whose launcher is gone can go to
/// the Bin after review. Nothing here is ever ticked for you.
struct GamesScanner: CairnScanner {
    let info = CategoryInfo(
        id: "games",
        title: "Games",
        subtitle: "Steam, Epic and CrossOver games, and games from the App Store",
        systemImage: "gamecontroller",
        group: .general,
        requiresFDA: false
    )

    /// Keys in ScanItem.detail, read by the Games page.
    enum Key {
        static let launcher = "launcher"        // "Steam", "Epic Games", "CrossOver", "App Store", "Download"
        static let lastPlayed = "lastPlayed"    // seconds since 1970, when known
        static let launcherGone = "launcherGone" // "1" when the launcher app is no longer installed
        static let uninstallURL = "uninstallURL" // a launcher link that uninstalls the game
        static let name = "name"
    }

    static let steamRoot = FileScan.home.appendingPathComponent("Library/Application Support/Steam")
    static let epicShared = URL(fileURLWithPath: "/Users/Shared/Epic Games")
    static let epicManifests = FileScan.home.appendingPathComponent("Library/Application Support/Epic/EpicGamesLauncher/Data/Manifests")
    static let crossOverBottles = FileScan.home.appendingPathComponent("Library/Application Support/CrossOver/Bottles")

    /// Steam libraries can sit on other drives; their games may go to the Bin
    /// from there too, once Steam is gone.
    var allowedRoots: [URL] {
        [FileScan.home, Self.epicShared] + Self.steamLibraries().map { $0.appendingPathComponent("steamapps/common") }
    }

    private static let maxFiles = 80_000

    func scan(_ ctx: ScanContext) async {
        scanSteam(ctx)
        if ctx.isCancelled() { return }
        scanEpic(ctx)
        if ctx.isCancelled() { return }
        scanCrossOver(ctx)
        if ctx.isCancelled() { return }
        scanMacGames(ctx)
    }

    // MARK: - Launchers

    static func installed(_ appName: String) -> Bool {
        ["/Applications", FileScan.home.appendingPathComponent("Applications").path].contains {
            FileScan.exists(URL(fileURLWithPath: $0).appendingPathComponent(appName))
        }
    }

    // MARK: - Steam

    /// Values from Valve's text format: `"key"  "value"` on one line.
    static func vdfValues(_ text: String, key: String) -> [String] {
        var values: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\"", omittingEmptySubsequences: true)
                .map { String($0) }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            if parts.count >= 2, parts[0].caseInsensitiveCompare(key) == .orderedSame {
                values.append(parts[1].replacingOccurrences(of: "\\\\", with: "\\"))
            }
        }
        return values
    }

    /// The main Steam folder plus any extra libraries listed in libraryfolders.vdf.
    static func steamLibraries() -> [URL] {
        var libraries = [steamRoot]
        let vdf = steamRoot.appendingPathComponent("steamapps/libraryfolders.vdf")
        if let text = try? String(contentsOf: vdf, encoding: .utf8) {
            for path in vdfValues(text, key: "path") {
                let url = URL(fileURLWithPath: path).standardizedFileURL
                if !libraries.contains(where: { $0.standardizedFileURL.path == url.path }) { libraries.append(url) }
            }
        }
        return libraries.filter { FileScan.exists($0.appendingPathComponent("steamapps")) }
    }

    private func scanSteam(_ ctx: ScanContext) {
        let libraries = Self.steamLibraries()
        guard !libraries.isEmpty else { return }
        ctx.progress("Steam games")
        let gone = !Self.installed("Steam.app")
        for library in libraries {
            let steamapps = library.appendingPathComponent("steamapps")
            let common = steamapps.appendingPathComponent("common")
            var listed = Set<String>()
            for manifest in (FileScan.children(of: steamapps) ?? []) where manifest.lastPathComponent.hasPrefix("appmanifest_") {
                if ctx.isCancelled() { return }
                guard let text = try? String(contentsOf: manifest, encoding: .utf8),
                      let folder = Self.vdfValues(text, key: "installdir").first else { continue }
                listed.insert(folder)
                let name = Self.vdfValues(text, key: "name").first ?? folder
                let appID = Self.vdfValues(text, key: "appid").first
                let played = Self.vdfValues(text, key: "LastPlayed").first.flatMap { Double($0) }.flatMap { $0 > 0 ? $0 : nil }
                emitGame(at: common.appendingPathComponent(folder), name: name, launcher: "Steam", gone: gone,
                         lastPlayed: played.map { Date(timeIntervalSince1970: $0) },
                         uninstallURL: appID.map { "steam://uninstall/\($0)" }, ctx: ctx)
            }
            // A folder no manifest lists is left over from an uninstall Steam did not finish.
            for folder in Self.subdirectories(of: common) where !listed.contains(folder.lastPathComponent) {
                if ctx.isCancelled() { return }
                emitGame(at: folder, name: folder.lastPathComponent, launcher: "Steam", gone: true,
                         lastPlayed: nil, uninstallURL: nil, ctx: ctx)
            }
        }
    }

    // MARK: - Epic

    private func scanEpic(_ ctx: ScanContext) {
        let gone = !Self.installed("Epic Games Launcher.app")
        var listed = Set<String>()
        for manifest in (FileScan.children(of: Self.epicManifests) ?? []) where manifest.pathExtension == "item" {
            if ctx.isCancelled() { return }
            guard let data = try? Data(contentsOf: manifest),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let location = json["InstallLocation"] as? String, !location.isEmpty else { continue }
            let folder = URL(fileURLWithPath: location).standardizedFileURL
            listed.insert(folder.path)
            ctx.progress("Epic games")
            let name = (json["DisplayName"] as? String) ?? folder.lastPathComponent
            let launch = (json["LaunchExecutable"] as? String).map { folder.appendingPathComponent($0) }
            emitGame(at: folder, name: name, launcher: "Epic Games", gone: gone,
                     lastPlayed: launch.flatMap(Self.lastUsed), uninstallURL: nil, ctx: ctx)
        }
        for folder in Self.subdirectories(of: Self.epicShared) where !listed.contains(folder.standardizedFileURL.path) {
            if ctx.isCancelled() { return }
            // The launcher's own files sit beside the games.
            if folder.lastPathComponent.hasPrefix("Launcher") || folder.lastPathComponent.hasPrefix("Epic") { continue }
            emitGame(at: folder, name: folder.lastPathComponent, launcher: "Epic Games", gone: true,
                     lastPlayed: nil, uninstallURL: nil, ctx: ctx)
        }
    }

    // MARK: - CrossOver

    /// Each CrossOver bottle is a small Windows install holding the games run in it.
    private func scanCrossOver(_ ctx: ScanContext) {
        let gone = !Self.installed("CrossOver.app")
        for bottle in Self.subdirectories(of: Self.crossOverBottles) {
            if ctx.isCancelled() { return }
            ctx.progress("CrossOver bottles")
            emitGame(at: bottle, name: bottle.lastPathComponent, launcher: "CrossOver", gone: gone,
                     lastPlayed: nil, uninstallURL: nil, ctx: ctx, bottle: true)
        }
    }

    // MARK: - Mac games

    /// Games in /Applications, by the category the developer set. App bundles
    /// are removed from the Apps page, so these are listed as advice.
    private func scanMacGames(_ ctx: ScanContext) {
        let folders = [URL(fileURLWithPath: "/Applications"), FileScan.home.appendingPathComponent("Applications")]
        for folder in folders {
            for app in (FileScan.children(of: folder) ?? []) where app.pathExtension == "app" {
                if ctx.isCancelled() { return }
                guard let plist = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
                      let category = plist["LSApplicationCategoryType"] as? String,
                      category.lowercased().contains("games") else { continue }
                ctx.progress("Mac games")
                let stats = FileScan.measure(app, maxFiles: Self.maxFiles)
                guard stats.allocatedSize >= ctx.minSizeBytes else { continue }
                let store = FileScan.exists(app.appendingPathComponent("Contents/_MASReceipt"))
                let name = (plist["CFBundleDisplayName"] as? String) ?? app.deletingPathExtension().lastPathComponent
                var item = ScanItem(
                    url: app, allocatedSize: stats.allocatedSize, itemCount: stats.fileCount,
                    latestModified: stats.latestModified, categoryID: info.id, severity: .review,
                    isRegenerable: false, cleanMethod: .adviceOnly,
                    note: "\(name), installed with the \(store ? "App Store" : "a download"). Remove it from Apps, which also finds its leftovers",
                    permissionDenied: stats.permissionDenied, volumeURL: FileScan.volumeURL(of: app), selected: false)
                item.detail = [Key.name: name, Key.launcher: store ? "App Store" : "Download"]
                if let used = Self.lastUsed(app) { item.detail[Key.lastPlayed] = String(Int(used.timeIntervalSince1970)) }
                ctx.emit(item)
            }
        }
    }

    // MARK: - Emitting

    private func emitGame(at folder: URL, name: String, launcher: String, gone: Bool, lastPlayed: Date?,
                          uninstallURL: String?, ctx: ScanContext, bottle: Bool = false) {
        guard FileScan.exists(folder), SafePaths.protectedSessionReason(folder) == nil else { return }
        let stats = FileScan.measure(folder, maxFiles: Self.maxFiles, maxDuration: 3)
        guard stats.allocatedSize >= ctx.minSizeBytes else { return }
        let what = bottle ? "CrossOver bottle \(name), with the Windows games and apps installed in it" : name
        let note: String
        if gone {
            note = "\(what). \(launcher) is no longer on this Mac, so this was left behind. You can download it again if you reinstall \(launcher)"
        } else if bottle {
            note = "\(what). Remove it in CrossOver, Bottle > Delete Bottle"
        } else {
            note = "\(name), installed with \(launcher). Uninstall it in \(launcher) so \(launcher) knows it is gone"
        }
        var item = ScanItem(
            url: folder, allocatedSize: stats.allocatedSize, itemCount: stats.fileCount,
            latestModified: stats.latestModified, categoryID: info.id, severity: .review,
            isRegenerable: false, cleanMethod: gone ? .trash : .adviceOnly, note: note,
            permissionDenied: stats.permissionDenied, volumeURL: FileScan.volumeURL(of: folder), selected: false)
        item.detail = [Key.name: name, Key.launcher: launcher]
        if gone { item.detail[Key.launcherGone] = "1" }
        if let uninstallURL, !gone { item.detail[Key.uninstallURL] = uninstallURL }
        if let played = lastPlayed ?? Self.lastUsed(folder) {
            item.detail[Key.lastPlayed] = String(Int(played.timeIntervalSince1970))
        }
        ctx.emit(item)
    }

    /// When Spotlight last saw the file or app opened, if it knows.
    static func lastUsed(_ url: URL) -> Date? {
        NSMetadataItem(url: url)?.value(forAttribute: "kMDItemLastUsedDate") as? Date
    }

    static func subdirectories(of dir: URL) -> [URL] {
        ToolDownloadsScanner.subdirectories(of: dir)
    }
}
