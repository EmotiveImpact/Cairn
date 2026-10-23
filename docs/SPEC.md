Both load-bearing facts verified: the TimeMachine plist is world-readable (FDA false-positive confirmed) while Safari Bookmarks is the correct TCC-gated probe. The prototype files exist as cited. Here is the complete revised spec.

---

# PRODUCT SPEC — **Cairn** — Developer-Native Disk Cleaner for macOS

*Solo studio: Emotive Impact (Augustus Edem, Team ID FC88M2P4F9). Native SwiftUI, Developer ID + notarized, no Mac App Store, one-time purchase via Polar. v1 target: macOS 14 Sonoma+.*

---

## 1. Positioning

**Wedge (one line):** *"Reclaim 50–150 GB of dev-tool bloat in one click — Cairn knows Xcode, node_modules, Docker, Cargo and simulators by name, runs the *correct* clean command for each, and refuses to touch anything it can't safely undo. Buy once. No subscription, no daemon, no nags."*

**Who it's for (in priority order):**
1. **iOS/macOS + full-stack developers on capacity-constrained Apple Silicon (256/512 GB soldered SSDs), including those with repos on external/secondary SSDs.** Sharpest, highest-confidence pain: dev toolchains silently hoard 50–200 GB in *known, regenerable* paths; these users know it's safe to delete but lack a fast, transparent, all-projects, *all-volumes* tool that runs the right command and won't break a live build.
2. **Power users** who resent CleanMyMac's subscription and distrust its scareware tone.
3. **General users (secondary)** confused by the opaque "System Data" bucket — served by an *actionable* explainer (incl. Time Machine local-snapshot thinning, the usual #1 hidden hog), not just the headline pitch.

**Why it beats incumbents (citing the gaps):**

| Incumbent | Gap Cairn exploits |
|---|---|
| **CleanMyMac** (~$40/yr sub) | "Barely moves the needle" on dev caches — left 220 GB of System Data untouched because it can't see Xcode/Docker/node hoards. Background daemon, RAM/malware nags, "awesomize your Mac" tone the technical crowd punishes. Subscription is the single most-cited dealbreaker. **Cairn:** dev-native scanners, *correct per-tool clean command*, runs only when opened, paid once. |
| **DaisyDisk** ($9.99) | Visualizer only — *doesn't clean caches*. **Cairn:** finds *and* safely reclaims, with per-target CLI-correct methods. |
| **DevCleaner / npkill / Pearcleaner** (free OSS) | Validated demand but ship unpolished/abandonment-prone (Pearcleaner paused dev end of 2025). No maintained safety DB, no undo, no running-process guard, no monorepo awareness, CLI-only or rough UX. **Cairn:** maintained safety DB *with a v1 remote-update channel*, undo, running-app guard, workspace-aware regeneration, notarized, tested. |

Cairn is the only tool combining all three advantages competitors can't claim simultaneously: **developer-native depth + correctness** (beats CleanMyMac/DaisyDisk) + **one-time price** (beats CleanMyMac) + **polish, maintenance, safety, undo** (beats free OSS). The moat is not "knows the paths" — npkill knows the paths. It is **runs the right command, on the right volume, only when safe, and can put it back.**

---

## 2. Pricing & Monetization

**$29 one-time. Single tier. 2-Mac activation. No subscription, ever.**

Justification:
- **Anchors:** DaisyDisk $9.99 (visual toy), DevCleaner Pro $29 lifetime, Sensei $59, CleanMyMac ~$40/yr. $29 sits below CleanMyMac's first-year sub, reads "fair and honest" to the anti-sub crowd, beats Sensei's entry, signals quality over the $9.99 toys, lands on the celebrated DevCleaner lifetime anchor.
- **2-Mac activation** matches laptop + desktop without giving away seats; the limit lives on the Polar benefit, not the binary.

**Conversion mechanic — restructured so transparency doesn't kill conversion (addresses the "free scan reveals everything, power user runs `rm -rf`" defeat).** The old free-scan/paid-clean model handed the power user exact paths + the correct CLI for $0. New model:

- **Free tier (the honest hook, deliberately tedious to act on manually):** full scan, grand-total "Reclaim X GB", per-*category* totals, and **single-item, one-at-a-time** clean (select one item, review, Trash). Free users get the safety harness and undo on individual items. They do *not* get exact leaf paths exported, the correct per-tool CLI command strings, or batch operation.
- **Paid unlocks the things that are actually worth $29 to a developer who could otherwise script it** — the time and risk, not the `trash`-vs-`rm` swap:
  1. **Dev-Project Explorer batch clean** — select-all-regenerable across every repo/volume in one operation (the signature feature; scripting this safely yourself is real work).
  2. **Multi-category / "Clean selected" batch** across all categories at once.
  3. **Correct-command execution** for tool-mediated cleans (`simctl delete unavailable`, `go clean -modcache`, `pnpm store prune`, `conda clean`, `ollama rm`, version-manager uninstalls) — Cairn runs them with running-process guards, timeouts, and shim resolution; free users see *that* a tool-method exists but run it themselves.
  4. **Saved exclusions, removal-log export, presets** ("keep current + N recent" for runtimes/simulators), and **remote-updated safety DB** refreshes (see §6).
- **Free scan still shows the number** ("you could reclaim 84 GB") so the value is undeniable before paying — but realizing it across dozens of projects and a dozen toolchains *without* hand-scripting and *without* breaking a live build is the paid product. We do **not** print copy-pasteable destructive CLI strings or leaf-path lists in the free tier.
- **No trial** (decided 23 Oct 2026). Pro is a one-time £35.99 licence and `isUnlocked = isPro`. Older notes below that mention a trial or $29 are history.

**Revenue sustainability (addresses "$29 one-time can't fund perpetual maintenance, no telemetry to even know it broke").** Realistic GTM number is 100–400 units in 14 days (~$2.6k–$10k after Polar MoR fees). The maintenance burden is real and is *decoupled from app releases* by design:
- **The safety path database is a separately versioned, signed remote JSON** (see §6), so a moved Xcode/Node/Docker path or a new toolchain ships as a small data update Cairn fetches on launch — *not* a rebuild/notarize/redistribute cycle. This is the single change that makes one-time pricing survivable: maintenance cost per ecosystem change drops from "ship a release" to "edit a JSON, sign, upload."
- **Opt-in, anonymous error/failure reporting** (see §6) gives the field-failure signal the original spec lacked — so a solo dev *can* detect when a path moved or a delete started failing, without an account or behavioral telemetry.
- **Paid major-version upgrades** (Sketch/Sublime model) are the planned recurring lever, scoped to a concrete v2 trigger (uninstaller + treemap + System-Data explainer = the "Cairn 2.0, $19 upgrade" line), not hand-waved indefinitely.
- No behavioral telemetry, no account for the app itself. The remote DB fetch and opt-in error reporting are the only network calls beyond licensing.

---

## 3. Cleaning Categories

Tiers: **SAFE** = regenerates locally, trivial cost (default-selected). **REVIEW** = regenerates but expensively, or holds the only local copy (shown unchecked). **RISKY** = irreplaceable; never auto-selectable, requires explicit per-item confirm. All reclaim figures use **on-disk allocated size** (`totalFileAllocatedSizeKey`), deduped by inode for clones/hardlinks.

**Two cross-cutting safety facts now apply to every category (detailed in §5):**
- **`isRegenerable` is computed, not assumed.** A "SAFE" tier is only granted after a per-item regenerability check passes (workspace lockfile resolution, `npm link`/`file:`/patch-package detection, etc.). If the check is inconclusive, the item is *downgraded to REVIEW*, never silently kept SAFE.
- **`requiresQuit` gating.** Any cache owned by a running app (Xcode, Simulator, Docker daemon, VS Code, Cursor, JetBrains, a dev server holding files open) is **blocked from cleaning until the owning process exits**, with a quit-first prompt. This generalizes the old "quit Simulator first" note to all app-owned caches.

### 3.1 DEVELOPER CATEGORIES (the wedge — lead here)

#### Xcode & Apple toolchain
| Item | Path | Tier | Typical | Reclamation method / gotcha |
|---|---|---|---|---|
| **DerivedData** | `~/Library/Developer/Xcode/DerivedData/*` | **SAFE** | 10–50 GB | Trash contents (not parent). **`requiresQuit`: Xcode must be closed** — trashing DerivedData under a live Xcode corrupts the active build/index and can crash it mid-index. Per-workspace subfolders shown individually so an open project's folder can be skipped. |
| **iOS/watchOS/tvOS DeviceSupport** | `~/Library/Developer/Xcode/{iOS,watchOS,tvOS} DeviceSupport/<build>` | **REVIEW** | 10–40 GB | Trash old-OS subfolders; keep folder matching current test-device build. Re-extracts on next attach. |
| **Xcode Archives** | `~/Library/Developer/Xcode/Archives/` | **RISKY** | 5–30 GB | **Never blanket-delete** — each `.xcarchive` holds dSYMs to symbolicate shipped crashes. Surface build/version/date; default OFF. |
| **CoreSimulator Caches (+ `dyld`)** | `~/Library/Developer/CoreSimulator/Caches`, incl. `.../Caches/dyld` | **SAFE** | 1–10 GB | Trash directly. `dyld` subcache called out explicitly (common large item). `requiresQuit`: Simulator closed. |
| **Unavailable simulator devices** | `~/Library/Developer/CoreSimulator/Devices` | **REVIEW** | 20–150 GB | **`xcrun simctl delete unavailable`** — do NOT `rm`. `requiresQuit`: Simulator. |
| **Simulator runtimes** | mounted under `/Library/Developer/CoreSimulator` (**outside HOME**) | **REVIEW** | ~5–8 GB each | **SIP-protected — raw delete fails.** `xcrun simctl runtime list` → `runtime delete <id>` / `--notUsedSinceDays N`. Root declared in scanner's allowlist-of-roots (§5), *not* HOME. Re-download is multi-GB. |
| **CocoaPods cache** | `~/Library/Caches/CocoaPods` | **SAFE** | 1–5 GB | Trash, or `pod cache clean --all`. |
| **SwiftPM cache + SPM artifacts** | `~/Library/Caches/org.swift.swiftpm`, `~/Library/org.swift.swiftpm`, per-project `.build/` | **SAFE** (artifacts) / **REVIEW** (`org.swift.swiftpm/security` signing trust) | 3–8 GB | Trash artifact/clone caches; restore via `swift package resolve`. Don't touch SPM signing-trust/config. |
| **Carthage cache** | `~/Library/Caches/org.carthage.CarthageKit` | **SAFE** | 1–8 GB | Trash; rebuilds on `carthage bootstrap`. |
| **Old Command Line Tools / extra Xcodes** | `/Library/Developer/CommandLineTools` (advice), multiple `Xcode*.app` in `/Applications` | **REVIEW (advice card)** | 5–15 GB each | Surface size + version of each installed Xcode and CLT; advise which are superseded. Do not delete `.app` bundles directly in v1 — link to manual removal (deleting the active toolchain breaks builds). |

#### Docker (the headline gotcha — first-class UX, no reckless one-click)
| Item | Path | Tier | Typical | Reclamation method / gotcha |
|---|---|---|---|---|
| **Docker logical reclaim** | (inside VM) | **REVIEW** | 20–200 GB | `docker system df -v` to size (read-only). Offer **graduated, individually-checked** prune options, each with explicit consequence copy: `docker builder prune` (build cache — safest) → `docker image prune -a` (unused images) → `docker container prune`. **`docker system prune -a --volumes` is RISKY, never pre-checked, and gated behind a typed confirmation** because named volumes hold the only copy of local DB data — this is exactly the "reckless cleaner" move the brand forbids, so it's quarantined behind a per-item RISKY confirm, not a checkbox. `requiresQuit`/`requiresRunning`: Docker daemon must be *running* to prune; if stopped, show advice only. |
| **Docker.raw physical reclaim** | `~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw` | **RISKY (advice-only in v1)** | 20–200 GB | **Prune frees space *inside* the VM; the host `.raw` does NOT shrink.** Only resizing the disk image (Settings ▸ Resources) returns bytes — and destroys ALL images/containers/volumes. Surfaced as a labeled *advice card* (non-actionable item kind), not a delete button. |

#### node_modules & JS workspaces (whole-disk hunt — see §4 Dev-Project Explorer)
| Item | Path | Tier | Typical | Reclamation method / gotcha |
|---|---|---|---|---|
| **node_modules (per project / workspace package)** | `<project>/node_modules/`, `<repo>/packages/*/node_modules/` | **SAFE only after the §5 regenerability check passes** | 200 MB–1 GB each; 5–50 GB aggregate | Trash the dir; reinstall reproduces — **only if regenerable.** See §5 "Monorepo & non-regenerable JS" for the full rule: lockfile resolved at *repo root* (pnpm/yarn/npm workspaces), `package.json` workspace globs, and **non-regenerable detection** (`npm link` symlinks, `file:` deps, `patch-package` patches, missing-lockfile-and-not-a-workspace-member) → **downgraded to REVIEW**. Prune-on-match: size + `skipDescendants()`, never recurse into nested node_modules. |

#### Package-manager caches (global)
| Item | Path | Tier | Method / gotcha |
|---|---|---|---|
| npm | `~/.npm/_cacache`, `~/.npm/_logs` | **SAFE** | Trash, or `npm cache clean --force`. (Plain user dir — **no FDA needed**, §6.) |
| Yarn classic / Berry | `~/Library/Caches/Yarn`, `~/.yarn/berry/cache` | **SAFE** | `yarn cache clean`. Don't touch a project's committed `.yarn/cache` (zero-installs). |
| pnpm store | `~/Library/pnpm/store`, `~/.local/share/pnpm/store` | **REVIEW** | **Hard-linked into projects — `pnpm store prune`, never `rm`.** |
| bun | `~/.bun/install/cache` | **SAFE** | No built-in clean → trash directly. |
| pip / uv / poetry | `~/.cache/pip`, `~/Library/Caches/pip`, `~/.cache/uv`, `~/Library/Caches/pypoetry` | **SAFE** | `pip cache purge`; others trash. |
| Cargo registry | `~/.cargo/registry/cache`, `~/.cargo/git/db` | **SAFE** | Trash. Cargo 1.88+ auto-GCs — don't double-warn. |
| Go module cache | `~/go/pkg/mod` (`$GOMODCACHE`) | **SAFE** | **Mode-0444 read-only — `rm`/`trashItem` errors mid-tree. Use `go clean -modcache`** (handles perms + atomicity). `requiresQuit`: no running `go build`. |
| Go build cache | `~/Library/Caches/go-build` | **SAFE** | `go clean -cache`. |
| Gradle | `~/.gradle/caches`, `~/.gradle/wrapper/dists` | **REVIEW** | Trash targeted (`build-cache-*`, `transforms-*`); wrapper dists pile up forever. |
| Maven / Ivy | `~/.m2/repository`, `~/.ivy2/cache` | **REVIEW** | Shared by Gradle+Maven; re-resolves on next build. |
| Bazel | `~/.cache/bazel`, `/private/var/tmp/_bazel_<user>` | **REVIEW** | Can exceed 50 GB. `bazel clean --expunge` per workspace; outside-HOME `_bazel` root declared in scanner allowlist (§5). |
| ccache | `~/.cache/ccache`, `~/Library/Caches/ccache` | **SAFE** | `ccache -C`. |
| Composer (PHP) | `~/.composer/cache`, `~/.cache/composer` | **SAFE** | Trash; `composer clear-cache`. |
| NuGet / .NET | `~/.nuget/packages`, `~/.dotnet`, `~/.local/share/NuGet` | **REVIEW** | `dotnet nuget locals all --clear`. `.dotnet` may hold SDK installs (REVIEW). |
| Homebrew | `~/Library/Caches/Homebrew` | **SAFE** | `brew cleanup --prune=all`. |
| Deno | `~/Library/Caches/deno` | **REVIEW** | Module cache. |
| **Nix store (TRAP — advice only)** | `/nix` | **read-only advice** | **NEVER deletable** — `/nix/store` is not user-`rm`-safe and lives outside HOME. Surface size with copy: "Managed by Nix — use `nix-collect-garbage -d`." Explicitly excluded from any delete path. |

#### Language runtimes, version managers & mobile SDKs
| Item | Path | Tier | Method / gotcha |
|---|---|---|---|
| Per-project Rust `target/` | `<project>/target/` | **SAFE** | `cargo clean`. Biggest Rust hog (1–20 GB each). Prune-on-match. |
| Per-project Gradle `build/`, Pods/, `.venv` | `<project>/build`, `Pods/`, `.venv`/`venv` | **SAFE** (`.venv`/`venv` → **REVIEW** — only copy of resolved env) | Trash; recreate cost noted on venvs. |
| **Android SDK / AVD / emulator images** | `~/Library/Android/sdk` (system-images, ndk, build-tools), `~/.android/avd` | **REVIEW** | 10–40 GB; huge for RN/Flutter/mobile. Use `sdkmanager --uninstall` / `avdmanager delete avd`; surface old API-level system images + NDK versions. Don't delete the active SDK. |
| **Flutter / Dart pub cache** | `~/.pub-cache`, Flutter SDK `bin/cache`, `~/.gradle` Flutter artifacts | **REVIEW** | `flutter pub cache clean` / `dart pub cache clean`; re-downloads on next pub get. |
| nvm / asdf / mise / pyenv / rbenv versions | `~/.nvm/versions/node/*`, `~/.asdf/installs/*`, `~/.local/share/mise/installs/*`, `~/.pyenv/versions/*`, `~/.rbenv/versions/*` | **REVIEW** | Use the manager's `uninstall`, not `rm` (keeps shims). **Don't delete a version pinned by any project's `.nvmrc`/`.tool-versions`/`.python-version` found in the scan.** Offer "keep current + N most-recent" preset. |
| Ruby gems (old versions) | inside each rbenv version's gems dir | **SAFE** | `gem cleanup` (keeps newest). rbenv trees reach 40 GB. |
| conda envs / pkg cache | `~/miniconda3/envs/*`, `~/anaconda3/pkgs` | **REVIEW** | `conda clean --all` for the pkg cache (provably safe — envs untouched). Deleting an *env* folder is irreversible and may be the only copy of a resolved env; show last-used date, default OFF. |

#### IDE, AI-tool & Electron-app caches
| Item | Path | Tier | Method / gotcha |
|---|---|---|---|
| VS Code / Cursor caches | `~/Library/Application Support/{Code,Cursor}/{Cache,CachedData,Service Worker,GPUCache,Code Cache}`, `~/Library/Caches/com.microsoft.VSCode` | **SAFE** | **`requiresQuit`: editor closed.** Trash Cache/CachedData/logs. **Never touch `.../User`** (settings/keybindings/snippets). |
| JetBrains caches/logs | `~/Library/Caches/JetBrains/*`, `~/Library/Logs/JetBrains` | **SAFE** | `requiresQuit`. Trash caches/logs; keep config under Application Support. |
| **Electron app caches (Slack/Discord/Notion/etc.)** | `~/Library/Application Support/{Slack,discord,Notion,...}/{Cache,Code Cache,GPUCache,Service Worker/CacheStorage}` | **SAFE** | `requiresQuit` the app. Cache subpaths only — **never the app's data/IndexedDB/Local Storage** (holds login/session). Each can be GBs. |
| API/DB tools (Postman/Insomnia/TablePlus) | `~/Library/Application Support/Postman/{Cache,...}`, Insomnia/TablePlus cache subpaths | **REVIEW** | Cache subpaths only; never collections/connections/saved queries (state). |
| Git GUI repo caches (Sourcetree/Tower) | their cache subpaths under Application Support | **REVIEW** | Cache subpaths only; never bookmarks/account state. |
| LLM model caches | `~/.ollama/models`, `~/.cache/huggingface/hub`, `~/.cache/lm-studio` | **REVIEW** | **Most expensive to re-acquire of anything here.** Ollama → `ollama rm <model>` (keeps manifest consistent); HF → show size + last-access + re-download cost. Never disposable. |

### 3.2 GENERAL CATEGORIES

| Category | Path(s) | Tier | Method / gotcha |
|---|---|---|---|
| **App caches** | `~/Library/Caches/<bundle-id>` | **SAFE** | Trash. Exclude browsers (specialist scanner) and **state-caches** (auth/license — §5). `requiresQuit` for the owning app where running. |
| **Browser caches** | per-browser cache subpaths (Safari/Chrome/Firefox/Brave/Arc/Edge/Opera), incl. Chrome `Code Cache`/`GPUCache`/Service Worker CacheStorage | **SAFE** | `requiresQuit`. Trash cache subpaths *only* — never cookies/profile/Login Data. |
| **Logs** | `~/Library/Logs`, project `*.log`, `~/.npm/_logs` | **SAFE** | Trash. |
| **Installers / disk images** | `~/Downloads/*.dmg`, `*.pkg`, `*.iso` older than 30 days | **REVIEW** | Restrict to `.dmg`/`.pkg`/`.iso` only — never `.xz`/`.zip`/`.tar.gz` (user data). Default unchecked. |
| **Stale iOS firmware (.ipsw)** | `~/Library/iTunes/*Software Updates/*.ipsw`, `~/Library/iTunes/iPad*` | **REVIEW** | Old device firmware, 5–8 GB each; re-downloadable. Default unchecked. |
| **Trash** | `~/.Trash` **and per-volume `/Volumes/*/.Trashes/<uid>`** | **SAFE** | Empty Trash (the genuine reclaim). Volume-aware: surface each volume's Trash separately so external-SSD reclaim is visible (§5). |
| **Orphaned app data** | `~/Library/{Application Support,Containers,Group Containers}` for uninstalled apps | **REVIEW** | Bundle-id **prefix** match against installed apps (strip team-id + `group.`); vendor-folder allowlist; require staleness (>6 months). Tie to uninstall flow — never auto-delete data for an installed app. |
| **Large / old files** | user-selected roots | **REVIEW** | Manual review; on-disk size, sort by size/age. Never auto-select. |
| **iOS device backups** | `~/Library/Application Support/MobileSync/Backup/` | **RISKY** | Irreplaceable. Show device name + date, default OFF, explicit confirm. |
| **Time Machine local snapshots (ACTIONABLE)** | `tmutil listlocalsnapshots /` | **REVIEW** | **Frequently the single largest reclaim on capacity-constrained Macs and the #1 source of opaque "System Data."** Surface each snapshot's date; offer **`tmutil thinlocalsnapshots / <bytes> <urgency>`** (or delete-by-date) with explicit consequence: "these are local Time Machine restore points; thinning reduces your local rollback window but does not affect networked/disk backups." Never auto-selected; never blanket-deletes APFS purgeable. This upgrades the old read-only treatment to deliver on the System-Data promise. |
| **iCloud / CloudKit caches** | `~/Library/Caches/CloudKit`, `~/Library/Caches/com.apple.bird` | **SAFE (cache)** | Trash cache; **never** evict/dehydrate iCloud Drive files. iCloud "Optimize Storage" evicted files surfaced as *explainer only* (managed by macOS). |
| **"System Data" explainer (general users)** | local TM snapshots, MobileSync, CloudKit cache, sleepimage/swap, stale caches | **mixed: actionable where safe, read-only where managed** | Itemize the real culprits in plain language with sizes, each linked to its actionable category where one exists (esp. TM snapshot thinning above). Sleepimage/swap surfaced read-only ("managed by macOS"). |

---

## 4. Differentiating Features

1. **Scan animation / UX.** Streaming results: items appear live per scanner, with per-category running totals and a hero counter — *"Reclaimable: 84.3 GB and counting…"* — animating upward (~50 ms UI throttle). Cancellable anytime.
2. **Dev-Project Explorer (signature feature, volume-aware).** Whole-disk hunt (default root `$HOME`; **additional roots include mounted `/Volumes/*` APFS volumes the user opts in**, full-disk optional) finding *every* `node_modules`, `.venv`/`venv`, Rust `target/`, Gradle `build/`, `Pods/`, `.build/` across all repos and volumes — grouped by project, each tagged regenerable-or-not via the §5 workspace-aware check. Prune-on-match. **Batch clean is the paid hook (§2).** This is npkill done natively, safely, across volumes, with monorepo awareness it lacks.
3. **"Reclaim X GB" framing everywhere.** *"Free 84 GB — DerivedData 35, Gradle 22, simulators 18, node_modules 9."* Per-category/grand-total figures on **allocated** bytes (inode-deduped), shown before action. **Each figure is annotated with whether it lands after Trash or only after Empty Trash, and whether the target volume has room to trash at all** (§5).
4. **Safety / trust features:**
   - **Computed severity tiers** (SAFE/REVIEW/RISKY) gate selection: SAFE pre-checked *only after the regenerability check passes*, REVIEW unchecked, RISKY never selectable without per-item confirm.
   - **Running-app guard.** Items owned by a live process (Xcode, Simulator, Docker, editors, dev servers) are blocked with a quit-first prompt before cleaning.
   - **Trash-not-delete default, volume-aware.** Removals go to the *correct volume's* Trash (recoverable). Cross-volume and low-space cases are detected and handled honestly (§5) — never a silent copy+delete that doubles usage or fails at 98% full.
   - **Mandatory dry-run preview.** Scan is one-click; cleaning is review-then-clean, showing exact paths + sizes + per-item consequence + per-volume free-space precondition.
   - **Undo / removal log + quarantine.** Auditable, exportable history; one-click "Restore from Trash"; **per-tree transactional semantics with a quarantine/rollback story for partially-completed multi-tree ops** (§5).
   - **Persistent, editable exclusions** per category; survive updates.
   - **Honest regeneration copy.** "Regenerates automatically" only on items that *passed* the regenerability check; "you'll re-download / re-resolve / re-enter your license" on expensive or state items.
5. **Full Disk Access onboarding — accurate and minimal (addresses verified false-positive probe).** Not all scanners need FDA: plain user dirs (`~/.npm`, `~/.cargo`, `~/go`, `~/.gradle`, `~/Library/Caches` which is user-owned 0700) need *none*. **Each scanner declares `requiresFDA`.** Cairn requests FDA only when a TCC-gated scanner is enabled, with a banner explaining *which* features need it. FDA detection test-reads a **genuinely TCC-gated** path only — `~/Library/Safari/Bookmarks.plist` (verified TCC-gated) — and **never** `/Library/Preferences/com.apple.TimeMachine.plist` (verified `root:wheel 0644`, world-readable → would falsely report FDA granted). Use 2–3 confirmed-gated paths (Safari, `~/Library/Mail`, `~/Library/Messages`) to avoid false negatives. Per-item "incomplete (permission denied)" state so sizes are never silently wrong.

---

## 5. Safety Model — DO / DON'T and UI enforcement

This section is the product. Every gap the critic raised resolves to a rule here.

### 5.1 Allowlist-of-roots, not single-HOME confinement (fixes the safeToTrash conflict + external-SSD targets)

The prototype's `safe_under_home` (and the original spec's "resolved path must be under HOME") is **wrong for v1**: simulator runtimes live under `/Library/Developer/CoreSimulator`, Bazel under `/private/var/tmp`, Nix under `/nix`, and the target buyer keeps repos on `/Volumes/<ext-ssd>`. A single HOME check either blocks real targets or forces ad-hoc carve-outs that reintroduce prototype BUG-002.

**Replacement model — `safeToTrash(url, scanner)` chokepoint that every destructive op passes:**
1. **Resolve symlinks** to the real path (`URL.resolvingSymlinksInPath` + `realpath`); operate only on the resolved path.
2. **Check the resolved path against the *scanner's declared allowlist-of-roots*** — each scanner ships an explicit list of permitted root prefixes (e.g. node_modules scanner: `$HOME` + opted-in `/Volumes/*`; simulator-runtime scanner: `/Library/Developer/CoreSimulator`). A path not under any declared root for *that* scanner is rejected. Roots outside HOME exist only where a scanner explicitly and narrowly declares them, with a matching method (tool-mediated, not `rm`).
3. **Check the resolved path against the global denylist** (below) — denylist always wins over any allowlist.
4. **Confirm the path matches the scanner's pattern** (it's a `node_modules`/`target`/cache subpath, not its parent).
5. **Tier + regenerability + running-app gates** must all pass.

The allowlist-of-roots is itself part of the signed safety DB (§6), so adding a new safe outside-HOME root is a reviewed data change, not a code carve-out.

### 5.2 Cross-volume & low-disk-space trash strategy (fixes the "Reclaim 84 GB then trashItem fails at 98%" headline failure)

`FileManager.trashItem` on a file on a secondary/external APFS volume goes to *that volume's* `/Volumes/X/.Trashes/<uid>` — same-volume, fast, clones/hardlinks preserved. **A cross-volume move would be copy+delete (slow, needs 2× transient space, breaks clones).** Cairn therefore:
- **Always trashes to the same volume as the file** (the OS default for `trashItem`); never moves a file to a different volume's Trash. Each volume's Trash is also a surfaced reclaim category (§3.2).
- **Computes a per-volume "needs N GB free to safely trash" precondition** before promising reclaim. For each target volume, estimate transient space (effectively 0 for same-volume APFS trash, which is a rename) and verify `volumeAvailableCapacityForImportantUsageKey` ≥ required. If a volume is too full for even a rename-based trash of some pathological case, **offer a direct, explicitly-confirmed delete-without-trash for SAFE-and-regenerable items only** ("This volume is too full to use the Trash safely. Delete directly? (regenerable, no undo)") — never silent, never for REVIEW/RISKY.
- **States honestly that reclaim lands after Empty Trash**, and that Empty Trash needs the bytes to already exist. The hero counter distinguishes "moved to Trash" from "reclaimed" and shows the **verified free-space delta** post-empty.
- Detects ENOSPC and EXDEV (cross-device) at the API boundary, surfaces a clear per-item failure, and **never reports a failed trash as reclaimed.**

### 5.3 Running-app / open-file guard + transactional cleaning (fixes live-corruption + half-trashed trees)

- **Before cleaning any app-owned cache, check whether the owning process is running** (`NSRunningApplication` by bundle id; for daemons like Docker, a process/socket probe; for Xcode/Simulator, both). If running → block the item and show a **quit-first prompt**; do not proceed.
- **Per-tree transactional semantics.** Each target tree is one logical operation. Trash succeeds-or-fails as a unit per tree where the API allows; on partial failure (e.g. a mode-0444 file mid-`~/go/pkg/mod`, or an open file held by a running build), **stop that tree, record exactly what moved and what didn't in the removal log, and present a recovery action** rather than leaving a silently half-gone toolchain.
- **Prefer the tool over `trashItem` for trees that resist it.** `~/go/pkg/mod` (0444), pnpm store (hardlinks), simulator runtimes (SIP) are cleaned via their tool (`go clean -modcache`, `pnpm store prune`, `simctl runtime delete`) which handles perms/atomicity; raw trash is reserved for plain caches.
- **Recovery story:** the removal log records per-file outcome; "Restore from Trash" reverses the moved portion, and for tool-mediated cleans the log notes the exact regeneration command (`swift package resolve`, `npm install`, etc.) so a half-state is recoverable by re-running it.

### 5.4 Monorepo & non-regenerable JS / env detection (fixes false-SAFE node_modules and "regenerates" lies)

`isRegenerable` for a `node_modules`/env is computed, not assumed by sibling-lockfile presence:
- **Workspace-aware lockfile resolution.** Walk *up* from the package to find a repo-root lockfile (`pnpm-lock.yaml`, `yarn.lock`, `package-lock.json`, `bun.lockb`) and a root `package.json` declaring `workspaces`/`pnpm.workspaces` globs. A `packages/*/node_modules` whose package matches a root workspace glob is **regenerable → eligible SAFE**, even with no sibling lockfile. This fixes the false REVIEW on every workspace package.
- **Non-regenerable detection → downgrade to REVIEW (never silently SAFE):**
  - `node_modules` containing **`npm link` symlinks** (entries that are symlinks to outside the project) — `npm install` does not reproduce them.
  - dependencies declared with **`file:`/`link:`** protocols in the resolved lockfile/manifest.
  - presence of **`patch-package` patches** (`patches/` dir or `postinstall` patch step) — patched state may not reproduce identically.
  - a `node_modules` with **no resolvable lockfile and not a workspace member** (the npkill ⚠️ case — could be a vendored runtime).
- **`.venv`/`venv`/conda envs are REVIEW** (only copy of a resolved env); recreate cost shown.
- **Inconclusive check ⇒ REVIEW.** SAFE is granted only on a positive regenerability result.

### 5.5 DO / DON'T

**DO:**
- **Scan read-only, metadata-only.** Enumerate minimal attributes; never open/read/hash content. Check `isUbiquitousItemKey`/downloading-status *first* so iCloud dataless stubs stay unhydrated (a stub reports size 0). Skip FileProvider/iCloud-managed paths.
- **Route every deletion to the file's-own-volume Trash by default** via `FileManager.trashItem`; track resulting Trash URLs for Restore. Direct delete only via the explicit low-space/ regenerable path in §5.2.
- **Maintain a curated, remotely-updatable, signed safety database** keyed by macOS version + bundle id — allowlist of safe cache subpaths, allowlist-of-roots per scanner, and denylist of data stores (§6). Port the prototype's curated tables.
- **Clean only a known cache *subpath*, never its parent.**
- **Separate pure caches from state-caches** (auth/license/sessions) and default state items OFF with a plain consequence.
- **Report space honestly** — verify actual free-space delta post-empty; never promise instant gains; account for snapshots holding deleted blocks.
- **Generalize the running-app and per-volume precondition checks** to every applicable item.

**DON'T (hard-excluded by construction):**
- Never touch `/System`, `/System/Library`, `/Library`, system-wide `/Library/Caches`, or `/nix` (**removed from the prototype allowlist; Nix is advice-only**).
- Never enter `*.photoslibrary` — originals *or* derivatives.
- Never delete `~/Library/Application Support/MobileSync/Backup`, `~/Library/Developer/Xcode/Archives` (dSYMs), or any sqlite/realm/leveldb/core-data store.
- Never auto-delete app data for an *installed* app — gate behind uninstall flow.
- Never auto-delete APFS purgeable; **Time Machine local snapshots are actionable only via `tmutil thinlocalsnapshots` with explicit, opted-in consequence** (§3.2) — never blanket-`rm`'d, never auto-selected.
- Never `rm -rf` blindly — map each category to its correct tool; raw delete only for plain caches.
- Never run `docker system prune -a --volumes` from a checkbox — RISKY, typed-confirm only.
- Never cross-volume-move to Trash; never trash when it would risk ENOSPC without an explicit confirmed fallback.
- No blind one-click "clean everything."

**How the UI enforces it:** A `Severity` (computed) drives selectability; "select all" never includes REVIEW/RISKY. The single `safeToTrash` chokepoint (resolve symlinks → scanner allowlist-of-roots → global denylist → pattern → tier/regenerability/running-app gates) guards every destructive op. A mandatory review screen sits between scan and clean, showing consequence lines, per-volume free-space preconditions, and quit-first prompts for running apps. The exclusion list is sticky across launches and updates.

---

## 6. Technical Architecture

**Distribution posture (non-negotiable):** **App Sandbox OFF, Hardened Runtime ON, Developer ID Application signature, notarized.** A full-disk cleaner cannot be sandboxed — FDA and the sandbox are mutually exclusive (confirmed by CleanMyMac's feature-limited App Store build). Scanning `~/Library/{Caches,Developer,Containers}`, `/private/var`, mounted `/Volumes`, and shelling out to `docker`/`brew`/etc. are all impossible inside a sandbox.

**App structure (SwiftUI, macOS 14+):**
```
CairnApp (App)
├─ ScanStore (@MainActor @Observable)        // categories, items, totals, scan state, per-volume preconditions
├─ LicenseManager (templates/Licensing.swift)// isUnlocked = isPro || isInTrial; gates batch/CLI/Explorer
├─ SafetyDB (signed remote JSON + bundled fallback) // paths, allowlist-of-roots, denylist, tool-methods
├─ Views
│  ├─ Sidebar (categories + grand reclaim total)
│  ├─ DevProjectExplorer (whole-disk, volume-aware hunt; batch = paid)
│  ├─ ItemList (per-category, severity-colored, checkboxes gated by computed tier + regenerability + running-app)
│  ├─ ReviewSheet (mandatory dry-run: paths, sizes, consequence, per-volume free-space precondition, quit-first)
│  ├─ FDAOnboarding (per-scanner requiresFDA → deep-link → poll, accurate probe set)
│  └─ RemovalLog (history + Restore + per-tree partial-op recovery)
└─ Engine (actor-isolated)
```

**Scanner engine (port from prototype, keep the good IP):**
- **Pluggable scanner registry + base protocol**, each scanner an `AsyncSequence` of `ScanItem`. Port the prototype's `registry.py`/`base.py`/`scan_worker.py` onto a Swift actor + `AsyncStream`.
- **Each scanner declares metadata:** `allowlistOfRoots`, `requiresFDA`, `requiresQuit`/`requiresRunning` (owning bundle ids / daemon probe), `cleanMethod` (`.trash` | `.tool(command)` | `.adviceOnly`), and a `regenerabilityCheck` where applicable. This metadata is the maintenance surface and lives in the remote SafetyDB.
- **`ScanItem`** model: `path, resolvedPath, allocatedSize, latestMtime, volumeID, category, severity (computed), isRegenerable, requiresQuitOwner, isActionable, cleanMethod, note, selected`. The `isActionable` flag keeps Docker.raw/Nix/sleepimage advice cards out of the deletable set (fixes the prototype's fake-RISKY-path smell).
- **Single-walk sizing.** One `FileManager.enumerator(at:includingPropertiesForKeys:[.totalFileAllocatedSizeKey,.contentModificationDateKey,.isDirectoryKey,.fileResourceTypeKey,.fileResourceIdentifierKey,.volumeIdentifierKey])` pass per tree — accumulate size + latest-mtime together, dedup by inode/`fileResourceIdentifier` for clones/hardlinks, capture `volumeIdentifier` for the per-volume trash strategy. Use allocated (on-disk) bytes for reclaim. Prune-on-match via `skipDescendants()`.
- **Curated target tables ported verbatim then extended** (the high-value IP): prototype's dev-cache table (17 entries) + Xcode table (7 entries) + browser subpaths + orphaned-app reconciliation (rewritten to prefix-match), **plus the new entries in §3** (Android SDK/AVD, Flutter/pub, Bazel, ccache, Carthage, Composer, NuGet/.dotnet, Electron caches, multi-Xcode/CLT, Nix-as-trap, TM-snapshot thinning, .ipsw). All shipped as SafetyDB data, not hardcoded.

**Concurrency:** Work-stealing `TaskGroup` across independent scanners + a bounded child-task pool walking large trees concurrently (not task-per-call). FileManager's enumerator is the pragmatic high-performance default; drop to a `getattrlistbulk` C shim only if the ~6×-over-`du` ceiling is needed. Stream to the `@MainActor` store via `AsyncStream` with ~50 ms throttle.

**Permissions / TCC flow (corrected):** No public API to query FDA. **Per-scanner `requiresFDA`** — many dev caches (`~/.npm`, `~/.cargo`, `~/go`, `~/.gradle`, `~/Library/Caches` at 0700) need none, so Cairn does not show a scary prompt for a node_modules-only scan. When a TCC-gated scanner is enabled, detect FDA by test-reading **genuinely gated paths only** — `~/Library/Safari/Bookmarks.plist` (verified gated), plus `~/Library/Mail`, `~/Library/Messages` for redundancy. **Do NOT probe `/Library/Preferences/com.apple.TimeMachine.plist` — verified `root:wheel 0644`, world-readable, false-positive.** `EPERM`/`EACCES` = not granted. Request by opening `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles` and polling. Distinguish `PermissionError` from other errors per-item.

**Safe-delete API:** `FileManager.trashItem(at:resultingItemURL:)` to the **file's own volume** exclusively — preserves Put Back + undo, and eliminates the prototype's AppleScript-injection bug (no osascript). Keep name-collision handling + reclaimed-bytes accounting. `removeItem` reserved for app-internal temp files **and** the explicit, confirmed low-space/regenerable direct-delete fallback (§5.2). Separate explicit "Empty Trash" reclaims bytes; success is verified by free-space delta, not `path.exists()`.

**Free-space reporting:** Headline "free" = `volumeAvailableCapacityForImportantUsageKey` per volume (accounts for purgeable); never raw `statfs`/`df`. Surface APFS snapshots + purgeable as separate read-only/managed-where-appropriate categories; TM local snapshots are the one actionable member (§3.2).

**Shelling out to docker / brew / pnpm / go / simctl / xcrun / conda / ollama — robust resolution, timeout, cancellation (fixes brittle absolute-path + hang assumptions):**
- **Tool resolution order, not a hardcoded `/opt/homebrew/bin`:** (1) explicit user-set path in settings; (2) `which`-style lookup using a **reconstructed login-shell PATH** — read the user's shell (`$SHELL`) and run it once `-l -i -c 'command -v <tool>; echo $PATH'` to capture the interactive PATH (resolves **corepack/nvm/asdf/mise/Volta shims** that a Finder-launched GUI app's minimal PATH misses); (3) known absolute locations (`/opt/homebrew/bin`, `/usr/local/bin`, `~/.asdf/shims`, `~/.local/share/mise/shims`, corepack shims) as fallback; (4) if unresolved, mark that scanner's tool-method **unavailable** and degrade to advice-only rather than failing silently or guessing a path that doesn't exist.
- **Invocation:** Foundation `Process` with a resolved **absolute** `executableURL`, discrete `arguments` array, **never** `/bin/sh -c "string"` (injection). Wire stdout/stderr to `Pipe`, check `terminationStatus`.
- **Timeout + cancellation contract (every shelled tool):** read-only sizing calls (`docker system df`, `simctl runtime list`) get a short timeout (~10 s); mutating calls (`prune`, `runtime delete`, `go clean`) get a longer, user-cancellable timeout with a visible spinner and a Cancel that sends `SIGTERM` then `SIGKILL`. A hung/prompting `simctl` is killed and surfaced as a failed item, never blocking the UI. No tool runs as root.
- **`docker system prune -a --volumes`** is the one mutating call quarantined behind a typed RISKY confirmation (§3.1), because it destroys named volumes.

**No privileged helper in v1.** Scan, size, trash, user-space cache cleanup, and tool invocations run in the single user-space process with FDA-where-needed. `SMAppService` root daemon (XPC) is v2-only, for genuinely root-owned caches.

**Safety-database update & field-failure channel (fixes the hollow "maintained DB" moat with no v1 mechanism):**
- **SafetyDB ships as a signed, versioned remote JSON** (paths, allowlist-of-roots, denylist, per-scanner methods, regenerability hints), with a bundled fallback copy. On launch (and on demand) Cairn fetches the latest, **verifies an Ed25519/Developer-ID signature** before trusting it, and falls back to the bundled copy on any verification or network failure. This lets a moved Xcode/Node/Docker path or a brand-new toolchain ship in *hours* as a data update — no rebuild/notarize/redistribute — which is what makes one-time pricing maintainable.
- **Opt-in, anonymous error reporting** (off by default, plain toggle): when a clean fails (path missing, tool unresolved, trash ENOSPC, perms mid-tree), Cairn can send a minimal, non-identifying event (category, error class, macOS version, tool version) so the solo dev *detects* field breakage without an account or behavioral telemetry. This is the only thing that closes the "no telemetry to even know it broke" gap while honoring the no-tracking promise.
- Together these give v1 a real update + observability channel even though **Sparkle full auto-update remains v2** — the DB is the part that rots fastest, and it updates independently of the binary.

**Signing / notarization (reuse studio kit verbatim):** Build universal (`swift build -c release --arch arm64 --arch x86_64`), assemble `dist/Cairn.app`, sign inside-out with Hardened Runtime + `--options runtime --timestamp --entitlements` using **`Developer ID Application: Augustus Edem (FC88M2P4F9)`**, notarize via `xcrun notarytool submit … --keychain-profile vlume-notary --wait`, `stapler staple`, **ship a stapled ZIP** (not a DMG). Reuse `templates/build_release.sh` (`~/mac-apps/SIGNING.md`). Entitlements minimal — no sandbox.

**Licensing (Polar, reuse studio kit):** Merchant-of-record Polar under org **"Emotive Impact"** (`033c682c-…`); one-time product ($29) + license-keys benefit (2 activations). In-app `LicenseManager` from `templates/Licensing.swift`: Keychain-stored license + trial start, IOKit hardware UUID fingerprint, customer-portal `activate`/`validate`/`deactivate`, 14-day offline grace, revoke only on definitive 403/404. `isUnlocked = isPro || isInTrial` gates **batch operations, Dev-Project Explorer batch, correct-command execution, presets, exclusions, removal-log export** (not scanning, not single-item clean — §2). Website: `/api/checkout` → `/thanks`; `/api/portal`. No webhook, no account for the app. (`~/mac-apps/LICENSING.md`.)

---

## 7. MVP Scope (v1) vs Later (v2)

**v1 ships:**
- Dev-wedge scanners: Xcode (simctl-correct simulators, Archives-as-RISKY, CLT/multi-Xcode advice), package-manager caches (incl. Bazel, ccache, Carthage, Composer, NuGet/.dotnet, Nix-as-trap-advice), language runtimes/version managers, **Android SDK/AVD + Flutter/pub**, IDE/Electron/AI-tool caches, Docker (graduated prune + RISKY volume-prune + Docker.raw advice).
- **Dev-Project Explorer** — whole-disk, **volume-aware** node_modules/target/.venv/Pods hunt with **workspace-aware regenerability**.
- General categories: app/browser caches, logs, installers (dmg/pkg/iso), .ipsw firmware, **volume-aware Trash**, orphaned app data (prefix-matched + stale), large/old files, **actionable Time Machine local-snapshot thinning**, iCloud/CloudKit cache, System-Data explainer.
- Computed severity tiers, regenerability check, **running-app guard**, mandatory review/dry-run with **per-volume free-space preconditions and cross-volume/low-space handling**, Trash-by-default (same-volume), undo + removal log + **partial-op recovery**, editable exclusions, **accurate per-scanner FDA onboarding**.
- **Tool-resolution + timeout/cancellation contract** for every shelled tool.
- **Signed remote SafetyDB update channel + opt-in anonymous error reporting.**
- Streaming animated scan + "reclaim X GB" framing (with after-Trash vs after-Empty honesty).
- Developer-ID signed + notarized ZIP; Polar one-time license + 14-day trial; **restructured free single-item / paid batch+CLI conversion**.
- **Tested safety harness** (prototype shipped zero tests — non-negotiable): unit tests for `safeToTrash` (incl. allowlist-of-roots + symlink-resolution + denylist precedence), cross-volume/low-space trash logic, the orphaned matcher, prune-on-match, **workspace-aware regenerability (monorepo, npm-link, file:, patch-package)**, running-app gate, tool-resolution fallback, and SafetyDB signature verification.

**v2 / later:**
- Application uninstaller (drag app → remove app + caches + prefs + containers + login items/launch agents).
- Duplicate-file finder; DaisyDisk-style treemap/sunburst.
- Expanded System-Data explainer + mail/iMessage attachment cleanup; `.lproj` stripping; broken login items/launch agents.
- Menu-bar quick-clean + low-disk alerts + optional scheduled scans (no required daemon).
- `SMAppService` root daemon for system-owned caches.
- Project hibernation / archive-and-restore for idle projects.
- **Sparkle auto-updater** (binary updates; SafetyDB already updates in v1), localization + VoiceOver.
- **Paid major-version upgrade (Cairn 2.0)** as the recurring-revenue lever, anchored to the uninstaller + treemap + full System-Data explainer.

---

## 8. Top Prototype Bugs to Avoid Carrying Over

1. **AppleScript path injection in `trash.py` (CRITICAL).** `f'…POSIX file "{posix}"…'` allows arbitrary code execution via an attacker-named download on "Move to Trash." **Fix:** drop osascript — use `FileManager.trashItem`.
2. **Over-permissive safe-delete guard.** `safe_under_home` allowlists system-wide `/Library/Caches`. **Fix:** replace with the **per-scanner allowlist-of-roots + global denylist + symlink-resolved-path** model (§5.1); remove `/Library/Caches` and `/nix`; expand denylist (Mail, Messages, Photos, MobileSync, Keychains, `Containers/com.apple.*`).
3. **Orphaned-app false positives.** Exact bundle-id equality flags live data. **Fix:** prefix match, strip team-id/`group.`, vendor allowlist, >6-month staleness.
4. **Every directory walked twice.** **Fix:** single enumerator pass accumulating size + mtime + inode + volume.
5. **No FDA detection, and a *wrong probe*.** Scanners swallow `PermissionError` → 0 B; and the proposed TimeMachine-plist probe is world-readable (false positive). **Fix:** per-scanner `requiresFDA`, probe **only** genuinely gated paths (Safari/Mail/Messages), surface a banner, track per-item "permission denied."
6. **Installer scanner pre-selects `.xz`/`.bz2` as SAFE.** **Fix:** restrict to `.dmg`/`.pkg`/`.iso`; default unchecked.
7. **Logical `st_size`, no APFS awareness.** **Fix:** allocated size; dedup by inode.
8. **Clean scoped to current category only; racy success check.** **Fix:** operate over all selected items across categories; recompute totals from survivors; **track success by catching the action's errors and verifying free-space delta, never `path.exists()`.**
9. **Docker info overloaded onto a fake RISKY path.** **Fix:** non-actionable "advice" item kind (`isActionable=false`) — also used for Docker.raw, Nix, sleepimage.
10. **Worker poll loop drops the final DoneMessage.** **Fix:** key completion off a Done signal / `AsyncStream` termination, drain once more.
11. **(New) Single-volume / single-process assumptions.** Prototype assumes one volume and never checks running apps or cross-volume trash. **Fix:** volume-aware trash + per-volume preconditions (§5.2) and the running-app guard (§5.3).
12. **(New) Sibling-lockfile = SAFE heuristic.** Misfires on monorepos and `npm link`/`file:`/patched deps. **Fix:** workspace-aware computed regenerability (§5.4); inconclusive ⇒ REVIEW.

---

## 9. Name Shortlist

> Several names are taken in this category — avoid: **Cruft**, **Brisk**, **Scrub**, **Pry**, **MacSweep**, **Tidy Up**, **Mole**, plus all named live competitors. **Run USPTO class-9/42 + domain clearance BEFORE committing the brand — this is a gating launch task, not a post-launch check, given Cairn's self-flagged MEDIUM TM risk and the cost of a forced rename after Product Hunt/SEO equity builds.**

1. **Cairn** *(top pick, pending clearance)* — a deliberate, curated stack of stones; flips "pile of junk" into "intentional, considered removal," directly answering the audience's #1 fear of reckless cleaners. Short, evocative, strong studio fit. **TM risk MEDIUM** (unrelated energy/publishing firms; software class likely clear but unverified). `getcairn.com`/`cairn.app` plausible. **Do not finalize until the class-9/42 + domain check clears; ship under the runner-up if it doesn't.**
2. **Vacuo** — Latin root of "vacuum/empty"; invented-feel, ownable. No Mac cleaner found. TM risk LOW–MEDIUM; `vacuo.app`/`vacuo.dev` strong.
3. **Derel** *(developer wink)* — nods at Xcode **Der**ived**D**ata and "derelict" caches. Strongest insider signal; uncommon as software, low TM risk; `derel.app` likely free.

*Recommendation: pursue **Cairn** as the lead and run clearance immediately; the trust/safety angle is the conversion lever, and Cairn reads as a premium, intentional tool. Fall back to **Vacuo** (lowest TM risk) if clearance fails.*

---

**Key grounding files (absolute paths):** prototype reusable IP at `/Users/augustusedem/CLEANSTUFF/reference-prototype/macsweep/scanners/dev_caches.py` and `/xcode.py` (port + extend target tables into the SafetyDB), `/core/item.py` (Severity model → make computed), `/core/fs.py` (replace `safe_under_home` with allowlist-of-roots chokepoint), `/core/trash.py` (replace osascript with `FileManager.trashItem`, add volume-aware + low-space handling); studio kit at `/Users/augustusedem/mac-apps/SIGNING.md` (Team `FC88M2P4F9`, `vlume-notary`, ship-a-ZIP), `/Users/augustusedem/mac-apps/LICENSING.md` (Polar org `033c682c-…`, `templates/Licensing.swift`, `isUnlocked = isPro || isInTrial`), and `/Users/augustusedem/mac-apps/GTM.md` (100–400 units / 14 days — the number the §2 economics are built against).