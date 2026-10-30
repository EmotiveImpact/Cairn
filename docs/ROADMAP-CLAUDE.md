# Cairn production-readiness roadmap

Updated 30 October 2026. Production readiness is incomplete. See the [requirement-by-requirement acceptance audit](../artifacts/production-readiness-20261030/ACCEPTANCE-AUDIT.md) for A01–A24 evidence and gaps. Continue the work
below without repeating completed fixes. Preserve personal data and existing work;
read AGENTS.md and the storage-control PRD/handoff first.

## Implemented

- Disk-map available-space proportions stay independent of overlapping category
  estimates; incomplete coverage leaves a gap. Removed unsupported attribution
  of capacity-minus-walk differences to System Data.

- Added contextual accessibility labels to Look Through selection/expansion,
  Apple Intelligence selection and review expansion; custom selection controls
  now expose selected/not-selected values. VoiceOver acceptance remains open.

- Minimum-size fixes preserve filenames beside the Large Files inspector and
  keep Home action labels readable; native before/after captures verified.
- Per-cleanup Smart / Delete now / Move to Trash choice, personal-deletion
  acknowledgement, exact-item review, actionable category rows and blocked-item guidance.
- Verified Trash destinations, truthful failed rollback reporting, mandatory
  identity checks for permanent Trash deletion.
- Serialized, journaled Trash deletion with durable recovery status and receipts;
  only successful entries are marked deleted.
- Separate file estimates from measured capacity changes. Trash-only operations
  earn no immediate reclaim credit. Preserve original scan dates and cached Ready totals.
- Preserve cancelled worker handles until drained; yield while applying scan
  results; avoid quadratic sibling-path deduplication.
- Packaging uses unique output directories, preserves previous builds on failure,
  and stops before notarization when signed entitlements cannot be inspected.
- Filesystem metadata/enumeration failures retain incomplete/permission flags;
  disk-map aggregation preserves zero-byte partial areas and unknown capacity.
- Disk mapping now uses the shared operation queue, supports Stop and worker
  drain, retains prior results on cancellation, and throttles stale-safe progress.
- Malformed licensing responses no longer fabricate revocation; seven in-memory
  HTTP cases pass. Price and trial are decided (see Owner decisions below).
- Put Back explains preflight refusals; replaced-object and no-overwrite fixtures pass.
- Failed Trash deletion persists stopped receipts and explains recovery preflight
  errors; Activity no longer lets a Checked badge hide failures.
- Regression fixtures now use 12,000 distinct files; overload tests remain separate.

## Verified

Native debug and universal optimized builds and safety, workspace, evidence, reliability and CLI-refusal
checks passed on the paired macOS 14.5 Mac. Packaging passed 16 disposable
success/failure cases on Linux and macOS. Load/hash-memory checks passed.
Twelve lifecycle rounds and eight native workspace rounds retained 12,000
results each; lifecycle crash/recovery checks passed. Native workspace sampled
peak was 44 MiB, maximum heartbeat gap 0.365 seconds. The native review-sheet
capture was inspected for clipping; this is not interaction/accessibility acceptance.
The universal optimized build emitted no warnings and contains both architectures.
Intel-slice reliability/safety checks passed under existing Rosetta. A disposable
bundle passed plist/resource checks and native preview rendering. The later
arm64 local candidate passed strict Developer ID signature checks and its full
diagnostic suites; notarization and installed-app acceptance remain open.
The refreshed local.Wi820o candidate includes accessibility and disk-map fixes
and passed core diagnostics; older candidate soak results remain separately identified. Detailed results: [validation log](../artifacts/production-readiness-20261030/VALIDATION.md).

## Remaining work

| Priority | Work | Completion evidence / constraint |
|---|---|---|
| 1 | Reconnect AI tools to the installed build | Done 30 October 2026 at the owner's request: the [signed local candidate](../artifacts/production-readiness-20261030/LOCAL-CANDIDATE.md) local.Wi820o was copied to `/Applications/Cairn.app` (nothing was there before); signature, hardened runtime, team FC88M2P4F9 and executable hash verified; not notarized, so Gatekeeper blocks a plain double-click. It predates the plain-wording and disk-map follow-up (PR #21). Remaining: changing AI tool settings needs concrete authorization; verify status through each connected client. |
| 2 | Reproduce weekly scan failure | `AppShell` loads the saved snapshot then checks enabled preference, idle phase, previous date and age greater than seven days. No snapshot intentionally means no automatic scan. Disposable saved-snapshot tests now pass for absent/fresh/exactly-seven-day/stale/disabled/suppressed/future states and busy-gate handoff. The hook reaches the real fixture scanner and respects Stop. Remaining: reproduce through the installed app launch and notification path; do not infer a root cause from these passing tests. |
| 3 | Run native acceptance and executor review | Build once after related edits; run the CI safety, workspace, evidence and CLI-refusal checks. Add focused failure fixtures as needed. Cover cancellation, restart, journal persistence failure, source swaps, protected descendants and no-overwrite recovery. Record exact commit and output. |
| 4 | Validate SSD moves separately from exports | Use an explicitly approved disposable drive/workload. Check identity replacement, unplug during copy/verification, interrupted source removal, restore collision and missing-drive tool startup. Export must retain source and earn zero immediate reclaim; move success must depend on verified outcome. No personal-file experiments. |
| 5 | Validate Apple Intelligence and cleaning rules | Supported Mac required. Obtain concrete authorization before system-setting changes or destructive tests. Test disable/Undo/restart, rule pause/off, byte caps, stale previews and executor refusal. Private API presence is not proof of supported behaviour. |
| 6 | Profile first scan and whole-disk sizing | Measure wall time and physical footprint by scanner with bounded fixtures and retained results. Include rapid cancel/navigation/rescan. Keep existing memory bounds and guards; do not loosen the 100,000-entry safety walk to improve throughput. |
| 7 | Native UI and accessibility acceptance | Compare real renders to approved mockups at default/minimum sizes; keyboard, VoiceOver and Reduce Motion. Preserve native UI and rounded blue stones. Replace website screenshots only with accepted captures. |
| 8 | Commercial and distribution work | Price, trial and provider are settled (see Owner decisions below). Update hosting is still open. Sparkle dependency approval has been requested and is pending. Prepare signing/notarization/update interruption and recovery tests; defer installation during operations. Payments and publishing need concrete authorization. |
| 9 | Remaining product scope | System Data explanation and arbitrary-drive disk map, larger text support, and removal of obsolete lifetime counters need scoped implementation/review. Do not migrate or erase historical data merely to hide old claims. |

## Owner decisions already made

Do not ask for these again.

- **Price:** Pro is £35.99, paid once (`static let price` in `Cairn/Licensing/Licensing.swift`; the amount charged also has to be set in Polar).
- **No trial of any kind.** The 14-day trial was removed on purpose.
- **Licence length:** lifetime for this major version, with a small fee for the next major version.
- **Provider:** Polar, at cairnmac.com.
- **Free version:** the scan, the big number, category totals and cleaning one item at a time ([SPEC §2](SPEC.md)). Pro adds one-click batch cleaning.
- **Words in the app:** plain British English for people who are not engineers. Avoid terms such as "capacity", "identity", "attributed" or "classification" in anything the app shows.

## Boundaries

Source fixes and bounded fixtures do not certify personal whole-disk workloads,
overnight energy/memory, sleep/wake, accessibility, external-drive unplug/recovery,
Apple Intelligence, live licensing or signed update delivery. macOS 14.5 cannot
validate Apple Intelligence's supported-hardware flow. No personal cleanup,
installed-app replacement, live payment or release has been performed.

Advice-only rows still need individual supported adapters. The mode picker does
not bypass executor protection for credentials, protected sessions, system data,
Docker volumes or irreplaceable chat databases. Existing app/owner routes should
be tested before introducing broader deletion paths.
