# Unfinished feature follow-up — 1 October 2026

## Built

- Opt-in inspection suggestions for measured growth in individually selected
  known locations. The user sets a 1–20 GB threshold. The engine requires two
  compatible, complete readings from the same volume and hides suggestions
  after seven days. Suggestions are visible in Overview and Changes and route
  to inspection only. Downloads is selectable but off by default; Codex state
  cannot become a cleanup rule.
- Background location monitoring can run for selected suggestion locations
  without requiring reserve alerts. The existing memory, thermal, low-space,
  scan-priority, pause and quiet-window limits still apply. This mode observes
  only selected roots; manual Measure locations remains broader and explicit.
- External export now rejects duplicate mounted drive UUIDs at preflight and
  after copying or rechecking. Storage explains eligibility for each drive.
  The export still retains the source and credits no reclaimed internal space.
- Storage has a user-triggered, read-only npm cache-path inspection. It shows
  the effective value in Cairn's environment and the selected drive's
  eligibility, without reading out npm credentials or changing configuration.
  Other shells, projects and flags may have different effective paths.

## Validated locally

- Debug build passed.
- Workspace fixtures passed, including threshold, selection, stale, partial,
  replacement-volume, duplicate-drive and npm-path parsing cases.
- Reliability fixtures passed for protected work, interrupted export, receipts,
  recovery, bounded memory and unbundled notification startup.
- Evidence fixtures passed, including a disposable FSEvents write. The first
  sandboxed run could not start macOS FSEvents; the permitted native run passed.
- A local Developer ID signed bundle was staged at `stage/Cairn.app`. Its
  signature and designated requirement passed native verification, and its
  packaged executable passed the workspace fixture check. This is not a
  notarized release. The existing `dist/Cairn.app` was running during the
  update, so it was left untouched; no second GUI instance was launched.

## Still open

- No configured npm/Xcode/Docker relocation adapter, source-removal step or
  unattended cleanup. The npm writer/startup contract and rollback behaviour
  remain unproven, so suggestions cannot be promoted to actions by a toggle.
- No real external-drive unplug/reconnect matrix, prolonged overnight energy
  run, native visual/accessibility acceptance, independent release audit,
  notarized public release or App Store commerce certification in this batch.
- No personal files were deleted, moved, exported or reconfigured, and no
  real external drive was written during validation.
