Both load-bearing claims are confirmed in source: `bySize` Pass-1 retains a fully-resolved URL per candidate with no cap (line 352-354), and `AppInventoryStore.run()` wraps the walk in `Task.detached` whose `Task.isCancelled` (line 123) cannot see the parent's cancellation. I have enough to write the plan.

---

# Cairn — Combined Action Plan (Memory, Architecture, Bugs, UI, Naming, Gaps)

*Principal-engineer synthesis of the memory/perf audit, the correctness/bug audit, the product-gap audit, and OSS research (Pearcleaner, czkawka, MacDirStat, GrandPerspective, mac-cleanup, SpaceSaver). The two test stub findings in the JSON were noise and are ignored.*

---

## 1. MEMORY — make it run lean (you hit 50 GB)

### 1.1 Is the hoist fix sufficient? — Verdict: necessary, sound, but NOT sufficient.

The hoist is the correct root-cause fix for the *runaway* growth and all three audits independently confirm it:

- `HealthStore`, `DuplicateStore`, `AppInventoryStore` are now owned as `@State` in the single live `AppShell` (`Cairn/UI/AppShell.swift:59-62`), so they persist for the app's lifetime instead of being recreated per navigation.
- Each has `nonisolated(unsafe) private var scanTask` + `deinit { scanTask?.cancel() }` (`HealthStore.swift:54-56`, `DuplicateStore.swift:108-110`, `AppInventoryStore.swift:61-63`).
- Re-entry is idempotent (`scanIfNeeded`/`startIfNeeded` guard on `phase`/`hasScanned`), so navigate-away no longer orphans a walk and return no longer spawns a second one.
- The prime offender, `FileScan.measure`, **already** wraps each enumerated item in `autoreleasepool` (`FileScanning.swift:70-86`) — the single hottest path is already mitigated. **Do not "fix" this twice.**

**But four classes of growth remain that the hoist did not touch.** On a machine already pushed to 50 GB these compound. Address all of them.

### 1.2 Concrete additional changes (in priority order)

**A. `DuplicateStore` Pass-1 — the #1 remaining spike. `Cairn/Core/DuplicateStore.swift`, `findDuplicates(...)` ~lines 330-358.**

The Pass-1 enumerator is already wrapped in `autoreleasepool` (line 336) and already short-circuits symlinks/iCloud/packages — better than the audit's worst-case read. The two *real* remaining problems, both confirmed in source:

1. **`bySize` is uncapped.** `candidateCap` (the `cap` argument) only bounds Pass-2 hashing (lines 362, 370, 374). Pass-1 appends a `Candidate` for *every* regular file ≥ `minSize` (1 MB) across Downloads/Documents/Desktop/Pictures/Movies. A media-heavy `~/Pictures`/`~/Movies` holds tens-to-hundreds of thousands of ≥1 MB files; `bySize` grows with the full count.
2. **Eager symlink resolution.** Line 353 computes `url.resolvingSymlinksInPath()` for *every* candidate and stores it in the `Candidate` struct (`resolved`), so each retains **two** URLs — even though the vast majority never reach a duplicate group.

Fixes:
- **Cap Pass-1 retention.** Track a running count; once total candidates exceed a bound (e.g. 200,000), stop appending and surface a `partial: true` flag to the UI ("Scanned the largest files — N more not shown"). Mirrors czkawka's bounded streaming and SpaceSaver's progressive batching.
- **Defer `resolvingSymlinksInPath()` into Pass-2.** Drop `resolved` from the Pass-1 `Candidate`; compute the resolved URL only inside the `byHash` loop (lines 380-388) for files that actually survive into a group. Halves the per-candidate URL retention and removes one syscall per candidate.
- **Cheap singleton pruning (optional).** Periodically drop size-buckets that still have count==1 — only `count > 1` buckets can ever be duplicates (line 360). This is czkawka's stage-1 "group by exact size" funnel; pruning singletons keeps `bySize` small without changing results.

**B. `IconCache` — unbounded process-lifetime dictionary. `Cairn/UI/FileIcon.swift:6-36`.**

`IconCache.shared` holds `byPath: [String: NSImage]` and `byExt: [String: NSImage]`, inserted forever, never evicted, guarded by a manual `NSLock`. Every `FileIcon` (LargeFiles rows, Apps rows + uninstall sheet, `ToolIcon`) and every `ThumbnailView` fallback funnels through `icon(for:)`, so scrolling a large list keys one full-resolution `NSWorkspace` icon per distinct path **permanently**.

Fix: replace **both** dictionaries with `NSCache<NSString, NSImage>`.
- `byPath` keyed by path string; `byExt` keyed by lowercased extension.
- Set `countLimit` (1,000–2,000) and `totalCostLimit` (cost = pixel area).
- `NSCache` is thread-safe — **delete the `NSLock`** — and evicts automatically under memory pressure.

**C. `ThumbnailCache` — unbounded full-thumbnail dictionary. `Cairn/UI/DuplicatesView.swift:10-35`.**

`ThumbnailCache.shared.store: [String: NSImage]` grows forever — one QuickLook-rendered `NSImage` per representative AND per file row in every expanded group (sizes 40 and 28). A large duplicate result with many expanded groups retains hundreds of decoded bitmaps, directly working against the RAM fix.

Fix:
- Switch `store` to `NSCache<NSString, NSImage>` with `countLimit` ≈ 500 and `totalCostLimit` based on pixel area.
- **Fix the stale-key bug while here:** the key is `path+side` but the doc comment claims `+mtime`. Include `mtime` in the key so a changed file doesn't serve a stale thumbnail.

**D. Bounded concurrency on Smart Scan. `Cairn/Core/ScanStore.swift`, `run()` ~lines 100-124.**

`withTaskGroup` adds a child task for *every* one of the 19 scanners with **no cap**. `DevProjectsScanner` and `GitMaintenanceScanner` each DFS the entire home tree; `OrphanedAppDataScanner`/`AppCachesScanner` walk Library subtrees — all at once, while DevProjects *also* spawns its own `activeProcessorCount-1`-wide inner sizing group. This is the launch CPU/page-cache thrash spike and amplifies every other issue.

Fix:
- Throttle outer fan-out to **4–6 concurrent scanners** (semaphore, or a windowed `withTaskGroup` that only keeps N in flight).
- Run the two whole-home walkers (`DevProjects`, `GitMaintenance`) **sequentially**, or better, **share a single home traversal** between them — they prune nearly the same `skipNames` set (GrandPerspective's "walk once" lesson).

**E. Parallelize + cache `AppInventoryStore`. `Cairn/Core/AppInventoryStore.swift`, `enumerate(...)` lines 133-198.**

Confirmed: for each of 100+ apps it does `FileScan.measure(raw.url, maxFiles: 40_000)` (whole bundle) plus a `FileScan.measure(entry.url, maxFiles: 20_000)` per matching `~/Library` entry — **fully sequential** on one task, every result retained for the session, and `rescan()` repeats the whole cost.

Fix:
- Parallelize per-app sizing with a **bounded `TaskGroup`** (width = `activeProcessorCount - 1`) — the exact pattern `DevProjectsScanner` already uses.
- Add a **bundle-size cache keyed by (bundle path, mtime)** so a rescan skips unchanged apps (czkawka/GrandPerspective incremental-rescan lesson).
- Lower `maxFiles` for associated entries from 20,000 → ~5,000; they feed only a size label.

**F. `ItemRow` `NSWorkspace.runningApplications` churn. `Cairn/UI/ItemRow.swift:83-88` + `Cairn/Safety/RunningApps.swift:9-25`.**

`RunningApps.running(amongst:)` is called in the view body per visible quit-gated row per redraw; each call builds `Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })` — a full process enumeration. Not a leak, but needless main-actor allocation during live-streaming scans.

Fix: compute the running-bundle-id `Set` **once per render pass** (or cache it in an `@Observable` with a short TTL, refreshed off `NSWorkspace.didLaunch/didTerminate` notifications) and pass it down.

**G. Shared mtime-keyed size cache (efficiency, not a spike). `HealthStore.swift:295-330`, `OrphanedAppDataScanner`, `AppInventoryStore`.**

Health (Bugs page), the Smart-Scan `OrphanedAppDataScanner`, and Apps each independently `measure` overlapping `~/Library` trees, so a user who visits all three pays the same sizing 3×. Introduce a small shared `path → (mtime, allocatedSize)` cache that all three `FileScan.measure` callers consult. (HealthStore already does the right cheap pre-filter on folder mtime at line 312 — extend that idea into a shared cache.)

### 1.3 Memory acceptance criteria

After A–F: idle RSS stable on navigation; a full duplicates scan over a large `~/Pictures` stays bounded (cap enforced, partial flag shown); icon/thumbnail memory drops under pressure; Smart-Scan peak CPU bounded to the concurrency window. Profile with Instruments (Allocations + the "persistent vs transient" split) before/after.

---

## 2. Scan architecture — what should auto-run vs run on-demand

### Direct answer to "does everything just auto-scan? is that normal?"

**Right now: yes, and no, it's not normal — it's the single biggest deviation from how every credible OSS cleaner works, and you should change it.**

`AppShell.onAppear` fires `store.startScan()` unconditionally on first launch (`AppShell.swift:86`), running all 19 scanners — including the whole-disk DevProjects hunt and (unless disabled) external volumes — *before the user has oriented*. The per-page stores (Duplicates/Apps/Health) are correctly lazy, but the heavy main scan is the opposite.

**The OSS consensus is unambiguous — nobody scans everything on launch:**

- **Pearcleaner / AppCleaner** are *purely on-demand per single app*. Nothing is indexed at launch. The only background process is a ~2–5 MB **Trash watcher** ("Sentinel" / "SmartDelete") that wakes the app on a real event (an `.app` hits the Trash) and then runs a *scoped* scan. (alienator88/Pearcleaner; freemacsoft.net/appcleaner)
- **MacDirStat / GrandPerspective / OmniDiskSweeper / czkawka / SpaceSaver** all scan **on-demand per user-chosen root**, stream results incrementally, and cache/persist between runs. (phalladar/MacDirStat; grandperspectiv.sourceforge.net; qarmin/czkawka)
- This is also Cairn's own positioning advantage vs CleanMyMac's daemon: "runs only when you open it." Auto-scanning everything at launch throws that away.

### Recommended model

| Tier | What | When |
|---|---|---|
| **Instant (launch)** | Land on Dashboard **idle**, showing **last cached scan snapshot**. Zero filesystem work. | Always |
| **Light auto (optional, opt-in)** | Cheap, bounded **caches-only** subset (dev caches, app caches) — fast, low-risk. | Only if user opts in |
| **On-demand (user-initiated)** | Full Smart Scan, Developer hunt, Large Files, Duplicates, Apps, Health. | When user clicks "Start Smart Scan" / navigates to that page |
| **Event-driven watcher (future, opt-in)** | Pearcleaner-style ~MB Trash/FSEvents helper → scoped scan on relevant event (app trashed, big download finished). **Never** an autonomous full-disk scan. | Background, near-zero cost |

**Concrete changes:**
1. **Remove the unconditional `startScan()` from `AppShell.onAppear`** (`AppShell.swift:86`). Land idle; the Dashboard already has a prominent "Start Smart Scan" CTA (`DashboardView.swift:37-43`) that is currently redundant. Scan on first navigation to Smart Scan, or on that button.
2. **Persist scan snapshots** (SwiftData/Core Data, compressed) so reopening shows results instantly without re-walking — GrandPerspective stores compressed snapshots ~1/10 size, ~10× faster load; SpaceSaver persists via SwiftData. Reload-then-incremental-refresh.
3. **Incremental refresh:** re-walk only folders whose dir mtime changed (FSEvents or mtime compare), not a full re-traversal (GrandPerspective "Refresh").
4. **Stream + throttle:** keep streaming results to the UI throttled to ~50 ms (MacDirStat's `AsyncStream` + `ScanCoordinator`); pair with OmniDiskSweeper-style live size sorting so the biggest items are actionable before the walk finishes.
5. **Faster traversal (perf, later):** for the disk-map/large-file walker, prefer BSD `fts_open/read/close` or `getattrlistbulk` over `FileManager.enumerator` (MacDirStat).
6. **Dup engine funnel:** adopt czkawka's 3-stage funnel — size-group → **prehash first/last few KB** → full hash. Cairn already does size-group + full SHA-256 (`DupHash.fingerprint`, line 375) but **lacks the prehash stage**; adding it eliminates ~50% of same-size candidates without full reads. Persist a hash cache keyed on `(path, size, mtime)`, only caching files > 5 MB to bound cache size, so re-scans are near-instant.

---

## 3. Bugs to fix (ordered by severity, with file + fix)

### CRITICAL / HIGH — data safety & security

**B1 — App uninstall trashes associated `~/Library` data even when the bundle move fails (orphans user data). HIGH.**
`Cairn/Core/AppInventoryStore.swift` `uninstall(_:)` ~lines 387-408. The loop trashes every `app.associated` entry **first**, then trashes `app.url`, then decides success on the bundle move. If the bundle trash fails (busy, perms, re-launched), `failed += 1`, the app is **not** added to `done` — so the app stays installed while its Application Support / Containers / Preferences are already in the Trash. Violates the all-or-nothing Safe Removal promise.
**Fix:** trash the bundle first, bail if it fails, *then* trash associated:
```swift
let (bundleOK, bundleBytes) = Self.trash(app.url)
guard bundleOK else { b.summary.failed += 1; continue }
for entry in app.associated { /* trash entry */ }
```

**B2 — App uninstall bypasses the central `SafePaths` chokepoint. HIGH.**
`AppInventoryStore.uninstall()` trashes via its own `isUninstallSafe()` (~lines 417-453), **not** `SafePaths.evaluate()`. That guard only checks "is the `.app` under /Applications" and "is the associated file under `~/Library`" — but the audited denylist (Keychains, Mail, Messages, MobileSync, Photos, `.ssh`) lives *under* `~/Library`, so it is never consulted. The associated set is built by `dottedPrefixMatch` over normalized names (lines 171-179); a short/common-token bundle id can prefix-match unrelated `~/Library` folders and sweep protected data into `associated`.
**Fix:** route **every** uninstall trash through `SafePaths.evaluate()` with an explicit audited app-uninstall allowlist-of-roots. Require `dottedPrefixMatch` to demand ≥2 dotted bundle-id segments before collecting associated paths. Add unit tests proving a system app, `~/.ssh`, `Library/Keychains`, and a mis-matched protected folder are all **rejected**.

**B3 — `AppInventoryStore` enumeration is uncancellable. HIGH.**
`run()` (lines 121-130) does `Task.detached { Self.enumerate(isCancelled: { Task.isCancelled }) }`. A **detached** task gets a fresh context, so `Task.isCancelled` inside is **always false** — `cancel()`/`deinit` cancels the wrapper but the heavy walk (40k/20k `maxFiles` per item) runs to completion off-main. This is the very "orphaned scan keeps running" class the hoist meant to kill, hidden one layer down. (Confirmed in source: the `isCancelled` closure at line 123 closes over the detached task's own cancellation, not the parent's.)
**Fix:** don't use `Task.detached` for the cancellation-sensitive walk. Run `enumerate` inside the (non-detached) `scanTask` context with a captured cancellation flag you flip — exactly how `DuplicateStore.findDuplicates` (a `nonisolated static` run in a non-detached `Task`) correctly propagates `Task.isCancelled`.

### MEDIUM — trust, correctness, monetization

**B4 — Duplicates "Review Duplicates →" deletes immediately, no review step. HIGH on trust / MEDIUM functional.**
`Cairn/UI/DuplicatesView.swift:315-318` → `DuplicateStore.removeSelected()` trashes selected copies on the spot. The button labeled "Review" performs the destructive action with no review/dry-run/confirm — and the per-group primary button labeled "Remove" (lines 234-240) only stages selection (`keepBest` + expand) and removes nothing. Two removal entry points behave oppositely; both labels lie. This is the one place that violates Cairn's "mandatory dry-run, review-then-clean" brand promise (SPEC §4.4).
**Fix:** route the footer action through a confirm/review sheet (reuse a generalized `ReviewSheet` seeded with the selected `DupFile`s — one chokepoint — or a `DuplicateConfirmSheet` mirroring `UninstallConfirmSheet`). Relabel footer "Move N to Trash" (only honest if a confirm follows); relabel the per-group button "Stage for removal."

**B5 — `RootView.swift` is dead code that hard-codes `proEnabled = true` and owns a second `ScanStore`. MEDIUM.**
`Cairn/UI/RootView.swift:3-41` constructs its own `@State ScanStore`, sets `private let proEnabled = true`, and calls `startScan()` in `onAppear`. Never instantiated (live path is `CairnApp → AppShell`). As dead code it (a) contradicts the single-store hoist invariant, (b) would unlock paid cleans for free if rewired, (c) spawns a full second concurrent scan if a preview touches it.
**Fix:** delete `RootView.swift`. Verify `Sidebar.swift`/`SettingsView.swift`/`CategoryDetailView`/`ScanningHero` aren't otherwise orphaned and delete those too (live settings screen is `SettingsPage`).

**B6 — "Clean AI Models" mission pre-selects Review-severity items. MEDIUM.**
`Cairn/UI/Missions.swift:25-28`: mission `ai` does `s.select { _, g in g == .ai }` — selects *all* AI items regardless of severity, while the `dev`/`creator` missions correctly add `it.severity == .safe`. A one-click mission can stage Review-severity model weights (the only local copy). Items still pass ReviewSheet, but it violates "never pre-select Review."
**Fix:** `s.select { it, g in g == .ai && it.severity == .safe && it.isRegenerable }`.

**B7 — Apps filter-chip counts: no thousands separator + O(n) per chip per render. MEDIUM.**
`Cairn/UI/AppsView.swift:149` renders `Text("\(count(c))")` with raw `Int` interpolation — no grouping, unlike `DuplicatesView`'s `grouped()`. With many apps "All Apps" shows e.g. `1043` un-grouped; combined with `.fixedSize()` + capsule padding this is the reported "wrapped/cramped number." Also `count(c)` runs a full `store.apps.filter{}.count` for every chip on every body eval (5× full scans per render).
**Fix:** format with the shared `grouped()`/`NumberFormatter` helper; compute all five counts in a **single pass** into `[Chip: Int]`.

### LOW — defensive / consistency

**B8 — Force-unwrap in duplicate engine. LOW (latent crash).** `DuplicateStore.swift:361` `clusters.sort { $0.first!.size > ... }`. Safe today (filter guarantees ≥2), but a future predicate change crashes a background task. Fix: `($0.first?.size ?? 0) > ($1.first?.size ?? 0)`.

**B9 — `FileScan.home` vs `SafePaths.home` symlink mismatch. LOW (fails closed).** `FileScanning.swift:21` does **not** `resolvingSymlinksInPath()` while `SafePaths.home` (`SafePaths.swift:16`) does. On FileVault-relocated / symlinked homes, a legit `~/LaunchAgents` plist can be wrongly *refused* (never wrongly deleted — fails closed). Fix: make `FileScan.home` also resolve symlinks, or pass `SafePaths.home` as the allowed root in `HealthTrash`.

**B10 — Apps `.task` lacks the `didStart` latch. LOW (consistency).** `AppsView` relies solely on `hasScanned`/`isScanning`; HealthView/DuplicatesView use a `didStart` latch. Functionally adequate today; add `@State private var didStart = false` for parity and re-entrancy safety. (`AppsView.swift:45`)

**B11 — Health per-row "Fix" runs with no confirm, unlike "Fix All". LOW.** `HealthView.swift:144-162`: per-group `Fix` calls `store.fix(group:)` inline (recoverable Trash, SafePaths-guarded) while "Fix All" goes through `FixAllSheet`. Inconsistent, and the small Fix button shares a row with `onTapGesture`, so trackpad hits can mis-fire. Fix: route per-group Fix through `HealthReviewSheet` (it already exposes `onFix`); make the button consume the tap.

**B12 — `RunningApps.displayNames` label cosmetics. LOW.** Works correctly; `shortName` produces odd uppercased tags like "QUIT DOCKER". Optional: map known bundle ids to display names. No correctness change.

---

## 4. UI/UX upgrades to hit the premium-mockup bar

The eight redesigned screens are built and broadly match the mockups. Gaps, mockup-driven:

**Iconography & naming surface:**
- Sidebar "Bugs & Fixes" uses a `ladybug` icon — literally a bug. Change to `heart.text.square` / `stethoscope` / `checkmark.shield` (see §5).

**Interaction polish (mockup parity):**
- **Developer donut is static.** No hover-dim, no tap-to-expand. Wire the donut legend/segment → expand the matching `DevToolRow` (lift `expandedBucketID` into `DeveloperCleanupView`). `DeveloperCleanupView.swift:16-20,99-101`
- **Large Files "Last Opened" column is mislabeled** — it shows `item.latestModified`, not access date. Either fetch `contentAccessDate` for that column/inspector row, or relabel it "Modified." `LargeFilesView.swift:104-105,152-153`
- **Dashboard Duplicates tile shows "—"/"Soon"** though `DuplicatesView` is fully built. Wire live `groupCount`/`reclaimable` or a "Scan" CTA. `DashboardView.swift:73`

**Missing premium states / elements:**
- **No FDA onboarding banner.** Engine tracks `FullDiskAccess.isGranted` / `ScanStore.fdaGranted` / `ScanItem.permissionDenied`, but no UI prompts for it. Add a dismissible Dashboard/Smart-Scan banner when `!fdaGranted` (deep-link `FullDiskAccess.openSettings`) and render `bucket.permissionGap` as an "Incomplete — grant Full Disk Access" row state. (SPEC §4.5)
- **No persistent removal log / undo surface.** Only a transient `CelebrationOverlay`/`undoLast`. Add Settings ▸ Restore Bin backed by `lastCleanSummary.restorable`; unify Health/Duplicate/App removals into it. (SPEC §4.4)
- **No per-volume free-space precondition** messaging before promising reclaim (mac-cleanup's dry-run-first "this will free ~N GB"). Surface "needs N GB free" in the review sheet. (SPEC §5.2)
- **`SafetyPill`** correctly reflects worst severity (honest deviation from always-green mockup — keep it).

**Spacing/sizing:** the chip width issue in B7 is the most visible spacing defect — fix the number grouping and it resolves.

---

## 5. Naming recommendation

| Current | Verdict | Recommended |
|---|---|---|
| **Bugs & Fixes** | ✗ Wrong. Reads like an app changelog (which it literally used to be). "Bugs" implies defects *in Cairn*, not maintenance of the user's Mac. The screen's own hero says "Keeping your Mac healthy." | **→ "Health"** (best) or "Maintenance" |
| **Duplicates** | ✓ Keep. Industry-standard (DaisyDisk, Gemini, CleanMyMac all use it). | Duplicates |
| Developer Cleanup / Large Files / Apps / Smart Scan | ✓ All clear. | Keep |

**Clear pick: rename "Bugs & Fixes" → "Health."** It matches the existing `HealthStore`/`HealthView` names and the hero copy, so it reduces code/UI drift. Update consistently: `NavSection.bugs` title (`AppShell.swift:18,34`), the Dashboard tile label (currently "Fixes," `DashboardView.swift:75`), the screen header, **and** swap the `ladybug` sidebar icon for `heart.text.square`/`stethoscope`/`checkmark.shield`.

---

## 6. What's still missing vs spec / research

1. **Tool-mediated "correct-command" cleans are invisible in the new UI** (the headline paid wedge). `CleanMethod.tool(ToolCommand)` + `Cleaner.runTool` exist with Pro gating (`Models.swift:30-48`, `Cleaner.swift:79-100`), but the Developer screen only renders bucket totals + generic trash-path clean. Docker/Go/pnpm items that *need* a command will fail or be skipped. **Add:** a "Correct command" chip + command string on `.tool` items, a Pro lock + upgrade affordance for free users, and a "run it yourself" fallback. This is core value, not polish. (SPEC §2, §4)
2. **FDA onboarding banner + permission-gap row state** — §4 above. (SPEC §4.5)
3. **Persistent removal log / undo / Restore Bin** — §4 above. (SPEC §4.4)
4. **Per-volume free-space preconditions** — §4 above. (SPEC §5.2)
5. **Persisted/compressed scan snapshots + incremental refresh** — not present; required to make launch instant (§2). (GrandPerspective, SpaceSaver)
6. **Event-driven Trash/FSEvents watcher** — not present; the OSS-standard replacement for background scanning (§2). (Pearcleaner Sentinel, AppCleaner SmartDelete)
7. **Dup-finder prehash stage + persistent hash cache** — engine does size-group + full SHA-256 but no prehash and no `(path,size,mtime)` cache (§2/§3). (czkawka)
8. **Declarative dev-cache module catalog** — consider making cache locations data, not hardcoded scanners, so new targets are config (mac-cleanup-py's 40+ modules).
9. **Orphaned data double-surfaced** — detected by both `HealthStore` and the registered `OrphanedAppDataScanner` (Apps area), risking double-counted reclaim. Pick one owner. (`HealthStore.swift:218-330`, `AppShell.swift:50`)
10. **Multi-window scan duplication** — `CairnApp` uses `WindowGroup` (`CairnApp.swift:22`); a second window = a second `AppShell` = a full second scan + new unbounded caches. **Switch to single `Window` scene** (macOS 13+), or hoist stores above the scene so all windows share one `ScanStore`. Direct multiplier on the memory problem.

**Security guardrail from research (do not repeat Pearcleaner's CVE):** if Cairn ever adds an elevated/privileged helper for system-dir deletes, **authenticate every XPC client** (`setCodeSigningRequirement` / verify peer `audit_token` via `SecCodeCheckValidity`, reject non-Cairn signing identities) and expose **only narrow typed operations** ("trash these validated paths") — never a generic shell/command endpoint. Validate every path server-side against an allowlist. (GHSA-gr2j-65fh-8pvc)

---

## 7. Ordered implementation checklist (do this first)

**Wave 1 — Safety & data integrity (ship before anything else):**
1. **B1** — reorder uninstall: trash bundle first, bail on failure, then associated. (`AppInventoryStore.swift`)
2. **B2** — route all uninstall trashes through `SafePaths.evaluate()`; tighten `dottedPrefixMatch` to ≥2 segments; add rejection unit tests. (`AppInventoryStore.swift`)
3. **B4** — put a confirm/review sheet in front of Duplicates removal; fix both misleading labels. (`DuplicatesView.swift`)
4. **B3** — make `AppInventoryStore` enumeration cancellable (drop `Task.detached`). (`AppInventoryStore.swift`)

**Wave 2 — Memory (close out the 50 GB class fully):**
5. **1.2A** — cap Pass-1 `bySize`, defer symlink resolution, prune singletons. (`DuplicateStore.swift`)
6. **1.2B/C** — `IconCache` + `ThumbnailCache` → `NSCache` with limits; fix thumbnail mtime key. (`FileIcon.swift`, `DuplicatesView.swift`)
7. **#10** — `WindowGroup` → single `Window`. (`CairnApp.swift`)
8. **1.2D** — bound Smart-Scan fan-out to 4–6; serialize/share the two whole-home walkers. (`ScanStore.swift`)
9. **1.2E** — parallelize + (path,mtime)-cache `AppInventoryStore` sizing. (`AppInventoryStore.swift`)
10. **1.2F/G** — cache running-bundle-id set; shared mtime size cache. (`ItemRow.swift`, `RunningApps.swift`)

**Wave 3 — Scan architecture (the "stop auto-scanning everything" change):**
11. **§2.1** — remove unconditional `startScan()` from launch; land idle on Dashboard. (`AppShell.swift:86`)
12. **§2.2/2.3** — persist compressed scan snapshots + incremental mtime/FSEvents refresh.
13. **§2.6** — add czkawka prehash stage + `(path,size,mtime)` hash cache (>5 MB only). (`DuplicateStore.swift`/`DupHash`)

**Wave 4 — Naming, cleanup, monetization, polish:**
14. **§5** — rename "Bugs & Fixes" → "Health"; swap `ladybug` icon; update Dashboard tile.
15. **B5** — delete `RootView.swift` (+ verify/delete orphaned `Sidebar`/`SettingsView`).
16. **B6/B7** — AI mission severity guard; Apps chip count grouping + single-pass counts.
17. **#1** — surface `.tool` correct-command cleans + Pro lock in Developer screen.
18. **#2/#3** — FDA banner + permission-gap row; persistent Restore Bin / removal log.
19. **B8–B12** — defensive/consistency cleanups (force-unwrap, symlink home, Apps `didStart`, per-row Fix confirm, label cosmetics).
20. **§4** — interactive Developer donut; Large Files "Last Opened" relabel/fix; Dashboard Duplicates tile live data.

**Wave 5 — Future / strategic:** event-driven Trash watcher (Pearcleaner Sentinel model); declarative dev-cache module catalog; fts/getattrlistbulk traversal; secure-XPC privileged helper *only if* elevated deletes are ever needed.

---

### Key file references
- `/Users/augustusedem/CLEANSTUFF/Cairn/Core/DuplicateStore.swift` (Pass-1 cap, prehash, force-unwrap, removal flow)
- `/Users/augustusedem/CLEANSTUFF/Cairn/Core/AppInventoryStore.swift` (B1/B2/B3, sizing parallelism+cache)
- `/Users/augustusedem/CLEANSTUFF/Cairn/UI/FileIcon.swift` + `/Users/augustusedem/CLEANSTUFF/Cairn/UI/DuplicatesView.swift` (caches, B4)
- `/Users/augustusedem/CLEANSTUFF/Cairn/Core/ScanStore.swift` + `/Users/augustusedem/CLEANSTUFF/Cairn/UI/AppShell.swift` (concurrency, launch scan, naming)
- `/Users/augustusedem/CLEANSTUFF/Cairn/App/CairnApp.swift` (WindowGroup → Window)
- `/Users/augustusedem/CLEANSTUFF/Cairn/UI/RootView.swift` (delete), `/Users/augustusedem/CLEANSTUFF/Cairn/UI/Missions.swift` (B6), `/Users/augustusedem/CLEANSTUFF/Cairn/UI/AppsView.swift` (B7/B10)