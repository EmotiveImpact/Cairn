# Bugs & Fixes

Living log of bugs, safety risks, and their fixes for the Mac cleaner app. Newest at top of each section. Every entry: **symptom → cause → fix → status**.

Severity legend: 🔴 critical (data loss / crash) · 🟠 high · 🟡 medium · ⚪ low/polish.

---

## Where things stand, 23 October 2026

A plain summary of what is wrong now, what has been fixed but not merged, and what is still to build. The detailed log from earlier passes follows underneath.

### Open bugs

| | Problem | What it means | Next step |
| --- | --- | --- | --- |
| 🟠 | **Freed space was over-reported.** The old lifetime counter said 90 GB freed; the receipts only show about 2.6 GB, and that went to the Trash rather than being freed. | Any "you have freed X" figure on `master` cannot be trusted. | Fixed (PR #5, merged): figures come from receipts and Trash is called Trash. The old counter is still stored and should be removed. |
| 🟡 | **The command line refused to run while the app was open.** | AI tools and scripts could not even read the status. | Fixed in PR #5 for `status`, `scan`, `categories` and `help`. `clean` still needs the app closed, on purpose. |
| 🟡 | **Claude Code and Codex point at a test build** in `~/imagetemp` on Edem's Mac. | They stop working if that folder is cleared. | PR #5 makes Connect prefer `/Applications/Cairn.app`. Cairn is not installed there yet, so this needs an installed build and then Reconnect in Settings › AI tools. |
| 🟡 | **The AI tool link was slow** (7.5 minutes for a full answer on a busy Mac). | AI tools time out or give up. | Fixed in PR #5 with a 10-minute scan memory and answers from the last scan. The first scan is still slow (about 5.5 minutes). |
| 🟡 | **Most of the scan total is "Large & old files"** (33 of 53 GB), which Cairn only shows for review. | The headline number looked far bigger than what one click frees. | Fixed in PR #5: "Ready to free" is shown separately from "Needs you". |
| 🟡 | **Weekly auto-scan on launch did not run** on a test build. | The menu bar and Home can show old numbers. | Not investigated yet. |
| 🟡 | **Whole-disk search and sizing large folders is slow** (BUG-014). | Long waits on big disks. | Reduced, not solved. |
| 🟠 | **"I can't delete after selecting."** Clean › General said "Review and free 1.31 GB", then the review said "Free 188.5 MB". | The clean did run (23 Oct, 08:37): caches deleted, installers moved to the Trash. The review left Trash-bound files out of its number, and a 1.2 MB `.cursor` build folder was listed but always refused. The window then closed because a test session quit the wrong Cairn. | PR #12: one total from button to review, refused items never listed, Large Files reviews only its own picks. |
| ⚪ | **GitHub's automatic build checks sometimes do not start** on this repository. | Pull requests can show red for reasons outside the change. | Builds are checked on the Mac instead when this happens. |

### Open issues (not bugs, but blocking a release)

- **No signed, notarised download and no automatic updates.** `build_release.sh` can sign and notarise, but no build has been published and there is no update feed yet.
- **Nothing is installed in `/Applications`** on the test Mac, so every check so far has used test builds.
- **Screen Recording permission is needed** before Claude can take screenshots on the Mac, so the built app cannot yet be compared side by side with the mockups automatically.
- **The built app does not always match the mockups.** Spacing, type sizes and busy screens have been the repeated complaint. Every screen needs a side-by-side check against its approved mockup.
- **The Claude Code plugin and Gemini extension are published** from the public `Emotive-Impact-Studios/cairn-plugins` repository, but they only work once PR #7 (AI tools cleaning) is merged and released in the app.
- **Website screenshots are out of date.** They show the old look, and some show items as cleanable that Cairn now treats differently.
- **Pro is on hold.** The licence screen exists, but what Pro unlocks has not been decided.
- **Some large caches are still refused** by the safety walk (over 100,000 files, or folders containing database files, such as some `node_modules` and DerivedData). Loosening this needs a decision.

### Fixed recently

| Date | Fix | Where |
| --- | --- | --- |
| 24 Oct | Apple's own caches in `~/Library/Caches` were listed as junk, and clearing one (the Neural Engine's compiled models) breaks text recognition until a restart. They are now off limits, as are macOS Install Data and partial removal of Ollama's shared store. | PR #16 (merged 25 Oct) |
| 23 Oct | A ready clean removed a running test build's `.build` folder and the review didn't say caches are deleted outright. Cleaning now needs a click, the review says what can't be put back, and Cairn skips its own app, folders in use and fresh builds. | PR #5 (merged 23 Oct) |
| 23 Oct | Items found by two scanners were counted twice (about 1 GB on the test Mac). | PR #5 (merged 23 Oct) |
| 23 Oct | Home's scan number counted everything found, then dropped to the ready amount at the end. It now counts only ready space, with "to look through" shown separately. | PR #5 (merged 23 Oct) |
| 22 Oct | Freed space is read from receipts; Trash is no longer counted as freed; scan age shown correctly; "0 KB" instead of "Zero KB". | PR #5 (merged 23 Oct) |
| 22 Oct | Read-only commands run beside the app; scan splits Ready from Needs you; AI tool answers cached. | PR #5 (merged 23 Oct) |
| 22 Oct | Pages no longer slide when switching; numbers count cleanly instead of rolling digits. | PR #5 (merged 23 Oct) |
| 21 Oct | Cairn now actually frees space: deletes rebuildable caches, empties the Trash and runs each tool's own clean. Before this it only moved things to the Trash. | PR #1 (merged) |
| 21 Oct | Rebuildable caches, build output and `node_modules` are no longer refused, while AI chats, personal files, iCloud, Mail, Keychains, `.git` and `.ssh` stay protected. | PR #1 (merged) |
| 21 Oct | Fixed CI workflow quoting; relocation records now change only inside their own task. | PR #2 (merged) |
| 21 Oct | About 3,300 lines of unreachable old screens removed. | PR #2 (merged) |

### Still to build

See the roadmap in [README.md](README.md#whats-next).

---

## Resolved — 2026-07-01 lag/crash hunt (reported: "keeps lagging or crashing in some modes")

### 🔴 BUG-029 — Idle CPU/memory blowout: 1.3 GB + 86% CPU doing nothing
- **Symptom:** the app lagged/beachballed shortly after opening, before the user did anything.
- **Cause:** `DiskUsage.compute()` (the Storage Overview bar) recursively measured `/Applications`, `~/Documents` and `~/Movies|Pictures|Music` at up to **80,000 files each, on every launch** — to draw one decorative bar. Measured: idle RSS climbed 659 MB → **1,305 MB**, 86.6% average CPU.
- **Fix:** recompute at most **once every 24 h** (cache + staleness check), cap each tree to 12k files, run at `.background` priority. **Measured after: peak 193 MB, settles 168 MB, 0.0% CPU.**
- **Status:** resolved (≈7.7× less idle memory).

### 🟠 BUG-030 — Scan-time lag: a full UI re-render per found item
- **Cause:** `apply(.item)` published an `@Observable` change for **every** item (thousands per scan) and `.progress` did the same per path, so SwiftUI re-rendered the entire dashboard hundreds of times a second.
- **Fix:** the event stream is now **coalesced** — items batch and flush at ~12 fps (80 ms); lifecycle events flush first so ordering is exact. Progress text only surfaces on a flush tick.
- **Status:** resolved.

### 🟠 BUG-031 — `DeviceInfo` hit the filesystem on every redraw
- **Cause:** `available`/`used`/`totalCapacity`/`usedFraction` each performed a synchronous volume query, read from 13 view sites (sidebar card, dashboard, status rows) on **every** redraw — hundreds of disk calls per second on the main thread during a scan. `name`/`chip`/`ramGB`/`deviceSymbol` re-ran `Host.current()`/`sysctl` too.
- **Fix:** volume info cached with a 1 s TTL (+ `invalidateVolumeCache()`); hardware facts became `static let` (computed once).
- **Status:** resolved.

### 🟠 BUG-032 — Every table row enumerated all running processes
- **Cause:** `ItemRow` called `RunningApps.running(amongst:)` **in its view body** to draw the "QUIT APP" badge; each call built a `Set` of all running applications. With hundreds of visible rows that was hundreds of full process sweeps per redraw.
- **Fix:** cached with a 2 s TTL for display reads; the clean/uninstall paths now call the new **uncached** `runningNow(amongst:)`, so the safety guarantee is unchanged.
- **Status:** resolved.

### 🟡 BUG-033 — Three force-unwraps that could crash
- `DuplicateStore` sorted clusters with `first!` (traps on an empty cluster); `snapshotURL`/`removalLogURL` used `urls(for:).first!` (traps if Application Support is unavailable). All replaced with safe optionals + a `~/Library` fallback.
- **Status:** resolved.

### 🛡️ Data-safety hardening — AI conversation history can never be touched
Prompted by a report of missing Claude Code conversations. **Verified Cairn was not the cause** (no removal log existed → it had never deleted anything on this Mac; all 2,968 `.jsonl` transcripts intact). Regardless, `~/.claude`, `~/.codex`, `~/.cursor`, `~/.continue`, `~/.aider`, `Library/Application Support/Claude` and VS Code History are now in the **SafePaths denylist** and the uninstaller's protected list — irreplaceable, never deletable at any severity. Added **`Cairn --safetycheck`**, a release gate that asserts 12 irreplaceable locations are refused while normal caches stay cleanable.

---

## Resolved — 2026-07-01 "best of everything" QA pass

Full audit of every feature: found **9 Settings toggles that did nothing** and two Restore Bin bugs. All fixed:

### 🟠 BUG-027 — Nine inert Settings (the app didn't do what it said)
- **Now real:** *Open at login* → registers via `SMAppService`. *Show menu bar item* → a real `MenuBarExtra` (Open Cairn / Quit; app stays alive in the menu bar when the window closes). *Auto Scan Weekly* → auto-refreshes a scan older than 7 days on open (never on first run). *Scan Notifications* → local notification "Scan complete — X reclaimable" (asks permission when toggled on). *Include developer caches* / *Include simulators* → filtered at the scan-item chokepoint (`dev-caches` category / `CoreSimulator` paths).
- **Now honest:** *Protect System Files*, *Skip Open Files* → converted to green **"Always on"** guarantee rows (they're hard engine guarantees, not options) + added a third: "Recoverable Removal". *Secure Deletion* → **removed** (meaningless on APFS/SSD and contradicts our recoverable-Trash design). *Smart Recommendations* → removed (nothing behind it).
- **Status:** resolved.

### 🟡 BUG-028 — Restore Bin: Undo left stale entries; Put Back could wedge
- **Symptom:** After Celebration→Undo, restored items stayed listed as "recoverable" (Put Back then failed silently). If the user emptied the Trash, dead rows stayed forever.
- **Fix:** `undoLast` now prunes restored entries from the removal log; `restoreFromLog` drops stale entries whose Trash file no longer exists.
- **Status:** resolved.

### ⚪ Polish folded in
Health page header renamed to match nav ("HEALTH", crisp non-rounded title); ScanningHero recolored off purple → brand blue/teal; Storage Overview caches its last disk breakdown (no "Zero KB" flash); pointing-hand cursor on all remaining tap targets (chips, table rows, menus, pill); dead `ComingSoon` view deleted; SwiftPM resource warning silenced.

---

## Resolved — 2026-06-30 premium pass (10-round /loop)

A 10-round self-paced loop ("make it premium + find/fix bugs"), driven by a 9-agent design+bug critique. Full design plan + per-round checklist in [docs/PREMIUM-PLAN.md](docs/PREMIUM-PLAN.md). Design highlights: token system (Space/Elevation/radius scales, brand wash, eyebrow), wired the dormant animated `ScanningHero`, unified gradient primary button + hover/press feedback everywhere, rounded+monospaced metric numbers, depth-as-hierarchy elevation, DonutChart draw-on, real category/app icons, canonical `StatusPill`, deleted 4 dead view files, lit app background, honest celebration, section cross-fades — all with `reduceMotion` fallbacks. Bugs fixed in the pass:

### 🔴 BUG-023 — Duplicates could destroy the only copy
- **Symptom:** `removeSelected` trashed every *selected, non-keeper* file with no guarantee a copy survived — if no keeper was set (or the keeper was already gone), it could trash all copies of a file.
- **Fix:** survival guard — refuse to trash a group unless at least one kept copy still exists on disk; plus a system/photo-library path block. (Deliberately does NOT apply the cleaner's Documents denylist — deduping your own Documents/Pictures is the point.)
- **Status:** resolved.

### 🟠 BUG-024 — ReviewSheet over-promised the clean total for free users
- **Symptom:** the primary button read "Clean <total>" including Pro-only tool cleans a free user can't run — over-promising reclaim.
- **Fix:** button now shows the **effective** total (free-method items only without Pro) + a sibling "Unlock <paidTotal> with Pro →" that hops to Settings.
- **Status:** resolved.

### 🟠 BUG-025 — Destructive actions without confirmation / honest labels
- **Large Files** "Move to Bin" trashed irreplaceable data instantly → now a confirmation dialog. **Trash-empty** items (permanent `removeItem`) are now marked "permanent" in the ReviewSheet instead of implying "recoverable." Celebration distinguishes recoverable vs permanently-removed.
- **Status:** resolved.

### 🟡 BUG-026 — Pro state hardcoded; snapshot stale after clean; misc correctness
- Large Files cleaned with hardcoded `proEnabled: true` → real `license.isUnlocked`. Snapshot now re-saved after a clean (no over-report next launch) via a single canonical save path. `Fmt.split` no longer drops the unit on non-breaking spaces. Item checkbox is brand-blue (was purple). Health "Checks" count is real (`HealthStore.checkCount`). Python venv `isRegenerable` now reflects whether a manifest exists. `HealthStore.fix` matches on resolved+standardized paths. iCloud mirrors (Mobile Documents, CloudStorage) added to the cleaner denylist. Ignoring a Large File now hides it immediately. Celebration can't double-present.
- **Status:** resolved.

---

## Resolved — 2026-06-30 hardening pass (memory + safety)

Driven by a real user report (app hit ~50 GB RAM and nearly crashed the Mac) plus a 7-agent research/audit team (OSS study of Pearcleaner/czkawka/GrandPerspective + memory/perf + correctness + product-gap audits). Full plan in [docs/HARDENING-PLAN.md](docs/HARDENING-PLAN.md).

### 🔴 BUG-015 — ~50 GB RAM, near-crash (orphaned scans pile up on navigation)
- **Symptom:** Memory climbed to ~50 GB; navigating between pages made results "disappear" and re-scan.
- **Cause:** `HealthStore` / `DuplicateStore` / `AppInventoryStore` were each owned by `@State` **inside their views**. Leaving a page destroyed the view, orphaning its in-flight scan `Task` (never cancelled, no `deinit`); returning recreated the store and started a *new* scan — repeated navigation stacked concurrent heavy disk walks.
- **Fix:** Hoisted all three stores into the single long-lived `AppShell` (`@State`), passed down via `@Bindable`. Scans now run **once** (`scanIfNeeded`/`startIfNeeded` idempotent), results persist across navigation, and each store got `deinit { scanTask?.cancel() }`. **Measured: peak now ~2–3 GB and flat, settling <1 GB — down from 50 GB.**
- **Status:** resolved (verified live).

### 🟠 BUG-016 — App-inventory walk was uncancellable (`Task.detached`)
- **Symptom:** Leaving the Apps page didn't stop its scan; the heavy bundle/`~/Library` sizing ran to completion off-screen.
- **Cause:** `AppInventoryStore.run()` ran `enumerate` inside `Task.detached { … Task.isCancelled … }`. A detached task has its own context, so `Task.isCancelled` was **always false** — cancelling the wrapper did nothing.
- **Fix:** Introduced a thread-safe `CancelBox` shared with the off-main walk; `cancel()`/`rescan()`/`deinit` flip it and `enumerate` checks it between apps.
- **Status:** resolved.

### 🟠 BUG-017 — Uninstall could orphan user data (not all-or-nothing)
- **Symptom:** If the `.app` bundle failed to move to Trash (busy / relaunched / perms), its `~/Library` data had **already** been trashed while the app stayed installed.
- **Cause:** `uninstall()` trashed associated files **first**, then the bundle, then judged success on the bundle move.
- **Fix:** Trash the bundle **first**; on failure, `continue` before touching any associated data. Only after the bundle succeeds do we trash support/leftover files.
- **Status:** resolved.

### 🟠 BUG-018 — Uninstall id-match could reach protected `~/Library` data
- **Symptom:** A short/common bundle id could prefix-match unrelated `~/Library` folders into the "associated" set.
- **Cause:** `dottedPrefixMatch` allowed single-token matches; the uninstall guard didn't consult a denylist for sensitive subtrees.
- **Fix:** Require the matched id to carry ≥2 dotted segments; added an explicit protected-subtree denylist to `isUninstallSafe` (Keychains, Mail, Messages, MobileSync, AddressBook, CallHistoryDB, `com.apple*`, Calendars, Photos, Suggestions).
- **Status:** resolved.

### 🟡 BUG-019 — Memory leanness (unbounded caches, big-walk spikes)
- **Symptom:** RAM kept growing over a session; Duplicates briefly spiked ~5 GB.
- **Cause:** `IconCache`/`ThumbnailCache` were unbounded dictionaries; `FileScan.measure` and the Duplicates Pass-1 walk had no `autoreleasepool` (autoreleased `URL`/resourceValues piled up over huge trees); Duplicates `bySize` was uncapped and eagerly called `resolvingSymlinksInPath()` per file; Smart Scan ran all 19 scanners at once.
- **Fix:** `IconCache`/`ThumbnailCache` → `NSCache` (auto-evicting + count limits); `autoreleasepool` per item in `FileScan.measure` and the Duplicates walk; capped Pass-1 retention (300k) and deferred symlink resolution to only the files that become duplicates; bounded Smart Scan to ~4 concurrent scanners; thumbnail cache key now includes mtime.
- **Status:** resolved (Smart-Scan peak ~2.2 GB, down from ~3 GB; Duplicates no longer spikes to 5 GB).

### 🟡 BUG-020 — Apps filter pills wrapped ("Unu sed", count "16 6")
- **Symptom:** Filter chips broke across lines when the content area was narrow.
- **Cause:** Chips could compress; `Text` wrapped inside the capsule.
- **Fix:** `.fixedSize()` + `.lineLimit(1)` per chip, row in a horizontal `ScrollView`.
- **Status:** resolved (verified live).

### ⚪ CHANGE-021 — Launch no longer auto-scans (lands idle + cached snapshot)
- **Was:** every launch auto-ran all 19 scanners — a CPU/RAM spike and re-walk each time; not how any OSS cleaner behaves.
- **Now:** the app lands on an idle Dashboard showing the **last scan's cached results instantly** ("Last scan · Xm ago"); a fresh scan runs only from the "Start Smart Scan" CTA / Smart Scan page. Snapshot persisted to `~/Library/Application Support/Cairn/last-scan.json` (display-only — cleaning always requires a fresh scan, never stale data). New idle/cached state added to `SmartScanView`.
- **Status:** done (verified: relaunch shows 121.89 GB cached, no scan).

### ⚪ CHANGE-022 — "Bugs & Fixes" page renamed to "Health"
- **Was:** the system-health *fixer* page was labelled "Bugs & Fixes" (reads like Cairn's own changelog) with a literal ladybug icon.
- **Now:** "Health" + `heart.text.square` icon, matching the `HealthStore`/`HealthView` code and the page's "Keeping your Mac healthy" hero. The separate changelog tab in the Transparency panel keeps the "Bugs & Fixes" name (that one genuinely is Cairn's fix log).
- **Status:** done (verified live).

---

## Open

### 🟡 BUG-014 — Whole-disk hunt + large-tree sizing is slow (MITIGATED)
- **Symptom:** A full scan to *completion* takes ~90 s on a heavy dev machine; `Cairn --selftest` (which waits for every scanner) didn't finish in 150 s.
- **Cause:** Two parts. (1) `DevProjectsScanner` used a recursive enumerator that stat'd every file in the home tree. (2) Sizing large trees is inherently IO-bound `stat`-ing — measured per-scanner: dev-projects 92 s, dev-caches 57 s, app-caches 41 s, browser-caches 20 s (each sizing multi-GB many-file dirs).
- **Fix (done):** Rewrote the hunt as a directory-only DFS with `isDirectory` pre-cached (files skipped with a cached read, no per-file syscall), depth bound 7, hard 40k-dir cap, aggressive prune list. Split fast traversal (collect candidates: ~10 s) from sizing, and size candidates **in parallel across cores** with a per-tree `maxFiles` cap (50k → marks "(partial size)"). The 14 scanners already run concurrently in the engine and **stream** results live + are cancellable, so the GUI shows value in seconds and worst-case total ≈ the slowest scanner, not the sum.
- **Follow-up (v1.x):** Parallelize sizing *within* the heavy cache scanners too (dev/app/browser), or add a coarse fast-estimate path, to pull the worst-case total well under a minute. Tracked, not blocking.
- **Status:** mitigated (product UX is responsive; completion time scales with disk usage, like other cleaners).

---

## Carried over from the Python prototype (`reference-prototype/macsweep`)

These were found by reading the prototype on 2026-06-30. They are the mistakes the native rewrite must **not** repeat. Status `design-fix` = the new architecture avoids it by design; we verify in code review.

### 🟠 BUG-001 — Every directory is walked twice (size + mtime)
- **Symptom:** Scans are slow on large folders (Caches, DerivedData, node_modules).
- **Cause:** `dir_size()` does a full `os.walk`, then `latest_mtime()` does *another* full `os.walk` of the same tree — `scanners/*.py` call both per item (`core/fs.py:36`, `core/fs.py:59`).
- **Fix:** Single traversal returning `(totalSize, latestMTime, fileCount)` in one pass. In Swift, one `FileManager.enumerator` walk per node.
- **Status:** design-fix (new scanner engine does one pass).

### 🔴 BUG-002 — AppleScript path injection in "Move to Trash"
- **Symptom:** Paths containing `"` or other AppleScript-special characters could break the `osascript` command or, worst case, alter the command sent to Finder.
- **Cause:** `core/trash.py:28` interpolates the raw POSIX path directly into an AppleScript string literal.
- **Fix:** Native Swift uses `FileManager.trashItem(at:resultingItemURL:)` — no shell, no string interpolation, preserves Put Back. No AppleScript at all.
- **Status:** design-fix.

### 🟠 BUG-003 — Sizes silently undercounted without Full Disk Access
- **Symptom:** "Recoverable space" totals look smaller than reality; some categories appear empty.
- **Cause:** Many paths under `~/Library` and most dev caches require Full Disk Access (TCC). The prototype swallows `PermissionError` (`core/fs.py:54`) and shows nothing — the user has no idea the number is wrong.
- **Fix:** Detect FDA status, drive a first-run onboarding to grant it, and surface a clear "limited results — grant Full Disk Access" banner when denied. Never present an undercount as if it were complete.
- **Status:** design-fix (TCC onboarding is a v1 requirement).

### 🟡 BUG-004 — Orphaned-app-data heuristic can flag live data
- **Symptom:** Folders for apps that *are* installed (or whose data is shared) can be reported as "orphaned," risking deletion of real data.
- **Cause:** `scanners/orphaned.py` matches `~/Library/Application Support` / `Containers` folder names against installed bundle ids with loose string rules; non-bundle-id folder names and helper-process ids slip through.
- **Fix:** Keep severity REVIEW (never auto-select), expand the allowlist of system/shared ids, match against a fuller bundle-id set (Login Items, helpers, embedded bundles), and require explicit user confirmation. Consider a known-safe-to-keep list.
- **Status:** design-fix + needs a curated allowlist.

### 🟡 BUG-005 — Large/Old file scan can be very slow and noisy
- **Symptom:** Scanning `~/Downloads`, `~/Desktop`, `~/Movies`, `~/Music` with `rglob("*")` can take a long time and surface things the user wants to keep.
- **Cause:** `scanners/large_files.py:34` recurses the entire tree with no early pruning; threshold logic mixes "large" and "old."
- **Fix:** Bounded-depth enumeration, skip known-keep locations (Photos library, iCloud-only/dataless files), and separate "large" from "old" as distinct, clearly-labeled findings.
- **Status:** design-fix.

### ⚪ BUG-006 — Tkinter UI is not competitive
- **Symptom:** The `aqua`-themed Tkinter UI (`ui/app.py`) looks dated; no animation, no premium feel — the opposite of the goal.
- **Cause:** Tkinter has no real animation/compositing; can't match the studio's design system.
- **Fix:** Native SwiftUI app using the Emotive Impact design system (dark navy + purple/blue/cyan, Satoshi), with animated scanning (radial sweep / live-counting reclaimable total).
- **Status:** design-fix (this is the whole rewrite).

### 🟡 BUG-007 — No protection against scanning materializing dataless (iCloud) files
- **Symptom:** Walking the home tree could force-download iCloud "Optimize Mac Storage" / dataless files just to stat them, *consuming* space instead of freeing it.
- **Cause:** Naive `os.walk` + `stat` on everything; no dataless-file awareness.
- **Fix:** Use APFS dataless-aware enumeration (skip `NSURLUbiquitousItemIsDownloadingKey` / dataless items; use `URLResourceValues`), and never recurse into iCloud-only content.
- **Status:** design-fix (verify in macOS engine).

### 🔴 BUG-008 — `safe_under_home` allowlists system `/Library/Caches` for deletion
- **Symptom:** A path resolving under the *root-level* system cache could pass the delete guard.
- **Cause:** `core/fs.py:98-102` allowlists `/Library/Caches` and `/private/var/folders`; `safe_under_home()` is the **sole** guard for both `move_to_trash` and `permanent_delete`.
- **Fix:** Drop `/Library/Caches` (user caches live under HOME, already covered). Native engine: hard allowlist of HOME subpaths + the process-owned temp dir only; re-verify the *resolved* path is contained after symlink resolution.
- **Status:** design-fix.

### 🟠 BUG-009 — Orphaned match needs bundle-id PREFIX + team-id strip (refines BUG-004)
- **Cause:** `scanners/orphaned.py:62-77` requires exact `CFBundleIdentifier` equality, so `com.google.Chrome.helper`, `group.com.google.Chrome`, and `<TeamID>.com.google.Chrome` folders of *installed* apps look orphaned.
- **Fix:** Match on bundle-id **prefix**; strip a leading 10-char team-id; claim `group.*` and `<teamid>.*` variants. Keep REVIEW severity + explicit confirm.
- **Status:** design-fix + curated allowlist.

### 🟡 BUG-010 — Installer scan pre-selects generic `.xz`/`.bz2`/`.zip` as SAFE
- **Symptom:** `myphotos.xz`, `important_notes.bz2`, a project `.zip` in Downloads get matched as "installers," marked SAFE, and **pre-checked** for deletion.
- **Cause:** `scanners/installers.py:12` includes bare `.xz`/`.bz2`; matches yield `severity=SAFE, selected=True` (`installers.py:52-54`).
- **Fix:** Restrict to true installer types (`.dmg`/`.pkg`/`.iso`). Ambiguous archives → REVIEW, never pre-selected.
- **Status:** design-fix.

### 🟡 BUG-011 — Scan worker can drop the final DoneMessage (race)
- **Cause:** `ui/app.py:210-220` reschedules the poll only while `worker.is_running()`; the thread can exit before the last queue drain, so "Scan complete" / final totals can be missed.
- **Fix:** Drain the queue once more after the worker stops (or key off having seen `DoneMessage`); catch only `queue.Empty`, not bare `Exception`. (Native: structured concurrency / `AsyncStream` removes the race.)
- **Status:** design-fix.

### 🟡 BUG-012 — Delete accounting races on `path.exists()` and only covers the current category
- **Cause:** `ui/app.py:429-454` sets `item.size=0`, then rebuilds by re-probing `path.exists()` (racy) and only for the visible category, so cross-category totals misreport.
- **Fix:** Operate over all categories' selected items; track success by catching the action's exceptions, not by re-probing existence.
- **Status:** design-fix.

### ⚪ BUG-013 — Docker advice overloaded onto a fake path + RISKY severity
- **Cause:** `scanners/dev_caches.py:84-93` yields a synthetic Docker "info" item with `size=0`, a non-existent sentinel path, and RISKY severity to make it non-deletable.
- **Fix:** Add a real `advice`/`info` item kind (or `isActionable` flag); render advice rows separately so they're never mistaken for deletable items. (Docker should be reclaimed via `docker system prune`, run with a daemon-running guard — see SPEC §3.)
- **Status:** design-fix.

---

## Fixed

_(none yet)_

---

## Notes / conventions
- Trash, don't permanently delete, by default. Permanent delete requires explicit, typed confirmation for large amounts.
- `SAFE` items may be pre-selected; `REVIEW` never auto-selected; `RISKY` never selectable (info-only).
- Every destructive action is logged here if it ever misbehaves in testing.
