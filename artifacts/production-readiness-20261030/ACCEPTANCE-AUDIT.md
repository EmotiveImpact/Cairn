# Production acceptance audit

30 October 2026. **Production readiness is not achieved.** This audit uses the
current source, the signed local candidate and its recorded diagnostics. A green
fixture is evidence for its tested contract, not certification of the whole app.
No destructive personal/hardware tests, installation or public release are inferred.

Requirements originate in [PRD §17](../../docs/CAIRN-STORAGE-CONTROL-PRD.md#17-acceptance-matrix).
Current artifact: [signed candidate](LOCAL-CANDIDATE.md). Results: [validation](VALIDATION.md).

| Gate | Evidence inspected | Remaining proof / implementation |
|---|---|---|
| A01 First launch/no history | Overview unavailable-state code; evidence-store initialization tests | Installed first launch with empty history and denied capacity; verify no fabricated trend/savings |
| A02 Compatible readings | EvidenceCheck exact-interval/allocated-delta and SQLite round-trip cases pass | Native real-evidence presentation and attribution review |
| A03 Partial/denied root | EvidenceCheck independent compatible subset; new FileScan missing/denied fixtures pass | Real permission-denied disk-map rendering; no whole-machine completeness claim |
| A04 Changed metric/scope/volume | EvidenceCheck changed exclusions, volume, recreated identity and missing-parent cases pass | Installed UI explanation across actual permission/drive changes |
| A05 Overlap/hard links/clones | PathDedupe parent/child regressions and planner hard-link test pass | APFS clone/snapshot matrix and visible uncertainty; sizes remain estimates |
| A06 30 GB target / 12 GB available | WorkspaceCheck asserts 18 GB shortfall and no unmeasured Trash/candidate credit | Full native review → execution → measured goal flow with disposable files |
| A07 Already met/impossible | EvidenceCheck met/impossible/stale goal cases pass | Native no-action/impossible presentation acceptance |
| A08 Changed reviewed source/scope | EvidenceCheck same-inode content change, selection substitution, expiry and exclusions cases pass | Permissions and identity changes through every live action surface |
| A09 Protected descendants | SafetyCheck protected system/app/conversation descendants and CLI refusal pass | Independent inventory/review of every mutation entry point |
| A10 Active owner/writer | Existing Cleaner/InUse enforcement; safety suite passes | Real active-writer/build races and supported tool version matrix |
| A11 Cancel/navigation/rescan | Actual ScanStore cancellation test, shared gate stress, disk-map queue/drain tests pass | Live rapid navigation and cancellation with retained selections across all workspaces |
| A12 Crash journal boundaries | LifecycleCheck process exits at intent/move/outcome/recovery/receipt boundaries; prior passes | Current signed candidate lifecycle suite passed all 12 rounds and process-boundary fixtures; specialist/hardware failure coverage remains bounded |
| A13 Honest capacity receipts | ReliabilityCheck mixed tool/Trash, missing readings, net decreases and estimates-vs-measurement pass | Inspect all native receipt/share surfaces with actual measured outcomes; capacity changes are observations |
| A14 Restore collision/full disk/missing item | Collision/replaced-object/history/preflight fixtures pass | Full-disk restore and live unavailable-item presentation |
| A15 Removed/replaced drive | Workspace/ Reliability export destination identity and interruption fixtures pass | Approved disposable physical-drive disconnect/replacement and mount-name reuse tests |
| A16 Copy/source mutation/corruption | ArchiveCopy cancellation, corruption, mutation and source-preservation cases pass | Physical-volume verification and supported-format matrix |
| A17 Event storm/dropped events | EvidenceCheck bounded scheduler, quiet window, backoff/restart and live disposable FSEvent pass | Sustained real event load and UI responsiveness across watcher restart |
| A18 Sleep/wake/notification denial | StorageControl observers inspected; alert gap/dedup/pause policy fixtures pass | Actual sleep/wake, notification-denied delivery and persisted-pause acceptance |
| A19 Low disk/history write failure | Evidence transaction failure, journal corruption and stopped receipt fixtures pass | Disposable near-full volume/VM, restore-space failure and prolonged degradation |
| A20 Retained-result memory | Current signed candidate passed load/hash-memory/12-round lifecycle/8-round native checks | Candidate peaks: load 26 MiB, native workspace 52 MiB; overnight/energy and personal-scale workloads remain unverified |
| A21 Accessibility/minimum size | Minimum-size native captures found/fixed hidden filenames and wrapped actions; long review fits | Keyboard, VoiceOver, Reduce Motion, larger text and remaining workspaces; captures alone are insufficient |
| A22 License unavailable | Deferred Keychain, injected locked/malformed storage and seven HTTP response cases pass | Full manager persistence/live activation integration and owner free/paid decision |
| A23 Interrupted app update | Package.swift and application sources inspected: no application updater present | Implement updater after dependency/hosting decisions; deferred install, interrupted update and verified restart/import tests |
| A24 Missing drive at tool startup | StorageRelocation/adapter boundary exists; fixture moves are separate from exports | Certify each advertised managed adapter on supported tool versions, including absent-drive startup; refuse unsupported adapters |

## Release and project gates outside the individual fixtures

- **Stable installed build:** signed arm64 candidate exists and passed core
  diagnostics. Copy to `/Applications/Cairn.app` awaits explicit authorization;
  AI-tool reconnection is a separate concrete configuration change.
- **Current build artifacts:** refreshed signed arm64 local.Wi820o passed safety,
  workspace, evidence and reliability checks. The same 169-input source manifest
  also built universal with no compiler warnings; lipo confirms both slices and
  Intel reliability passed under Rosetta. The universal executable is not a
  notarized/signed public bundle. See LOCAL-CANDIDATE.md and refresh evidence.
- **Public distribution:** no notarization, public download, update feed or
  published release is certified. Local signing does not satisfy these gates.
- **Commerce:** owner free-versus-paid decision requested, not received. No
  checkout/price/provider decision or payment has been inferred.
- **Apple Intelligence:** the paired macOS 14.5 machine cannot certify the
  supported-hardware/private-API disable/Undo workflow.
- **Independent review:** this agent's diagnostics are not the independent
  review requested by the handoff. No separate reviewer has been commissioned.
- **Preservation:** work remains uncommitted; no resets, blanket staging, app
  replacement, tool reconnection, personal cleanup or public publication performed.

## Candidate-specific longer checks

All four longer suites completed successfully from the immutable signed bundle:

- Load: 72 requests; 12 complete, 36 interrupted, 24 bounded-overflow. Sampled
  memory 13.2 MiB baseline / 26.0 MiB peak; largest main-actor gap 0.106 seconds.
- Hash/copy: hash-memory, verified-copy, cancellation and mid-read-change checks
  passed; both copy passes sampled 11 MiB footprint.
- Lifecycle: 12 rounds retained 12,000 findings; crash-boundary reconciliation
  passed. Sampled peak 30 MiB; largest heartbeat gap 0.278 seconds.
- Native workspace: eight rounds retained 12,000 findings; sampled baseline
  42 MiB / peak 52 MiB; largest heartbeat gap 0.320 seconds; plateau gate passed.

Evidence: candidate-soak-logs.tgz. These are bounded disposable workloads, not
overnight measurements, physical-drive tests or universal release certification.
The signed candidate source and binary hashes remain unchanged.
