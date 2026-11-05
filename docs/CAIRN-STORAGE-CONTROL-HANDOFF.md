# Cairn: implementation and independent review handoff

**Implementation continuation:** Read [current validation](../artifacts/storage-control/measurement/VALIDATION.md) and [capability ledger](STORAGE-CONTROL-CAPABILITIES.md) before treating the work packages below as unimplemented. Independent review and release gates remain.

29 September 2026 · Companion to [the product requirements](CAIRN-STORAGE-CONTROL-PRD.md).

**This is a handoff, not evidence that the new features are built.** The requested workflow is: agree the direction, switch to GPT-6 Sol for implementation, then switch to GPT-6 Astra for independent review and testing. This documentation task does not switch models, start another task, or activate monitoring/cleanup.

## 1. Read before making changes

1. `docs/CAIRN-STORAGE-CONTROL-PRD.md`: product behaviour, safety, UX and acceptance IDs A01–A24.
2. `BUILD_STATUS.md`: chronological evidence and caveats. Later entries supersede earlier UI/build statements.
3. `artifacts/duplicate-memory/ROOT-CAUSE.md`: the proven hash/read-buffer memory defect, actual fix, previous test-coverage gap and bounded native UI results.
4. `Cairn/Core/SafePaths.swift`, `Cairn/Safety/Cleaner.swift`, `Cairn/Core/ScanGate.swift`, `Cairn/Core/Scanner.swift`: current enforcement and concurrency boundaries.
5. `Cairn/Core/StorageHistory.swift`, `ScanComparison.swift`, `CleanupAccounting.swift`, `StorageTransfer.swift`: foundations and important semantic limits.
6. `Cairn/UI/AppShell.swift`, `OverviewWorkspace.swift`, `DialogKit.swift`, `WorkspaceKit.swift`, `Cairn/App/Brand.swift`: active presentation paths and visual tokens.

The older `docs/FEATURES.md` is not a reliable list of currently enabled capabilities. Do not re-enable actions because its checkboxes say they exist. `docs/DECISIONS.md` contains old brand/pricing/Store assumptions. M0 should reconcile these with pointers and explicit historical labels while preserving useful context.

## 2. Repository and running-app boundaries

- Work only in `/Users/augustusedem/Downloads/SSD/cairn-native` and this task's approved artifact locations.
- Inspect applicable instructions and fresh `git status --short` first. The checkout already has many modified/untracked files from prior work. Preserve all of them. Do not reset, clean, stage everything, overwrite handoffs or commit without instruction.
- Do not modify the older `/Users/augustusedem/CLEANSTUFF` app/repository or other products. Do not scan all repositories to generate test data.
- Resolve current app/process paths before launching or quitting. Different Cairn copies can share a bundle identifier. Use the full workspace bundle path, not `open -a Cairn`.
- Do not overwrite the executable inode used by a running app. Packaging changes need atomic replacement or a safe stopped process. Respect current user selections/results when deciding whether to relaunch.
- Do not run the release script casually: inspect it first; it writes a new `dist/release.XXXXXX` folder and can submit a release artifact for notarization.
- No personal-file deletion/movement, drive formatting/encryption, external-drive writes, tool-setting changes, service shutdown, system-security changes, payment transaction or public deployment is implied by an instruction to implement the PRD. Build and test with disposable fixtures. Ask only when the concrete next operation requires missing authorization.
- This app has no need for a Rust rewrite or a web UI replacement. No new agents/tasks/model switches are implied unless the user asks for them.

### Current brand correction: preserve it

The user rejected the angular carved variant and selected the dark tile with four **rounded blue stones**, with subtle diagonal facets. The native small mark is the smooth four-stone interpretation, and the menu-bar mark is 20 pt. The source resources have been updated by the branding task.

Read-only reference: `/Users/augustusedem/Documents/Codex/2026-09-28/cairn-brand-exploration/selected/README.md`. Do not touch that separate task's files. Do not regenerate icons, rename Cairn to Calenne, or restore the rejected angular geometry as part of this implementation.

The branding task reports a local Developer ID signed arm64 build, not notarized or distributed. Verify any later artifact separately. Prior memory-fix test artifacts used earlier local builds; do not present their signatures as evidence for a newly packaged binary.

## 3. Proposed first implementation scope

Implement PRD milestones **M0–M5**, with recorded progress and small coherent changes. This means trustworthy measurements, Changes/Overview, Make room planning, guarded existing execution/common receipts, and opt-in alert-only monitoring. The code for an uncertified reclaim adapter may be developed behind a default-off capability, but enabling a new permanent operation needs its explicit decision and safety evidence.

Do not bundle M7–M9 into this pass. Release integrations, tool-path relocation and unattended cleanup have separate external decisions/hardware requirements. Keep current export copying supported and accurately described. The future adapter contracts can be introduced without exposing unfinished actions.

No giant switch from old UI to a sample-only replacement. Work vertically: evidence → pure logic → native view → review/executor → receipt. Keep active specialist screens functional after each milestone.

## 4. Work packages for Sol

### M0 — Baseline and contracts

- Capture fresh source/build state and applicable instructions; record pre-existing failures without attributing them to new code.
- Map which routes use which stores, scan triggers, mutation entry points and recovery journals. Include CLI, menu actions, legacy `autoClean`, and code not currently reachable from the UI.
- Confirm `SmartTriggers` is not armed; make the new feature flags default off. Ensure an old persisted preference cannot silently enable new automation.
- Identify current tool commands disabled by policy. Classify observe/guide/Trash/tool cleanup/export/unsupported rather than treating all `.tool` cases as approved.
- Preserve memory fixes: per-chunk read/hash/copy pools, enumerator pooling, candidate limits, throttled delivery, generation guards, cancellation awaiting worker exit, physical-footprint metrics.
- Introduce a shared observed operation state over the existing gate. Do not create a competing scheduler that allows overlapping heavy work.
- Check the exact active logo resources and window/toolbar baseline; preserve the approved style.
- Produce a concise capability matrix and milestone ledger with the current baseline. Do not claim new tests from old logs.

Exit: existing bounded checks recorded, all destructive entry points understood, no existing safety restriction silently relaxed. Acceptance coverage: A09–A11, A20–A21.

### M1 — Measurement engine and persistence

- Define typed observations and coverage results before changing charts. Missing values are not zero; capacity metrics are not file estimates.
- Spike a serialized system-SQLite store with bounded queries/retention and interruptible import. If unavailable in the current build setup, keep the store interface and a bounded versioned prototype; document the decision rather than adding an unnecessary framework.
- Preserve current history and recovery records; legacy daily capacity history stays explicitly unscoped. No guessed historical UUIDs.
- Assign stable volume/root identities; compare only compatible readings. Add subset comparisons and exact intervals for valid roots while other roots are denied/partial.
- Distinguish observation-only protected roots from cleanup candidates. Never read chats, browser history or database contents for attribution.
- Deduplicate overlapping scopes. Do not force category sizes to sum to occupied volume space.
- Use an injectable clock, measurement provider, volume identity source and failure injection so tests do not depend on personal folders.

Exit: history import survives interruption; changed scope/permissions/identity produces the right evidence state; memory/storage retention bounded. Coverage: A01–A05, A19.

### M2 — Native Changes and Overview

- Build an inert representative preview of the whole journey using the real native components. Label every fixture; do not mutate data or preferences from preview mode.
- Preserve the sidebar; add Changes. Make room is a routed workspace from Overview, not a second application or another permanent sidebar tree.
- Render the new information hierarchy from measured data. Keep an obvious Scan/Stop action on Overview; remove any misleading universal-search implication.
- Chart supports reserve line, labelled readings, gaps and selection. It must fit at minimum/default size without clipped endpoints or squeezed controls.
- Inspector is contextual and hides/moves to a sheet before the content becomes cramped.
- Unify operation status across general scan, duplicates, app inventory, health, copy/verify and recovery; menu and footer agree.
- Keep rounded blue stones, graphite surfaces, sparse borders, stable icon colours, opacity-only sidebar disclosure, no selection slab/side stripe/press-scale flash.
- Avoid scanning as a consequence of navigation. Preserve results and selection when leaving a screen.

Exit: inspect native captures and interactions with real empty/partial/comparable states. Coverage: A01–A04, A11, A21. A pretty sample screen alone is insufficient.

### M3 — Goal planning, initially read-only

- Implement `Have T GB available` arithmetic and make the meaning visible. Default example: 12 GB available, 30 GB target, 18 GB shortfall.
- Build typed capabilities and deterministic ranking. Keep protected/unknown/personal-file actions unselected; never widen policy to fill a shortfall.
- Zero immediate reclaim credit for Trash and retained-source exports. Keep future/manual possibilities separate from executable estimates.
- Review snapshots include evidence IDs, exact identity/scope, consequences, preconditions and recovery contract.
- Revalidate plans after settings/permission/drive/measurement changes. Stale plans are explicit; do not execute against replaced sources.
- Show useful insufficient-space and already-met states, including an honest guide to manual actions.

Exit: fixture matrix cannot falsely reach a goal by adding candidate sizes or copying files. Coverage: A05–A08, A13.

### M4 — Guarded execution and common receipts

- Converge current cleanup, duplicate, app and health mutations on durable per-action intent/outcome logging. Retain each feature's stricter protections.
- Do not claim the filesystem and journal form one atomic transaction. Record/reconcile uncertain outcomes without automatic deletion replay.
- Persist intent before mutation, check source identity/exclusions/protected descendants/owner state immediately before acting, persist outcomes before showing success.
- Use the existing heavy-operation gate. Cancellation settles the active worker before handing the gate on.
- Keep restore no-overwrite and phase-specific. If history persistence fails, refuse to begin/continue mutation; don't erase corrupt journals.
- Receipts show affected size, recovery availability, observed capacity delta and current goal separately. Zero/negative/unavailable capacity changes are valid outcomes.
- Spike one narrow immediate-reclaim adapter on disposable fixtures, using current official documentation. Suggested research candidate is npm's supported cache verification/garbage-collection workflow, not blind removal of `~/.npm`. Measure whether it offers useful benefit and refuse unsupported writer/config states.
- Do not enable existing permanent Trash emptying or broad tool-prune commands as a shortcut. Present any new permanent capability with its concrete scope, no-Undo semantics, tests and required decision before enabling it.

Exit: reviewed existing actions use the common contracts; goal outcome cannot be fabricated. Public 1.0 remains blocked if there is no validated useful reclaim route. Coverage: A08–A16, A19.

### M5 — Reserve monitoring, never automatic cleanup

- Implement opt-in lightweight capacity sampling and bounded dirty-root observation with coalescing/backoff. FSEvents is a hint to remeasure, not a byte/process attribution source.
- Handle dropped events, continuous writes, unavailable roots, pause, sleep/wake, restart and external disconnection without scan storms.
- Respect shared operation priority, memory/thermal/energy limits, low-space write limits and the own-data budget.
- Implement reserve target, hysteresis and notification suppression; denied notification permission still allows an in-app state.
- Keep launch-at-login separate and opt-in. Quit semantics must be obvious. Do not add a hidden helper daemon.
- Remove or quarantine contradictory old auto-clean wording and entry points; the new UI must not accidentally arm them through an old setting.

Exit: alert-only rules pass event-storm/notification/restart tests, remain inexpensive and never remove user files. Coverage: A17–A20.

## 5. Test and evidence protocol

### Existing commands to verify, then reuse

Run from `/Users/augustusedem/Downloads/SSD/cairn-native`. These commands are references for the next implementation turn; they were not run as part of writing this handoff.

```sh
CLANG_MODULE_CACHE_PATH=/tmp/cairn-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/cairn-swift-cache \
swift build --disable-sandbox -c debug
```

Inspect current diagnostic source before executing, then run the fixture checks individually and retain exit status/output:

```sh
.build/debug/Cairn --safetycheck
.build/debug/Cairn --reliabilitycheck
.build/debug/Cairn --workspacecheck
.build/debug/Cairn --hashmemorycheck
.build/debug/Cairn --loadcheck
```

The previous recorded totals were 32 safety, 71 reliability and 30 workspace assertions. Counts will change; passing a count is not the objective. Read actual failures. Do not run the old unbounded `--selftest` as an all-purpose verifier.

`--readonlycheck` scans accessible real internal files and has a time/memory guard. `--scan-memory-report=/absolute/file` drives real native stores and updates ordinary scan-summary state. Those are different from disposable tests; confirm their current bounded behaviour and the authorized scope before using them. Never run simultaneous app instances that compete over shared user history or licenses.

Preview flags currently include `--preview-ui`, `--preview-states`, `--preview-menu` and `--capture-workspaces=/absolute/folder`. Use the dedicated preview bundle/identity where available. Inspect flags in source instead of inventing a launch command. The real app's safe launch flag is `--no-auto-scan`.

### Minimum evidence per milestone

- Build identity: source revision when available, working-tree patch scope, compiler/OS/hardware and relevant flags.
- Checks actually run, outputs, elapsed time and failures/skips. Do not cite previous artifacts as a fresh pass.
- Before/after physical footprint, not only RSS; sample peak, plateau and final retained-results state. Include duplicate hash and export-copy paths.
- Native screenshots at 1080 × 720, 1024 × 680 and an ordinary larger size, plus compact fallback where the visible screen is smaller.
- Keyboard navigation, selected state, reduced motion and permission/missing-drive/empty/partial/long-name states.
- Confirmation no personal data operations occurred, or an exact log of separately approved tests on disposable fixtures/drives.
- Remaining risks and unknowns, named precisely. No “all bugs fixed” sentence.

Suggested new evidence directory: `artifacts/storage-control/<milestone>/`. Keep aggregate diagnostics separate from any consented path-level debug material. Link the milestone ledger to exact artifact files; don't fill the PRD with machine-specific private paths from scans.

## 6. Stop conditions and reasonable independence

Continue useful local implementation when a later external decision is unresolved. Examples: a payment provider choice does not block the measurement model; a missing test SSD does not block the goal planner; an uncertified adapter can remain guidance-only while the rest is completed.

Stop the affected mutation/release work when it needs an unapproved permanent action, personal-data operation, credential/payment change, real external-drive write or public publication. Prepare a concrete reviewable result before asking. Do not infer consent from elapsed time or from this document describing the feature.

If code contradicts a factual baseline here, inspect and report the newer evidence. If it contradicts a safety requirement, preserve the stricter policy and identify the gap. Never silently update the spec to make a failing implementation appear complete.

## 7. Astra's independent review brief

Review the final diff, current runtime and artifacts, not Sol's confidence. Re-read the PRD's hard invariants and run representative checks independently. Focus on:

1. **Truth:** Are capacity, file-size estimates, observed changes and promised benefit kept separate? Can a partial scan, stale scope, duplicate path, nil-as-zero or missing volume produce a fabricated insight or successful goal?
2. **Safety:** Can planner, CLI, legacy triggers, app removal, health or duplicate routes bypass `SafePaths`, exclusions, writer checks or review? Are protected descendants caught?
3. **Lifecycle:** Do cancellation and errors await every worker? Can a screen change start duplicate work or release a lease early? Does “queued” remain distinguishable from “scanning”?
4. **Memory/energy:** Do every FileHandle/NSData loop and directory enumeration stay bounded? Are results/history/event queues capped and pressure states safe? Include the path that previous tests missed.
5. **Journal:** What happens if the app is killed immediately before/after each mutation? Does a write failure stop execution? Can rollback overwrite newer data? Is an uncertain action ever replayed destructively?
6. **Storage:** Are external identities and source changes rechecked? Does a copy incorrectly claim migration, backup or freed capacity? Are metadata limitations and missing-drive states exposed?
7. **UX:** Does the native app actually show the promised hierarchy and states at small sizes? No clipped graph, sidebar flash, nonfunctional search, hidden Scan button or conflicting operation status.
8. **Privacy:** Any new path/content upload, secret-bearing log, unnecessary account gate, or missing required API reason? Does diagnosis remain useful without sharing personal files?
9. **Release claims:** Are platform/architecture, licensing, updater and notarization claims backed by this artifact, not an old script or previous build? Are untested hardware scenarios explicit?

Deliver an issue list with severity, file/line, reproduction, consequence and proposed fix. Distinguish confirmed defects from unanswered questions. Critical/high data-loss, unreviewed action, false-success or unbounded-memory findings block release. Re-run relevant tests after fixes, then record a final matrix of passed, failed and unverified requirements.

Review does not mean run destructive tests on personal files. Use fixtures, a test user/VM and an explicitly approved disposable drive. Full-disk-pressure, physical unplug, live tool configuration and commerce tests may remain blocked until their environment/permission is supplied; identify those exactly.

## 8. Ready-to-use model prompts

### When switching to GPT-6 Sol

> Implement the Cairn storage-control direction in `docs/CAIRN-STORAGE-CONTROL-PRD.md`, following `docs/CAIRN-STORAGE-CONTROL-HANDOFF.md`. Start with a fresh source/status check and implement M0–M5 in coherent stages, preserving all existing work, protections, native style and approved rounded blue-stone branding. Keep a requirement/evidence ledger. Use disposable fixtures, bounded tests and actual native UI verification. Keep unapproved permanent reclaim, tool-location migration, unattended deletion and release actions disabled; complete independent work and present any needed decision concretely. Hand back the implementation, test artifacts and remaining gaps for an Astra review. Do not claim public-release readiness from a successful build.

### When switching back to GPT-6 Astra

> Independently audit and test the Cairn storage-control implementation against `docs/CAIRN-STORAGE-CONTROL-PRD.md` and the review brief in `docs/CAIRN-STORAGE-CONTROL-HANDOFF.md`. Inspect the actual diff and runtime, validate the evidence, and reproduce issues with disposable fixtures. Prioritize protected-data safety, honest space accounting, lifecycle/journaling, all memory-intensive paths and the real native UI. Fix confirmed defects within the authorized local scope and rerun relevant checks. Report passed, failed and unverified requirements separately, including any release/hardware/commerce gates that still need approval or external setup. Preserve unrelated work; do not perform personal cleanup or publish a release.

These prompts are provided for the user to use after choosing the model. They are not dispatched automatically.
