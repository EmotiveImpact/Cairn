# What Cairn looks for

Written from the scanners in the app. `cairn rules` prints the same list from any installed copy.

- Nothing is removed until you have reviewed it.
- Your own files go to the Bin, so you can put them back.
- Caches and build files that rebuild on their own are deleted, so the space comes back straight away. Settings can send them to the Bin instead.
- Every item is checked again against Cairn's protected list just before it moves: system files, credentials, Mail, Messages, Photos, iCloud, source code and AI conversation history are never touched.
- Apps that are still open keep their caches until you close them.

## Developer tools

- **Project Build Artifacts**: node_modules, Rust target, venvs, Pods, SwiftPM .build…
- **Developer Caches**: npm, yarn, pnpm, pip, cargo, go, gradle, Homebrew and more
- **Xcode & Simulators**: DerivedData, DeviceSupport, Archives, simulators, old runtimes & Xcode copies
- **Language Runtimes**: nvm, asdf, mise, pyenv, rbenv versions; conda envs & package cache
- **IDE & App Caches**: VS Code, Cursor, JetBrains, Slack, Discord, Notion caches
- **Docker**: Build cache, unused images, stopped containers, volumes
- **Git Maintenance**: Bloated .git histories & abandoned project roots
- **Android SDK & Emulators**: System images, NDK, AVDs, build-tools
- **Test Browsers & Build Tools**: Playwright, Cypress, Puppeteer, Electron, Bazel, Unity, Ruby gems

## AI tools

- **AI Model Stores & Caches**: Ollama, Hugging Face, PyTorch, LM Studio, Whisper, GPT4All, ComfyUI…

## Creative apps

- **Creative Caches**: Premiere/AE media cache, Final Cut, Resolve, Topaz, exports…

## Everyday Mac

- **Application Caches**: Per-app caches in ~/Library/Caches, which apps make again (needs Full Disk Access)
- **Browser Caches**: Safari, Chrome, Firefox, Brave, Arc, Edge, Opera web caches
- **Communication & App Caches**: Zoom, Teams, Spotify, Figma, Mail attachment copies
- **Chat apps**: WhatsApp and Telegram photos and videos
- **Games**: Steam, Epic and CrossOver games, and games from the App Store
- **Logs**: Stale application logs in ~/Library/Logs
- **Installers in Downloads**: Old .dmg / .pkg / .iso files in ~/Downloads
- **Large & Old Files**: Big or long-untouched files in Downloads, Desktop, Movies
- **Orphaned App Data**: Leftover data from apps that are no longer installed (needs Full Disk Access)
- **More App Caches**: Cache folders added by a cleaning rules update
- **Time Machine Snapshots**: Local APFS snapshots hiding inside opaque “System Data”
- **Trash**: Items already in the Trash, across all volumes
