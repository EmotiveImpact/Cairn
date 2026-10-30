# Production readiness checkpoint — 30 October 2026

## Built

Native debug build succeeded on paired Apple silicon Mac, macOS 14.5,
Swift 6.0.3, two build workers, in `/private/tmp/cairn-readiness.mzoBdc`.
Source archive included all current Cairn and Support working-tree changes.
This supersedes earlier notes saying the changes could not be compiled here.
It is a disposable executable build, not an installed or notarized release.

Activity permanent deletion now serializes through ScanGate, persists an action
intent before mutation and an outcome afterwards, requires recorded identity,
and durably records deleted status. Restart reconciliation links deletion
outcomes to the original recovery entry. UI only marks successful IDs deleted
and displays failure messages. Earlier Trash destination/rollback fixes and
per-item cleanup review changes are included in this build.

## Tested

- Native debug build: passed (62.64 seconds); existing Keychain deprecation warnings.
- Safety diagnostics: all passed, including new missing-destination and rollback-collision fixtures.
- Workspace diagnostics: zero failures.
- Evidence diagnostics: zero failures.
- Reliability diagnostics: zero failures, including deletion/restart reconciliation.
- CLI refusal script: passed both confirmed-cleanup refusal cases.
- Website interaction and storage-story builds: passed.
- Website interaction, documentation and storage-story checks: passed.
- npm locked dependency install: succeeded; audit reported zero vulnerabilities.
- `git diff --check`: passed.

Tests used disposable fixtures. No personal cleanup, installation, connection
rewriting, external-drive mutation, payment or publication was performed.

## Still unverified / unfinished

Production readiness is not complete. Remaining work includes broader executor
and receipt accounting audit, weekly auto-scan reproduction, scan performance,
SSD disconnect/recovery acceptance, Apple Intelligence on supported hardware,
native visual/accessibility acceptance, prolonged operation tests, commercial
choices, signing/notarization and updater delivery. The production-readiness
goal remains active. No public release is approved or certified by this pass.

## Accounting/freshness follow-up

Fixed mixed tool/Trash estimates, measured receipt totals, cached Ready totals,
and cleanup resetting scan freshness. Cancelled scans cannot overwrite the
completed snapshot. These are source-level fixes to freshness; the original
weekly-launch report still needs end-to-end reproduction.

Native rebuild passed in 16.59 seconds after correcting a compile-time leftover
reference to the removed `gains` variable. Safety, workspace, evidence,
reliability and CLI refusal checks all passed. New reliability cases exercise
mixed tool/Trash accounting, absent measurements, estimates exceeding measured
gains, net decreases across volumes and zero Trash-only reclaim credit.

Remaining accounting audit: Celebration's follow-up Trash emptying still adds
affected-byte estimates to its headline; rule summaries still use deletion
estimates; capacity changes must remain distinguishable from causally attributed
reclaim. These are open tasks, not covered by the current completion claim.

## Follow-up Trash receipts and rule summaries

Implemented: reviewed Trash emptying now creates and checkpoints a CleanupRun,
links action intents to that run, records successful deletion estimates separately
from before/after capacity readings, and persists the final receipt. Celebration
uses measured capacity gains for its headline, keeps affected-byte estimates for
remaining Trash, and displays operation failures. Rules use measured capacity
increase rather than describing deletion estimates as released space.

Native debug build passed in 31.39 seconds. Safety, workspace, evidence,
reliability and CLI refusal checks all passed. This validates the shared capacity
and recovery contracts through existing disposable diagnostics; full native UI
interaction and actual follow-up Trash execution still need dedicated acceptance.

Next packaging defect confirmed by source audit: build_local.sh and
build_release.sh remove dist/Cairn.app before the replacement is assembled and
verified. Preserve the previous bundle on failure and avoid replacing a running
executable. Do not execute signing/notarization as a way to test this fix.

## Packaging preservation

Both packaging scripts now allocate a unique output directory and leave old
bundles and archives untouched. An INCOMPLETE marker remains until all checks
succeed. Required icon/mark assets fail closed if absent. Release output no
longer promises compatibility with every Mac; it states macOS 14 or later.
README and CONTRIBUTING explain the new output locations. CI now runs the
packaging fixture script before building.

Reproduction: the original HEAD build_local.sh overwrote the fixture's previous
executable. Updated scripts passed 13 success/failure cases on Linux and paired
macOS: build, signing, signature verification, missing icon, notarization,
stapling and Gatekeeper failure paths. Bash syntax and git diff checks passed.
All external tools were disposable stubs. No real signing/notarization occurred.
Native Swift sources did not change in this packaging batch, so their already
passing diagnostic suites were not redundantly rerun.

## Cancellation and bounded workload evidence

Reproduced Stop followed by cancelAndWait returning before the actual ScanStore
producer exited: the new fixture failed on unfixed code (one reliability failure).
ScanStore and DuplicateStore now retain the cancelled task handle so a later
drain can await it. Handles are replaced when a new scan starts; the shared gate
continues to serialize workers. The focused reproduction uses the actual
ScanStore and a delayed disposable scanner, not a parallel implementation.

Fixed native build: passed in 5.48 seconds. Safety, workspace, evidence,
reliability and CLI refusal checks passed. Additional load suite: zero failures,
12.8 MiB baseline and 26.5 MiB sampled peak RSS, 104 heartbeats, largest main-actor
gap 0.100 seconds. Hash-memory, copy verification, cancellation and mid-read
change checks passed; two verified copy passes reported 6 MiB footprint.
These bounded fixtures do not certify overnight or personal whole-disk workloads.

## Sustained scan, native review and Keychain follow-up

Fixed quadratic sibling-path admission and main-actor starvation during result
application. Corrected the lifecycle fixture to create 12,000 distinct files
instead of repeatedly emitting two paths. The sustained fixture is paced; the
separate fast-producer test still asserts bounded overflow and incomplete status.

Native build and safety/workspace/evidence/reliability passed. All 12 lifecycle
rounds and crash-boundary recovery checks passed, with 29 MiB sampled peak and
0.229-second maximum heartbeat gap. Eight native workspace rounds retained
12,000 findings each, peaked at 44 MiB and passed the memory plateau gate; maximum
heartbeat gap was 0.365 seconds. These are bounded fixtures, not overnight results.

The native ReviewSheet screenshot was inspected at 1100×740: mode selector,
item rows and footer fit without clipping. It uses inert showcase data; live
interaction, minimum window sizing and accessibility remain unverified.

Replaced deprecated Keychain UI suppression with an LAContext whose
interactionNotAllowed is true. Rebuild passed in 19.39 seconds; reliability
regressions including injected locked/missing/malformed credentials passed.
Tests did not query personal credentials.

CI now runs reliability and lifecycle regressions in addition to the existing
checks, with two build workers and an eight-minute lifecycle timeout. The new
workflow configuration has not yet run on GitHub. No release was produced.
Logs: readiness-final-logs.tgz. Render: review.png.

Final diagnostic-warning cleanup: an initial incorrect removal of `try` failed
to compile and was corrected to explicit do/catch parsing. The final native
incremental build passed in 5.20 seconds with no emitted warnings; safety checks
passed. Logs remain parser-build.log and parser-safety.log in the isolated Mac
work directory. This was not a clean release build. Final git diff check passed.

## Weekly launch refresh investigation

Moved the existing launch decision into ScanStore.startWeeklyScanIfDue, called
by AppShell. The policy is unchanged: only idle, opted-in launches with a scan
strictly older than seven days refresh. Missing/future snapshots and the
--no-auto-scan flag suppress it. A stopped scan is not restarted by this hook.
Custom-history stores now use adjacent isolated snapshot/comparison paths,
preventing diagnostic snapshot loading from reading installed-app history.

Native build passed in 38.70 seconds. Reliability cases passed for absent, fresh,
exactly-seven-day, stale, disabled, command-suppressed and future timestamps.
The stale case queued behind an actual held ScanGate lease, reached the real
fixture scanner after release, refused duplicate starts, and drained on Stop.
Safety, workspace, evidence and both CLI refusal cases also passed.

This proves the shared launch policy and worker handoff using disposable saved
snapshots. It does not reproduce the original installed-app launch report or
certify notification delivery. The earlier snapshot-age bug is fixed separately;
no additional root cause is claimed. Logs: weekly-logs.tgz.

## Trash deletion failure receipts

Reproduced five regression failures on the preceding implementation: corrupt
and pending journals left both live and reloaded Trash deletion receipts without
the interrupted flag; corrupt recovery history refused deletion without a
user-facing explanation. Disposable files remained intact in all cases.

Fixed journal-intent/outcome/recovery-link aborts to mark the receipt stopped.
Recovery preflight and queued cancellation now explain why deletion did not
start. Activity prioritizes stopped/skipped/error states over the Checked badge,
and a receipt with issues cannot have the plain Cleanup finished title.

Native fixed build passed in 8.64 seconds. Reliability reported zero failures
(previously five); safety, workspace, evidence and two CLI refusal cases passed.
The fixture verifies persisted stopped state and zero deletion/reclaim. Actual
post-mutation disk failure injection remains outside this fixture's coverage.
Logs: trash-abort-logs.tgz, including before and after output.

## Restore refusal explanations and identity regression

Reproduced three silent restore refusals: already-restored records, unknown IDs,
and unreadable recovery history. ScanStore now reports these causes, as well as
busy/cancelled operations and deleted/no-Trash records. Executor identity checks
and no-overwrite restore behaviour are preserved. Added a real file-replacement
fixture: the recorded object is moved aside and a new object placed at its path;
restore is refused before invoking the executor and replacement bytes survive.

Before fix: reliability reported three failures. After fix: native build passed
in 5.84 seconds, reliability reported zero failures, and safety/workspace/
evidence/CLI-refusal checks passed. Logs: restore-logs.tgz. Disposable fixtures
only; live Finder/Trash interaction and full-disk recovery remain unverified.

## Release entitlement gate

Confirmed the packaging script ignored an entitlement-inspection failure and
continued to its success message/notarization route in a disposable reproduction.
The initial fixture accidentally failed signing instead of inspection; it was
corrected to target codesign -d before accepting the reproduction evidence.
The corrected fixture failed on the old script and passes with the fail-closed
inspection. All 16 success/failure cases passed on Linux and macOS, including
explicit no-notarization assertions for unreadable/unsafe entitlements and
missing hardened runtime. No real signing/notarization was run. Build scripts
now default to two workers, overridable with BUILD_JOBS. Bash syntax and diff
checks pass. Mac log: packaging-gates.log in the isolated build directory.

## Optimized production executable

First arm64 release build passed in 103.98 seconds with Swift 6.0.3 on macOS
14.5, two workers. The optimized executable passed reliability, safety,
workspace, evidence and both CLI-refusal cases. It exposed one deprecation in
InstanceLease's existing-app activation: activateIgnoringOtherApps is ineffective
on the minimum supported macOS 14. Removed that option, retaining normal
activation. The final optimized rebuild passed in 87.61 seconds with no compiler
warnings; reliability passed again. Other suites were not repeated for this
activation-option-only change. Logs: optimized-final-logs.tgz.

CI now includes optimized compilation and reliability checks, in addition to
debug and lifecycle coverage. That updated workflow has not run on GitHub yet.
This is an arm64 SwiftPM executable, not a universal, signed or notarized bundle.
No installed app was replaced and no public artifact was published.

## Universal build and disposable app bundle

`swift build -c release -j 2 --arch arm64 --arch x86_64` succeeded with no
warning/error diagnostics. `lipo -archs` confirmed x86_64 and arm64. The universal
executable passed native reliability checks. Rosetta was already installed;
explicit `arch -x86_64` runs passed reliability and safety diagnostics without
installing anything. This is translated Intel execution, not a physical Intel
Mac acceptance result.

Assembled a new disposable bundle at
/private/tmp/cairn-readiness.mzoBdc/bundle-check.pNywS3/Cairn.app using the universal
executable, source plist and resource copies. Plist lint passed; icon and mark
were byte-identical to their source files. Bundled inert review preview launched
and its real capture was inspected: Xcode/Docker/npm logos load from the bundle,
and text/controls/footer fit at 1100×740. Capture: review-bundled.png. No signing,
notarization, live launch, installed-app replacement or public release occurred.
This manual assembly does not certify the actual signing pipeline.

CI's optimized check now uses the universal build, verifies both slices with
lipo and runs reliability checks. The updated workflow is not yet executed on
GitHub. Logs: universal-logs.tgz. Final diff check passed.

## Minimum-window native UI

Added --capture-minimum (1024×658 content, allowing a 22-point title bar within
680-point minimum window height) and an inert --capture-review-stress sample.
Captured Developer, Activity, Large Files, Home and a 12-group personal-deletion
review. The review kept its acknowledgement, warning, Cancel and disabled sample
cleanup action visible; its long list scrolls within a bounded region.

Found two actual rendering defects: Large Files filenames had zero visible
width with the inspector open; Home's Rescan text wrapped mid-word. Large Files
now omits the redundant proportional meter while the inspector is open and
narrows its size/status columns. Home uses ViewThatFits to move actions into a
second row when needed. Before/after native captures show filenames restored
and complete button labels. Final native build passed in 14.69 seconds.

No executor code changed in this UI batch, so the full safety suites were not
rerun. New capture fixture still disables cleanup. Files: minimum-captures.tgz,
minimum-fixed-captures.tgz and extracted minimum/minimum-fixed directories.
Keyboard/VoiceOver/Reduce Motion and broader window-size interaction remain
unverified. Earlier universal release results predate these UI edits.

## Malformed licensing response

Found validate() converted missing/non-string/unknown status and non-JSON HTTP
success bodies into false. LicenseManager would then save granted=false, even
though the server had not actually revoked the key. The client now accepts only
Polar's documented granted/revoked/disabled values; malformed responses throw a
non-definitive error. The existing refresh catch retains offline-grace evaluation
without saving a fabricated revocation.

Contract source: https://polar.sh/docs/api-reference/customer-portal/license-keys/validate
Seven URLSession cases use a session-scoped in-memory URLProtocol: granted,
revoked, disabled, missing, unknown, wrong type and non-JSON. The old client failed
four cases; the fixed native build passed in 6.23 seconds with reliability zero
failures. No network request, payment or personal credential operation occurred.
This verifies the actual HTTP client response path; live activation/checkout and
a full manager/Keychain persistence integration remain unverified.
Logs: license-response-logs.tgz. Diff check passed.

A first-release free-versus-paid scope decision was requested from the owner.
No response was available at this checkpoint; purchases remain disabled and no
pricing or feature entitlement decision was inferred.

## Disk-map operation lifecycle

Reproduced DiskMapStore starting its reader while another operation held the
shared ScanGate (one failing reliability case). Mapping previously ran outside
the gate, offered no cancellation and sent progress to the singleton even when
another store initiated it. It now acquires a named disk-map lease, exposes Stop,
cancels and awaits its detached reader before releasing the gate, retains the
previous reading on cancellation, and rejects progress/results from stopped or
superseded requests. DiskMap.read checks cancellation between areas; recursive
FileScan.measure already checks it during walks. Existing ProgressThrottle now
limits UI progress delivery. Navigation still preserves the running map/results.

Injected-reader tests use no personal filesystem traversal. They verify waiting
behind a lease, starting after release, stopping while queued without invoking
the reader, cancellation reaching/draining the detached worker, preserving the
prior map, rejecting late updates and subsequent gate acquisition. Native build
and reliability/safety/workspace/evidence passed. Final throttle follow-up build
passed in 5.69 seconds; reliability passed again. No full suites repeated for
that progress-only follow-up. Logs: diskmap-final-logs.tgz. Diff check passed.
Actual whole-disk timing, live Stop interaction and arbitrary-drive map support
remain unverified/incomplete; these fixtures do not certify those paths.

## Incomplete filesystem measurements

Reproduced two failures: an absent root and a file beneath an unreadable parent
both appeared as complete zero-byte files. FileScan now records metadata and
enumeration errors as truncated observations, preserves permission gaps, and
does not increment fileCount for a root whose metadata was unavailable. Readable
siblings remain measurable. Nil enumerators also leave an incomplete flag.

DiskMap now distinguishes absent paths from failed lstat observations, retains
zero-byte partial areas, propagates failed child listing and Library measurement
flags to parents, and refuses a capacity reading whose free-space value is
missing instead of substituting zero. These map aggregation changes were source
reviewed; real denied-directory map rendering remains unverified.

Disposable missing-path and chmod-denied fixtures failed twice before the fix
and passed afterward. Permission changes were limited to the temporary fixture
and restored before cleanup. Native build passed in 6.61 seconds; reliability,
safety, workspace, evidence and both CLI refusal cases passed. Logs:
measurement-logs.tgz. Final diff check passed. No personal directory was scanned.

## Signed local acceptance candidate

Prepared and verified an actual local Developer ID build using build_local.sh.
All 169 source/resource inputs matched the current workspace manifest. First
candidate exposed a Swift 6 weak-capture warning in disk-map progress; changed
to immutable actor-isolated capture, rebuilt into a fresh directory, and retained
the preceding bundle. Final release compilation passed in 98.51 seconds with no
warnings. Strict signature verification passed, hardened runtime is enabled,
team identity matches FC88M2P4F9, and entitlements are empty. Safety, workspace,
evidence and reliability all passed from the signed app executable itself.

See LOCAL-CANDIDATE.md for exact Mac path, source and binary hashes and proposed
installation. No application was installed, no AI-tool path changed and no
notarization/public release occurred. Installation authorization is pending.
Evidence: candidate-verification.tgz. Final diff check passed.

## Candidate soak and requirement audit

Completed the PRD A01–A24 audit in ACCEPTANCE-AUDIT.md using current code,
diagnostic coverage and candidate evidence. Updater implementation is absent;
installed first-launch/permissions, accessibility, physical drives, live commerce,
Apple Intelligence and independent review are not certified. Installation and
free/paid scope decisions remain pending. The objective is not complete.

All longer checks passed from signed local.A6zVGG/Cairn.app: 72-job load suite
(26 MiB peak, 0.106-second max gap), hash/copy/cancellation/corruption checks,
12 lifecycle rounds (30 MiB peak, 0.278-second max gap) and crash boundaries,
and eight native workspace rounds (52 MiB peak, 0.320-second max gap, plateau
passed). Both retained-result suites kept 12,000 findings per round. Source and
binary hashes are unchanged. No installation or personal/hardware cleanup ran.
Evidence: candidate-soak-logs.tgz. Final diff check passed.

## Selection accessibility and refreshed universal build

Added contextual labels for Look Through selection and group expansion, Apple
Intelligence model selection, and review-group expansion. NightCheck exposes
selected/not-selected values; Look Through groups expose selected counts.
Debug compilation passed. An attempted in-process native preview tree inspection
returned only the hosting root, so it did not verify assistive navigation; the
unhelpful diagnostic was removed. Keyboard/VoiceOver acceptance remains open.

After the final edits, optimized universal compilation passed with no compiler
warnings. lipo confirms arm64 and x86_64. The universal executable passed native
reliability (zero failures) and Intel safety under Rosetta (all passed).
Evidence: accessibility-final-evidence.tgz. The previously signed immutable
local.A6zVGG candidate predates these accessibility changes and was not replaced.
No installation, system setting change or public release occurred. Diff check passed.

## Disk-map capacity proportions and unsupported residual attribution

Reproduced the prior arithmetic: total 100, available 20, category estimates 120
produced a 14.3% available segment instead of 20%. The chart now preserves the
capacity fraction independently, scales category estimates to the remaining
space and leaves gaps for incomplete coverage. Removed minimum segment widths
that could overflow the bar. Removed the capacity-counter-minus-file-walk
remainder previously attributed to System Data without compatible evidence.
The native view explicitly distinguishes estimated categories and missing coverage.

Native debug build and reliability suite passed, including overlap, coverage-gap,
invalid-capacity and finite nested-proportion fixtures. Final sample/copy changes
were rebuilt with no warnings and rendered at 1024×658; explanation and bar fit.
The first capture command used incorrect section casing; corrected to diskMap
and reran only capture/export. Evidence: map-proportions-final-evidence.tgz and
map-final-render.tgz. Final diff check passed. No personal scan or cleanup ran.
These changes postdate both the immutable signed candidate and the most recent
universal release build; final release artifacts still need refreshing.

## Refreshed current-source local candidate and universal verification

All 169 inputs matched candidate-refresh-manifest.json. build_local.sh produced
immutable local.Wi820o in 111.63 seconds, with no compiler warnings. Strict
Developer ID signature verification passed, hardened runtime enabled, team
FC88M2P4F9 and empty entitlements. Safety/workspace/evidence/reliability all
passed from that exact signed binary. See LOCAL-CANDIDATE.md for hashes.

The same source compiled universal with no compiler warnings; lipo confirms
arm64 and x86_64. Intel reliability passed under Rosetta. Evidence:
refresh-evidence.tgz and refresh-universal-evidence.tgz. No build/test jobs remain
running. No installation, notarization or publication occurred. The older signed
candidate's soak evidence is not presented as a soak of this newer binary.

README cleanup descriptions now match measured receipts and executor limits.
Sparkle dependency approval has been requested; integration remains pending.
Installation and free/paid scope requests are also unanswered. The goal remains
incomplete, with hardware/interaction/independent review gates recorded in the
acceptance audit. Final diff check passed.

## Release-blocker revalidation

The previous goal turn made progress by producing the refreshed signed candidate
and verifying the same source for both architectures. Current audit confirms all
169 manifest inputs remain unchanged. Read-only Mac check confirms macOS 14.5
and no /Applications/Cairn.app installation. No build/test handle remains active.

Installation and commercial-scope decisions have remained unanswered across
multiple consecutive goal turns; updater dependency approval is also pending.
The prepared local candidate is reviewable, but the remaining release path needs
those decisions and authorized installed/hardware acceptance. Apple Intelligence
requires a supported Mac; current hardware/OS evidence does not satisfy it.
Independent review and public distribution remain open. The production objective
is blocked, not complete. Preserve the worktree and all candidate artifacts.

## Everyday workflow verification on refreshed signed candidate

Following the user's request to establish normal app behaviour before release
work, ran local.Wi820o's native and lifecycle diagnostics. Native Large Files and
Clean views completed eight rounds with 12,000 retained results, 42 MiB baseline,
59 MiB peak and a stable retained-memory plateau. Maximum main-actor heartbeat
was 1.451 seconds: below the existing two-second limit but a responsiveness
concern requiring attribution, not evidence of a fully smooth interface.

Lifecycle completed all twelve rounds and process-boundary recovery checks with
zero failures. Cancellation settled; shared receipts survived reload and did not
label active specialist operations as crashes. Evidence: everyday-workflows.tgz.
These are disposable automated store/render workflows, not physical clicks or
installed-app permission/AI-connection acceptance. No personal cleanup, install,
service changes or public release occurred. Both jobs completed.
