# Reliability completion pass — 1 October 2026

This records a local implementation and validation pass, not public-release certification or an independent audit. No personal cleanup, service shutdown, external-drive write, package install, payment, or release was performed. Only generated fixture files were moved/restored; existing running Cairn apps were not restarted.

## Implemented

- Durable versioned run receipts for reviewed Clean/Make room actions and the Apps, Duplicates and Health workflows. Existing per-file recovery logs remain authoritative. Old history is retained as individual actions; no historical run grouping is invented.
- Receipt intents precede mutations. Central cleanup checkpoints progress and links action-journal entries to a run ID. Completed receipts retain skipped/error/interruption state, recovery paths, file-size accounting, and before/after capacity observations. Interrupted receipts show the last saved checkpoint and explicitly direct the user to recorded actions; they never imply unsaved outcomes or authorize replay.
- A serialized receipt actor uses private temporary files, synchronized writes, atomic replacement, version/conflict checks and bounded storage (512 runs / 8 MiB). It never silently expires receipts. Corrupt, conflicting or unwritable receipts block new operations. Live specialist runs are not mislabeled as crashed after Activity refresh.
- Activity exposes saved cleanup runs after restart. A fresh scan no longer discards the latest receipt. Completed restore status remains a per-file historical fact; receipts do not become permission to restore without checking the recovery log.
- A kernel-owned exclusive process lease prevents cooperating builds/CLI processes from opening the same live data store. Crash/exit releases the lease without deleting the lock file. Existing legacy apps with the production bundle ID are detected before new startup; they are activated instead of terminated. An unmodified old binary launched *after* a new one cannot be made to honor a lock it does not implement.
- The central cleanup path consistently uses its injected journal, enabling isolated tests of the actual executor. Fixture scans suppress personal snapshot/statistics writes. Cleaner retains all policy checks; tests substitute only the final OS Trash move with a no-overwrite move inside their temporary directory.
- Fixed a real Large Files rendering defect discovered in native stress testing: row highlights recomputed the whole filtered/sorted file set, making row construction quadratic. Visible items, inspected item and selection totals are now resolved once per render and passed into rows/footer. The All types filter also avoids needless extension parsing.

## Evidence

| Check | Result |
|---|---|
| Debug build | Passed; existing Security deprecation and sandbox SwiftPM-cache warnings only |
| Safety fixtures | Passed (`safetycheck.log`) |
| Reliability fixtures | 107 assertions passed (`reliabilitycheck.log`) |
| Workspace fixtures | 57 assertions passed (`workspacecheck.log`) |
| Evidence/monitoring | Passed including actual disposable-folder FSEvents and injected write failure (`evidencecheck.log`); watcher requires execution outside the tool sandbox |
| Hash/copy | Eight bounded hash passes; two verified copies at 9 MiB physical footprint; cancellation/mid-read-change checks passed (`hashmemorycheck.log`) |
| Shared operation load | 72 requests, 12 completed, 36 interrupted, 24 bounded-overflow; 24.7 MiB sampled peak RSS; 33 ms largest main-actor gap (`loadcheck.log`) |
| Lifecycle | 62 assertions, zero failures (`lifecycle.log`): competing real child processes; lease release on exit; scan → selected results → guarded cleanup → actual restart → exact-byte recovery; collision refusal; corrupt/conflicting receipts; actual process exits at intent, move, outcome, recovery and completed-receipt boundaries |
| Retained scan results | 12 rounds of 12,000 results plus cancellation, with bounded physical footprint and responsive main actor; exact measurements in `lifecycle.log` |
| Native workspaces | Eight repeated scans/navigation cycles, **12,000 retained results each**, rendering actual Large Files and cleanup workspaces in a fixed 1024×680 offscreen NSHostingView. 7 MiB baseline, 33 MiB peak, 25 MiB final retained footprint; 277 ms longest measured main-actor pause; plateau passed (`native-workspaces.log`) |
| Whitespace | `git diff --check` passed |

The first lifecycle harness used Foundation `waitUntilExit` from a migrating concurrency worker and stalled after a child had exited. The harness now uses termination callbacks. Native testing initially timed out; samples identified repeated file-list/selection computation. A subsequent fixture also needed fixed host sizing and complete preloaded results to avoid misleading partial-buffer/auto-sizing behavior. The final native pass uses the corrected fixture and optimized production view. Native stress is offscreen component/workspace evidence, not a claim of overnight whole-app stability.

## Delivery and remaining boundaries

The signed local bundle is `dist/Cairn.app`; the predecessor is preserved under this folder's `previous/Cairn.app`. Signing and strict verification are performed locally; no notarization/upload occurs. Existing running processes continue using their prior executable until quit/reopen.

Still outside this pass: independent full-PRD signoff; overnight/full-machine energy and memory acceptance; real sleep/wake/notification delivery; physical external-drive disconnection/replacement; forced-power-loss durability; exhaustive specialist process-death and accessibility matrices. No immediate-reclaim adapter, automatic cleanup, managed relocation, updater or payment capability has been enabled by these reliability changes.
