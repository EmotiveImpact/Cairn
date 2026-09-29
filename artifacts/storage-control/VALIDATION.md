# Storage-control implementation checkpoint — 29 September 2026

The pre-existing native app and PRD were preserved in local baseline commit `ae9d050`. This checkpoint adds a first integrated storage-control journey to that app. It is **not a public-release certification**. The currently running main `dist/Cairn.app` was not replaced or relaunched by this work.

## Implemented

- A versioned, bounded, local store records important-usage available capacity by internal-volume UUID, plus complete/partial cleanup-candidate categories after finished scans. It does not infer the writing app or sum candidates into total occupied capacity. Existing unscoped daily history remains intact and is presented separately.
- Overview uses the new capacity chart and compatible category changes. A dedicated Changes route has dated readings, a gap-aware plot and links back to specialist screens. The menu uses volume-aware capacity history and offers Changes, Make room and alert controls.
- Make room accepts a final available-space target, calculates its measured shortfall, and offers only individually reviewed, recoverable Trash candidates from a completed internal scan. It credits no immediate free space for Trash. Review reuses the existing confirmation and executor; the target is met only by a new capacity observation.
- Trash execution now checks the scanned device/inode before acting on a path. A shared bounded action journal persists per-item intent and outcome across general cleanup, duplicates, apps and health. An interrupted action is surfaced in Activity and blocks further cleanup; it is never replayed automatically.
- App-bundle and fixable health actions also retain a resolved-path/device/inode snapshot from discovery and refuse a replaced source at execution. The app-removal screen now correctly asks the user to close running apps. New local history files use private file and directory permissions.
- Activity now offers a manual review sheet for an interrupted action. Two explicit location checks precede acknowledgement; the journal keeps the outcome marked unknown and never replays the action. A failed acknowledgement leaves the safety block in place.
- Journal compaction preserves reviewed uncertain entries. If the bounded record fills with them, cleanup stops rather than silently discarding their evidence.
- Make room now filters ineligible results before its display cap and ranks equal-capability options deterministically. A fixture places a valid candidate after 120 larger blocked findings.
- Optional reserve alerts are off by default, can be paused, poll available capacity at most roughly every five minutes while Cairn runs, require two low readings and use hysteresis. They remove nothing.
- `AGENTS.md` records the requested test cadence: complete a coherent change, then run its build and suites together. The baseline commit contains this instruction.

## Checks actually run

| Check | Result | Evidence |
|---|---|---|
| Debug SwiftPM build after the source-identity and private-record changes | Pass; cache-access and existing deprecated Security API warnings | `checks/debug-build.txt` |
| Safety fixtures | Pass | `checks/safetycheck.txt` |
| Reliability fixtures, including journal interruption/corruption, replacement-inode refusal and private record permissions | 0 failures | `checks/reliabilitycheck.txt` |
| Workspace fixtures, including volume/scope/partial changes, goal arithmetic and reserve-alert hysteresis | 0 failures | `checks/workspacecheck.txt` |
| Hash/copy footprint and cancellation | Pass; 6 MiB peak footprint growth in this isolated fixture | `checks/hashmemorycheck.txt` |
| 72-request synthetic scan load | 0 failures; 24.7 MiB sampled RSS peak; 32 ms maximum heartbeat gap | `checks/loadcheck.txt` |
| Native sample-only workspace capture | 16 routes captured at 1120 × 740; Overview, Changes and Make room visually inspected at 1024 × 680 through the UI | `native-preview/` |

The default-size captures show the full graph and its endpoints. At 1024 × 680 the graph and plan controls remained visible; lower supporting content scrolls. Preview selectors and removal actions were disabled. The 1024 × 680 inspection was not saved as a standalone image. No real deletion, relocation, external-drive write, tool-configuration change, service stop, payment, publication or release packaging was performed.

One isolated QA launch initially started without `--preview-ui` because the desktop launcher did not forward the intended command arguments. It displayed current capacity and loaded Cairn's saved snapshot, and may have updated Cairn's ordinary capacity-history files. It showed no active scan and was promptly quit. The subsequent isolated bundle used a forced `--preview-ui` wrapper; the captured screens are labelled sample-only and took no disk actions. The main app was left running on its existing build.

## Remaining gates, not claims of completion

- M1 is partial: the bounded JSON prototype has no SQLite migration, injectable clock/probe/volume identity, root-level measurements or hard-link/clone accounting. It preserves rather than imports the legacy history.
- M2 has real native captures and minimum-size visual inspection for Overview, Changes and Make room, but the new interrupted-action sheet was only compiled and fixture-tested, not visually inspected. VoiceOver, Reduce Motion and long-name matrices remain. The specialist screens keep their existing style and behaviour.
- M3 is a review-only goal journey. It has no validated immediate-reclaim adapter and cannot promise to achieve an unmet target by moving files to Trash or copying to an SSD. Typed per-action capabilities and full plan snapshot/version contracts remain to be completed.
- M4 has a common durable intent/outcome record, app/health source-replacement checks and an in-app manual acknowledgement of uncertain actions. Acknowledgement records no verified filesystem outcome and does not recreate a missing Put Back record. Live writer races, journal crash boundaries, investigation of a missing Trash path and real mutation/restore flows need further fixture and controlled-environment testing. The existing removal log remains the Put Back source.
- M5 is capacity polling and alert suppression only. Bounded FSEvents dirty-root observation, event-drop reconciliation, sleep/wake and notification-denial tests remain. No unattended cleanup is armed.
- Physical SSD disconnect/replacement, low-space failures, public signing/notarization, updates, payment and long-duration memory behaviour were not validated. M6 independent Astra review is required before any public release claim.

The intended next review is to inspect this exact diff and the evidence above against `docs/CAIRN-STORAGE-CONTROL-PRD.md`, prioritizing interrupted actions, honest receipts, real scan/candidate compatibility and the main app's memory footprint with retained results.
