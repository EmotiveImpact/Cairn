# Cairn — Features & Functions

Status of the native SwiftUI macOS app as built. ✅ = implemented & compiling. 🔲 = not yet.

## 1. Cleaning coverage — 17 scanners across 4 pillars

### Developer ✅
- **Dev-Project Explorer** (whole-disk + opt-in external volumes): `node_modules` (with regenerability check), Rust `target/`, Python `.venv`/`venv`, CocoaPods `Pods/`, SwiftPM `.build/`, **Unity** (`Library`/`Temp`/`Logs`/`obj`), **Unreal** (`Saved`/`Intermediate`/`DerivedDataCache`), **Flutter** (`build`/`.dart_tool`).
- **Developer Caches**: npm, Yarn (classic + Berry), pnpm store (prune), Bun, pip, uv, Poetry, Cargo (registry + git), Go (module cache via `go clean`, build cache), Gradle (caches + wrapper dists), Maven, Ivy, CocoaPods, Carthage, SwiftPM, ccache, Composer, Homebrew, Deno, NuGet.
- **Xcode & Simulators**: DerivedData (per workspace), iOS/watchOS/tvOS DeviceSupport, Archives (advice — never auto-deleted), CoreSimulator caches, unavailable simulator devices (via `xcrun simctl delete unavailable`).
- **Language Runtimes**: nvm / asdf / mise / pyenv / rbenv installed versions, conda envs + package cache (`conda clean`).
- **IDE & App Caches**: VS Code, Cursor, JetBrains caches/logs, Electron apps (Slack, Discord, Notion).
- **Docker**: graduated prune options (build cache → unused images → stopped containers → full `--volumes` as RISKY typed-confirm), `Docker.raw` advice; only when the daemon is running.
- **Git Maintenance**: large `.git` folders (compacted with `git gc --prune=now`), abandoned-project detection (last touched > 6 months).

### AI Models & Caches ✅ (the novel pillar)
- Model stores (REVIEW — expensive to re-download): Ollama, Hugging Face hub, PyTorch hub, LM Studio, Whisper, GPT4All, Stable Diffusion / ComfyUI, sentence-transformers / CLIP.
- App caches (SAFE): Claude desktop, Windsurf.

### Creative Pro ✅
- Adobe media cache (Premiere/After Effects), After Effects disk cache, Final Cut / Motion / Compressor / Logic caches, Topaz, CapCut, DaVinci Resolve render cache.
- Stray **screen recordings** on Desktop, **large video exports** in Movies, Final Cut render-files advice.

### General ✅
- App caches (`~/Library/Caches`), browser caches (Safari/Chrome/Firefox/Brave/Arc/Edge/Opera), old logs, old installers (`.dmg`/`.pkg`/`.iso`), large/old files, orphaned app data (uninstalled apps), Time Machine local snapshots (`tmutil thin`), Trash (all volumes).

## 2. Scan engine ✅
- One-pass sizing on **on-disk allocated bytes**; skips symlinks and iCloud “dataless” files; tracks permission gaps.
- All scanners run **concurrently**, streaming results live to the UI (results appear as found).
- Whole-disk hunt is a bounded directory-only DFS with parallel, file-capped sizing (fast + cancellable).
- Per-volume free space (APFS purgeable-aware); volume-aware Trash.
- External CLI tools resolved via the login-shell PATH (finds nvm/asdf/corepack shims), with timeouts + cancellation.

## 3. Safety model ✅
- **Single delete chokepoint** (`SafePaths`): symlink-resolve → per-scanner allowlist-of-roots → global denylist (System/Library/Keychains/Mail/Messages/Photos/MobileSync/Xcode Archives…) → strict-descendant check.
- **Computed severity**: SAFE (pre-checked) / REVIEW (unchecked) / RISKY (locked, per-item confirm).
- **Regenerability check** for `node_modules`/envs: workspace lockfiles, npm-link, `file:` deps, patch-package → downgrades to REVIEW when uncertain.
- **Running-app guard**: blocks cleaning caches owned by a live app (Xcode, Docker, editors) with a quit-first prompt.
- **Trash-by-default** (`FileManager.trashItem`) with **Undo/Restore**; correct tool per target (no blind `rm`); permanent removal only for items already in Trash.
- **Full Disk Access** detection (probes genuinely TCC-gated paths) + onboarding deep link; honest "(partial size)" when blocked.

## 4. Interface ✅
- Animated scan hero (rotating gradient rings, pulsing core, live count-up "reclaimable — and counting…").
- Sidebar grouped by the 4 pillars with per-category sizes + live progress; running grand total.
- Category detail: item rows with severity dots, gated checkboxes, badges (`PRO·TOOL`, `REVIEW`, `RISKY`, `QUIT <app>`, `PARTIAL`, `ADVICE`), Select-safe / None, FDA banner.
- **Per-item ⓘ preview popover**: what it is, why it exists, rebuildable?, risk, last used, created-by app, size, action, path, Reveal in Finder.
- **Review & Clean** dry-run sheet: item list, quit-first warnings, Pro-gating note, destructive typed-confirm, free-space-after-Empty projection, recoverable framing.
- Bottom action bar (selected count/size), success **undo toast**.
- **Space Missions** bar: Free 10 GB Fast, Clean Developer Junk, Clean AI Models, Clean Creator Cache, Find Forgotten Giants, Prepare for Update, Prepare for Travel, Emergency Free Space.
- **Transparency panel** (ⓘ): What's New · Bugs & Fixes · Safety.
- Free-space readout, Rescan / Stop, dark studio design system (navy + purple/blue/cyan, brand icon).

## 5. Build & distribution ✅
- SwiftPM universal build; Developer-ID signed (`build_local.sh`); notarize pipeline ready (`build_release.sh`); app icon; hardened runtime, no sandbox.

## Not yet built 🔲
- **Licensing activation** — LicenseManager + Polar $29 product, 14-day trial, Pro gating (code stubbed to unlocked for now).
- **Notarized release zip** (pipeline exists, not yet run).
- **Landing / comparison site.**
- **Test suite** for the safety chokepoint.
- v2 ideas: signed remote safety-DB, opt-in error reporting, treemap/sunburst, duplicate finder, app uninstaller, Sparkle auto-update, menu-bar quick-clean.
