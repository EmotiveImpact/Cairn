# Cairn active capabilities and implementation ledger

29 September 2026. This map describes active source routes, not release certification.
Baseline for this continuation: `aa5030d`; clean checkout, six local commits ahead of origin.
Read the [PRD](CAIRN-STORAGE-CONTROL-PRD.md) for requirements and the
[validation checkpoint](../artifacts/storage-control/VALIDATION.md) for prior evidence.

## Active route and action map

| Route / entry | Data and trigger | Mutation and recovery boundary |
|---|---|---|
| Overview / Changes | StorageControl; capacity metadata on activation, explicit scan or Measure locations for tree walks | Observation only; SQLite evidence store is separate from recovery records |
| Make room | Completed ScanStore findings and current volume capacity | Explicit selection → ReviewSheet → ScanStore.clean; same guards and journal as Clean; Trash earns zero immediate reclaim |
| Clean / General / Browsers / Developer / AI / Creative / Large Files | Shared ScanStore, explicit scans; results survive navigation | ScanStore.clean → Cleaner → SafePaths, source identity, running owner and exclusion checks; ActionJournal intent/outcome plus removal log |
| Duplicates | DuplicateStore; explicit scan, keeper choice and full hash verification | Reviewed removal; shared gate and ActionJournal; separate duplicate protections; removal callback into Put Back log |
| Apps | AppInventoryStore; explicit inventory | Reviewed bundle-only Trash; app must be closed, source snapshot must match; ActionJournal and removal callback |
| Health | HealthStore; explicit check | Only supported fixable findings; HealthFixer policy, identity, exclusions, ActionJournal and removal callback |
| Storage | StorageTransferStore; drive metadata, user-selected export | Encrypted local APFS eligibility, UUID and directory checks, bounded content copy/hash; original retained; export history; no configured relocation |
| Activity & Recovery | Removal log and ActionJournal | Put Back uses no-overwrite restore; uncertain actions block cleanup until explicit manual review; no replay |
| Menu | Same native stores and volume-aware capacity history | Routes to window/review; no quick-delete action |
| CLI clean | Preview-only; --yes and -y rejected before scanning | Exact-item review in the native app is required; no CLI mutation route |
| Old autoClean / SmartTriggers | Compatibility declarations only | Inert, regardless of persisted clean-on-quit preference; no observers or collectors remain |
| Reserve monitoring | Explicit opt-in; default off | Alert/observation only. No link to autoClean or SmartTriggers |

Heavy traversals and data operations share ScanGate. The new location worker keeps its lease
until its detached traversal has stopped. Capacity metadata reads are cheap and coalesced.
Navigation does not launch a location traversal. The existing optional weekly scan is a
separate persisted setting and has not been turned on by this work.

## Action restrictions

- `.trash`: individually reviewed, subject to all executor checks; affected size is not freed space.
- `.adviceOnly`: observation/guidance, never executable.
- `.emptyTrash`: disabled in Cleaner.
- `.tool`: all tool commands are disabled by Cleaner, pending individual validated adapters. A `.tool` enum value is not adapter certification.
- External export: verified content copy only, source retained. Not migration, synchronization,
  automatic backup or increased internal capacity.
- Known chat/session data, repositories/worktrees, credentials, databases, protected system
  storage and excluded descendants remain outside generic removal. Observing folder sizes
  never creates a cleanup candidate.

## Measurement persistence decision

Use macOS system SQLite through a small C module map, with no downloaded dependency.
The serialized actor owns SQL and JSON encoding/decoding; the UI owns only bounded snapshots.
Each append and retention pass is transactional. The v1 JSON import commits its marker with
its records, preserves the input file and can be retried after interruption. Earlier unscoped
daily history remains separate; no historical volume IDs are invented.

Limits: 16 MiB SQLite page budget, 512 KiB SQLite page cache, 2,300 capacity readings,
32 candidate snapshots, 1,024 root readings, 90-day age retention, 128 KiB per encoded row.
The measurement walker has a 100,000-entry/64-level/30-second budget and one descriptor per
active depth. It never reads file contents, follows symlinks/mounts, or intentionally hydrates
placeholders. Allocated sizes remain estimates in the presence of APFS clones/snapshots.

## Milestone ledger

| Milestone | Current state | Remaining exit evidence |
|---|---|---|
| M0 | Active entry points mapped; inert legacy automation; shared typed operation state in footer/menu; specialist navigation no longer starts scans | Independent cross-entry review |
| M1 | Bounded root observations, compatible subsets, SQLite/import/retention, injected clock/probe/failures | Fixture checks pass; real full-volume/energy soak still needed |
| M2 | Native root evidence, exact intervals, text history and common operation state; retained graphite/rounded-stone identity | 16 route captures; minimum-size checks; full VoiceOver/Reduce Motion matrix remains |
| M3 | Typed capabilities, immutable reviewed plan, source/scope/permission/age checks, met/impossible/stale states, zero Trash reclaim | Fixtures pass; controlled personal workflow needs independent review |
| M4 | Shared action intents/outcomes, identity-bound recovery reconciliation, journaled restore, common capacity receipts; isolated npm verify spike | No certified production reclaim adapter; actual kill-at-every-boundary and receipt interaction matrix remain |
| M5 | Separate opt-in folder observation, bounded FSEvents mailbox, dirty-root coalescing/backoff, pressure/priority/pause/lifecycle guards, quiet hours and alert suppression | Live disposable event + scheduler fixtures pass; actual sleep/wake, notification-delivery and overnight energy tests remain |
| M6–M9 | Separate later milestones | Independent Astra audit; release/commercial gates; physical SSD adapter testing; explicit rules consent |

Passing a local fixture does not certify a public release or real personal cleanup.

Current detailed evidence and acceptance mapping: [implementation validation](../artifacts/storage-control/measurement/VALIDATION.md). These are implementation states, not assertions that every milestone exit gate is closed.

## Reliability addendum — 1 October 2026

New Clean/Make room, Apps, Duplicates and Health runs now have durable receipts shown in Activity after restart. Legacy recovery remains individual records. New builds acquire an exclusive lifetime lock before opening live state; existing legacy bundle instances are detected without stopping them. The Large Files per-row whole-list recomputation has been removed. Targeted actual-process interruption/recovery and offscreen native retained-results tests now pass; this supersedes the earlier missing durable-run-receipt and local copy/load follow-up gaps. Independent release assurance, prolonged real-machine/hardware tests and the production reclaim adapter remain open. See [current validation](../artifacts/reliability-completion-20261001/VALIDATION.md).


## Focused review and guided reclaim — 1 October 2026

Fixed receipt dangling-link handling, bounded receipt reads and conflicting diagnostic-mode lease bypass. Activity now guides individual Finder deletion with explicit no-recovery consequences and a same-volume capacity recheck; it does not execute permanent deletion. Local build/fixture checks and signed bundle completed. See `artifacts/review-followup-20261001/VALIDATION.md` for exact evidence and remaining visual, independent-review and reclaim-adapter gaps.
