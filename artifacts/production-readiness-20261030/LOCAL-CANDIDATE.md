# Verified local test candidate

30 October 2026. Local acceptance build, **not notarized or publicly released**.

## Latest candidate (includes accessibility and disk-map fixes)

Mac path: `/private/tmp/cairn-readiness.mzoBdc/dist/local.Wi820o/Cairn.app`.

- arm64 optimized build; actual build_local.sh completed in 111.63 seconds.
- Strict Developer ID signature verification passed; hardened runtime enabled,
  team FC88M2P4F9, empty entitlements; no compiler warnings.
- Executable SHA-256: `e2e016efa931be0836cfb5f54c7852095c13ca54495ce4c11bcf93d785fc337b`.
- All 169 inputs matched candidate-refresh-manifest.json before compilation.
  Manifest SHA-256: `6fb5c065c489c21439ec5dfb71e6c17c1d0bd21f0ef6fb79f8da4945dc258a6f`.
- Safety, workspace, evidence and reliability passed from this exact signed app.
  Evidence: refresh-evidence.tgz. The previous candidate's soak results below
  are separate evidence, not soak runs of this newer binary.
- The same source also compiled universal without compiler warnings; both slices
  were confirmed and Intel reliability passed under Rosetta. Evidence:
  refresh-universal-evidence.tgz. This signed bundle itself is arm64.
- This is a local build, not notarized, installed or publicly released.
  Installation authorization is still pending. Recheck destination before any
  authorized copy; preserve all existing candidates and installations.

## Earlier candidate — retained unchanged

`/private/tmp/cairn-readiness.mzoBdc/dist/local.A6zVGG/Cairn.app`

- arm64 optimized build, macOS 14 minimum; version 1.0.0 (1).
- Developer ID signature verified; team FC88M2P4F9, hardened runtime enabled,
  no additional entitlements. Existing apps were not replaced.
- Executable SHA-256: `fbcb75964d4c3a0830856c0415bff46488ac5bb35b6e020ac3185b8e479bf516`.
- Base commit: `860163f1fee95fde6c31cc3e10d1354d4c4bdfd3`, plus the current
  uncommitted worktree. Do not describe this as the committed master build.
- All 169 input files matched candidate-final-source-manifest.json before build.
  Manifest SHA-256: `5fdd687859fbb03c6061df4f3f0a2350b67b697da13e6028b26b5f0e0ddedca0`.

## Verification

Actual build_local.sh completed, including signing and strict signature validation.
Final optimized compilation took 98.51 seconds and emitted no warnings. Fixed a
Swift 6 captured-weak-variable warning from the preceding candidate; immutable
actor-isolated store capture retains the existing cancellation/generation checks.
Safety, workspace, evidence and reliability diagnostics all passed from this
exact signed bundle. Evidence archive: candidate-verification.tgz.

The same signed bundle also passed load, hash-memory/copy, 12-round lifecycle
and eight-round native workspace suites. Native sampled peak was 52 MiB and
maximum heartbeat gap 0.320 seconds. These bounded disposable tests are not an
overnight/hardware certification. Evidence: candidate-soak-logs.tgz.

## Proposed next action

Copy this verified bundle into `/Applications/Cairn.app`, provided that location
is still absent, then reverify its signature and executable hash. Retain the
source candidate. Do not overwrite an existing installation if one appears in
the meantime. No automatic launch, scan, cleanup or AI configuration rewrite is
part of this installation proposal. User authorization is pending.

Read-only check found no `/Applications/Cairn.app` and no running Cairn app process.
The source candidate lives in a temporary directory, so installation into a
stable location is necessary before treating any AI-tool pointer as durable.
Tool reconnection, installed-app permission/launch acceptance, live licensing,
physical-drive tests, Apple Intelligence, notarization and public distribution
remain separate unfinished gates. Earlier universal checks predate recent edits;
this signed candidate is arm64 only.

## Later source changes

The accessibility-label changes made after this candidate was built are not in
`local.A6zVGG/Cairn.app`. That immutable bundle remains the exact candidate tested
above; refresh the local candidate before treating it as the latest source.

The subsequent disk-map proportion/attribution fixes also postdate this candidate.
