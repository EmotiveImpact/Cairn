import Foundation

/// The set of scanners Cairn runs, in display order: the developer wedge first,
/// then the general categories.
enum ScannerRegistry {
    static func all() -> [CairnScanner] {
        [
            // Developer (the wedge)
            DevProjectsScanner(),       // signature: whole-disk node_modules / target / .venv / Unity / Unreal / Flutter hunt
            DevCachesScanner(),         // npm/yarn/pnpm/pip/cargo/go/gradle/brew…
            XcodeScanner(),             // DerivedData, simulators, archives
            LanguageRuntimesScanner(),  // nvm/asdf/pyenv/conda versions
            IDECachesScanner(),         // VS Code / Cursor / JetBrains / Electron app caches
            DockerScanner(),            // graduated prune + Docker.raw advice
            GitMaintenanceScanner(),    // large .git (git gc) + abandoned-project detection
            AndroidSDKScanner(),        // system images, NDK, AVDs, build-tools
            ToolDownloadsScanner(),     // Playwright / Cypress / Puppeteer browsers, Electron, Bazel, Unity, Watchman, gems, old SDKs

            // AI Models & Caches (the novel pillar)
            AICachesScanner(),          // Ollama / HF / LM Studio / SD / Whisper models + Claude/Windsurf caches

            // Creative Pro
            CreativeCachesScanner(),    // Adobe / FCP / Motion / Logic / DaVinci / Topaz / CapCut caches + renders

            // General
            AppCachesScanner(),
            BrowserCachesScanner(),
            CommunicationCachesScanner(), // Zoom / Teams / Spotify / Figma app caches
            ChatAppsScanner(),          // WhatsApp / Telegram sizes, cleared in each app (advice)
            GamesScanner(),             // Steam / Epic / CrossOver games, and Mac games
            LogsScanner(),
            InstallersScanner(),
            LargeOldFilesScanner(),
            OrphanedAppDataScanner(),
            TimeMachineSnapshotsScanner(),
            TrashScanner(),
        ]
    }
}
