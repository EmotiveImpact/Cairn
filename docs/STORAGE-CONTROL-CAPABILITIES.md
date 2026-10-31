# Cairn active capabilities and implementation ledger

29 October 2026 source reconciliation. This map describes source routes, not release certification.
See [the current handoff](ROADMAP-CLAUDE.md) for outstanding gates.
The milestone evidence and dated addenda below are historical; they do not certify later changes.
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
| Storage | StorageTransferStore; drive metadata, user-selected export | Encrypted local APFS eligibility, UUID/duplicate-identity and directory checks, bounded content copy/hash; original retained; export history; no configured relocation |
| Activity & Recovery | Removal log and ActionJournal | Put Back uses no-overwrite restore; uncertain actions block cleanup until explicit manual review; no replay |
| Menu | Same native stores and volume-aware capacity history | Routes to window/review; no quick-delete action |
| CLI clean | Preview-only; --yes and -y rejected before scanning | Exact-item review in the native app is required; no CLI mutation route |
| Old autoClean / SmartTriggers | Compatibility declarations only | Inert, regardless of persisted clean-on-quit preference; no observers or collectors remain |
| Reserve monitoring | Explicit opt-in; default off | Alert/observation only. No link to autoClean or SmartTriggers |
| Cleaning rules (Settings › Rules) | RuleRunner, every 30 minutes while the app is open; only rules the person approved after seeing a measured preview; fresh gather per run under ScanGate | Fixed list of six kinds; items must pass AgentCleanup.eligible; per-run byte cap; ScanStore.clean with the same guards, journal and receipt (run kind "Rule · …"); pause and off stop it at once. Not connected to the old autoClean or SmartTriggers |
| Projects sleep | Explicit "Put to sleep"; git status read with `--no-optional-locks` | Selection → ReviewSheet → ScanStore.clean; a note in sleeping-projects.json records cleared folders and a wake-up command that Cairn never runs |
| AI Models | LocalModels reads manifests and folder sizes on opening the page | Read-only list; Trash for a single confirmed model inside a known store, through SafePaths.evaluate; Ollama only via a copied `ollama rm` command |
| Disk map | DiskMap on request: APFS volume counters plus bounded walks, two-minute limit | Read-only |
| Growth suggestions | Explicit opt-in, selected known folders and threshold; recent comparable location readings | Inspect-only suggestions in Overview and Changes. No cleanup permission or unattended executor route |
| Fast-drop alert (31 Oct) | Explicit opt-in, default off. FastDropPolicy reads the five-minute capacity checks: 5 GB or more gone within 30 minutes, or 2 GB or more with the reserve under two hours away at that rate; one alert an hour. Then swap (`vm.swapusage`), local snapshot count (`tmutil listlocalsnapshots /`) and one bounded walk of each watched root (30 s total, 8 s per root, cheap roots first) under `ScanGate.tryAcquireForMonitoring` | Notification plus a Changes card naming what grew, each over its own dated interval; never summed into a residual. No cleanup permission; swap and snapshots are never candidates. "Went somewhere Cairn doesn't watch" only when every watched root was compared; roots with no earlier reading or not finished in time are listed. Keeps watched roots measured through the folder watcher while on, even with folder watching off. Respects pause, quiet hours (report kept, notification skipped, and a quiet-hours check never uses up the next alert, and a fall already reported overnight is not sent again in the morning), memory/thermal/Low Power/low-space pauses |

Heavy traversals and data operations share ScanGate. The new location worker keeps its lease
until its detached traversal has stopped. Capacity metadata reads are cheap and coalesced.
Navigation does not launch a location traversal. The existing optional weekly scan is a
separate persisted setting and has not been turned on by this work.

## Action restrictions

- `.trash`: individually reviewed, subject to all executor checks; affected size is not freed space.
- `.adviceOnly`: observation/guidance, never executable.
- `.emptyTrash`: routed to `Cleaner.deleteFromTrash`; permanent operation with executor checks. Runtime acceptance remains required.
- `.tool`: routed to `Cleaner.runTool`; supported commands remain subject to executor policy. An enum value or implemented route is not adapter certification.
- External export (`StorageTransfer`): verified copy with source retained and zero immediate reclaim.
  `StorageRelocation` separately implements moves and tool-location workflows. Its presence
  does not establish hardware acceptance; do not apply the export-only claim to all Storage actions.
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
32 candidate snapshots, 1,024 root readings (and at most 48 for any one root, so a quiet root
keeps its baseline), 90-day age retention, 128 KiB per encoded row. The watched catalogue has
16 disjoint roots (31 October: simulators, Ollama, Hugging Face, LM Studio, Docker, OrbStack,
Colima, `~/.claude`, Cursor worktrees and Conductor workspaces added, watch-only where
protected; Docker and OrbStack only with Full Disk Access).
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
| M4 | Shared action intents/outcomes, identity-bound recovery reconciliation, journaled restore, common capacity receipts; isolated npm verify spike | Permanent cleanup routes now exist in Cleaner; process-boundary crash fixtures now pass (see October 30 validation); production certification and receipt interaction matrix remain |
| M5 | Separate opt-in folder observation, bounded FSEvents mailbox, dirty-root coalescing/backoff, pressure/priority/pause/lifecycle guards, quiet hours and alert suppression | Live disposable event + scheduler fixtures pass; actual sleep/wake, notification-delivery and overnight energy tests remain |
| M6–M8 | Separate later milestones | Independent audit; release/commercial gates; physical SSD adapter testing |
| M9 suggest-only | Opt-in measured-growth inspection suggestions | Native visual/accessibility acceptance and prolonged monitoring; unattended execution remains a separate later gate |

1 October follow-up: the suggest-only phase of M9 now has an opt-in location
allowlist and growth threshold. With reserve alerts off, background observation
is limited to the selected locations. At that checkpoint no rule performed cleanup; the current Cleaning rules route above supersedes that restriction. External export
now rejects duplicate mounted volume identities, including on recheck. Storage
can inspect the npm cache path seen by Cairn but does not change its setting. This is
not the M8 configured relocation adapter; actual drive, sleep/wake and prolonged
energy testing remain outstanding. See
[unfinished-feature validation](../artifacts/unfinished-features-20261001/VALIDATION.md).

Passing a local fixture does not certify a public release or real personal cleanup.

Current detailed evidence and acceptance mapping: [implementation validation](../artifacts/storage-control/measurement/VALIDATION.md). These are implementation states, not assertions that every milestone exit gate is closed.

## Reliability addendum — 1 October 2026

New Clean/Make room, Apps, Duplicates and Health runs now have durable receipts shown in Activity after restart. Legacy recovery remains individual records. New builds acquire an exclusive lifetime lock before opening live state; existing legacy bundle instances are detected without stopping them. The Large Files per-row whole-list recomputation has been removed. Targeted actual-process interruption/recovery and offscreen native retained-results tests now pass; this supersedes the earlier missing durable-run-receipt and local copy/load follow-up gaps. Independent release assurance, prolonged real-machine/hardware tests and the production reclaim adapter remain open. See [current validation](../artifacts/reliability-completion-20261001/VALIDATION.md).


## Focused review and guided reclaim — 1 October 2026

Fixed receipt dangling-link handling, bounded receipt reads and conflicting diagnostic-mode lease bypass. Activity now guides individual Finder deletion with explicit no-recovery consequences and a same-volume capacity recheck; it does not execute permanent deletion. Local build/fixture checks and signed bundle completed. See `artifacts/review-followup-20261001/VALIDATION.md` for exact evidence and remaining visual, independent-review and reclaim-adapter gaps.
