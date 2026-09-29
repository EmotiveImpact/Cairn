# Cairn: understand your storage, make room, keep working

Product requirements document · 29 September 2026 · Version 1.0

**Status: proposed direction and implementation contract. No new product functionality is implemented by this document.**

Companion: [Sol implementation and Astra review handoff](CAIRN-STORAGE-CONTROL-HANDOFF.md).

## 1. The product decision

Cairn should evolve from a collection of cleaning tools into a native Mac storage manager that answers three questions:

1. **Where did my space go?** Show measured changes and explain what is known, missing, or uncertain.
2. **How do I make enough room?** Build a reviewed plan around the user's actual storage goal.
3. **How do I avoid this happening again?** Offer lightweight monitoring and, later, narrowly approved maintenance and supported external-storage arrangements.

Proposed promise: **“Know where your space went. Make room. Keep your work safe.”**

The user should not need to understand cache directories to use Cairn. Developers remain the initial audience because their storage problems are frequent and testable; browsers, creative work, downloads and ordinary Mac use remain first-class concerns. This is one application, using the existing SwiftUI/AppKit codebase and established Cairn identity. It is not a separate Codex utility, an AI chat interface, or a rewrite in Rust.

The opportunity is the complete journey from explanation to verified outcome. None of its individual ingredients is claimed to be unique. A Product Hunt ranking or App Store feature is a possible result of useful execution, not a product acceptance criterion.

### What changes in the product's centre of gravity

| Current emphasis | New emphasis |
|---|---|
| Scan, select categories, clean | Understand a change, choose a goal, review a plan, measure the result |
| Large total of candidate files | Current capacity, evidence quality, consequences, remaining shortfall |
| Repeated whole-machine scans | One baseline, bounded targeted measurements, explicit fresh scans when needed |
| “Safe” as a broad severity label | Why an action is eligible, what it affects, what recovery is available |
| External SSD as a copy destination | Initially verified exports; later supported data-location management |
| A lifetime “cleaned” counter | Separate affected file size, recoverable items and observed capacity change |
| A screen-specific busy state | One consistent operation state across the window and menu bar |

Do not remove useful specialist tools to make the home screen simple. Simplify entry and decisions; retain detail behind them.

## 2. Who this serves and what success means

### Primary jobs

| Situation | User needs | Cairn's answer |
|---|---|---|
| “I had 15 GB yesterday; now I have almost nothing.” | Explain a change without guessing | Capacity timeline plus comparable measurements for known locations; explicitly unresolved change |
| “I need 30 GB available for an install.” | Enough space, with the least disruption | A target-based plan, requirements, review and measured outcome |
| “My projects and chats matter more than the disk space.” | Confidence that working data is excluded | Enforced protections and exact action scope, not a reassurance badge alone |
| “My SSD is connected at my desk, but not when travelling.” | Know what depends on the drive | Later: per-tool dependency and missing-drive behaviour, with a readiness check |
| “I don't want to run another cleaner every week.” | Quiet, inexpensive monitoring | Optional reserve alerts and suggestions; automation is a later, separate consent |
| “I just use Chrome, downloads and creative apps.” | Plain explanations without developer terminology | App/location descriptions and ordinary file review; no developer setup requirement |

### Proposed validation targets, not existing results

- Recruit 20–30 consenting beta users across developer, creator and general-use Macs; include 8 GB and 16 GB RAM devices and different disk capacities.
- In moderated tests, at least 80% can identify the largest *observed* change and the measurement limitation within one minute, without help.
- At least 80% can distinguish “moved to Trash,” “copied externally,” and “space now available” after reading a receipt.
- For users with sufficient eligible data, at least 80% can reach their chosen target using a reviewed workflow. Record insufficient-data cases separately; never quietly lower the target.
- No known loss of protected data, unreviewed destructive action, false completed transfer, or silently corrupted recovery record. Any such finding blocks release regardless of averages.
- At least half of activated beta users use Changes, a space plan, or reserve monitoring on three separate days within two weeks. Measure with voluntary local summaries/interviews, not mandatory analytics.
- A first explanation appears from valid saved data immediately; new measurements clearly show their progress and coverage.

The north-star measure is **storage problems resolved with an understood, verified outcome**. Scanned bytes, deleted-file counts and leaderboard rank are secondary.

## 3. What exists today: evidence and limits

This baseline comes from source inspection on 29 September and recorded test artifacts. Older checklists are inconsistent with the current code. In particular, `docs/FEATURES.md`, `docs/DECISIONS.md` and some source comments describe old UI, enabled destructive commands, pricing or distribution assumptions. They must not be used to bypass current guards.

| Capability | Current evidence | Required evolution |
|---|---|---|
| Native app and shared UI | `Package.swift`, `UI/AppShell.swift`, `UI/WorkspaceKit.swift`, `UI/DialogKit.swift`; macOS 14+, SwiftUI/AppKit | Keep the native shell, sidebar, dialogs and specialist routes; add purpose-built Changes and planner views |
| General/developer/AI/creative scanning | `Scanners/ScannerRegistry.swift`: 19 registered scanners; bounded delivery in `Core/Scanner.swift` and `ScanStore.swift` | Separate measurement coverage from cleanup eligibility; deduplicate overlapping locations |
| Available-space history | `Core/StorageHistory.swift`: one launch-day reading, at most 90 readings; legacy forecast helpers | Versioned per-volume observations, explicit missing readings, finer recent history; replace overconfident forecast wording |
| Category comparison | `Core/ScanComparison.swift`: two immutable candidate readings; incompatible/partial coverage withheld | Root-level measurement history and independent comparable subsets; no inference that candidate growth explains all disk growth |
| Overview | `UI/OverviewWorkspace.swift`: capacity, history, one suggestion, storage/activity links | Goal-aware control panel with evidence, reserve state and clear first-use behaviour |
| Reviewed cleanup | `Safety/Cleaner.swift`, `Core/SafePaths.swift`, `UI/ReviewSheet.swift` | Capability-based plan execution; fresh validation; common durable action journal |
| Accounting and recovery | `Core/CleanupAccounting.swift`, `Core/ScanStore.swift`, recovery UI | Carry truthful accounting into goals; close end-of-batch journal gaps in app/duplicate/health paths |
| Duplicates, Apps, Health | Separate stores and workspaces owned by the shell | Preserve functionality and protections; share operation state and journal, with no scan merely from navigation |
| External drive support | `Core/StorageTransfer.swift`, `UI/StorageWorkspace.swift`: encrypted local APFS checks, UUID checks, bounded verified export copy/recheck, source retained | Keep current export scope explicit; directory migration and tool configuration require separate adapters |
| Background cleaning | `Core/SmartTriggers.swift` and `autoClean` are dormant legacy mechanisms; current UI does not arm them | Do not activate them. Audit/remove obsolete entry points before a new rules engine; their comments and notification wording are not the new contract |
| Menu bar | `App/CairnMenuBar.swift`: native dropdown, measurements and navigation | One shared status, reserve state and plan entry; no quick-delete control |
| Licensing | `Licensing/Licensing.swift`: Polar client and deferred Keychain access | Verify purchase, activation, offline use, expiry and revocation; keep startup independent; final pricing/provider decisions remain open |
| Updates/distribution | Build scripts and local bundles exist; the latest branding task reports a Developer ID signed arm64 build, replacing the earlier ad-hoc build. Notarization/distribution is not established | Verify the exact release artifact, supported architectures and notarization; tested update channel; Sparkle is not integrated |
| Crash diagnostics | Local bounded memory diagnostics/checks | Opt-in support export first; PLCrashReporter is not integrated and is not a substitute for performance testing |

### Memory evidence we must preserve

`artifacts/duplicate-memory/ROOT-CAUSE.md` records a reproduced FileHandle/autorelease buffer-retention defect. A repeated-read fixture rose to 388 MiB before a safety stop. After per-chunk pooling it completed at roughly 10 MiB. A recorded native UI run completed 604 duplicate groups and all 19 general categories with a sampled scan footprint peak of 65 MiB; later result-view sampling reported a 72.2M process peak.

These are prior bounded tests, not new measurements taken while writing this PRD or proof of zero remaining bugs. The earlier general-scanner test missed the standalone duplicate path. Every new release gate must include **all** scan, hash, copy and retained-result paths, and physical footprint rather than RSS alone.

### Visual baseline

The retained preview `artifacts/border-pass/dashboard.png` was inspected for composition. It demonstrates the intended compact graphite window and open sections, but is historical sample data, predates subsequent branding work, and is not evidence of the current running app. During this PRD, the branding task supplied a correction, confirmed by its selected-assets README: the user approved the **dark tile with four rounded blue stones and subtle diagonal facets**, superseding the angular carved version. Current `CairnArt.swift` uses the smooth compact mark; the menu mark is 20 pt. Preserve that corrected identity and rollback material. Do not redraw or rename the brand as part of this PRD.

Brand source: `/Users/augustusedem/Documents/Codex/2026-09-28/cairn-brand-exploration/selected/README.md`. A read-only signature inspection found a signed arm64 bundle with a team identifier; a full release-signature/notarization check was not performed in this documentation task.

## 4. Release boundaries

| Stage | Included | Explicitly absent |
|---|---|---|
| Private product beta | Comparable growth history; new Overview/Changes; goal planning; reviewed existing actions; common operation/journal state; optional alert-only reserve monitoring | Public safety/performance claims; automatic deletion; general migration |
| Public 1.0 candidate | Beta features plus at least one validated immediate-reclaim route, end-to-end receipts/recovery, sustained QA, licensing/distribution/update readiness | Blanket external relocation; cloud storage pool; automatic maintenance |
| Managed external storage | One independently certified tool-location adapter, supported version matrix, disconnect/restart/rollback tests | General symlink engine; arbitrary project/database moves |
| Selective maintenance | Opt-in rules over a very small certified allowlist, preview/history/caps and revocation | “Clean all caches,” automatic user-file deletion, forced app shutdown |
| Optional Mac App Store edition | Sandbox feasibility study followed by a tested capability-specific edition | Assumption that the present unsandboxed app can be uploaded unchanged |

An attractive planner that only moves files into Trash cannot satisfy the public “make room” promise by itself. If an immediate-reclaim route is not ready, ship only an accurately described preview/private beta or explicitly user-guided workflow, not a false completed goal.

## 5. Core experience and information architecture

### Navigation

Keep the sidebar. Add **Changes** after Overview. Retain Clean and Files with their existing children, Apps, Storage, Health, Activity, and Settings. Keep labels short; Activity opens recovery as well. Do not duplicate all specialist pages under a new navigation tree.

**Make room** is the primary action on Overview and a routed full workspace with Back, not an additional permanent sidebar category. A current plan can be resumed from Overview and Activity. Settings gains Monitoring; rules appear only when implemented. No disabled “coming soon” clutter in ordinary navigation.

```text
Overview ── What changed ── Changes ── Inspect location ── existing detail
    │
    └── Make room ── Choose target ── Plan ── Review ── Run ── Receipt
                                                          │       │
                                                     Activity   Re-measure
Storage ── Drive details ── Export / supported adapter ─────┘
Settings ── Monitoring ── Reserve target / pause / notifications
```

### First launch

1. Show measured internal capacity and one action: **Scan this Mac**. No sign-in, payment, Keychain access or permission wall before a basic view.
2. Explain that scanning reads metadata and does not remove files. Offer useful accessible-path results without Full Disk Access; explain permission gaps at the affected feature.
3. Display “First measurement” until another comparable reading exists. No synthetic trend or inferred history before installation.
4. After the scan, offer **Make room**. The user can review files without enabling monitoring.
5. Introduce reserve monitoring after the first useful result, with default off. Closing its explanation does not consent.

### Returning user with low space

Open to capacity, reserve shortfall if configured, the largest comparable change and one recommended next action. A stale result carries its actual date. A running duplicate scan appears as that operation, not “Ready” because Smart Scan is idle. Opening a screen never starts overlapping heavy work.

### User asks for space now

Enter target → see current capacity and shortfall → freshen affected measurements → compare plan choices and consequences → explicitly review actions → execute → measure again → either show target reached or explain the remaining shortfall.

### Nothing can safely be reclaimed

Say “Cairn hasn't found enough eligible space for this target.” Offer personal-file review, external-storage options, or Apple's storage settings. Do not widen the safety policy, turn missing data into zero, or replace the user's target without consent.

## 6. Requirements: measurement and explanation

### MEAS-01 — Separate three different quantities

1. **Available capacity:** a timestamped macOS volume reading, including its measurement type.
2. **Observed location sizes:** measured allocated/logical sizes for specific supported roots and scopes.
3. **Action estimates:** eligible file sizes and estimated consequences for a proposed operation.

These are not interchangeable. Candidate totals may overlap; APFS clones, hard links, snapshots, compression and purgeable space prevent a simple sum from proving reclaimable capacity. Never build a misleading pie chart that forces file estimates to equal total disk use.

Use the important-usage capacity API consistently for the user-facing “available” value, while explaining that macOS may include reclaimable capacity. Keep optional raw capacity readings separately typed; never mix series silently. Missing or failed readings are `unavailable`, not zero. Apple documents distinct volume-capacity keys and associated privacy declaration requirements; verify the selected APIs and required reasons for the release. [Apple capacity API](https://developer.apple.com/documentation/Foundation/URLResourceKey/volumeAvailableCapacityForOpportunisticUsageKey)

### MEAS-02 — Versioned observations with coverage

Every observation records volume identity, time, metric kind, scope/configuration signature, adapter version, access state, coverage, cancellation/limit status and source. A location measurement also has a stable root identifier and discovered identity; path strings alone are insufficient.

Two readings are comparable only when their identity, metric and measurement coverage agree. A permissions change invalidates the affected comparison. One unreadable root must not hide all other valid comparisons: show a comparable subset and its exact interval, without presenting it as a full-machine total. A deleted root is zero only if its parent was successfully checked and absence is established; otherwise it is missing.

Legacy history has no reliable volume/scope identity. Preserve it as a labelled legacy series; do not fabricate UUIDs or use it for new root attribution. Preserve old scan snapshots and recovery records during import.

### MEAS-03 — What changed, not who caused it

Start with known locations for build output, package caches, browser disk caches, downloads and selected creative exports. Expand observation-only coverage for protected application state without making it eligible for cleanup. Root-level size metadata is enough; do not read conversation contents, browser history or database records to make an explanation.

Use wording with a visible evidence class:

| Evidence | Permitted wording | Not permitted |
|---|---|---|
| Same root measured twice | “Xcode build output grew by 6.2 GB between these scans.” | “Xcode wasted 6.2 GB.” |
| Known browser cache location | “Chrome disk cache grew by 800 MB.” | “YouTube caused this,” or claims about browser RAM |
| Capacity changed; roots only partly covered | “12 GB less available. Some changes are outside measured locations.” | “The rest is macOS updates” |
| Independent read-only system observation | “macOS reports swap use of …” with time/source | Treating swap as a cleanup/move candidate |
| Forecast from sufficient observations | “At the recent rate, your reserve may be crossed in …” | “Your disk will be full Friday” |

A residual difference may be shown as **not explained by these measurements**, only when intervals and compatible metrics allow meaningful comparison. It must not be renamed “System Data” or “macOS-managed storage” without direct evidence. If reconciliation is not valid, present capacity change and location changes separately, with no residual arithmetic.

### MEAS-04 — Incremental monitoring, not continuous full scans

Proposed initial policy, to tune from energy tests:

- With monitoring enabled and the process awake, sample cheap local capacity metadata approximately every five minutes, plus wake/mount and completed-action boundaries.
- Use FSEvents for explicitly covered roots to mark locations dirty, not to infer byte deltas or the writing application. Coalesce changes; bound the dirty-root set; no unbounded per-file event retention.
- A dirty root waits for a 60-second quiet window and is not remeasured more often than every 15 minutes in background mode. A continuously changing root remains labelled pending; no scan storm.
- Give background traversal a time budget, initially 30 seconds per scheduled job. Budget exhaustion is partial, with backoff; large roots may require a user-started scan.
- Reconcile event gaps, root replacement and dropped events with a bounded rescan; never silently trust a discontinuous stream. Apple's FSEvents guidance explicitly requires rescanning after dropped events. [Apple FSEvents guide](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/UsingtheFSEventsFramework/UsingtheFSEventsFramework.html)
- Pause background traversal on low power, serious thermal/memory pressure, or critical storage pressure. Capacity/status remains available where feasible. Do not wake a sleeping Mac to scan.
- Network volumes are not watched automatically. External volumes require explicit inclusion. Cloud placeholders must not be downloaded or materialized by measuring them.
- Default retention: seven days of fine capacity readings, daily aggregates up to 90 days, bounded root measurements and change events. Proposed own-data budget: 100 MB, excluding separately bounded recovery records. Downsample disposable measurement data first; never delete recovery records to hit the analytics budget.
- Monitoring while the app is open and launch-at-login are separate permissions. Use Apple's Service Management APIs if login support is enabled. No hidden daemon or root helper. Quit stops monitoring; closing the window may leave the explicitly enabled menu-bar app running, which must be explained. [Apple SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice?language=objc)

### MEAS-05 — Honest forecasts

Forecasting is secondary and may be omitted from the first beta. Require at least seven comparable daily observations spanning seven days, exclude discontinuities, and show the window and uncertainty. A flat or noisy trend produces no date. Replace legacy phrases such as “No risk in the next year” and avoid calling a configurable reserve a universal macOS danger threshold.

## 7. Requirements: Make room planner

### PLAN-01 — Unambiguous goal

Default input is **“Have [30] GB available on [Internal storage].”** This is a final capacity target, not 30 GB extra. Optionally offer an explicitly labelled “Find [x] GB more” mode later.

For an available reading A and target T, current shortfall is `max(0, T - A)`. Example: 12 GB available, target 30 GB, shortfall 18 GB. A separate reserve R matters only if the user explicitly selects “leave my reserve after an estimated install”; do not silently add R twice. Installation requirements are entered by the user; Cairn cannot guarantee an install's unknown temporary-space needs.

If capacity is unavailable, the target is impossible for the volume, or the target is already met, show that state immediately. Never force a cleanup to justify the app.

### PLAN-02 — Action catalogue, not a pile of scanner results

Build typed action capabilities independent of the old SAFE/REVIEW/RISKY enum. Each action includes:

- Stable target identity, provider/adapter and version, scope and measurement date.
- Action kind: observe, guide, Trash, supported tool cleanup, export copy, future configured relocation.
- Protected-content checks, excluded ancestors/descendants, and reasons for ineligibility.
- Preconditions: owning application/build/daemon state, drive identity, permissions, freshness, available scratch space, licensing if applicable.
- Expected result: affected bytes, reclaim estimate with confidence/range if defensible, and whether immediate internal release is even possible.
- Consequences: rebuild, download/network cost, loss of offline availability, loss of recovery, or external-drive dependency.
- Exact recovery contract and an implementation-supported executor; UI alone never enables an action.

Rank deterministically by eligibility, disruption, recovery quality, evidence confidence and benefit. Size is not the only score. Hard protections override all ranking. Show up to three understandable groups, not a hundred prechecked rows. Recommendations do not execute and do not mean consent.

Overlapping parent/child findings and hard-linked items must not count twice. Unknown clone/snapshot effects lower confidence; they are not optimistically ignored. The planner never changes old exclusions or unlocks dormant destructive commands to meet a target.

### PLAN-03 — Make the Trash constraint unavoidable in the model

| Action | What the planner can promise before execution |
|---|---|
| Move to same-volume Trash | Recoverable organization/removal from the original location; zero immediate reclaim credit |
| Verified external export, source retained | A verified copy; zero internal reclaim credit |
| Supported tool cleanup | Potential release with stated uncertainty; typically no Cairn Undo for tool-deleted data |
| Personal-file review | A decision for the user, not automatic savings |
| Future verified relocation with source retained | Destination ready; zero reclaim until a separately approved source-removal step |
| Future source removal after verification | Potential release, subject to filesystem retention; final available reading decides outcome |

Do not sum “possible later” actions into “available after this plan.” Present them as separate optional steps. If the user manually deletes selected items through Finder, a fresh capacity reading may update progress, but Cairn must not attribute that change to its own executor.

**Immediate-reclaim feasibility gate:** before public 1.0, certify at least one narrow, documented tool-managed cache cleanup or another expressly reviewed reclaim path. `npm cache verify` is a candidate for a spike: npm documents integrity checking and garbage collection, but it may reclaim nothing and modifies cache contents. It needs isolated fixtures, version checks, process coordination and truthful no-Undo disclosure. Do not treat the entire npm directory as disposable. [npm cache documentation](https://docs.npmjs.com/cli/v11/commands/npm-cache/)

Existing permanent Trash emptying stays disabled. Enabling a new permanent operation requires its own explicit product decision and review. A guided external action can be part of a beta plan, but must be visibly distinct from an action Cairn can execute.

### PLAN-04 — Review and execution

Review shows exact targets, selection, requirements, expected consequences, recovery limits and what will *not* count as freed space. “Run 3 reviewed actions” is preferable to “Optimise.” No deceptive all-safe default. Protected and unknown items are never preselected.

Execution acquires the existing shared heavy-operation gate. Revalidate identity, policy, exclusions, owning-process state and mount state at the time of each action. A stale or altered action is skipped/replanned, not silently replaced by another target. Do not automatically quit applications or stop databases. A running GUI-app check alone cannot prove there are no command-line writers; unsupported concurrency means guide/blocked state.

Record durable intent before mutation, then outcome immediately after each item. A filesystem mutation and a database transaction are not atomic together: recovery must represent “outcome uncertain” and reconcile from evidence without replaying a deletion. If journal persistence is unavailable, destructive work does not start or continue.

Cancel means stop before the next safe boundary, settle the current bounded operation and record completed/unfinished actions. Changing screens does not cancel or duplicate execution. App Quit warns/blocks only for active data operations and offers safe cancellation where supported; a queued read-only scan is not an inescapable quit trap.

### PLAN-05 — Receipt and goal completion

Show four distinct facts: actions completed/skipped/failed; estimated file size affected; actual recovery availability; before/after capacity for the same volume. Refresh capacity after settled actions and again after a brief bounded delay if appropriate. Display timestamp and metric; APFS/purgeable-space changes may lag or have other causes.

“Target reached” requires a fresh valid capacity reading meeting T. It means **the target is currently met**, not that Cairn alone freed the delta or guarantees it stays met. If capacity decreases during the operation, display the decrease. If the drive disappears, status is unavailable. Never count a cancelled step, retained source or unrecorded recovery path as success.

Illustrative receipt: “2 items moved to Trash; 1 tool action completed. 4.1 GB more available now. Your 30 GB target is still 2.8 GB away.” Sizes in mocks are sample data and must be arithmetically consistent.

## 8. Requirements: reserve monitoring and later rules

### RES-01 — Alert-only reserve in the first product release

Users choose a reserve in GB; suggest 30 GB for the reference 500 GB Mac as an editable product default, not an Apple requirement. Enable only by explicit choice. It is a warning target, not an OS quota or a promise that Cairn can reserve bytes against other applications.

Use two readings at least five minutes apart before a normal crossing notification; urgent near-full states can alert on a single valid reading. Proposed urgency threshold: below 2 GB on the internal drive; tune through tests and explain actual capacity, not a generic health score. Suppress repeated notices, respect quiet hours, and reset crossing state only after sufficient recovery (initial hysteresis: 2 GB above target). Notify at most once per crossing with a 24-hour reminder ceiling unless a materially worse condition occurs.

Notifications open a plan, never run cleanup. Permission denial leaves in-app status functional. Pause for one hour, until tomorrow, or indefinitely. Persist notification state across restarts. Show coverage gaps and last observation if the process was not running.

### RES-02 — Later maintenance rules

Do not connect the old `SmartTriggers`/unbounded collector implementation to the new controls. Build rules on the same bounded measurements, policy catalogue, gate, executor and journal as manual plans.

A rule identifies a certified data type and exact approved scope, age/size threshold, schedule/trigger, affected-byte ceiling, owning-process condition, drive requirement, consequence and recovery contract. Provide a dry-run preview, visible last-run receipt, pause/revoke and a safe “do nothing” fallback. Age alone never proves disposability.

Initial mode is **suggest only**. Executing without a prompt is a later separate opt-in for a very narrow regenerable allowlist; not a global permission. Never automate conversation deletion, repo/worktree cleanup, DB directory sync, personal-file deletion, emptying all Trash, model removal or service shutdown. Subscription expiry must stop future paid automation without interrupting recovery or leaving a transaction incomplete.

## 9. Requirements: external storage

### EXT-01 — Preserve today's verified export workflow

Current scope is individual finished archive/document/media exports to an eligible encrypted local APFS volume. Originals stay in place. The content hash is verified, but existing export code does not preserve all extended attributes/resource forks. Say “verified content copy,” not full-fidelity migration or backup. A suffix such as `.zip` is not proof that the file contains no sensitive work; it remains a user-chosen export.

Explain unsupported formats, locked drives, insufficient space and unknown encryption as concrete states. Do not format, encrypt or benchmark-write a user's drive without approval. An encrypted SSD is recommended for sensitive work; a USB stick may be slow or unreliable, so eligibility is based on tested properties and workload, not advertised capacity or the word “SSD.” Never combine internal and external free space into a fictitious single pool.

### EXT-02 — One supported relocation adapter first, later

Recommended first research candidate: an isolated package-cache location, because tools such as npm document a configurable cache path. This is a candidate, not certification. The installed tool version, configuration precedence, concurrent writers and missing-drive behaviour must be tested first. [npm configuration](https://docs.npmjs.com/cli/v11/using-npm/config/)

A valid adapter must:

1. Discover the effective path without exposing credentials or mutating project configuration.
2. Explain and acquire the needed permission; establish a supported quiescent state or refuse relocation.
3. Bind to a volume UUID plus expected destination identity and permissions. UUID is a check, not cryptographic proof against a cloned/malicious drive; ambiguous duplicates fail closed.
4. Preflight space, filesystem semantics, encryption, file names, metadata requirements and temporary overhead.
5. Copy into a unique staging destination without overwriting anything. Preserve the adapter's required metadata; content-only export is not reused blindly for directories.
6. Verify contents/structure and metadata, recheck the source has not changed, and sync committed output.
7. Snapshot only the configuration needed for rollback in private local storage. Preserve unrelated settings and secrets; never log full credential-bearing config.
8. Change a documented tool setting with a reversible patch and verify the effective value in relevant environments. No blanket symlinks.
9. Test actual use. Explain offline behaviour. Do not claim successful redirection because a copy exists.
10. Keep the source by default. Offer any later source-removal step separately, after verification and explicit review; explain loss of a second copy and actual reclaim uncertainty.
11. Journal every phase and support safe recovery after process termination, power loss or drive removal.

For npm, one user setting cannot override every project/env/CLI setting. A missing `/Volumes/...` path can have dangerous or confusing fallback behaviour. If an adapter cannot establish safe startup with the drive missing, ship guidance only. Cairn cannot control a third-party tool launched while Cairn is not running.

Docker Desktop documents its own disk-image relocation workflow. Follow its supported mechanism; do not move `Docker.raw` as an ordinary live file. Database contents and container volumes need application-aware handling. [Docker Mac storage guidance](https://docs.docker.com/desktop/troubleshoot-and-support/faqs/macfaqs/)

### EXT-03 — Recovery is phase-specific

| Interruption | Required outcome |
|---|---|
| Copy interrupted | Source intact; partial never presented as complete; explicit resume/restart decision |
| Verification failed | No configuration change and no source removal |
| Configuration partly changed | Show exact uncertain phase; verify effective settings before any next action |
| Drive disconnected | Stop writes; never switch destination by name or recreate the missing mount path |
| Reconnected at another path | Resolve original identity; require revalidation, not string substitution alone |
| Source changed after copy | Invalidate removal eligibility and remeasure/reverify |
| Rollback after tool wrote new external data | Preserve both versions; no blind overwrite; adapter-defined reconciliation or manual recovery |
| Restore lacks internal space | Explain required capacity; do not remove the external copy to make room |

Relocation changes the active location. Synchronization propagates changes, including unwanted ones. Backup requires an independent recovery policy/version history. A verified second copy is useful but is not automatically a managed backup. Google Drive and a VPS are separate future archive/remote-compute choices; neither adds RAM, redirects swap, or substitutes transparently for an always-connected local disk.

## 10. Protection, recovery and privacy are product behaviour

- Keep known Codex/ChatGPT/other conversation locations, credentials, keychains, source control, uncommitted work, worktrees, session recovery, databases/WAL/sidecars, signing materials and irreplaceable application libraries out of generic cleanup and automation.
- Protect descendants even when their parent is selected. Resolve aliases/symlink and replacement races according to the existing policy; never follow a selected parent into excluded content.
- Permit observation-only aggregate sizing where appropriate without converting a protected folder into a candidate. A folder named cache is not sufficient evidence of disposability.
- User-added exclusions and custom session roots remain supported. Be explicit that arbitrary renamed unknown data cannot always be recognised. “Known work locations protected” is more honest than “all your work is safe.”
- Never move or delete live swap/update/protected system files, disable protections, or imply an external SSD adds memory.
- Never synchronize live databases as ordinary files. Later database support requires a documented export/backup/checkpoint and restore procedure for each database, with explicit approval.
- No paid gate on seeing action history, restoring supported recoverable items, stopping work, exporting support diagnostics, or understanding protection warnings.
- Local by default: do not upload file paths, browsing information, source, conversation content, volume serials or credentials. Optional diagnostics must be previewable and redacted. Local filenames and paths are still sensitive; protect store permissions.
- History deletion means a distinct user action with clear consequences. Never auto-expire actual Trash items because an activity display has a retention setting.
- Journal corruptions, full disks and persistence failures produce a visible safe stop. Never reset malformed recovery data to an empty “healthy” state.

## 11. Visual and interaction specification

### Keep the identity; improve the information

Keep charcoal/graphite surfaces, existing blue action accent, recognizable app icons, the approved rounded blue-stone branding, native traffic lights and a compact translucent titlebar. No new component library is needed for this direction. Use native Swift Charts, SwiftUI and small AppKit bridges where they solve actual platform behaviour.

The visual improvement is **clarity under real conditions**: richer but readable history, a plan you can understand at a glance, and excellent partial/error/completion states. No new decorative orb, “AI sparkle,” generic health score, oversized marketing heading, confetti, nested cards or constant animated gradient.

### Overview composition

```text
Native titlebar: sidebar toggle · Overview                   [Scan / Stop]
┌─ sidebar ─────┬─────────────────────────────────────────────────────────┐
│ Cairn mark   │ THIS MAC                          Observed 2 minutes ago │
│ Overview     │ 12.4 GB available             Reserve 30 GB · 17.6 short │
│ Changes      │                                                         │
│ Clean >      │ Available-space history           24 hours / 7d / 30d   │
│ Files >      │ [complete chart + optional reserve line + event marks]  │
│ Apps         │                                                         │
│ Storage      │ What changed                                             │
│ Health       │ Build output +6.2 GB · observed between comparable scans │
│ Activity     │ Other changes aren't fully measured.       [See changes]│
│              │                                                         │
│              │ Need more room?                              [Make room]│
│              │ External storage                 Recent action          │
│ Settings     │ Studio SSD · connected           Receipt / recovery     │
└──────────────┴─ one truthful operation status ──────────────────────────┘
```

This is a layout specification, not a rendered mock or real measurement. On first launch, replace the chart with its quiet empty state and make Scan the primary action. With valid findings, Make room becomes primary; Scan remains visibly accessible. Show the most useful insight, not an arbitrary rotating suggestion.

### Changes workspace

Full-width history across the top, then a compact table: location/app, observed increase/decrease, interval and coverage. Optional inspector shows before/after measurements, relevant paths, why a tool association is known, and available actions. Initial time ranges: 24 hours, seven days, 30 days, disabled with explanation when history is insufficient. Do not pretend the old launch-day history supports hourly events.

Selecting a row can highlight matching measured events on the graph; filter feedback never fabricates causality. Show gaps as gaps, not interpolated certainty. A trend needs a visible scale or exact reading labels, a unit and enough endpoint padding to avoid the earlier clipping concern. Event markers distinguish Cairn actions from observed growth; do not equate timing with cause. Offer an accessible text/table view of the same readings.

### Planner workspace

Keep the target and current shortfall in a compact summary, with rows grouped as **Available actions**, **Needs your review**, and **Not available now**. The third group is collapsed unless it explains the shortfall. A footer shows action count, honest expected benefit and Review. A consequence appears next to the action, not buried behind an info icon. Use an inspector for detail on wide windows and a detail sheet on narrow ones.

A plan-progress view shows named phases and completed actions; use indeterminate progress when total work is unknown. Never display a guessed 99% for minutes. The receipt replaces the plan state in place; recovery opens the common Activity view.

### Shared visual rules

| Element | Requirement |
|---|---|
| Window | Target first launch around 1080 × 720; respect visible screen bounds and restored frame. Validate 1024 × 680 and 1280 × 800. Collapse an inspector before clipping content. On smaller visible bounds, provide an accessible compact layout rather than forcing a window offscreen |
| Sidebar | Roughly 200 pt; preserve current grouping and no selection fill, cyan side strip, click flash or press scaling. Selected destination uses restrained text weight and semantic selected state |
| Branding | Small shared mark and name at sidebar top; one coherent master geometry. Full app tile belongs in Dock/About; template silhouette in menu bar. Verify actual source/bundle/running appearance rather than trusting a handoff |
| Toolbar | Native translucent chrome, current page and contextual actions. No nonfunctional universal search; Cmd-F opens a clearly scoped result filter only where it works |
| Type | System font; body approximately 12–13 pt, supporting text readable, page title 22–24 pt, capacity 36–42 pt. Monospaced digits; no oversized website headline |
| Surfaces | Existing `Brand` graphite tokens; use spacing and subtle surface changes for grouping. Sparse structural dividers, no border around every row/card |
| Charts | Blue for capacity; quieter contrasting reserve line; uncertainty/gaps explicit; hover/keyboard readouts; short fade for data replacement, no line racing across the screen on navigation |
| Colours | Stable app-icon colours; blue for a primary action, amber for attention, red only for a destructive action/failure, green only for a verified outcome. Labels/icons carry meaning without colour |
| Motion | 120–180 ms opacity transitions as initial tokens, no spring/scale/sidebar sliding. Expansion reveals rows by fade; layout changes do not animate a squeezing panel. Respect Reduce Motion |
| Focus | Preserve keyboard navigation and semantic selection. Respect the existing local optional sidebar-focus setting; provide a subtle keyboard-only cue when needed, never change system accessibility settings |
| Sheets | Consistent `CairnDialog` family, approximately 560–640 pt where space allows, constrained to window; scroll body, persistent footer, Cancel/Back left and primary action right; no nested confirmation pileup |
| State views | First reading, scanning, queued, partial, no change, no candidates, stale plan, denied access, disconnected drive, interrupted action, complete and complete-with-shortfall are designed states |
| Operation status | Shared across every store: queued, measuring, hashing, copying, verifying, cleaning, restoring, interrupted or idle. Name the operation; never contradict the visible workspace |
| Menu bar | Native dropdown with capacity/reserve, active operation, Open Changes, Make room, pause monitoring, Settings and Quit. Keep the restrained appearance; no miniature web dashboard or destructive quick action |

Every new screen needs real native captures at default/minimum sizes, long names, missing permissions and empty states. Compilation is not visual verification. Preserve the user's established style; check the information hierarchy against this specification in one inert end-to-end preview before broad visual implementation.

## 12. Proposed architecture

Retain Swift, SwiftUI/AppKit and the existing scan/copy primitives. No runtime LLM is needed for measurements, recommendations or permissions. Deterministic rules keep explanations testable and offline. A future language layer must not invent measurements or choose destructive commands.

```text
Capacity sampler + explicit scan + dirty-root watcher
                         │
               Operation coordinator
               (existing ScanGate underneath)
                         │
       Versioned measurement store ── Change explainer
                         │                    │
                   Capability catalog ── Goal planner
                                              │
                                       Review snapshot
                                              │
                                Guarded per-action executor
                                              │
                                 Durable journal + receipt
                                              │
                                   Fresh capacity reading
```

### Responsibilities and likely code seams

| Component | Responsibility | Existing integration points |
|---|---|---|
| `MeasurementStore` | Versioned, bounded per-volume/root observations; import and retention | `StorageHistory`, `ScanComparison`, `Volumes` |
| `GrowthMonitor` | Capacity scheduling, dirty roots, pause/backoff, coverage and event gaps | `AppSettings`, mount notifications, new FSEvents bridge |
| `OperationCoordinator` | One observed operation/queue/cancel state; no second independent gate | `ScanGate`, all shell-owned stores, menu/footer |
| `CapabilityCatalog` | Adapter versions, classification, preconditions, effects and recovery contract | `Models`, `SafePaths`, scanners, `Regenerability`, `ToolRunner` |
| `ChangeExplainer` | Pure comparable-reading rules and evidence-labelled text | `ScanComparison` |
| `SpacePlanStore` | Goal, immutable selected plan, stale state, dry-run and action outcomes | `ScanStore`, new planner workspace |
| `ActionJournal` | Durable intent/outcome, reconciliation and cross-feature recovery | removal log, transfer records, app/health/duplicates |
| `ReserveMonitor` | Hysteresis, alert suppression, permission state, no mutation | `Notify`, menu bar, Monitoring settings |
| `StorageAdapter` | Future supported configuration transaction and rollback | `StorageTransferStore`, bounded hash/copy helpers |

Use a local SQLite store behind one serialized owner for the new measurement/journal data if the integration spike supports the existing SwiftPM build cleanly; Apple's system SQLite is sufficient. Introduce no remote database. Bound transactions and WAL growth. Retain old JSON files during migration and do not rewrite all history on each progress event. A schema migration must be tested for interruption and rollback. If SQLite integration is deferred for the first measurement prototype, keep the same store interface and bounded/versioned files; do not build unbounded append logs or make recovery depend on a temporary format.

### Minimum data contracts

| Record | Required fields |
|---|---|
| `VolumeObservation` | ID, time, volume identity, mount context, metric type, available/total values or error, source/version |
| `RootObservation` | root ID and identity, volume ID, scope signature, logical/allocated bytes, time interval, coverage, permissions, adapter/version, partial reason |
| `ChangeEvidence` | before/after IDs, compatibility result, delta if valid, known association, explanation and uncertainty |
| `ActionCapability` | typed action/provider, target identity, policy version, preconditions, consequences, estimate provenance, recovery contract |
| `SpacePlan` | ID, target/volume, capacity baseline, evidence IDs, selected actions, creation/expiry, validation state |
| `ActionRecord` | ID, plan ID, intended operation, original/destination identity, durable phase, actual outcome, recoverability and error |
| `ReservePolicy` | volume ID, target, enabled/paused, notification consent, crossing state, cooldown/hysteresis |
| `MigrationRecord` | adapter/version, source/destination identity, phase, manifests/digests, safe config rollback reference, source-retention state |

Plans are invalidated by action-relevant identity, permission, exclusion, drive, policy or source changes. Initial plan freshness budget: five minutes for execution eligibility, always with just-in-time checks. A time limit is not a substitute for identity validation. Existing mutable post-cleanup snapshots cannot serve as historical evidence.

### Operation and persistence rules

One heavy operation at a time across general scanning, duplicates, inventory, health, measurement traversal, tool cleanup, hash/copy, restore and future migration. Metadata sampling can run independently only if cheap and cancellable. Priority is user-requested work over monitoring; coalesce queued duplicates, do not accumulate repeating timers in a queue. Producers must stop before releasing their gate lease. Views observe state; they do not own background workers.

Recommended action phases: proposed → reviewed → revalidating → intent recorded → executing → verifying → completed / skipped / failed / interrupted / outcome uncertain. Persist before showing success. A crash at any phase must never trigger automatic replay of destructive work. Safe resumable copying can be separately offered after revalidation.

## 13. Performance, resilience and own-data budgets

These are proposed release targets on an agreed test matrix, not claims about every Mac:

- Idle main app physical footprint target under 100 MiB; ordinary scan/hash/copy combined with retained results under 200 MiB. Investigate sustained footprint above 250 MiB. Use measured fixture baselines; do not “fix” failure by raising thresholds without review.
- Add a diagnostic growth guard at 384 MiB above baseline for stress runs. Runtime memory-pressure handling pauses/cancels at safe boundaries; do not abruptly kill a mutation or release its gate while its worker is alive.
- Main-actor heartbeat target p95 below 100 ms, maximum below 500 ms under normal local test workloads. A >2-second gap fails the responsiveness gate and needs explanation/fix.
- UI acknowledges Cancel within 200 ms; local traversal/hash/copy normally settles within two seconds. A blocked filesystem call may exceed that: keep the state honest, retain the gate and don't start overlapping work.
- Preserve current 2,048-event queue cap, 20,000 displayed/candidate limits and per-chunk autorelease pooling unless measured evidence supports a safer replacement. Partial results are explicitly labelled.
- No recursive walk, hashing, synchronous Keychain call, subprocess wait, large decode or history rewrite on the main actor.
- Idle background monitoring target below 0.5% average CPU on the reference 16 GB Mac over an agreed idle interval. Measure energy, wakeups and I/O as well as memory; file counts alone are not sufficient.
- At critically low space, bound or pause history writes, report monitoring degradation, and preserve action journaling capacity. If durable action records cannot be written, fail before mutation. Cairn must not become another unbounded storage consumer.
- Crash/diagnostic logs rotate and remain small. Optional support export excludes personal paths by default; users preview before sharing.
- Test on minimum supported macOS and a current release, Apple silicon and Intel if both binaries are shipped. Record hardware, workload and build identity beside results.

## 14. Existing features: keep, adapt, demote or defer

| Area | Product treatment |
|---|---|
| Smart Scan and specialist categories | Keep as expert views and data providers; use Review language and don't erase existing options |
| Old Space Missions/presets | Map useful goals into the planner; retire duplicate promises such as “Free 10 GB Fast” if they don't measure the outcome |
| Large files | Keep manual review, reveal and exclusions; don't interpret age/size as permission to delete |
| Duplicates | Keep full verification and keeper selection; separate browser/scan work from removal; no automatic selection of copies in the new goal plan |
| Apps | Keep bundle-only reviewed removal with current support-data protections; do not expand uninstall scope silently |
| Health | Keep current relevant findings and advice. No new general “speed booster” or malware feature to inflate breadth |
| AI models | Review only with download/offline cost; conversations and model data are distinct, never one generic AI cache bucket |
| Browser storage | Separate known cache roots from sessions/history/passwords/profile databases. Clearing a cache is not a memory-pressure solution |
| Protected macOS/swap/update areas | Observation/explanation only when supported; no cleanup or relocation capability |
| Recovery | Promote into every receipt; common journal for all mutating features; never gated by purchase |
| Storage | Honest export capability now, one proven relocation adapter later; no universal Move button |
| Search | Scoped filters that work; no new global search index unless evidence and bounded indexing justify it |
| Forecasts | Secondary, uncertain and optional; remove false precision before expanding |
| Legacy safe/risky flags | Retain compatibility while action capabilities take over eligibility; no UI-only safety enforcement |
| Brand/name | Keep Cairn and the corrected rounded blue-stone identity. Preserve current assets/rollback material; no rename to Calenne or return to the rejected angular mark |

## 15. Dependencies, payments and distribution

Do not add repositories just to make the app seem more advanced. Prior references such as Pearcleaner, czkawka, GrandPerspective, MacDirStat and npkill can inform research, but they are not required engines for this direction. Verify licenses and fit before reusing any code. Do not clone or modify unrelated product repositories during this work.

Use built-in frameworks for UI, charts, filesystem events, notifications, hashing and Service Management. A dependency must close a specific tested gap and include version/license/maintenance review.

For the proposed direct release, Sparkle is the likely updater: signed artifacts/feed, secure hosted URLs, version monotonicity, staged rollout and interrupted-download testing. Keep signing keys out of source. The app must defer installing an update during a data operation and preserve journals and licensing state. Sparkle's documentation requires cryptographic signing of update artifacts. [Sparkle publishing](https://sparkle-project.org/documentation/publishing/)

PLCrashReporter remains optional after memory/performance and structured local diagnostics are reliable. It needs consent/privacy policy, symbolication, collection destination and support ownership; crash reporting does not diagnose every hang and does not fix one.

Polar code exists, but pricing, commercial tier boundaries and live transactions are not certified. Proposed principle: scan, explain limitations, review protection, stop work and recover previous actions remain available without a purchase barrier. Paid value can be planning convenience, extended history, reserve monitoring or later storage management. Decide the actual free/paid split and price after beta evidence; do not silently reuse conflicting old prices or subscription assumptions. Test entitlement caching, refunds/revocation, offline grace and stalled Keychain access without blocking core UI.

Direct distribution proposal: website for explanation/support/checkout; a public binary-release repository or equivalent CDN; private source if desired; feed under a controlled domain. Developer ID signing, notarization and a tested update path are release requirements, not satisfied by a local ad-hoc signature or an existing script.

Mac App Store is a separate feasibility track using shared code. Test scoped access and every capability under App Sandbox; don't assume all cleaning is impossible or that all current features will work. Use App Store-compatible commerce and Apple-delivered updates for that edition. Review current policies before submission; older repository comments categorically ruling out the Store are not a final product decision. [Apple review guidelines](https://developer.apple.com/app-store/review/guidelines/#performance)

Prepare the privacy policy, support channel, exportable diagnostics, release notes, rollback guidance and accurate store/website screenshots before launch. No in-app “free RAM” promises, fictitious storage savings or unverified competitor/safety claims.

## 16. Delivery sequence and exit gates

| Milestone | Deliverable | Exit evidence |
|---|---|---|
| M0: baseline and contracts | Preserve work; map active routes/capabilities; reconcile stale docs and dormant automation; capture current test/visual baseline | File/status inventory, capability matrix, existing checks recorded, no protections weakened |
| M1: trustworthy measurements | Versioned per-volume/root store, migration, missing/partial semantics, comparable changes | Deterministic fixture tests for identity/scope/gaps/overlap/import; bounded retention and full-disk failure cases |
| M2: Changes and Overview | One inert end-to-end preview, then native evidence-driven screens and common operation status | Default/minimum-size captures, keyboard/VoiceOver checks, no clipped chart, no phantom actions/scans |
| M3: goal planner | Goal arithmetic, typed capabilities, deterministic recommendations, review-only plan | Fixture plans for met/impossible/partial/stale goals; Trash/copy never credited as immediate reclaim |
| M4: reviewed execution | Unified per-action journal, revalidation, cancellation/reconciliation, receipts; certify a narrow reclaim route | Crash/failure fixtures, no-overwrite recovery, same-volume capacity outcomes, no false completion |
| M5: reserve monitoring | Opt-in bounded observer, dirty-root coalescing, notifications/pause/restart | Event-drop, busy-loop, pressure, sleep/wake, permission and notification tests; no automatic deletion |
| M6: independent beta assurance | Astra audit of changed code and complete user journey, then controlled beta | Recorded issues by severity, fixes/retests, sustained tests and user-comprehension evidence |
| M7: public release preparation | Commercial decisions, updater, signing/notarization, support and onboarding | Actual end-to-end transactions/update tests and signed artifact evidence; explicit release approval |
| M8: managed external adapter | One supported tool-location workflow with phase recovery | Disposable-drive hardware tests, missing-drive startup, interrupted transfer/config, version and rollback matrix |
| M9: selective rules | Suggest-only first; later explicitly opted-in execution | Per-rule permissions/caps, pressure and expiry behaviour, audit history, independent safety review |

M0–M5 are the proposed next implementation scope; M6 is the planned Astra review before public-release work. M8/M9 are designed here so the architecture can accommodate them, not permission to enable them during the first build. Do not estimate calendar delivery until M0 reveals migration and executor work.

## 17. Acceptance matrix

| ID | Scenario | Pass condition |
|---|---|---|
| A01 | First launch/no history | Real capacity or unavailable state; no fabricated trend, growth or savings |
| A02 | Two compatible root readings | Correct delta and exact interval, linked to evidence; clear association without causal speculation |
| A03 | Partial/denied root | Valid subset remains useful, missing root not zero; no full-machine claim |
| A04 | Metric/scope/volume changed | Incompatible series not joined; user understands why comparison is absent |
| A05 | Parent/child/hard-link overlap | No double-counted action benefit; clone uncertainty remains visible |
| A06 | Goal 30 GB, capacity 12 GB | Shortfall 18 GB; Trash/export-only plan cannot mark target reached |
| A07 | Target already met/impossible | Honest no-action or impossible state; no unnecessary cleanup |
| A08 | Source/permissions/exclusion changed after review | Mutation refused or re-reviewed; no substitute target |
| A09 | Protected content nested in selected parent | Every relevant entry point blocks it, including planner/CLI/legacy routes |
| A10 | Owner/build/writer active | Unsafe action blocked; no automatic quit or service shutdown |
| A11 | Cancel, navigate, rescan rapidly | Workers settle before gate reuse; no stale callback or duplicate action |
| A12 | Crash around each journal/mutation boundary | Completed/uncertain actions reconcile; no destructive replay or hidden loss of history |
| A13 | Capacity same/lower/unavailable after cleanup | Receipt preserves truth; no “freed” from summed file sizes |
| A14 | Restore collision/full disk/missing Trash file | No overwrite; exact unavailable or interrupted recovery status |
| A15 | Drive removed/replaced/name reused | Stop safely, source retained, correct identity required; no fallback mount directory |
| A16 | Export/source mutation/copy corruption | Failed verification never marks complete; no source removal |
| A17 | Monitoring event storm/dropped events | Bounded queue/backoff and reconciliation; UI responsive |
| A18 | Sleep/wake/restart/notification denied | No fake uninterrupted history, duplicate alert storm or lost pause preference |
| A19 | Near-full disk/history write fails | Bounded degradation; destructive operation blocked without durable intent |
| A20 | Hash/copy/repeated scans with retained results | Physical footprint bounded across real paths, not just a standalone general scan |
| A21 | Keyboard/VoiceOver/Reduce Motion/small window | Every action reachable, meaningful labels/state, no clipped chart/footer or sidebar flash |
| A22 | Upgrade/license unavailable | Core UI responsive; existing recovery and safe cancellation remain available |
| A23 | Update during action/interrupted update | Installation deferred; app/data intact; verified restart/import |
| A24 | Future adapter missing drive at tool startup | Documented safe behaviour or adapter refuses support; no claim beyond control |

Tests first use disposable fixtures and simulated failures. Real personal cleanup, external-drive writes, tool-path changes, database shutdown, system-setting changes, remote publishing and paid transactions need explicit approval for the concrete operation. Existing authority to build does not silently authorize those tests.

Run current safety/reliability/workspace/hash-memory/load suites, add focused tests for new behaviour, and profile the actual UI retaining results from multiple tools. Add overnight observation/soak, low-disk VM or disposable-volume tests and hardware disconnect tests before related release claims. Record what was not run. Passing synthetic tests does not substitute for runtime validation.

## 18. Main risks and product decisions

| Risk | Response |
|---|---|
| “Explain everything” exceeds ordinary filesystem evidence | Explicit coverage and uncertainty; no process/website attribution without evidence |
| Planner feels impressive but cannot release bytes | Immediate-reclaim feasibility gate; goal completion tied to capacity, never Trash totals |
| Background manager recreates the original memory problem | Shared budgets/gate, per-chunk pooling, dirty-root bounds, actual multi-store soak tests |
| Generic action accidentally includes work | Typed allowlists, nested protection, revalidation, journal and cross-entry-point tests |
| Migration works only while Cairn is running | Test third-party startup/missing-drive behaviour; refuse unsupported adapters |
| Too many features obscure the main value | Prioritize Changes → Make room → receipt; preserve expert tools as secondary destinations |
| Review disagrees with implementation claims | Requirement IDs and evidence per milestone; no blanket “all fixed” report |
| Model handoff loses local work or style | Dedicated handoff, source inventory, preserve uncommitted/untracked files and native captures |

Recommended defaults, pending user review: same Cairn brand; same native app; direct beta first; no runtime AI; monitoring opt-in and read-only; shared safety model; managed relocation and automatic cleanup after core proof. These are planning recommendations, not applied settings.

Decisions that genuinely need the owner before the affected stage:

1. Public distribution priority: direct first as recommended, Store feasibility alongside it, or Store-first with capability compromises.
2. Payment model, exact price and free/paid boundaries; provider accounts/domain and update hosting ownership.
3. Whether any new permanent reclaim operation should be offered, its exact scope, and its recovery disclosure. Keep current guards until approved and tested.
4. Whether to promote one external-location adapter after its feasibility results, and which disposable drive/workload is approved for hardware tests.
5. Any future unattended cleanup permission. Alert-only monitoring is not that permission.

Do not ask these questions as a blocker to M0–M3. Build the measurement/review foundation with conservative defaults and surface a concrete decision when it affects execution.

## 19. Launch story and claims discipline

Proposed 45-second real demonstration: unexplained storage drop → comparable observed growth → choose an available-space target → review consequences → execute a supported action → show measured capacity and remaining/reached target. Use sample labels if any part is a fixture. Do not demonstrate fake historical evidence or claim a retained export freed internal space.

Before launch, recruit people with the actual problem, document their outcomes with consent, make onboarding easy, and publish an understandable protection/recovery explanation. Product Hunt encourages authentic engagement, not ranking hacks; a #1 result is not guaranteed. [Product Hunt preparation](https://www.producthunt.com/launch/before-launch)

For a Store edition, pursue a feature nomination after the app is compatible and polished. Editorial featuring is different from chart position. [Apple featuring](https://developer.apple.com/app-store/getting-featured/)

Do not market “revolutionary” as a substitute for proof. The strongest claim we can earn is that Cairn helps people understand a storage problem, resolve it with informed control, and keep working without losing what matters.

## 20. Definition of done for this direction

The direction is delivered when a user can follow the complete core journey on their Mac with honest evidence, protected work, a reviewed action, an accurate receipt and optional quiet reserve alerts; when every retained specialist tool follows the same safety/operation contracts; and when the relevant reliability, accessibility and distribution gates have actual evidence.

A new theme, a passing build, an inert mock, a planner backed by sample values or an updater configuration alone does not meet that definition. External relocation and unattended maintenance earn their own later completion claims only after their separate gates pass.
