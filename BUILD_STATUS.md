# Cairn native workspace rebuild — 28 September 2026

## Deliverable

`dist/Cairn.app` is the native SwiftUI/AppKit local development build. It is ad-hoc signed, not Developer ID signed or notarized. It does not replace the installed application or the read-only original repository at `/Users/augustusedem/CLEANSTUFF`.

The selected dark native reference now drives every main navigation route: compact translucent topbar, retained sidebar with neutral selected-child fill, dense lists/tables, consistent right inspector and bottom review bar. The old dashboard, section, apps, duplicates, health, storage and settings layouts no longer handle AppShell navigation. Existing engine code remains connected.

## Connected functions

- Overview: measured available capacity, local daily history with 7/30-day filtering, ranked scan findings, contextual next steps and recovery entry. Empty and cached states are labelled. Preview fixtures never stand in for live data.
- Smart Scan / General / Browsers / Developer / AI / Creative: existing scanners, category expansion, search, size/name sort, selection, item requirements and exact-path review. Smart Scan retains selection presets and storage map as compact controls.
- Large Files: flat list, file-type filters, global size/name/modified sorting, path inspection, reveal, exclusion and reviewed cleanup.
- Apps: inventory, all/unused/large/removable filters, support-data disclosure, reviewed bundle-only uninstall. Codex and ChatGPT hosts are protected.
- Duplicates: expandable groups, keeper selection, recommended extra-copy selection, full-content verification before Trash.
- Health: individual findings and reviewed obsolete launch-agent cleanup; unmatched app data, preferences and permissions remain advice-only.
- Activity & Recovery: original paths, recorded Trash paths, existence-based recovery availability, guarded Put Back. App, duplicate and health operations now feed the same removal history as cleanup.
- Preferences: general, scanning, protection, exclusions, existing licensing and optional CLI command handoff. Mandatory protections are not switches. Automatic cleanup-on-quit is not armed.
- Storage: current volume inventory, volume UUID, encryption and format checks, supported-tool path guidance, verified export copies, transfer history, cancellation and mount/unmount refresh.

## External-storage scope

The working transfer action copies ONE finished archive, PDF or media export to a writable local external APFS volume whose encryption is reported by macOS. It checks UUID/capacity, writes a private destination, compares full SHA-256 content, and marks success only after verification. Partial files stay visibly incomplete; source files are always retained. Copy state is journaled and interrupted previous runs are shown as interrupted. The store survives navigation.

This is a content export, not a whole-directory migration or a managed backup. Resource forks/extended attributes are not copied. Use an archive when those are required. It does not reclaim internal space automatically, remove originals, configure npm/Xcode/Docker paths, move swap, synchronize databases, or provide cloud/VPS integration. Those are explicit product limits, not simulated functionality.

Official references checked for guidance:
- Apple APFS and external formats: https://support.apple.com/en-gb/guide/disk-utility/dsku19ed921c/22.7/mac/26
- Apple Xcode Locations: https://developer.apple.com/documentation/xcode/configuring-command-line-tools-settings
- npm cache configuration: https://docs.npmjs.com/cli/v11/using-npm/config/#cache
- Docker disk-image relocation: https://docs.docker.com/desktop/troubleshoot-and-support/faqs/macfaqs/

## Safety and reliability

Known conversation locations and nested protected contents remain blocked. Unknown application data is never treated as disposable merely because the app is absent or a folder is old. Health's separate orphan-data route was made advice-only. App removal retains associated state. Permanent Trash emptying and destructive tool actions remain blocked.

Scan and removal operations use the shared gate; duplicate, health, app and general cleanup reject overlapping mutations. Stores live in AppShell so navigation does not spawn replacement engines. The window's minimum width exceeds sidebar plus workspace constraints. Disk capacity is sampled outside view layout. Cleanup review snapshots the selected items, displays exact paths and tool commands, and prevents dismissal while its operation is running. Completion explains bytes affected rather than promising that Trash frees space.

## Verification

- Swift debug build passed; no new Swift diagnostics. SwiftPM cache-access warnings are environmental.
- Safety checks passed, including known session paths, nested protected data and CLI conflicts.
- 12 isolated transfer checks passed: full-content match, source retention, byte/hash recording, private permissions, pre-start cancellation, missing destination, symlink/database/directory rejection, mid-copy cancellation, source preservation and refusal to overwrite an existing destination.
- Ad-hoc signature verification and `git diff --check` passed.
- Native preview navigated all 14 routes and produced screenshots in `artifacts/native-workspaces/`.
- Native accessibility interactions verified search, expansion, selected byte totals, inspector visibility, navigation/search reset and application filters; Codex selection was disabled.
- Preview was responsive after navigation; one idle sample was approximately 95 MB RSS and 0% CPU. This is a smoke check, not a long-duration stability guarantee.
- No real cleanup, app uninstall, health fix, restore, drive formatting, source relocation or external transfer was executed. Real-drive unplug/reconnect and live mutation testing remain release gates.

## Run modes

Open `dist/Cairn.app` normally for live functionality. A preview process was opened with `--preview-ui`: it shows labelled fixtures and disables disk actions/settings changes. Quit that preview before opening normally.

Developer checks: `Cairn --safetycheck`, `Cairn --workspacecheck`.
Deterministic native captures: `Cairn --preview-ui --capture-workspaces=/absolute/output/folder`.

Current build and check logs: `artifacts/checks/`. Visual QA: `design-qa.md`.

## Overview and window refinement — 28 September 2026

Overview now uses its own storage-summary layout, without the generic right inspector. Launch size is 1120 × 740, constrained to the screen; the fixed window floor is 1024 × 680. Sidebar is 200pt and inspectors are 300pt. Screenshot automation no longer saves a forced oversized frame. Build, safety, isolated transfer and signature checks passed again. Native screenshots and interaction evidence are in `artifacts/overview-redesign/`; search, period switching, finding-to-Developer navigation and manual resizing to 1024 × 680 were checked. Daily history is sampled on launch, not a continuous monitor or per-app growth attribution. No real cleanup was exercised.

## Selected Overview + Storage implemented — 28 September 2026

The selected concepts are now two screens of the same native app. Overview has full-width history, paired capacity/change metrics, category deltas, search, period switching and a review sheet linking to existing cleanup tools. Storage has an internal/external drive strip, drive identity details, a category table, selected export workflow, tool-specific guidance and transfer history. Sidebar groups start collapsed; all existing routes remain available.

New `ScanComparison` preserves two completed scan measurements separately from the mutable cleanup snapshot. Comparisons require matching settings/category coverage, full-disk access and internal-only scope; incomplete readings, reported permission gaps and incompatible measurements do not produce deltas. Old last-scan snapshots cannot establish a comparison baseline: two new qualifying scans are required. No real scans were run for this delivery. A cancelled old scan task also now returns before flushing pending items into a subsequently started scan.

Build/signature/diff checks, safety checks and 23 isolated workspace checks passed. UI verification and source comparison passed for this scope; see `design-qa.md`. The updated `dist/Cairn.app` is a local ad-hoc-signed development build and remains open in sample-only preview. Actual copying, removal and disconnect/recovery testing remain release gates. Tool configuration changes are guidance, not implemented relocation actions.

## Cleaner component direction — 28 September 2026

Applied the selected component-study direction to native Overview and Storage: quieter graphite tokens, open sections instead of nested cards, a native chart selection guide with an exact dated reading, slim drive-capacity bars, compact export steps and expandable copy details. Shared primary buttons now honor the SwiftUI disabled environment and use smaller default spacing. Existing navigation, safety guards and transfer logic are retained; no new dependencies.

Debug build, ad-hoc signature verification, safety checks, 23 isolated workspace checks and diff whitespace validation passed. Actual native captures from the first pass are in artifacts/clean-components (Storage was subsequently compacted further). Overview selection was observed in native accessibility and captured output. The final sample-only build is open; final Storage disclosure click-through was blocked by UI automation state errors/timeouts, so that interaction and minimum-window sizing remain unverified for this pass. No real scans, cleanup or file transfers were run.

## Cleanup inspector refinement — 28 September 2026

Cleanup uses neutral selected rows and a roomier item column: the duplicate Location column is hidden only while the inspector is visible. Category details prioritize measured size, requirements and review guidance. File details prioritize consequences, required application closures and the actual cleanup method; full resolved path, modification date and exclusion action are in a disclosure. Finder access remains available. Disclosure state resets per inspected item/category. Existing selection, review and protection logic is unchanged. Close-app prerequisites use amber rather than a green checkmark.

Debug build, signature validation, diff check, safety checks and all 23 workspace checks passed. Native screen captures in artifacts/clean-inspector verify the category inspector and list layout (captured before the final amber prerequisite correction). UI automation selected a separate live app instance, so no disk actions or settings were exercised there. Individual disclosure interaction remains a manual QA item. No real cleanup or transfer was run.

## Control-panel Overview — 28 September 2026

Replaced the prior Overview composition with the selected in-chat control-panel design: regular-weight capacity headline, minimal full-width history graph, a single Start here suggestion, and quiet external-storage/activity sections. Added a purpose-built compact button style rather than reusing the old primary component. History opens a period picker and exact daily readings; What changed opens observed category deltas. Positive growth suggestions choose the largest measured increase among matching categories, only when comparison is available; missing/incomplete/incompatible data offers a scan rather than invented growth. Review links use existing cleanup routes. External storage reads the shared drive store and refreshes on mount/unmount. Activity uses the existing removal log. No new library or mutation capability was introduced.

Debug build, strict ad-hoc signature verification, safety checks, all 23 isolated workspace checks and git diff --check passed. Actual native capture: artifacts/control-panel/dashboard.png. In the separately identified Cairn Preview sample-only app, native accessibility verified History, period switching, What changed, change-to-Developer navigation, Storage shortcut, and Copy details expansion (closing a prior interaction QA gap). Final minimum-size/first-use rendering was not rechecked in this pass. Other workspaces retain their existing layouts; this is an Overview redesign, not a claim that every screen has been rebuilt. No real scan, cleanup, settings change or copy was performed.

## App-wide control-panel styling — 28 September 2026

Extended the selected Overview design language through the shared workspace, all cleanup categories, Large Files, Duplicates, Apps, Health, Activity, Storage, Preferences and review dialogs. Larger regular-weight page headings, quieter column headers, neutral selection, slim separators and compact control-panel buttons replace the heavier prior treatment. Lists open without a permanent inspector; selecting a row reveals its existing details and navigation resets the inspector. Preferences uses direct segmented tabs and drops its redundant permanent explanatory inspector; protection information remains in its dedicated tab. Selection, removal eligibility, review requirements and underlying engines are retained.

Main windows now restore their saved frame on later live launches, use a centered compact first-launch size, and clamp restored frames to the current screen. Frame restoration happens once outside SwiftUI layout to avoid the prior resizing feedback loop. Preview windows do not persist the live frame. This persistence path has compiled but has not been exercised in a live launch/relaunch test.

Build, strict ad-hoc signature verification, safety checks, 23 isolated workspace checks and diff whitespace validation passed. Native screenshot traversal captured all 14 routes in artifacts/suite-style. Visually inspected Smart Scan, Apps and Settings captures. The final segmented Preferences picker and removal of unfocused row highlights were built after capture. Manual on-demand inspector interaction could not be conclusively verified because the preview changed during automation; no personal-data actions were executed. No live scans, cleanup, app removals, service changes or transfers were performed. Updated local executable: dist/Cairn.app. The open suite preview predates those final two small refinements and has been left undisturbed.

## Steady sidebar feedback — 28 September 2026

Sidebar rows and group disclosures now use a dedicated button style that returns the label unchanged, removing system plain-button press dimming/scaling. Selected labels retain regular weight and no minimumScaleFactor, avoiding selection-driven text-size shifts. Sidebar transactions disable inherited animation; clicking the current route is a no-op. Persistent selection fill/icon colour and hover fill remain. Build, signature and diff checks passed. This patch did not change data operations; press-and-hold visual verification is still needed on the refreshed build. Existing running preview processes were not restarted.

## Overview scan control and interaction polish — 28 September 2026

Overview always exposes Scan this Mac / Rescan / Stop scan beside History, independent of whether a growth suggestion is available. Cmd-R invokes that control; preview and cleanup guards remain. Other scanning workspaces also expose Cmd-R. Cmd-F focuses the current workspace search through focused scene commands; Escape clears search and releases focus. Cancel in cleanup review supports Escape and remains disabled while cleaning. Read-only sheet buttons share the compact style; completion Escape dismisses without starting any action. Native NSVisualEffectView header material follows window activation, with a Reduce Transparency fallback and no layout/tracking hooks. Scan timestamps, partial-result wording and a scanning indicator distinguish idle, active, stopped and completed states. Activity navigation uses a constant smaller label font to avoid truncation without selection scaling.

Build, signature, whitespace, safety and 23 workspace checks passed. Native accessibility verified that Overview retains Rescan alongside a growth suggestion, Cmd-F focus, Escape search clearing and History dismissal. Sample-only route captures are in artifacts/polish; no actual scan/cleanup ran. Live operation-state transitions and Reduce Transparency switching were not exercised. The final Activity label sizing was built after the captured screenshots. Main local bundle dist/Cairn.app is updated; the separate polish preview remains open with fixture actions disabled.

## Sidebar flash follow-up — 28 September 2026

Removed transient sidebar hover fills and wrapped route/disclosure mutations in an explicitly nonanimated transaction. Sidebar label content transitions are identity-only; stable selection remains the sole fill change. Three different preview apps were running; the two older preview instances were closed and the newest preview was quit, updated and reopened with --preview-ui. Main app bundle also updated. Build, signature and diff checks passed; native accessibility verified navigation to Storage and expansion of Clean in the restarted preview. These checks establish the new build is running and navigation works; they do not constitute frame-by-frame proof that no transient flash remains. No real scans or file operations ran.

## Dialogs and finished states completed — 28 September 2026

Active workspace sheets now use CairnDialog: shared 600pt standard / 740pt wide geometry, 24pt content spacing, a fixed footer, consistent action placement, scrollable long content, visible keyboard focus and Escape dismissal. This covers cleanup review and completion, app/duplicate/health/restore confirmations, storage map, drive information, transfer history and Overview history/change details. Destructive confirmation actions have no Return shortcut. Cleanup completion is a native modal sheet, presented after review dismisses; active cleanup cannot be interactively dismissed.

CairnStateView provides scanning, empty, interrupted, completed and attention states across cleanup, Apps, Duplicates, Health, recovery and transfers. Partial results and skipped items are explicit; moving to Trash is not presented as immediately freed capacity. Cancelled app and health scans remain stopped on navigation until an explicit rescan. Filtered empty states suggest changing the search rather than unnecessarily rescanning. Empty cleanup results do not repeat their scanning/interruption banner.

Native sample-only QA exercised all five states, actual confirmation and completion sheets, long-path wrapping, Tab focus and Escape dismissal. Actual History, empty Transfers, Drive information scrolling and Apps search-empty views were inspected. The state gallery is opt-in via --preview-ui --preview-states and performs no disk actions. Build, strict signature verification, safety suite, all 23 isolated workspace checks and whitespace validation passed. No live scan, cleanup, removal, restore or external-drive operation ran; live interruption/recovery and long-duration stability remain release gates.

## Sidebar disclosure motion — 28 September 2026

Clean and Files now reveal their children as one clipped group using SwiftUI's native smooth animation (280ms, no extra bounce). Opacity, a 6pt vertical offset, group height and chevron rotation move together; row text never scales. The prior global animation suppression is removed only from the sidebar container; route selection remains explicitly nonanimated and the custom button style retains no press dimming/scaling. Collapsed children cannot receive pointer input and are hidden from accessibility. Reduce Motion uses immediate disclosure updates with no offset.

Debug build, strict app signature and whitespace checks passed. The refreshed sample preview verified Clean and Files expansion, child navigation, and Clean collapse removing its children from the accessibility tree. Final expanded layout was visually inspected. Native animation interpolation and Reduce Motion switching were not frame-recorded or live-toggled. No scanner or disk action was run. Main and polish-preview bundles are updated.

## Identity, status and filter clarity — 28 September 2026

The topbar now has an explicit 200pt sidebar identity area and a workspace title aligned at the main content inset. The toolbar uses CairnMark.png, extracted without visual changes from the 128pt representation of the existing Cairn.icns master. Explicit original PNG rendering avoids a colour mismatch observed with direct ICNS rendering. Local/release packaging includes the asset. Activity uses a full-size, untruncated sidebar label while keeping Activity & Recovery in the page title, help and accessibility label.

Overview now changes its heading for low storage using the existing below-5-percent threshold, instead of always displaying a reassuring headline. Search placeholders and help identify the current filter scope. Overview explicitly explains that an unmatched mp3 query filters category growth rather than searching files. Filtering logic and scanner/removal engines remain unchanged.

Debug build, strict signature verification, shell syntax checks and diff whitespace checks passed. Native sample UI verified final blue artwork, header alignment, low-space copy, category-filter help and empty results, Escape clearing, and Activity navigation with full page title and route-specific filter. No real scan, cleanup, settings change or file transfer ran. Other capacity states are source-verified, not separately exercised in the UI. Main and polish-preview bundles updated.

## Topbar simplification — 28 September 2026

Removed the always-visible global-looking filter and generic info popover. The titlebar now contains the quiet blue Cairn mark, current page title, and only applicable Rescan/Details actions; Details has a text label. Restored the established capsule mark with a fixed blue base instead of embedding the colourful Dock tile. Chrome now blends within the window over graphite, avoiding wallpaper-driven colour shifts.

Find is retained for measured result lists through Edit > Find in Results / Cmd-F. It opens a local inline filter below the titlebar. Escape or Done clears and closes it; navigation also clears it. Overview, Storage and Settings do not offer Find. No filesystem-wide search is implied or implemented.

Debug build, strict signature and diff checks passed. Refreshed native sample preview visually checked on Overview and Apps. Cmd-F plus Chrome narrowed four sample apps to Google Chrome; Escape closed the row and restored all four. Cmd-F on Overview did not expose a filter. No real scans or data actions ran. Main and polish-preview builds updated.

## Fade-only sidebar — 28 September 2026

Replaced animated group-height/offset/chevron movement with a 180ms opacity fade. Opening reserves space before fading children in; closing fades them out before releasing space without layout interpolation. Rapid reversals cancel the prior disclosure task. Reduce Motion changes disclosure immediately. Collapsed children are disabled, untargetable by pointer and hidden from accessibility. Removed selection backgrounds from category headers and navigation rows; text/icon tone and the selected accessibility trait identify the current route. Native keyboard focus remains available.

Build, strict signature and whitespace checks passed. Sample preview verified expansion, navigation to Developer with no category/child selection fill, and collapse removing children from the accessibility tree. Final disabled/selected accessibility modifiers compiled; no frame recording or live Reduce Motion switch was performed. Main and preview bundles refreshed. No data operation ran.

## Selected native-window mock implemented — 28 September 2026

Replaced custom topbar/HStack navigation with NavigationSplitView and a system unified toolbar. macOS owns window controls, sidebar toggle and page title; no logo/name spacer or global search appears in the toolbar. Existing shell-owned stores remain outside navigation so hiding the sidebar does not restart scanners. Current workspace actions use native toolbar items. Graphite toolbar background, wider sidebar row rhythm, content-only footer and supporting-column divider match the selected mock. Fade-only category disclosure and background-free selection remain.

Debug build, strict ad-hoc bundle signatures and diff validation passed. Safety suite and 23 isolated workspace checks passed with the new shell; subsequent changes only adjusted spacing, copy and colors and rebuilt successfully. Final native captures cover all 14 workspaces. Paired comparison and native hide/show/Details interactions passed; see design-qa.md. Preview idle sample was about 72 MB / 0% CPU. No sustained scan or live-operation stability claim is made.

Updated dist/Cairn.app and dist/Cairn Polish Preview.app by replacing executable files via rename rather than overwriting the inode of a running executable. An already-running main app retains its old executable until the next launch. This reduces the risk of update-induced invalid-code-page termination; it does not prove the exact cause of the earlier signature failure. The sample preview uses the new build. No real data operation or system-setting change ran.

## Restrained border treatment — 28 September 2026

Removed custom button outlines, repeated result-row rules, inspector/action-footer borders, settings row dividers and shared dialog section lines. Major structural separators use a faint shared token; native split-view separation and keyboard focus remain. Spacing and surface tones retain grouping and selected result visibility. Functionality and data-operation guards are unchanged.

Debug build, strict signatures for both bundles and diff checks passed. Updated sample preview captured all 14 workspaces in artifacts/border-pass; Overview and Developer captures and the History sheet were visually inspected. History opens and dismisses correctly. Main bundle updated for its next launch using atomic executable replacement. No live scans or personal-data operations ran; this styling pass makes no new crash-stability claim.

## Native menu-bar dropdown — 28 September 2026

Replaced the two-item SwiftUI MenuBarExtra with one AppKit NSStatusItem/NSMenu controller. Reuses the existing Cairn mark as a monochrome template. Native menu rows expose available capacity, dated daily change, explicit Scan/Stop, latest measured category count and scan date, Activity, local external-drive submenus, protection/exclusion shortcuts, Settings, Open and Quit. No cleanup action is offered in the menu. The count is categories with measured bytes, not a promise of safe savings.

The menu owns no ScanStore and does no recursive scanning. One background metadata task refreshes capacity/history/local drive listings on menu open; network-drive capacity is excluded. Same-day or missing history does not invent a daily delta. Actions route through the existing AppShell stores and validate busy/preview guards both at dispatch and execution. Settings toggles create/remove the item explicitly without App-scene observation or a MenuBarExtra binding feedback cycle. Quit is blocked in this menu while scans or data operations are active. Native app-menu Quit behavior is otherwise unchanged.

Build and strict signatures passed for dist/Cairn.app and dist/Cairn Polish Preview.app. Thirty isolated workspace checks passed, including seven menu status/history cases. Native sample-menu interactions verified Results, Activity, the selected external drive, and the Protection settings tab. Sample scan is disabled. Menu rendering captured from its own AppKit view, with no Screen Recording request. Main app executable updated via atomic rename for next launch; sample preview is running with --preview-menu. No real scans, cleanup, relocation or settings changes ran. Live scan/stop, actual unplugging, menu visibility preference changes and closed-window reopening were not exercised.

## Reliability and storage hardening — 28 September 2026

Fixed verified defects before adding updater/crash-reporting dependencies. Sparkle and PLCrashReporter remain uninstalled.

- LicenseManager construction no longer reads Keychain synchronously. One serial background worker handles storage; a three-second watchdog explains a delay. Missing records are distinguished from denied/malformed reads, update uses SecItemUpdate before add, and trial creation does not replace an existing record. Startup forbids interactive Keychain prompts. Failed reads preserve records and do not manufacture a new trial. The older noninteractive Security query flag remains intentionally in use on this macOS 14 build; the LAContext replacement failed the local interaction-disabled fixture. Compiler deprecation warning remains.
- Scan delivery now has a 2,048-event bound, throttled progress, a 20,000-item display limit and explicit incomplete status on overflow. Cancellation awaits detached producer termination before the shared gate is released. Cancelled queued gate requests are covered by stress fixtures. Transfers/rechecks and restores share the heavy-operation gate.
- Cleanup checks nested exclusions and custom configured conversation roots, plus nested VCS, session/recovery markers, database files/sidecars and credentials. Existing exclusions cannot be bypassed by selecting their parent. Changed scan paths and missing items fail safely. Uninstall no longer requests that applications quit; the user must close them first.
- Recovery and transfer histories reject malformed, duplicate or externally changed records rather than overwrite them. Main cleanup saves each removal before continuing. Restore is asynchronous, validates the recorded entry, refuses existing destinations atomically and retains a Restored record. Cleanup preflights recovery persistence. Ordinary Quit refuses active data operations, and reopening a closed main window is handled.
- External exports pin destination directories, reject path substitution and final-name collisions, verify source and copy, sync the destination, retain originals and mark interruptions. A new Check copy action can verify a recorded finished copy again after reconnection to the matching volume UUID. Missing selected drives do not silently switch to another drive.

Validation: debug build, strict ad-hoc signatures for main and polish-preview bundles and git diff --check passed. 57 isolated reliability assertions, 30 workspace assertions and the safety suite passed; logs in artifacts/reliability. Tests use disposable temporary fixtures, injected Keychain failures and simulated disconnections/collisions. No real Keychain write is made by the suites. Tests include delayed credentials, nested protections, original preservation, corrupt histories, no-overwrite restores, gate cancellation, scan delivery overflow/shutdown and bounded subprocess output/timeouts.

Live UI: exact workspace app launched with --no-auto-scan. Overview and Storage responded while macOS's Security call remained stalled on dev.cairn.license-storage rather than the main thread; the banner truthfully explains the delay. Transfer history opens/dismisses; no-drive copying is disabled. Closing and reopening the same app window worked. Startup smoke sample before the final scan-pipeline addition: about 43.5 MB physical footprint, 46.4 MB peak, ~61 MB RSS, 0.2% CPU. This is idle/UI evidence, not full-scan stability proof. Final packaged build relaunched and Overview verified responsive.

Limits: underlying macOS Keychain delay is not repaired; licensed features wait for that read. No real external drive was connected, so hardware removal, power loss, full-disk behavior and long-duration scans remain release checks. Recovery journaling is not a transactional filesystem: a hard crash or failed final journal write after a Trash operation can still leave Finder recovery necessary; app/health/duplicate batches retain their existing end-of-batch history saving. Arbitrarily renamed/custom session data cannot be inferred from every path. External storage remains verified export copying with originals retained, not automatic developer-folder migration, backup/versioning, RAM expansion or space reclamation. No real cleanup, relocation, service shutdown, tool-path change or other repository edit was performed by this verification.

## Quiet launch, sidebar identity and overload validation — 28 September 2026

LicenseManager now defaults to deferred loading. Constructing the app performs no Keychain read, trial creation or licence-server call. Opening Settings > License requests the check once; subsequent visits do not queue another attempt. Slow/failed checks are contained within that settings card, with an explicit retry after an attempt finishes. The global licence banner is removed. Upgrade routes now select the License tab directly. Purchases are not promoted before the existing entitlement check completes. Pro/tool actions remain locked until the on-demand entitlement check succeeds; no licence is bypassed. The underlying macOS Keychain delay has not been repaired, and a stalled check can still postpone paid features.

Added the established blue Cairn mark and a restrained 16pt semibold name above sidebar navigation. No extra topbar logo, selection fill, outline or press animation was added. Native sample screenshot visually verified size, alignment, graphite continuity and unobstructed navigation.

Validation: debug build, strict signatures on main and sample-preview apps, and diff whitespace checks passed. 59 reliability assertions, 30 workspace assertions and the safety suite passed. New isolated tests confirm no default-startup credential access and on-demand loading.

The new --loadcheck uses the production ScanEventPipeline, ScanGate and FileScan.measure against 1,000 disposable temporary files. Across 72 concurrent/queued requests over 30.63 seconds: 12 completed normally, 36 were cancelled, and 24 stopped at the bounded delivery limit. Heavy operations never overlapped; scanner concurrency stayed at or below four; all workers exited before their slot was released. Sampled RSS: 10.4 MiB baseline, 38.2 MiB peak, 27.0 MiB final. Main-actor heartbeat maximum gap: 44ms. Fixtures were removed after verification; no personal paths were scanned or cleaned by this test. This is a short synthetic regression test, not proof of every real-world workload.

A separate sample-data native UI cycled all 14 workspaces every 1.2 seconds for over 77 seconds. At the measurement it used 107,056 KB RSS (about 104.5 MiB), 0.1% CPU. No multi-gigabyte growth or hang was observed in this bounded run; all preview data actions were disabled. Evidence: artifacts/identity-reliability.

Delivery: both bundles updated using atomic executable replacement and signed. The user's existing main window had a stopped real scan with five items selected, so it was left intact; it retains the preceding executable until relaunch. The final sample preview is open on Overview without automatic cycling. No update framework or crash reporter added; no system security/privacy settings or tool paths changed.

## Optional sidebar focus outline — 28 September 2026

Added a local Settings > General > Sidebar focus outline preference, default off. SwiftUI focusEffectDisabled applies to navigation and disclosure buttons only; their focusability, accessible labels, selection traits and keyboard actions remain. This does not change macOS accessibility settings or other controls' focus rings.

Build, strict signatures and diff checks passed. Native sample UI verified a clicked/selected Overview row without a focus rectangle; Tab moved focus to Clean and Space expanded its children, still without the blue rectangle. General settings exposes the saved preference. Main and preview bundles updated; this change does not touch scanning or cleanup engines.

## Real-machine scan retention fix and cleanup receipts — 28 September 2026

A newly explicit `--readonlycheck` runs the production scanner pipeline against accessible internal storage, without ScanStore persistence, cleanup, license access or configuration changes. It measures resident memory and main-actor heartbeat, cancels at 512 MiB growth, and awaits worker shutdown. Two short cancelled passes surround a scan capped at 90 seconds. Aggregate results only are logged, without personal paths.

The first run FAILED: resident memory reached 523.4 MiB from 7.5 MiB in about seven seconds of the second pass. This exposed directory-walk retention that the prior synthetic workload did not reveal. FileScan now places the enumerator's nextObject call inside its per-entry autoreleasepool and drains measurement-local Foundation objects at each tree boundary. Developer project discovery, Git discovery and large-file walks drain per-directory objects. Nested developer sizing is limited to three workers rather than CPU-count-minus-one.

The repeated real scan PASSED: 5.02-second cancellation, all 19 categories completed in 74.48 seconds (463 candidates; 21 reported access/partial gaps), then 5.14-second cancellation. RSS 7.8 MiB baseline, 30.5 MiB sampled peak, 23.9 MiB final; largest main-actor heartbeat gap 67 ms. All workers stopped before gate reuse. This is bounded real-machine evidence, not exhaustive coverage or a claim that every hang is fixed. Access-denied locations, partial tree measurements, external hardware and overnight operation remain unverified. Baseline failure and successful repeat are retained in artifacts/accounting-stability.

Cleanup now accounts separately for estimated sizes moved to Trash, successfully journaled recovery paths, tool actions and per-volume before/after available capacity. Capacity deltas require matching volume UUIDs, preserve decreases and zero changes, and remain unavailable when readings are missing. The receipt explicitly avoids attributing all capacity changes to Cairn, and says Trash still occupies space. A failed recovery journal write is not counted as recorded recovery. The legacy lifetime total is labeled an affected-size estimate; its stored value is preserved. CLI confirmed cleaning now uses the same ScanStore recovery logging and running-owner guards as GUI cleaning. No real CLI cleanup was executed.

Validation: build passed; 68 reliability assertions (including nine new receipt/capacity cases), 30 workspace assertions, 32 safety assertions and the 72-request synthetic load check passed. Synthetic load: 28.57 seconds, 12 completed, 36 interrupted, 24 bounded-overflow; RSS peak 22.8 MiB, maximum heartbeat gap 31 ms. Strict bundle signatures and whitespace checks passed. Native sample receipt visually checked, including scrolling to the skipped-item explanation and separate tool/Trash/capacity figures. No personal data was cleaned or moved. No external-drive writes, tool-path changes, service shutdowns, Sparkle or PLCrashReporter additions.

Both dist bundles rebuilt. The existing main Cairn process was left intact to preserve its current selection; relaunch is required to use this engine. The updated sample preview opens the inert state dialog. Branding exploration is a separate user-owned Codex task (Cairn logo and name exploration); no identity change was applied here.

## Selected dark carved-stone identity — 29 September 2026

Explicitly authorized selected branding integrated: graphite/carved-stone Dock icon, simpler four-stone blue sidebar mark, opaque monochrome system-template menu-bar silhouette. Name and app identifiers preserved. Selected 1024 px source, reproducible drawing source and identity notes retained locally. Encoded all standard macOS icon representations; iconutil required execution outside the sandbox to encode the otherwise valid size set.

Debug build, strict ad-hoc signature checks on both main and polish-preview bundles, and diff whitespace checks passed. Actual main app launched with --no-auto-scan; sidebar and native About icon visually verified. Left on Overview. Menu-bar template code compiled; menu-bar visibility preferences were not changed. No scanner, cleanup, migration, Keychain, system setting or other repository changes were made for this identity task. No runtime dependencies added. Existing scanner fixes remain in the packaged executable.

## Duplicate-reader runaway reproduced and fixed — 29 September 2026

The previous real-machine engine check omitted the standalone duplicate finder. Investigation of the subsequent user report found duplicate scanning active in the incident log, with no displayed groups and Smart Scan queued at 0%. An isolated production-reader fixture reproduced linear memory growth with bytes read: 64 MiB per pass, reaching 388 MiB before a safety stop while retaining only one digest. The cause was autoreleased FileHandle/NSData read buffers surviving the hashing loop on a background task, not retained findings.

Hashing and archive copying now drain every read buffer within a per-chunk autoreleasepool. Duplicate enumeration drains nextObject within its pool too. Candidate/entry limits are bounded and surfaced; size grouping uses logical lengths; stale callbacks cannot overwrite a cancelled/restarted scan. Memory logging now records physical footprint as well as RSS.

Same hash fixture after fix: eight passes, 10 MiB peak; two verified 64 MiB copies at 10–11 MiB, cancellation and mid-read mutation rejected. Actual native app completed duplicate scanning (604 groups, 108.25s) then all 19 Smart Scan categories (462 findings, 65.45s). Sampled scan footprint peak 65 MiB. Subsequent result-view navigation/sample: 69.2M current, 72.2M process peak. Main-actor heartbeat max 280ms during duplicate scan / 121ms during Smart Scan. Findings remained resident without runaway growth.

71 reliability, 30 workspace and 32 safety assertions passed, as did build, signatures and whitespace checks. Exact evidence, prior-test gap and limits are in artifacts/duplicate-memory/ROOT-CAUSE.md. Main app is running the fixed engine; main and polish-preview bundles updated. No personal cleanup, relocation, system change, other-repository edit or external-drive write occurred. Normal scan summary state was refreshed by the real app. This does not certify every release scenario or every possible crash.

## Storage-control journey checkpoint — 29 September 2026

After the user-requested baseline commit `ae9d050`, Cairn gained internal-volume capacity history, a dedicated Changes screen, a measured-space Make room flow, opt-in alert-only reserve monitoring, source-inode revalidation for Trash and a shared per-action intent/outcome journal across its four cleanup stores. The new screens preserve the existing native sidebar and specialist workspaces. The goal never treats file sizes, Trash moves or a retained-source copy as measured space freed.

Debug build, safety, reliability, workspace, hash/copy-memory and 72-request load fixtures passed. Native sample-only captures cover all 16 routes at 1120 × 740; Overview, Changes and Make room were also inspected at 1024 × 680. Exact logs, captures, limitations and an accidental brief capacity-only QA launch are recorded in [the storage-control validation record](artifacts/storage-control/VALIDATION.md). The running main app and its bundle were not replaced. M1–M5 remain partial, with specific journal recovery, FSEvents, immediate reclaim and independent-review gates; this is not a signed/notarized release or a claim that all prior crashes are fixed.

Follow-up safety pass: app-bundle and fixable health actions now verify the discovered resolved location and device/inode again immediately before Trash. A fixture verifies refusal after a path is replaced. Local action and capacity records use private application-support directory and file modes; the action-journal fixture checks them after atomic save. The app-removal description now correctly says the user must close a running app. The debug build and safety, reliability, workspace, hash/copy-memory and 72-request load fixtures passed again after these changes. That pass sampled 26.6 MiB peak RSS with a 61 ms maximum heartbeat gap. This is fixture evidence, not a real-machine long-run or crash certification.

Activity gained a manual review sheet for interrupted actions. It requires the user to confirm inspection of the original location and Finder Trash, then records the action as reviewed with its outcome still unknown; it does not retry a move or fabricate recovery history. An acknowledgement write failure keeps cleanup blocked, and bounded journal compaction preserves reviewed uncertain entries. The new journal transition has a relaunch fixture. Native UI and long-run recovery still require independent review. The final 72-request load fixture sampled 24.7 MiB peak RSS with a 32 ms maximum heartbeat gap.
