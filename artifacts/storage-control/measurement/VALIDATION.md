# M0–M5 implementation and review handoff

**Later follow-up:** [recovery I/O and action placement](../reliability-followup/STATUS.md) moves recovery persistence off the main actor. Its final copy/load checks are blocked by critically low disk space; do not carry forward the earlier all-pass claim.

29 September 2026. Baseline `aa5030d` on `master`; this continuation is uncommitted.
This report supersedes the earlier checkpoint's implementation-gap list, not its historical
measurements. It records an initial implementation pass; milestone exit gates and public release
are **not all complete**. No independent Astra audit has happened.

## Built

- Metadata-only observations of six known roots, independently comparable by identity, volume,
  scope, coverage and interval. No file-content attribution. Hard links deduplicated per root;
  overlapping scopes removed; symlinks, mount boundaries and cloud placeholders do not expand
  the walk. Partial, denied, missing-parent, replaced and cancelled evidence is not false zero.
  Bounds: 100,000 entries, depth 64, 30 seconds across one scheduled batch.
- A system-SQLite actor serializes measurement I/O/encoding away from the UI, with transactional
  v1 import, retained original JSON, private permissions, bounded rows and page/cache budgets.
  Earlier daily history remains explicitly unscoped. No new package download.
- Native Changes shows location evidence, exact intervals, coverage and a text alternative to
  the chart. Overview highlights observed growth. Shared gate operation labels feed menu/footer.
  Opening Apps, Duplicates or Health no longer launches a traversal. Manual scans remain.
- Make room uses typed capabilities, deterministic candidates, a final-capacity target and an
  immutable reviewed scope. Settings/permissions, source identity/metadata, target, scan and
  expiry are rechecked. Met/impossible/stale states are explicit. Trash/export receive no
  immediate reclaim credit; no production permanent-reclaim adapter was enabled.
- Durable per-action outcomes include recovery metadata and link to Put Back only after its
  log saves. Missing recovery records can be reconstructed from known successful outcomes;
  completed restores reconcile without replay. Unknown actions remain a manual-review block.
  Restore checks recorded Trash identity and never overwrites the original. History is no
  longer silently pruned by an old retention setting. Specialist receipts now distinguish
  affected file estimates, recorded recoveries and timed same-volume capacity observations.
- Separate opt-in folder monitoring uses a bounded FSEvents mailbox, sixty-second coalescing,
  fifteen-minute minimum per root, capped failure backoff and full reconciliation on event gaps.
  It yields to user work, stops under pressure/low power/thermal/near-full conditions, and has
  pause/resume, quiet hours, sleep/wake/mount hooks and notification-denial text. Reserve alerts
  can use live observations even if history persistence fails. Legacy auto-clean remains inert.
- The [isolated npm spike](npm-spike/DECISION.md) demonstrates possible orphan reclamation and
  a healthy-cache zero-reclaim outcome. It does not certify a production adapter.

## Checks actually run

Environment: macOS 14.5 (23F79), arm64; Apple Swift 6.0.3. Logs in `checks/`.

| Check | Evidence/result |
|---|---|
| Debug build | `final-build.txt`, pass after final FSEvents/alert refinements; sandbox cache-access and pre-existing Security deprecation warnings |
| Safety fixtures | `safetycheck.txt`, pass |
| Reliability | `reliabilitycheck.txt`, 97 assertions, zero failures; includes lost Put Back callback, exact Trash identity, idempotent reconciliation, replaced Trash refusal and completed-restore history reconciliation |
| Workspace | `workspacecheck.txt`, zero failures; repeated only because final capacity-alert integration changed |
| Evidence | `evidencecheck.txt`, 50 assertions, zero failures; metadata/scope/plan/import/write-failure/event schedule plus live disposable FSEvents |
| Hash/copy | `hashmemorycheck.txt`, eight hash passes at 10 MiB footprint; two verified copies at 12/14 MiB; cancellation and mid-read changes checked |
| Shared-gate load | `loadcheck.txt`, 72 requests over 29.25s; 12 completed, 36 interrupted, 24 bounded overflow; peak sampled RSS 21.1 MiB, maximum main-actor heartbeat gap 31 ms |
| npm feasibility | `npm-spike/result.txt`, offline npm 10.9.8; 4,194,304 orphan bytes removed; referenced package and outside sentinel unchanged; second verify no further content reduction |
| Native UI | `native-preview/`, 16 routes captured at 1120×740; Overview, Changes and Make room inspected through native UI, including 1024×680 and expanded location evidence |
| Local bundle | Isolated sample preview ad-hoc signature verified; not notarized; main app bundle left unchanged |
| Whitespace | `git diff --check`, pass |

Live FSEvents startup is blocked inside this execution sandbox. The isolated temporary-directory
check passed outside it. No personal directory was used as a test fixture. The last two source
refinements affected only monitoring/alerts; the other checks were not wastefully repeated.

The latest Make room capture/inspection includes the simplified title/category rows and fixed
review footer. Chart endpoints are visible and lower content scrolls at minimum size. Accessibility
labels/text were inspected, but **not** a full spoken VoiceOver or Reduce Motion acceptance pass.
The isolated preview forces sample mode; its disabled mutation controls are deliberate. The
preview inspected visually precedes the final two non-visual monitoring refinements; final source
build/tests include them. The main running app was neither quit nor replaced.

## Acceptance coverage and remaining evidence

| IDs | Implemented/fixture evidence | Still required before certification |
|---|---|---|
| A01–A05 | Empty/partial/identity/scope/overlap measurement and planner fixtures; native evidence display | Real denied-folder and APFS clone/snapshot matrix; explicit attribution remains limited |
| A06–A08 | Correct shortfall, met/impossible/stale and reviewed-source/scope contracts | Controlled full review/execute journey; no promise that Trash meets the goal |
| A09–A11 | Existing protected-path/running-owner executors retained; gate/cancellation fixtures; navigation-trigger scans removed | Independent audit of every entry point and live-writer race boundaries |
| A12–A14 | Journal corruption/write failures, lost recovery callback, replaced Trash, no-overwrite and receipt arithmetic fixtures | Actual process termination at every mutation boundary; full-disk restore; all receipt dialogs in native UI |
| A15–A16 | Existing export interruption/collision/hash fixtures pass; original retained | Physical disconnect/replacement and real hardware matrix, separate M8 |
| A17–A19 | Bounded scheduler storm/backoff/gap tests; live temporary event; transactional failure injection | Actual sleep/wake/denied-notification delivery; prolonged near-full-disk and event storms |
| A20 | Current synthetic gate/hash/copy checks pass; existing buffer fix preserved | New whole-app sustained measurement + retained-results soak; old real-machine evidence is not a new run |
| A21 | Default/minimum native inspection and accessible text alternative | Complete keyboard/VoiceOver/Reduce Motion, long names, all dialog/receipt states |
| A22–A24 | Existing licensing/recovery boundaries preserved; no new updater or relocation adapter | M6 independent review, M7 release/commercial choices, M8 startup/drive adapter certification |

Important review limits: filesystem moves and JSON journals are not one atomic transaction;
source revalidation is not an atomic compare-and-Trash operation. Recovery-log encoding/saving
still uses the bounded existing main-actor path (up to 20 MiB), which needs a large-history latency
check and likely a later serialized persistence owner. Measurement DB has a 4,096-page budget
(16 MiB at the system default 4 KiB page size), with a bounded DELETE journal during transactions;
no WAL grows indefinitely. No forced power loss, physical full-volume test or overnight energy
measurement was performed. The metadata catalogue intentionally covers known roots only; it
cannot explain every byte of whole-disk growth or attribute writes to YouTube/a process.

No personal cleanup, SSD write, swap/update modification, tool-path change, service stop, install,
payment, updater integration, push, release or automatic cleanup occurred. Commits and public
signing/notarization were not part of this continuation.

## Next review

Review the complete working diff including untracked Swift/module-map files, starting with
LocationMeasurement, StorageEvidenceStore, SpacePlan, StorageControl/LocationMonitoring,
ActionJournal/ScanStore and the four action stores. Use this report alongside the PRD and
`docs/STORAGE-CONTROL-CAPABILITIES.md`. Run independent M6 assurance before enabling a
permanent reclaim route or presenting this build as public-release ready. The concrete permanent
operation decision is documented in `npm-spike/DECISION.md`; nothing has been enabled implicitly.
