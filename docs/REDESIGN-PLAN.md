Confirmed — Space Missions uses an adaptive `LazyVGrid` (wraps) and Safe & Secure sits under System Status in the dashboard. Everything in the specs is grounded. Here is the consolidated plan.

---

# Cairn Redesign — Consolidated Implementation Plan

**Scope:** 5 section screens (Developer, Apps, Duplicates, Large Files, Bugs & Fixes) move from generic `SectionView`/`CategoryDisclosure`/`ComingSoon` rendering to dedicated page layouts. This plan answers the 4 cross-cutting decisions, defines reusable archetypes and the icon system, and gives an ordered roadmap with concrete files and the new engine work.

---

## 1) PAGE vs COLLAPSE — Decision: dedicated pages, 3 reusable archetypes

**Recommendation: convert every section to its own full page.** The accordion `CategoryDisclosure` card was right for a generic "smart scan results" list, but the mockups are dedicated workspaces (sortable tables, filter chips, right-side inspectors, donuts). Keep `SectionView` only as the fallback for the sections we are *not* redesigning yet (`.ai`, `.creative`). Route each redesigned section to its own root view in `AppShell.content`.

Do **not** invent new layout primitives per screen. All 5 screens collapse into **3 archetypes**:

### Archetype A — "Table + Right Summary/Donut Panel"
Left ~65% scrollable table card; right ~35% (~320–380pt fixed) sticky panel with totals, a donut/breakdown, a "why safe" rationale, and the primary CTA. Selection drives the right panel live.
- **Developer Cleanup** (donut breakdown of dev buckets + "Why it's safe")
- **Apps / Uninstaller** ("What will be removed" breakdown panel instead of a donut)

### Archetype B — "Table + Right Detail/Inspector Panel"
Same split, but the right panel is a *per-row inspector* (shown only when a row is selected for inspection) with metadata + per-file quick actions (Reveal / Ignore / Move to Bin). Selection-for-inspection is independent of the cleanup checkbox.
- **Large Files** (file inspector: kind, created, last-opened, reveal)

### Archetype C — "Grouped List + Stat Cards + Pinned Footer"
Top stat-card row, a toolbar (sort menu / search), an expandable grouped list (parent row → child rows mirroring `CategoryDisclosure` rotation + `.easeInOut(0.18)`), and a pinned bottom footer with the selection summary + primary CTA. No right panel.
- **Duplicates** (group → copies, keeper star)
- **Bugs & Fixes / Health** (a *centered hero* variant of C: header + `ShieldBadge` hero + issue-list card + "Fix All" footer)

> Shared building blocks across all three: `CardBackground`/`cairnCard`, `BrandButtonStyle`/`GhostButtonStyle`, `Fmt.*`, `Brand.*` tokens, the existing `ItemRow`/`ItemDetail` for any expanded per-item lists, and the `ReviewSheet` chokepoint for every actual clean. Build the table header + sortable-column + fixed-width-column pattern **once** (in Large Files or Apps) and reuse it for the other table screen.

---

## 2) ICON SYSTEM — one shared resolver, 4 tiers, async + cached

There is **no `.xcassets` in the project** (verified). The existing `IconCache` (`Cairn/UI/FileIcon.swift`) already wraps `NSWorkspace.shared.icon(forFile:)` with an extension-based fallback and a path/ext cache — **reuse it, do not reinvent.** It is currently a plain `final class` (sync); add async loading + a bundle-ID helper.

**Tier strategy (decided per row/bucket, fallback chain):**

1. **Tier 1 — Real installed-app bundle icon** via `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` → `IconCache.icon(for: appURL)`. Authoritative and self-updating. Used for: every Apps-screen row (`icon(forFile: appURL.path)`), and Developer buckets that map to a real Mac app (`xcode`→`com.apple.dt.Xcode`, `docker`→`com.docker.docker`, `ide-caches`→`com.microsoft.VSCode`/first `requiresQuitBundleIDs`, `android`→`com.google.android.studio`).
2. **Tier 2 — Real file/folder icon** via existing `IconCache.icon(for: item.resolvedURL)`. Used for: all Large Files & Duplicates rows (they are real on-disk paths), Developer folder buckets (`dev-projects` → node_modules folder, `git-bloat` → `.git`), and expanded `ItemRow`s everywhere.
3. **Tier 3 — Bundled brand-logo set** for tools with no Mac app and no system icon: **npm, yarn, pnpm, Homebrew, CocoaPods, Gradle, Flutter, Python/pip, conda.** **Recommendation: hand-draw simple brand-tinted glyphs** as `Shape`/`Canvas` marks in `CairnArt.swift` (consistent with the hand-drawn `CairnLogo`), tinted with `Brand` tokens. This stays license-clean (no shipping third-party trademarked raster art), theme-aware (dark/light), and avoids adding an asset catalog. Only used on **Developer** (and later AI/Creative cache) screens — explicitly **not** needed on Apps, Large Files, or Health.
4. **Tier 4 — SF Symbol fallback** from `bucket.info.systemImage` / `app.dashed`, rendered in `Brand.blue` inside a tinted `RoundedRectangle` tile. Guaranteed to always render; also the right choice for *abstract* rows — the **entire Health screen is SF-Symbols-only** (no real files to depict).

**New work for icons (build once, in the foundation phase):**
- Extend `IconCache` with `icon(forBundleID:)` (resolve app URL → `icon(for:)`) and make it `@Observable` with **async loading + memoization** so table scrolling stays smooth.
- New **`Icon`/`ToolIcon` view** (`Cairn/UI/ToolIcon.swift`): runs the 4-tier chain, fixed 28pt (rows) / larger in panels, `.interpolation(.high)`, async placeholder while loading, SF-Symbol final fallback. This single view serves Developer (per-bucket map), Apps (`AppIconView` is a thin wrapper), and Large Files/Duplicates (file-icon path).
- Add the **brand glyphs** (`BrandGlyph(.npm/.homebrew/.cocoapods/.gradle/.flutter/.python/.conda/...)`) in `CairnArt.swift`.
- For Duplicates only, add **`ThumbnailView` + `ThumbnailCache`** on top of `IconCache`, using `QLThumbnailGenerator` (QuickLookThumbnailing) for image/video/PDF content previews, falling back to `IconCache.icon(for:)` while loading / for non-previewable types.

> One trust rule, stated once: **real files & installed apps → NSWorkspace; tools with no system icon → bundled/hand-drawn brand glyph; anything categorical/abstract → SF Symbol.**

---

## 3) BUGS & FIXES — changelog relocation + real health fixer, with a conservative fix policy

**Confirm both moves:**
- **Move the changelog** (`TransparencyPanel` + `AppInfo` releases/fixes/promises) **into Settings/About.** Add an "About Cairn" card/entry in `SettingsPage.swift` that presents `TransparencyPanel`; rewire so `.bugs` no longer opens it (`AppShell.showAbout`). Update `DashboardView.cardItems` so the `.bugs` tile shows the **live health-issue count**, not `AppInfo.fixes.count`.
- **Build the real System-Health fixer** at `Cairn/UI/HealthView.swift` (centered-hero Archetype C). Flip `NavSection.bugs.opensSheet` to `false` (currently `true`, verified), add `case .bugs: HealthView(...)` to `AppShell.content`, and remove the `.bugs` special-casing in `NavSidebar.navRow` and `DashboardView.onOpen`.

**Safe-to-actually-fix vs advice-only in v1** (be conservative; drive the row button off `bucket.actionableCount > 0`, never hardcoded):

| Issue type | v1 behavior | Why |
|---|---|---|
| **Old Launch Agents** (`launch-agents`) | ✅ **Actually fix** — Trash the orphaned `~/Library/LaunchAgents/*.plist` whose program is missing | Lives under HOME (`allowedRoots = [FileScan.home]`), recoverable via Trash. Skip `com.apple.*`. The one genuinely safe deletion. |
| **Orphaned App Data** (`orphaned`, existing scanner) | ✅ **Actually fix** — already emits `.trash` items | Reuse `OrphanedAppDataScanner` as-is. |
| **Broken Login Items** (`login-items`) | ⚠️ **Advice-only** (`.adviceOnly`) | The `backgrounditems.btm` store is opaque/SIP-protected on modern macOS; detection is partial. Advise + Reveal, never auto-edit the login DB. May fold into LaunchAgents detection for v1. |
| **Corrupted Preferences** (`prefs-corrupt`) | ⚠️ **Advice-only** | Deleting a live prefs file resets app state. Flag parse failures + Reveal only. |
| **Permission Issues** (`permissions`) | ⚠️ **Advice-only**, tightly scoped to world-**writable** files in HOME config dirs | Never `chmod`, never touch system files. High false-positive risk — scope narrowly or it cries wolf. |

All health items are `severity .review` (never pre-selected). "Fix All" must **explicitly select safe+actionable items, then route through `ReviewSheet`** — never a silent purge. Advice-only rows are excluded from Fix All by construction (`cleanMethod.isActionable == false`, verified in Models). Keep grouping simple: leave the new buckets in `CategoryGroup.general` and have `HealthView` filter `store.buckets` by the fixed id set `['login-items','prefs-corrupt','orphaned','launch-agents','permissions']` (avoid an enum change). **Caveat:** `orphaned` is also surfaced under the current Apps mapping — once Apps moves to the new uninstaller, fold orphaned leftovers into the Apps "Leftover Files" chip or leave them solely in Health to avoid double-surfacing.

---

## 4) Two quick fixes already done (verified)
- **Safe & Secure** is now pinned/sticky under System Status in `DashboardView.swift`.
- **Space Missions** now wrap via an adaptive `LazyVGrid(columns: [GridItem(.adaptive(minimum: 168))])` in `Missions.swift` instead of scrolling off-screen.

No further work required on these; listed for roadmap completeness.

---

## 5) NEW engine work (the long pole — build before the UI that needs it)

1. **App Uninstaller scanner** (`AppInventoryScanner`) — biggest new capability. Enumerate `*.app` under `/Applications`, `~/Applications`, `/System/Applications` (system = shown, non-removable); read `Info.plist` (bundle id/name/version), `FileScan.measure` the bundle, `kMDItemLastUsedDate` via `NSMetadataItem`, Intel-vs-AppleSilicon via Mach-O fat-header read, and gather support/cache/leftover paths by reusing `OrphanedAppDataScanner`'s `normalize`/`strippingTeamID`/`dottedPrefixMatch` **in reverse** (collect instead of exclude — extract into a shared `BundleMatch` util). New `AppEntry` model groups `[ScanItem]` (bundle + support + leftover) with a `toggle()` that flips the whole set.
2. **Duplicate finder** (`DuplicateFinder`) — two-pass: group candidates by exact size, then SHA-256-verify multi-file clusters (`CryptoKit`, streamed 1MB chunks off-main, cancellable). New `DuplicateGroup`/`DuplicateCopy` models (the flat `ScanItem`/`Bucket` model has no grouping), new `FileHashing.swift`, `DuplicateStore`. Reuse `LargeOldFilesScanner` walk rules (no symlinks, skip iCloud stubs, opaque bundles, min-size floor).
3. **System-health scanners** ×4 — `LaunchAgentsScanner` (the only `.trash` one), `CorruptedPreferencesScanner`, `PermissionIssuesScanner`, `BrokenLoginItemsScanner` (last three `.adviceOnly`). Register all in `ScannerRegistry.all()`.
4. **SafePaths extension (BLOCKER for Apps).** Verified: `SafePaths.denyAbsolutePrefixes` hard-denies `/Applications`, `/Library`, `/System`. The current `Cleaner.trash()` **cannot** move an app bundle or its `/Library` support files. Add an **audited app-uninstall mode/flag**: give `AppInventoryScanner.allowedRoots` legitimate access to `/Applications`, `~/Applications`, the relevant `~/Library` + `/Library/Application Support` subtrees, and carve `/Applications` app-bundle removal out of the deny list **only for that path** — while keeping `/System`, Keychains, `.ssh`, Mail/Messages, Photos, MobileSync denied. **Ship with unit tests proving a system app and a protected path are still rejected.**

Smaller engine adds: `Fmt.count(_:Int)` grouped-decimal helper (Models.swift); developer-scoped sum helpers (or just local `reduce` in the view — no store change required); a generalized `ReviewSheet(items:onClean:)` so Duplicates can reuse the one trust surface.

---

## 6) Ordered build roadmap (what to build first)

**Phase 0 — Shared foundation (unblocks 4 of 5 screens; do first)**
1. Icon system: extend `IconCache` (async + `icon(forBundleID:)`, `@Observable`); new `Cairn/UI/ToolIcon.swift` (4-tier resolver); brand glyphs in `CairnArt.swift`.
2. Reusable table primitive (header + sortable columns + fixed-width alignment + hover/selected highlight) — build during the first table screen, then reuse.
3. `Fmt.count`; generalize `ReviewSheet` to `items:[ScanItem] + onClean` (preserves a single clean chokepoint for non-`ScanStore` flows).

**Phase 1 — Large Files (Archetype B, lowest risk, no new engine)** — *quickest visible win.*
- All data already exists (`large-old` + `installers` buckets, verified routed at `AppShell.swift:49`). New: `LargeFilesView.swift`, `FileIcon`-backed rows, `LargeFileType` UI classifier, on-demand `URLResourceValues` metadata loader, inspector panel. Branch `.largeFiles` to it; compute selection sums **locally** over the two buckets (not the global `store.selectedTotal`). Validates Archetype B + the table primitive.

**Phase 2 — Developer Cleanup (Archetype A)** — *exercises the full icon system + donut.*
- New: `DeveloperCleanupView.swift`, `DonutChart.swift` (make `ArcShape` in `DiskMapView.swift` non-private — verified `private` today — and reuse it). Recommended **8 rows = 8 real buckets** (finer tools shown on expand) rather than a synthetic 11-row re-bucket. `SafetyPill` reflects the bucket's *true worst severity* (honesty deviation from the always-green mockup). Route `.developer`. No engine change; all sums local.

**Phase 3 — Bugs & Fixes / Health (Archetype C centered-hero) + changelog relocation**
- Engine first: 4 health scanners + register. Then `HealthView.swift` (`ShieldBadge` over existing `HeroIllustration`), the Settings/About relocation of `TransparencyPanel`, routing flip (`opensSheet=false`), and the dashboard tile count update. Conservative fix policy per §3.

**Phase 4 — Duplicates (Archetype C grouped)** — *heaviest pure-engine net-new.*
- `FileHashing.swift` → `DuplicateFinder.swift` → `DuplicateModels.swift` → `DuplicateStore.swift` → `ThumbnailView`/`ThumbnailCache` → `DuplicatesView.swift`. Replace the `ComingSoon` case (verified `AppShell.swift:93`), lazy-start the scan on first navigation (do **not** run whole-disk hashing at launch), wire the dashboard `.duplicates` card. Min-size floor + candidate cap + cancellation + skip system/library. Add a `SelfTest` that two identical temp files group and a distinct one does not.

**Phase 5 — Apps / Uninstaller (Archetype A, highest risk — last)** — *the SafePaths blocker gates everything here.*
- Engine: `AppEntry` model → shared `BundleMatch` util → `AppInventoryScanner` (Intel/Mach-O + `kMDItemLastUsedDate`) → `AppInventoryStore` (grouped selection + `clean(appEntries:)`) → **SafePaths app-uninstall mode + rejection tests (BLOCKER)**. UI: `AppIconView`, `FilterChip`/`FilterChipBar`, `AppRow`/`AppsTable` (reuse Phase-1 table primitive), `AppRemovalPanel`, `ReclaimSummaryCard`, `AppsView`. Re-route `.apps` (currently → `orphaned` bucket, verified `AppShell.swift:50`); reconcile orphaned with the Health screen. Final uninstall confirm reuses `ReviewSheet` (QUIT-first via `RunningApps`) + `CelebrationOverlay`. **QA: undo must restore a trashed app bundle + support files; SafePaths must still reject `/System` and `~/.ssh`.**

**Rationale for order:** Phase 0 is shared scaffolding. Large Files ships value with zero engine risk and proves the table primitive. Developer proves the icon system + donut. Health and Duplicates are independent and can parallelize after Phase 0. Apps is intentionally last because it requires the audited SafePaths change and the most net-new engine surface — you want the table primitive, icon system, and review/undo flow all battle-tested before touching app-bundle deletion.

---

## 7) New files / views index

| Phase | New files | New views inside |
|---|---|---|
| 0 | `Cairn/UI/ToolIcon.swift` | `ToolIcon`; brand glyphs added to existing `CairnArt.swift`; `IconCache` extended in `FileIcon.swift`; `ReviewSheet` generalized; `Fmt.count` in `Models.swift` |
| 1 | `Cairn/UI/LargeFilesView.swift` | `LargeFilesHeader`, `StatCardRow`, `FilterChipBar`, `LargeFilesTable`, `LargeFileRow`, `LargeFileDetailPanel`, `FileIcon` (or reuse), `LargeFileType`, metadata loader |
| 2 | `Cairn/UI/DeveloperCleanupView.swift`, `Cairn/UI/DonutChart.swift` | `DevTableCard`, `DevToolRow`, `SafetyPill`, `RightSummaryPanel`, `ReclaimableCard`, `DonutBreakdownCard`, `WhySafeCard` (make `ArcShape` non-private) |
| 3 | `Cairn/UI/HealthView.swift`, `Cairn/Scanners/LaunchAgentsScanner.swift`, `Cairn/Scanners/CorruptedPreferencesScanner.swift`, `Cairn/Scanners/PermissionIssuesScanner.swift`, `Cairn/Scanners/BrokenLoginItemsScanner.swift` | `ShieldBadge`, `HealthIssueRow`; About card added to `SettingsPage.swift` |
| 4 | `Cairn/Core/DuplicateModels.swift`, `Cairn/Core/FileHashing.swift`, `Cairn/Scanners/DuplicateFinder.swift`, `Cairn/Core/DuplicateStore.swift`, `Cairn/UI/DuplicatesView.swift` (+ `Thumbnail.swift` or in `FileIcon.swift`) | `ThumbnailView`/`ThumbnailCache`, `DuplicatesHeader`, `StatCardsRow`, `ListToolbar`, `DuplicateGroupRow`, `DuplicateFileRow`, `DuplicatesFooter` |
| 5 | `Cairn/Apps/AppEntry.swift`, `Cairn/Core/BundleMatch.swift`, `Cairn/Scanners/AppInventoryScanner.swift`, `Cairn/Core/AppInventoryStore.swift`, `Cairn/UI/AppsView.swift` (+ SafePaths edit + tests) | `AppsHeader`, `ReclaimSummaryCard`, `FilterChip`/`FilterChipBar`, `AppsTable`, `AppRow`, `AppIconView`, `AppRemovalPanel`, `AppsFooter` |

**Routing changes, all in `Cairn/UI/AppShell.swift`:** branch `.largeFiles`→`LargeFilesView`, `.developer`→`DeveloperCleanupView`, `.bugs`→`HealthView` (+ `opensSheet=false`), `.duplicates`→`DuplicatesView` (replacing `ComingSoon`), `.apps`→`AppsView`. Leave `.ai`/`.creative` on `SectionView`.

---

### Key risks / honest caveats to carry forward
- **SafePaths app-uninstall carve-out is the single highest-risk change** in the whole redesign — audited, test-gated, Apps-only.
- **SafetyPill must not be uniformly green** — real Developer buckets contain `.review`/`.risky`/advice items (Xcode Archives risky, Android system images review, Docker-down = size-0 advice). Reflect true worst severity.
- **Never use global `store.selectedTotal`/`selectedCount`** on per-section pages (they're whole-app) — compute section-scoped sums locally.
- **Don't auto-run Duplicates at launch** — whole-disk hashing is heavy; lazy-start on first navigation with cancellation.
- **Health row buttons** ("Fix" vs "Review") must be derived from `bucket.actionableCount`, so prefs/permissions/login never show a destructive "Fix".