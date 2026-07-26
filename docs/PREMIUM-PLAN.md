I have enough grounding across tokens (Brand/BrandUI), the shell, the Developer screen, Settings, and the full findings set. The plan is now file-accurate. Writing the final deliverable.

---

# Cairn Premium Polish Plan

A two-part execution script. Round 1 ships the changes that most move "generic" → "premium" plus the three deferred features. Rounds 2–10 are the themed backlog — each is a self-contained loop iteration. Findings are de-duplicated across rounds: a token added in an early round is *consumed* (not re-defined) in later ones.

Guiding principle for every round: **systematize, don't hand-tune.** The biggest premium wins are tokens in `Brand.swift`/`BrandUI.swift` that re-skin every screen at once, applied with discipline.

---

## ROUND 1 — DO NOW

Ordered by premiumImpact, then severity. ~11 changes. Three are the deferred features (a/b/c). The rest are the transformative, low-risk token + signature-moment fixes that touch every screen.

### R1.1 — Establish the foundational token layer (transformative, enables everything else)
The single highest-leverage move. Add to `Cairn/App/Brand.swift`:
- **Spacing scale:** `enum Space { static let xs:CGFloat=4, sm=8, md=12, lg=16, xl=20, xxl=24, page=28 }`.
- **Layout tokens:** `static let contentMaxWidth: CGFloat = 1080`, `static let rowVPad: CGFloat = 12`.
- **Elevation ramp** (replace the single `cardShadow`): three tokens — `elevationLow` (slate @ 4%, r3, y1), `elevationMed` (slate @ 7%, r10, y4), `elevationHigh` (slate @ 10%, r24, y10).
- **Radius scale:** `rSm=8, rCard=14, rHero=20, rXL=22` (delete the unused `cornerRadius=16` or repoint it to `rCard`).
- **Type helpers** (so other rounds consume them): a `Brand.heroNumber`/`Brand.metric` font convention note + an `.eyebrow()` `ViewModifier` (10pt, `.heavy`, tracking 1.4, `textMuted`).
- **Surfaces:** `brandWash` (LinearGradient blue @ 6% → cyan @ 4%); darken `textMuted` one step to `#8593AD`.

Then thread `level:` into `CardBackground`/`cairnCard` in `BrandUI.swift` (default `.med`). This round only *adds* the tokens and wires `CardBackground`; the per-screen rollout happens in Rounds 2–4. Do this first so the rest of Round 1 can use them.

### R1.2 — Fix the #1 number: the ScanRing hero value (transformative)
`SmartScanView.swift:157` → `.font(.system(size: 54, weight: .bold, design: .rounded)).monospacedDigit()`; line 159 unit → `(size: 20, weight: .semibold, design: .rounded)`. Attach `.animation(.spring(response: 0.4, dampingFraction: 0.9), value:)` to the value so `.numericText()` actually rolls instead of jittering. Mirror onto `DonutChart.swift:25` centerValue. This is the brand's signature moment seen every scan.

### R1.3 — Wire the live scan to the animated `ScanningHero` (transformative)
`ScanningHero.swift` is a fully built premium scan visual (counter-rotating gradient rings, pulsing core, reduce-motion aware) that the live `AppShell` path never references. Route `SmartScanView.scanning` (`SmartScanView.swift:47-82`) through it, keeping the elapsed timer, %, statCards, and Stop button. The most magical moment in a cleaner is currently the least animated; the asset already exists.

### R1.4 — Unify the primary CTA into `BrandButtonStyle` (high)
`BrandButtonStyle` (`BrandUI.swift:42-56`) is a flat blue rect, yet its own comment promises a gradient and the marquee "Fix All" (`HealthView.swift:170-187`) hand-rolls the prettier gradient+glow version. Bake the premium look into the shared style: `Brand.brand` gradient fill, `rCard`(12), soft `Brand.blue.opacity(0.28)` shadow, keep press-scale; add a `prominent`/full-width size variant. Delete the hand-rolled HealthView button and route it through the style. Fix the doc comment. Now every primary CTA (Start Scan, Review & Clean, Uninstall, Clean Dev Junk, Fix All) shares one identity.

### R1.5 — [DEFERRED a] Surface `.tool` correct-command cleans + Pro lock in Developer (transformative)
The marquee differentiator currently shows zero Pro signal. In `DeveloperCleanupView.swift`:
- Thread `proEnabled: Bool` (license.isUnlocked) down from `AppShell.content` (currently it only gets `store`).
- In `DevToolRow` (`:141`), when a bucket contains `.tool` items, render a `PRO · runs <cmd.display>` pill next to the size (`ToolCommand.display` already exists in `Models.swift:33`). During trial, show the command with **no** lock so users feel the value.
- In `summaryPanel`, below `whySafe` (`:118`), add a compact Pro card when any `.tool` item exists and `!proEnabled`: title "Correct-command cleans", body naming `docker prune`, `simctl delete unavailable`, `git gc`, and an "Unlock with Pro" button that hops to `section = .settings`. Use the unified `BrandButtonStyle` from R1.4.

### R1.6 — Make `AppBackground` a faintly lit field (transformative)
`AppBackground` (`AppShell.swift:133-143`) is the flattest surface in the app — flat near-white at 0.7 opacity — while the signature `AmbientBackground` glow is dead code reaching only RootView/HealthView. Replace `AppBackground.body` with `Brand.background` + two very soft brand radials (blue @ ~6% top-left, cyan @ ~5% top-right). Every content screen gets the studio glow for free; keep it light enough that `textPrimary` contrast holds.

### R1.7 — [DEFERRED b] Global FDA onboarding banner (high)
The only FDA banner lives in `CategoryDetailView.swift` (dead code the live nav never renders). Promote it to a slim, dismissible strip at the top of `AppShell.content` (above the `switch`), shown when `store.hasScanned && !store.fdaGranted` and a visible bucket has a permission gap: "Some results are incomplete — grant Full Disk Access so Cairn can measure and clean everything." with "Open Settings" (`FullDiskAccess.openSettings()`) + dismiss X. Also add a calm one-line pre-scan note under the `SmartScanView.idle` CTA when `!FullDiskAccess.isGranted()`. (CategoryDetailView is deleted in R6.)

### R1.8 — [DEFERRED c] Persistent Restore Bin / removal log (high)
The Settings "Restore Bin" (`SettingsPage.swift:135-145`) is hollow controls with no backing store, and the only undo (Celebration "Undo") is transient. Make it real:
- In `ScanStore.clean` (`ScanStore.swift:305`), append each successful `Outcome` (original URL, trash URL, bytes, date, category) to `Application Support/Cairn/removal-log.json` (mirror snapshot persistence at `:99-121`).
- Replace the fake `restoreBin` card with a real list: recent removals grouped by date, each with size + "Put Back" (`Cleaner.restore(from:to:)`, `Cleaner.swift:103`) + "Reveal in Trash" fallback, plus a Pro "Export log…" button (matches the spec).
- Keep the keep-days dropdown but make it prune the log.

### R1.9 — Honest celebration per clean method (high)
`CelebrationOverlay.swift:23` only shows Undo when `summary.restorable` is non-empty, and `:20` always claims "recoverable" — wrong for `emptyTrash`/`tool` cleans that go through permanent `removeItem`. Add `recoverableCount`/`permanentCount` to `CleanSummary` (`ScanStore.swift:26`), populate in the clean loop, and switch the subtitle: "N moved to Trash — recoverable" vs "N permanently removed." When nothing is recoverable, make "Done" the clear sole action. Also add the spring scale-in + `.symbolEffect(.bounce)` on the checkmark and `.contentTransition(.numericText())` on the reclaimed figure — this is the emotional payoff and should pop.

### R1.10 — Universal hover/press on the dead interactive elements (transformative)
The sidebar nav rows, 8 Dashboard category tiles, and "Review" buttons all use `.buttonStyle(.plain)` with no feedback — the cursor lands on dead targets on the two most-used screens. Extract the existing `MissionCard` treatment (`Missions.swift:108-112`: -2pt lift, border tint, 0.14s ease) into a reusable `HoverLiftCard`/`HoverButtonStyle`. Apply to: `NavSidebar.navRow` (`AppShell.swift:180`, animate hover + selection), Dashboard category tiles (`DashboardView.swift:88-102`), and Review buttons. One shared style fixes the largest cluster at once.

### R1.11 — Section navigation transition (high)
`AppShell.content` is a bare `switch` (`:92-119`) — every page change is a hard cut. Give `content` `.id(section)` + `.transition(.opacity.combined(with: .move(edge: .trailing)))`, driven by `withAnimation(.easeOut(duration: 0.22))` on the `section` set in `navRow`. Fall back to plain `.opacity` under `reduceMotion`. The most frequent interaction in the app gets motion.

---

## ROUNDS 2–10 — THEMED BACKLOG

Each round is one loop iteration. They assume Round 1's tokens exist and consume them.

---

### ROUND 2 — Typography pass
Apply the now-defined type conventions everywhere; eliminate the four-size title chaos.
- **Page-title two-tier system.** Hero H1 = 30pt `.bold .rounded` (`DashboardView.swift:37`, `HealthView.swift:61`); Page H1 = 24pt `.bold .rounded` (`SectionView.swift:56` 22→24; `DeveloperCleanupView.swift:38` and `AppsView.swift:90` 26→24; `LargeFilesView.swift:57`, `DuplicatesView.swift:119`, `SettingsPage.swift:16` 28→24).
- **Card-header token = 14pt semibold.** Drop the Dashboard 15pt headers (`DashboardView.swift:109/136/166/193`), `SmartScanView.swift:50`, `AppsView.swift:294` to 14.
- **Headline metrics get `.rounded` + `.monospacedDigit()`:** `DeveloperCleanupView.swift:92`, `AppsView.swift:119/121`, `DuplicatesView.swift:165`, `LargeFilesView.swift:76`, `AppsView.swift:309`.
- **Eyebrow token** via the `.eyebrow()` modifier from R1.1 applied to all six sites (`HealthView:58/85`, `SmartScanView:54`, `LargeFilesView:227`, `Missions:66`, `SectionView:31`).
- **Muted text floor:** bump 10/11pt `.regular` metadata to `11pt .medium` (`SettingsPage:170/182/194`, `SectionView:115`, `DeveloperCleanupView:157`, `AppsView:246/248/339`, `DashboardView:182`, `ItemRow:41`).
- **List-row weight rule:** primary label 13 `.medium`, trailing metric 13 `.semibold`, metadata 11 `.regular` — align `LargeFilesView:146`, `AppsView:240`, `DuplicatesView:285`.
- **Body line-height:** `.lineSpacing(3)` on multi-line paragraphs (`DashboardView:40/194`, `HealthView:65`, `DeveloperCleanupView` whySafe).

**Bugs to fix (folded here — these are correctness defects in the type/number layer):**
1. **(high) Stale snapshot over-reports reclaimable after a clean.** `ScanStore.clean` never re-saves the snapshot; next launch shows pre-clean totals. Fix: call `saveSnapshot()` at the end of `clean()` (`ScanStore.swift:305`).
2. **(medium) `AppInfo.fixes.count` is the wrong source for the Health "Checks" card.** `DashboardView.swift:83` shows changelog entry count, not health-check count. Expose `HealthStore.checkCount = 5` and use it.
3. **(low) `Fmt.split` mis-splits non-breaking-space byte strings,** dropping the unit on the hero ring. `Models.swift` `Fmt.split` → split on `.whitespaces` filtered for empties; handle "Zero KB"/single-token.
4. **(low) `ItemRow` selected checkbox is `Brand.purple`** while every other selection control is `Brand.blue`. `ItemRow.swift:68` purple→blue.

---

### ROUND 3 — Spacing & rhythm
Route every literal through the `Space` scale from R1.1.
- **Snap off-grid values** (7→8, 9→8, 11→12, 13→12) across `UI/`.
- **Content max-width:** wrap each scroll screen's content VStack in `.frame(maxWidth: Brand.contentMaxWidth).frame(maxWidth: .infinity, alignment: .center)` (`DashboardView`, `SettingsPage`, `SmartScanView` results, `DuplicatesView`). Health already does this.
- **Shared table columns:** add `enum Col { check=30, size=88, date=112, dev=130 }`; apply across `DeveloperCleanupView`, `LargeFilesView`, `AppsView` so size figures stop shifting between tabs. Leading gutter 30, trailing chevron gutter 24 everywhere.
- **Header/row vertical padding parity:** header `Space.md`(12), rows 10, in all three tables (fix the 10-over-9 mismatch at `LargeFilesView:107/155`).
- **One row height:** `Space.md` vertical for `ItemRow:53`, Settings rows (`175/187/209`), `DuplicatesView:313` — reserve taller 14 only for Health 2-line rows as a deliberate `dense` vs `comfortable` choice.
- **One inter-card gap = `Space.lg`(16):** `DashboardView:88` 14→16, stat-card HStacks in LargeFiles/Apps/Duplicates.
- **cairnCard 3-tier insets:** `compact`(12)/`standard`(16)/`feature`(20) — replace the 10/14/18 calls; keep `(0)` only where the card supplies its own row padding.
- **Sidebar rhythm:** nav-row spacing 3→`Space.xs`(4-6) (`AppShell:163`); symmetric logo inset (top/bottom 20); unify sidebar horizontal inset so nav labels align with ProPill/DeviceCard.

---

### ROUND 4 — Depth & elevation
Consume the R1.1 elevation ramp; make depth the hierarchy.
- **Assign levels:** hero + ShieldBadge + CelebrationOverlay → `.high`; standard content cards → `.med`; nav tiles + list-row containers → `.low`. Set via the `level:` param on `cairnCard`/`CardBackground`.
- **Drop the doubled chrome:** in `CardBackground` remove the `Brand.border` stroke for raised cards (`BrandUI.swift:89`); lean on shadow. Optionally add a 0.5px top white@60% inner highlight. Reserve `border`/`inputBorder` hairlines for flush/inset surfaces only.
- **Recessed-vs-raised language:** fill all inset controls (search fields in Duplicates/Apps, the segmented Picker in SmartScan, toggle "off" tracks, info wells) with `Brand.surfaceSubtle` + 0.5px inner border; reserve accent-tint fills strictly for selected/on states.
- **Brand wash on heroes:** apply `Brand.brandWash` (R1.1) under the Dashboard hero card and the `ShieldBadge` card (over `HeroIllustration`, under content); ≤8% so text stays crisp.
- **ItemRow hover fix:** `ItemRow.swift` hover fill is white-on-white — change to `Brand.surfaceSubtle` (or `Brand.blue.opacity(0.05)`) so deletion rows visibly seat.
- **Radius-to-elevation pairing:** repoint literal radii (10/12/18/22) to the `rSm/rCard/rHero/rXL` scale so size, radius, and shadow move together.

---

### ROUND 5 — Motion & micro-interactions
Everything not already animated in Round 1.
- **DonutChart draw-on:** animate each slice's `trim` end 0→1 on appear (`.easeOut(0.6)`), tween boundary shifts with `.animation(.easeInOut(0.35), value: total)` (`DonutChart.swift:14-29`).
- **Number rolls everywhere:** ensure every `.numericText()` has a value-keyed `.animation` (Dashboard hero ring reusing ScanRing, panel totals).
- **List insertion transitions:** `.transition(.opacity.combined(with: .move(edge: .top)))` on ItemRow ForEach + statCards (`SectionView:139`, `DeveloperCleanupView:177`, `SmartScanView:84`), keyed to collection count; optional per-row stagger on results.
- **Checkbox feedback:** `.contentTransition(.symbolEffect(.replace))` + `.symbolEffect(.bounce, value: item.selected)` on the ItemRow checkbox; eased hover fill.
- **Button states:** give `GhostButtonStyle` the `0.97` press-scale + `.animation(.easeOut(0.12))` and a hover background lift; add hover to both shared styles.
- **Storage bars tween:** `.animation(.easeInOut(0.4), value:)` on the DeviceCard capsule (`AppShell:219`) and the Reclaimable-by-area bar (`DashboardView:170`).
- **Proportional ScanRing center inset:** replace fixed `.padding(38)` (`SmartScanView:165`) with `diameter * 0.16` so the 212pt and 300pt rings have a constant number-to-arc gap.
- **Scan-complete beat:** brief 1–1.5s "Scan complete — reclaim X GB" state on the ring before cross-fading to results (gives `progressText="Scan complete."` a place to live); tap-to-advance.

---

### ROUND 6 — Iconography & imagery + dead-code removal
- **One icon source of truth:** make `ToolIcon.forCategory` the single category-icon path. Replace bare `Image(systemName: bucket.info.systemImage)` in `CategoryDisclosure` (`SectionView.swift:112`), the sidebar row (`Sidebar.swift:71` — or its live equivalent), Smart Scan stat cards (`SmartScanView:88`), and Dashboard biggest-finds (`DashboardView:117`) with `ToolIcon.forCategory(bucket.id)` (or wrap in an `IconTile` with the category tint).
- **Stop glyph drift:** have `ToolIcon.forCategory` read its fallback `systemImage` from `CategoryInfo.systemImage` instead of hardcoding a second value (`ToolIcon.swift:59-83`); add the missing `installers` case; audit every registry id has a matching entry. Give `dev-caches` a distinct glyph from `docker` (`archivebox.fill`).
- **Reconcile the mark:** rebuild `CairnLogo` (`CairnArt.swift:4`) to the icon's filled-pebble silhouette in the blue→teal gradient; re-render `Cairn.icns` off purple onto blue→teal; replace `ScanningHero.swift:34` `mountain.2.fill` with the real `CairnLogo`.
- **Nav glyph consistency:** standardize the nav set to one fill/weight (outline, `.medium`); replace `a.square` for Apps with `macwindow.stack`/`square.stack.3d.up`; fix the Apps header `IconTile` from `trash.square.fill` (`AppsView:88`) to an app-management glyph.
- **Reusable `EmptyState`/`LoadingState` components** in `BrandUI.swift` (icon-in-tinted-circle + headline + caption; consistent spinner). Adopt across the six empty states; positive "all clean" states use the blue→teal gradient checkmark-shield at larger size with glow, not flat gray `checkmark.circle`.
- **Hero art:** replace the self-described placeholder `HeroIllustration` (`CairnArt.swift:28`) with a refined cairn-on-calm-water vector in the brand palette, dropped into the Dashboard hero, ShieldBadge, and AppBackground slots.

**Bugs to fix (folded here — dead code that misleads and can mis-wire):**
1. **(medium) Delete dead view files** after confirming no refs: `RootView.swift` (unreferenced; sole consumer of the next three), `Sidebar.swift`, `SettingsView.swift`, `CategoryDetailView.swift`. Removes the purple-accent ambiguity and the celebration double-wire risk at the source. Lift CategoryDetailView's FDA banner first (already done in R1.7).
2. **(medium) `RootView.onAppear` auto-starts a full scan + hardcodes `proEnabled=true`** — directly contradicts the "land idle" launch contract. Resolved by deletion above; verify `CairnApp` only instantiates `AppShell`.

---

### ROUND 7 — Component & state consistency
- **Canonical `StatusPill`** in `BrandUI.swift` (one shape, one font ramp, color from `Severity.color`). Replace `ItemRow.tag` (`:100`), `DevToolRow.pill` (`:185`), `DuplicatesView.pill` (`:371`), `AppsView.tag` (`:269`), and the inline KEEP badge (`:286`).
- **Selection accent = `Brand.blue` everywhere** (audit anything still purple after R2 bug-fix; reserve purple for AI category + Pro affordances).
- **`CairnTextField`** matching the Duplicates search chrome (surfaceSubtle, inputBorder, `rSm`, leading glyph, blue focus ring, danger error border). Replace ProView's off-brand `.roundedBorder` (`ProView.swift:40`); wire license error to the error-border state.
- **Focus & keyboard:** add `@FocusState` + `.onSubmit` to ProView key field (auto-focus on reveal) and Duplicates search; define one 2px blue focus ring in the shared field; make primary actionable rows `.focusable()`.
- **`FilterChip(label:icon:count:isOn:)`** unifying `LargeFilesView:83` and `AppsView:140` (one fill opacity, padding, always in a horizontal ScrollView).
- **Disabled-state rule:** give `GhostButtonStyle` a disabled look (0.4 opacity + muted); prefer "visible but disabled" over "hidden" — apply to LargeFiles "Review & Clean"; confirm Duplicates destructive buttons gate on selection.
- **`MenuButtonChrome` + `RowIconButton`** helpers to unify the `…`/sort/dropdown triggers and standardize idle icon-button opacity (0.35 → 1 on row hover).
- **Sheet surface token:** `ReviewSheet.swift:55` `Brand.deepPanel` → `Brand.surfaceElevated` (latent dark-mode inconsistency).

---

### ROUND 8 — Per-page deep polish A (Smart Scan, Dashboard, Developer)
- **Smart Scan idle is a dead end:** add a secondary "Rescan & Review" ghost button beside "Start Smart Scan" when `showingCachedResults`; relabel primary to "Rescan" when cached, reserving "Start Smart Scan" for never-scanned. Reconcile with the Dashboard auto-start entry point (`AppShell:124`).
- **Cancelled-scan honesty:** `phase == .cancelled` currently renders partial buckets as final. Add a `wasCancelled` flag; show "Scan stopped — partial results" caption + Resume/Rescan in `DashboardView`/`SmartScanView`.
- **Dashboard Duplicates card** shows `—`/"Open" — give it a real value once scanned or label it "Scan" with a neutral glyph; never show a bare em-dash as a primary number.
- **Developer:** verify the R1.5 Pro card + command pills read well at all bucket counts; ensure the donut/`selectedSize` total excludes Pro-locked items for free users (ties to ReviewSheet split below).

**Bugs to fix (folded here):**
1. **(high) ReviewSheet over-promises the clean total for free users.** Primary button reads "Clean <total>" including `.tool` items it won't clean (`ReviewSheet.swift:17/104`). Split: "Clean <freeTotal>" + sibling "Unlock <paidTotal> with Pro →" using the existing `paidItems`/`destructiveItems` computed props (`:22-25`).
2. **(medium) Large Files trash hardcodes `proEnabled: true`** (`LargeFilesView.swift:48`) — thread real `license.isUnlocked` from AppShell.
3. **(medium) Inconsistent selectability** between `ItemRow.selectable`/`ScanStore.toggle` (allow REVIEW) and `selectAllSafe`/`selectSafeUpTo` (require `isRegenerable && safe`). Pick one rule and enforce it in both `ItemRow.swift` and `ScanStore.swift`; the "will be reclaimed" figure currently can include REVIEW data the safety model means to keep unchecked.

---

### ROUND 9 — Per-page deep polish B (Health, Apps, Duplicates, Settings) + safety
- **Microcopy unification:** tighten the Dashboard hero subhead to one confident line; match Developer empty-state voice to SectionView's ("…your tools are tidy"); add "everything unlocked" to the trial ProPill.
- **Apps/Duplicates/Health** state polish using the R6 EmptyState/Loading components and R7 pills/chips; verify selection totals and pill semantics are consistent post-refactor.

**Bugs to fix (folded here — the safety-critical cluster; do these carefully, highest severity first):**
1. **(critical) `DuplicateStore.removeSelected` bypasses SafePaths and never verifies the keeper survives** — can destroy the only copy. In `DuplicateStore.swift`: guard `FileScan.exists(keeper)` before trashing any group member; route each removal through `SafePaths.evaluate`; re-confirm content identity (size/re-fingerprint) at removal; assert ≥1 copy of each hash survives.
2. **(high) Large Files "Move to Bin" trashes irreplaceable data with no confirmation** (`LargeFilesView.swift:48`) — gate behind a `confirmationDialog` or route through ReviewSheet.
3. **(high) Trash items pre-selected as SAFE but cleaned via permanent `removeItem` while UI says "recoverable."** `TrashScanner.swift` → `selectedIfSafe:false` for `.emptyTrash`; render a "Permanent — empties Trash" badge in ReviewSheet/ItemRow; require separate acknowledgement; fix the ReviewSheet header copy.
4. **(high) "Create Restore Snapshot" & "Ask Before Deleting" settings are inert.** Either implement (`tmutil localsnapshot` before clean when on; honor `askBeforeDeleting` in Health single-Fix and Large Files) or remove the rows until backed. (R1.8's removal log partially delivers the restore promise.)
5. **(medium) Health per-group "Fix" trashes with no confirmation** (`HealthView.swift:149`) — route through `HealthReviewSheet` or add a `confirmationDialog`.
6. **(medium) Running-app cache cleans only warned, never blocked.** Make `ReviewSheet.canClean` require empty `runningBlockers` (or explicit override); or quit owners in `ScanStore.clean` like uninstall does.
7. **(medium) Add `Library/Mobile Documents` + `Library/CloudStorage` to `SafePaths.denyHomeRelative`** and `AppInventoryStore.isUninstallSafe` so no clean trashes iCloud mirrors.
8. **(low) Python venv `isRegenerable:true` contradicts its own note** — `DevProjectsScanner.swift:205-219` → `isRegenerable:false`.

---

### ROUND 10 — Final holistic + regression
- **Token audit sweep:** grep `UI/` for surviving magic numbers (spacing literals, raw `.shadow(radius:`, hardcoded radii, `Color(hex:` outside `Brand.swift`) and route through tokens; confirm `Brand.cornerRadius`/`cardShadow` legacy tokens are fully retired.
- **Type/number audit:** confirm every hero/metric number is `.rounded + .monospacedDigit()`; every `.numericText()` has an animation driver; one title scale (30/24) and one card-header (14) hold everywhere.
- **Motion regression:** verify `reduceMotion` fallbacks on the section transition, ScanningHero, donut, and celebration.
- **Cross-screen consistency pass:** tab through Developer/Large Files/Apps side-by-side — columns locked, row heights equal, hover/press identical, pills/badges identical, selection accent uniformly blue.
- **Safety regression:** re-run the destructive paths from R9 with FDA on/off, free/Pro, cancelled scans, and an ejected external volume; confirm no path trashes without SafePaths + the intended confirmation.

**Bugs to fix (folded here — latent state/lifecycle edges):**
1. **(medium) `AppSettings.shared` mutations don't refresh non-`@Bindable` views.** Ignoring a file in Large Files doesn't hide the row until rescan — filter `LargeFilesView.allItems` through `AppSettings.shared.isExcluded` and hold a tracked reference.
2. **(low) Celebration overlay can double-present** — guard `if celebration == nil` before setting in `AppShell` (largely mooted once RootView is deleted in R6).
3. **(low) `ScanStore` has two completion paths; only `apply(.done)` saves a snapshot** — consolidate `saveSnapshot()` into the single post-loop completion branch so completion always persists exactly once.
4. **(low) `HealthStore.fix` path-matching is fragile to trailing-slash/non-standard URLs** — compare `standardizedFileURL.path` on both sides.
5. **(low memory-hygiene) `MEMORY.md` index line says "subscription"** but code/detail-note agree on one-time Pro — fix the index entry to "freemium + one-time Pro ($29), NOT a subscription" so a future agent doesn't regress the pricing copy.

---

**Files that anchor the most cross-cutting work:** `/Users/augustusedem/CLEANSTUFF/Cairn/App/Brand.swift` (tokens), `/Users/augustusedem/CLEANSTUFF/Cairn/UI/BrandUI.swift` (CardBackground, button styles, shared components), `/Users/augustusedem/CLEANSTUFF/Cairn/UI/AppShell.swift` (shell, background, sidebar, FDA banner, transitions), `/Users/augustusedem/CLEANSTUFF/Cairn/Core/ScanStore.swift` (snapshot/clean/removal-log/completion), `/Users/augustusedem/CLEANSTUFF/Cairn/Core/DuplicateStore.swift` and `/Users/augustusedem/CLEANSTUFF/Cairn/Core/SafePaths.swift` (the critical safety gaps).