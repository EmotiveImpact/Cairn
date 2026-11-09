# Scheduled rule consent and cancellation hardening

Date: 2026-11-09. Base: `2c75709` (`master` integration baseline).

## Implemented

- Each approved rule carries a SettingsSeal HMAC over versioned policy, kind, schedule, age, cap, approval/pause state, unique consent ID and last-run timestamp. Legacy, missing, forged, duplicate or out-of-range records fail closed. Saving receipts does not blindly reseal invalid approvals.
- Scope edits revoke approval and require a fresh matching preview and explicit approval. Preview generations prevent an old asynchronous result from enabling a newer scope. Failed measurements do not become empty successful previews.
- Runs capture immutable consent, revalidate persisted settings after preview and at executor admission, and check again between items and immediately before the filesystem move. Pause/off/scope edits revoke the shared run token. Later reapproval cannot revive that token.
- Scheduled rules are narrowed to Trash-only file actions. No tool commands or permanent tree deletions are authorized by this policy version. UI explains that Trash does not free immediate space. An atomic move already admitted can finish; its outcome and recovery record are retained. Cancellation is not rollback.
- Bounds avoid arithmetic overflow from malformed age/cap/size settings. Normal manual cleanup is unchanged.

## Added regression coverage (not executed here)

`CleaningRuleCheck.run`, invoked by `--workspacecheck`, uses a disposable preferences suite and generated temporary files, with injected seal verification and no production Keychain writes. Covers exact persistence, unsealed/forged settings, changed category/schedule/age/cap, pause/off, replacement approval, tampered last-run state, duplicate records, extreme caps, fresh valid approval during preview, permanent run-token revocation, timestamp serialization, refusal at Cleaner entry and revocation between admission and the final move.

## Verification actually performed

- Read AGENTS.md, CONTRIBUTING.md, storage capability ledger, implementation handoff and PRD safety requirements. No local `.agents/skills` directories were present in this checkout/workspace.
- Reviewed full diff and call sites, including isolated existing Cleaner fixture closures.
- `git diff --check`: passed.
- Focused source-boundary assertions: passed (recorded in task output). These are static wiring checks, not Swift tests.
- `command -v swift`: unavailable. This Linux workspace cannot compile or run the native macOS app.

## Outstanding release gates

Required on macOS after combining branches: `swift build -c debug`, `--workspacecheck`, `--safetycheck`, and `--lifecyclecheck`; inspect Rules UI preview/edit/pause/off interactions. Actual HMAC/Keychain behavior is reused from SettingsSeal and must be verified in the native integration environment. The injected verifier fixtures test policy binding, not Keychain security. The follow-up below closes whole-preferences replay after successful protected-state persistence. A compromised signing key/Keychain remains outside this settings-integrity guarantee.

No personal cleanup, real Trash writes, deployment, push, PR or merge was performed. All new runtime fixtures are pending macOS execution.

## Follow-up: protected revocation and task cancellation

- Added one Keychain latest-seal head per rule, outside UserDefaults. Successful off/scope changes persist a random tombstone. Approval, pause/resume and scheduling receipts write/read-back their latest seal before updating preferences. Old signed blobs no longer match after restart, and pre-head approvals require new consent.
- Keychain reads are not cached. Missing/unreadable heads fail closed. Failed seal/head writes or failed read-back latch the affected rule off for the process, cancel its active run, and show a persistent retry-required warning plus an explicit retry-off control. Failures for different kinds remain tracked separately.
- **Storage-failure limit:** no implementation can claim durable revocation when its protected store refuses the write. The UI explicitly tells the person to keep Cairn open and retry before restarting; it does not claim off was durably saved. A successful retry tombstones the old approval. Restoring Keychain state itself or compromising it is not covered.
- Updates now reload current persisted authority and preserve current receipts. A stale row cannot pause/resume or reapprove a superseded grant. A stale off action revokes without overwriting current scope.
- Both RuleRunner and the entire ScanStore cleanup boundary use task-cancellation handlers to revoke the shared token. This covers cancellation while journal intent is awaited and while detached Cleaner validation runs. Begun intents still receive an outcome and final receipt; cancelled last-item runs are marked interrupted.
- Added injected protected-store fixtures: missing state, successful restart/replay rejection (including restored serialized preferences), reapproval, pause, receipt replay, read/write/read-back failure and retry. No real Keychain writes.
- Added async lifecycle fixtures for Task.cancel at journal intent and during detached final validation. They use generated files, isolated journals, injected authority and a nonmutating move adapter. They have no sleeps, polling or semaphore waits. Existing suite/process timeout controls remain required for native I/O hangs.

Static diff/wiring checks passed again. All Swift compilation and runtime fixtures above remain **unexecuted** in this environment; run native `--workspacecheck` and `--lifecyclecheck` after integration, as well as the safety/build gates.

## Follow-up: responsive protected-state I/O

- RuleRunner initializes with inert rules, then loads verified state on a dedicated off-main serial queue. Complete consent transactions (fresh read, stale-snapshot check, HMAC seal, protected write/read-back and preferences persistence) and receipt merges run on that queue.
- Pause/off/scope edits revoke the active in-memory token before any queued I/O. They update display state immediately, with a visible saving/checking state; approvals and new runs wait for outstanding transactions. Revision-tagged callbacks cannot overwrite newer user changes. Per-kind persistence outcomes also have revisions so out-of-order delivery cannot hide a later failure.
- ScanStore admission and between-item authority checks now await fresh off-main verification. Only detached Cleaner uses the synchronous final authority check. No persistent authority cache was introduced; restart and mutation still revalidate against protected latest heads. Cancelled tokens short-circuit before reading protected storage.
- Added a bounded injected latency fixture to `--lifecyclecheck`: a fake protected-store read holds its lock for at most two seconds, while the main actor constructs RuleRunner and pauses an active token. It checks sub-500 ms cancellation responsiveness, refusal after the slow read completes, and preservation of the later pause over the delayed launch snapshot. Its event watchdog is three seconds and callback drain is bounded to one second; all spawned test tasks are drained. No real Keychain/settings writes.

Validation here: focused static call-boundary/revision assertions and `git diff --check` passed. Swift/macOS compilation, latency fixture execution and interactive UI responsiveness remain pending native CI. A stalled OS Keychain call can still delay the serialized state queue and cleanup completion; it no longer occupies the main actor or delays in-memory cancellation. Pending operations do not claim durable completion.

## Follow-up: termination while consent is not durable

- The application-level termination delegate now checks an in-memory rule quit state after the existing active-operation guard. Pending consent transactions and failed protected-state writes no longer silently allow ordinary Cmd-Q/menu quit.
- The warning defaults to Return to Cairn, explains that earlier approvals can run on restart if saving is abandoned, and offers an explicit Quit Without Saving risk decision. The alert works without a main window. That decision rechecks current filesystem-operation activity and cannot bypass the existing operation guard. Force quit, process kill and power loss are outside normal application termination control.
- Rules UI asks the person to keep Cairn open while state is being saved. The quit state remains guarded after failed persistence even when the queue is no longer busy; successful durable completion clears it.
- Extended the bounded injected lifecycle fixture with pause-then-quit while the fake read is stalled, successful-save clearance, and failed-off persistence after queue drain. Added pure policy assertions for ordinary pending/failed quit, explicit risk acceptance, and the active-operation override prohibition. The additional failure callback drain is bounded to one second.

Static termination-policy/wiring assertions and `git diff --check` passed here. Native compilation, fixture execution and actual Cmd-Q/modal interaction remain pending macOS validation. No personal cleanup, protected-state write, push, merge or release was performed for this follow-up.
