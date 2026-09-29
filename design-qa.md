# Cairn selected Overview and Storage — 28 September 2026

final result: passed

Scope: the two selected screens, their read-only preview interactions and compact layout. This is not a production safety certification or a live-copy test.

## Visual targets and evidence

- Overview source: `/Users/augustusedem/.codex/generated_images/01a0e383-8d4b-7ed2-af4b-eca87bb9a5ad/exec-66ceec80-a260-419c-8593-69a32a6c85dd.png`
- Storage source: `/Users/augustusedem/.codex/generated_images/01a0e383-8d4b-7ed2-af4b-eca87bb9a5ad/exec-6eca859b-d469-4b43-83e8-04ac41ed4986.png`
- Implementations: `artifacts/selected-screens/overview.png`, `storage.png`.
- Source images are 1543 × 1019, implementing their intended 1120 × 740 native window proportions. Native captures are 1120 × 740 at one screenshot pixel per displayed point; no CSS viewport. Compare source proportions at approximately 0.726 scale. Both sources and both implementations were opened together in the same comparison tool input, in source/implementation pairs. No claim of a composed side-by-side image.
- State: graphite theme, sample data, collapsed navigation groups, Overview 7-day history; Storage finished exports selected. Titlebar includes genuine native controls and an OS capture indicator in implementation.
- Additional evidence: `overview-minimum.png`, `storage-minimum.png`, `storage-minimum-scrolled.png` at 1024 × 680; `overview-empty.png`, `storage-no-drive.png` at default size.

## Comparison history

1. Initial Storage capture had [P2] a native Menu flattening its custom label and hiding capacity/encryption metadata. Replaced it with a full drive-summary button and a separate destination chooser. Post-fix capacity, encryption and drive name are visible.
2. Initial Storage capture had [P2] copy explanation below the default viewport. Reduced row heights and section padding; default-size copy action and backup limitation now fit. At minimum height the lower section intentionally scrolls, and a captured scrolled state proves the action remains reachable.
3. First paired comparison found [P2] selected-row contrast and copy stages weaker than target. Increased neutral selection fill and restored three clear stages with native symbol markers and separators. Final `storage.png` shows these corrections.
4. Final source/implementation pairs show no actionable P0/P1/P2 differences. Overview preserves the full-width graph, paired metrics, review action and measured-change list. Storage preserves drive strip, three-category table, selected export detail and clear primary action.

## Required fidelity surfaces

- Typography: native SF system font, compact heading and metric hierarchy, readable 12–14pt content; small secondary metadata 10.5–11pt. Native controls differ slightly from rendered concept typography. No clipped graph dates or persistent toolbar labels.
- Layout: retained 200pt sidebar, 61pt toolbar, 24pt content margin, consistent graphite grouping. Separate screen-specific content structures replace the generic inspector. Minimum-size content scrolls vertically without horizontal overflow.
- Color: existing Brand graphite tokens, blue actions, neutral selected row. No cyan sidebar edge stripe or competing new palette.
- Assets: existing Cairn logo and native SF Symbols. No new raster assets needed; mock imagery consists of native icon equivalents. Chart remains a real Swift Charts plot, not a screenshot.
- Copy: deliberately corrects unverified mock locations and broad safety claims. Tool-managed paths are not claimed to have been discovered. Supported-path setup is explicitly guidance only. Preview fixtures are labelled in the footer. Candidate deltas are not guaranteed savings or a full accounting of disk changes.

## Interaction verification

- Review changes opens a sheet with measured deltas and dates; selecting Build output opens the existing Developer cleanup screen.
- Overview search filters category changes; clearing restores them. 7/30-day controls change selection.
- Drive details show identity, format, encryption, location and capacity.
- Storage category selection switches between export workflow, tool guidance and protected-data explanation.
- Transfer history opens and shows its honest empty state.
- First-use Overview shows no invented graph or growth values. Missing external drive disables copying.
- Both screens resized to the fixed 1024 × 680 minimum and returned to 1120 × 740.
- Preview disk actions stay disabled. No real scan, cleanup, migration, service shutdown or file copy was performed.

## Validation and remaining limits

Swift debug build, ad-hoc signature verification, diff whitespace check, safety suite and 23 isolated workspace checks passed. Workspace checks include 11 scan-comparison checks and 12 existing transfer checks. Logs are in `artifacts/selected-screens/`.

The comparison engine keeps two immutable scan measurements separate from post-cleanup snapshots. It withholds comparisons for incomplete readings, reported permission gaps, changed settings, missing/duplicate categories, invalid chronology and external-volume scope. It does not claim every scanner detects every read failure. Daily capacity history is not continuous monitoring. Live external-drive disconnection, live cleanup, all-settings combinations and long-duration stability remain unverified.

## Follow-up polish

[P3] Native control typography and exact footer spacing differ slightly from ImageGen. Future graph hover details can provide per-reading values without adding permanent clutter. No more decoration is required for this delivery.

## Dialog and state completion pass — 28 September 2026

- Shared native sheet geometry and footer applied to active workspace dialogs. Standard sheets are 600pt wide; map/transfer sheets are 740pt. Longer content scrolls above a fixed action footer.
- Native inert gallery verified scanning, empty, stopped, completed and skipped-item states; actual WorkspaceConfirmation wrapped a long path and cancelled with Escape. Actual WorkspaceCompletion showed skipped reasons, affected bytes and Trash-space wording, with Tab focus and Escape checked.
- Actual Overview History, empty Transfers and Drive information sheets were visually checked. Scrolling Drive information exposes the full capacity description without overlapping the footer. Apps filtered-empty layout checked; subsequent copy correction now suggests changing search/filter. Duplicate status banners were removed from empty cleanup views.
- No personal-data actions were exercised. State rendering and keyboard checks do not establish live cleanup, restore, unplug/reconnect or cancellation behavior. App/Health cancellation persistence is code-verified and compiled; live scanner interruption remains untested.

Final refreshed-build check confirmed Apps search-empty guidance now reads “Try another search or choose All apps.” Escape cleared search and the preview was returned to Overview. Final build/check logs: artifacts/dialog-states/.

## Native window layout from selected mock — 28 September 2026

final result: passed

Source: artifacts/native-chrome/selected-reference.png. First comparison: artifacts/native-chrome/comparison.png. Final paired comparison: artifacts/native-chrome/final-comparison.png. Both are full-window Overview/sample-state images normalized to 1120 × 740 without aspect-ratio distortion. AppKit's frame-view capture includes genuine window controls, unlike the previous content-only capture.

Findings and corrections:
- [P2, resolved] The first native toolbar used a visibly lighter grey than the target. Applied the existing graphite token through the system toolbar background API. The final comparison shows a consistent dark header.
- [P2, resolved] Sidebar spacing was tighter than the selected target. Top-level rows increased to 44pt, category headers to 39pt, and initial inset to 18pt; labels are 14pt. Final capture shows the intended row rhythm without selection rectangles.
- [P2, resolved] The footer previously spanned under the sidebar. It now belongs to the detail column, matching the target's hierarchy; Settings stays at the bottom of the full-height sidebar.
- Added the subtle divider between external storage and activity; aligned warning/review copy with the selected mock.

Verified interactions: system Hide Sidebar expands the workspace; Show Sidebar restores it and retains the current page and expanded groups. Native Details opens the existing inspector. Existing scan/review actions retain preview and mutation guards. Captured all 14 final routes in artifacts/native-chrome/final. No extra raster assets were needed: native SF Symbols and Swift Charts supply existing functional visuals.

P3 differences: the system places the sidebar toggle beside the traffic lights rather than at the far edge of the sidebar header. Native title weight, material and traffic-light geometry follow macOS. Retained What changed and protection/status copy because these expose existing functionality and distinguish sample data. The mock's extra decorative material texture was not recreated as an image.

Limits: no live scan/cleanup, long-duration stability test, or final minimum-window resize was performed. Runtime smoke sample after native navigation was about 72 MB resident memory and 0% CPU; this is not a stability guarantee. No Screen Recording permission was requested; images came from the app's sample-only view capture.

## Restrained border treatment — 28 September 2026

final result: passed for scoped visual checks

Evidence: artifacts/border-pass/dashboard.png and developer.png; all 14 sample workspaces captured. Visually inspected the Overview, Developer table and native History sheet. Repeated row outlines and framed inspector/dialog sections are removed; layout, labels, selectable rows and action affordances remain readable. Faint major separators and native split-view boundary remain intentionally. History opened and dismissed successfully; preview returned to Overview. Build and strict signatures passed. No live data operation, new sustained stability test or exhaustive interaction regression was performed.

## Compact native dropdown — 28 September 2026

final result: passed

Source: artifacts/menu-bar/reference.png (1174 × 1339); implementation: artifacts/menu-bar/verified/menu-2544.png (290 × 307). Paired comparison: artifacts/menu-bar/comparison.png. Source menu crop is 818 × 1090; both menu regions normalized to 580px width, preserving aspect ratios. Native control dimensions are 290 × 307 points, 1x app-view capture. Context: sample data, idle state, scan disabled. Screenshot uses the actual NSMenu rendered inside the preview window so the UI automation can inspect it; production uses the same menu on NSStatusItem. Native view capture excludes desktop-composited translucency/shadow, so material appearance cannot be compared pixel-for-pixel. The complete menu is readable in the paired image; no further focused crop was needed.

Findings and corrections:
- [P2, resolved] First sample presentation was positioned near the bottom of the window and macOS inserted menu scrolling arrows, hiding Quit. Corrected flipped-view coordinates. Final render includes all rows without scrolling. This affected the sample inspection anchor, not the status-bar anchor.
- Expected native differences: macOS supplies compact menu fonts, line spacing, material, focus and separators. The mock's blue pill count is a standard textual category count, and connection status is in the drive submenu. Added the saved scan date and sample-data label for accuracy. These are intentional rather than replacements with custom panel widgets.

Required surfaces: native system menu font and SF Symbols remain sharp at original size; compact spacing retains clear groups; semantic amber/green indicators are restrained; existing Cairn mark is reused as a template (no new raster assets); copy maps to real actions and measured values rather than invented cleanup savings. Disabled informational rows and sample scan use native muted text. P3: a future accessibility pass could evaluate more prominent status text across system appearances.

Interactions passed using the same NSMenu: Results → Smart Scan, Recent activity → Activity & Recovery, Studio SSD → Storage, View protections → Settings / Protection. Build, strict signatures and 30 isolated checks passed. No real scan/cleanup or full live-operation stability test was run. Status-icon anchoring, live disconnects, light appearance and closed-window reopening were not directly inspected. Preview remains available from its status icon or View → Preview status menu.

## Reliability pass — 28 September 2026

Scoped native UI result: passed. Live main application opened directly from this workspace with --no-auto-scan. Verified an actual delayed-Keychain status banner alongside responsive Overview → Storage navigation, a disabled export chooser when no external drive exists, the empty Transfers sheet and its Done action. Window close/reopen returned to the existing workspace, then Overview was visibly verified. The final executable after scan-pipeline changes was relaunched and its Overview accessibility tree verified. Keyboard focus outline remains the native accessibility indication, not a restored selection fill.

The final pass is functional, not a redesign. The updated transfer recheck action and restored history state have isolated engine coverage but no real-drive/live-user-history UI test. No personal cleanup or migration was performed. See BUILD_STATUS.md and artifacts/reliability for precise testing and remaining release boundaries.

## Sidebar identity and quiet launch — 28 September 2026

Scoped visual check passed in the native sample preview. Small blue existing Cairn mark and name align with sidebar icon/text columns. No topbar identity duplicate, new card/border or selection background. Overview remains balanced at the existing 1120 x 740 window size. The global Keychain warning has been removed; licensing feedback is confined to Settings > License. Existing read-failure UI and a spinner remain there, without presenting a purchase before saved entitlement is checked.

Repeated sample navigation ran for over 77 seconds across all 14 routes; sampled RSS about 104.5 MiB with no observed runaway growth. This does not establish long-session or real full-disk scan stability. Final preview is idle on Overview. The user's selected scan items in the existing main application were preserved by not terminating it; the new main executable takes effect on relaunch. Build/signature, 59 reliability, 30 workspace, safety and isolated load checks passed. See artifacts/identity-reliability for logs.

## Sidebar focus outline control — 28 September 2026

Scoped check passed. Default-off outline verified visually with Overview actually focused, then with Clean keyboard-focused and expanded using Tab/Space. Existing text/icon selection indication and keyboard access remain. Local General setting can restore the native sidebar outline. No OS accessibility setting changed. Debug build, bundle signatures and whitespace checks passed; scanner tests were not rerun for this cosmetic preference.

## Cleanup receipt verification — 28 September 2026

Native sample-data Result sample checked at 600 × 590 points. Header and bottom actions remain fixed; content scrolls to the skipped-item explanation. Receipt shows 2.3 GB moved to Trash, one recovery record, one tool action with 400 MB scanned input, and 9.9 GB before/after with No measured change. These fixture values do not describe actual cleanup. Corrected singular item/action labels and recovery-record failure wording after inspection. Current sidebar focus preference remains unchanged. Real-machine scan memory evidence and scope limitations are recorded in BUILD_STATUS.md and artifacts/accounting-stability.
