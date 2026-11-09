# Model-removal safety hardening — 9 November 2026

## Implemented

- Local model discovery captures the resolved path/device/inode. Conversion to a cleanup item refuses absent, stale or non-removable identities, including command-only Ollama models. The captured identity is retained through execution, rather than reread as a new authorization.
- The AI Models page uses the app's shared ScanStore, explicit Trash-only mode, normal gate, Cleaner checks, durable intent/outcome journal, receipt and Put Back history. Its success message requires one recorded recoverable result and no errors/interruption. A nil Trash destination or journal failure is not success. Trash earns zero immediate reclaimed space.
- Apple asset removal owns the shared cleanup gate through the response/timeout of the active request. Profile consent and cancellation are checked before each set, after lookup, after each retry delay, and immediately before the production XPC operation. Undo cancels and awaits the tracked removal before opening profile settings. Navigation cancels the tracked removal; the service retains its lease until it settles. Requests already accepted by macOS cannot be recalled.
- Added `ModelSafetyCheck` to `--reliabilitycheck`: disposable identity replacement before conversion and after review, nil destination, journal refusal, recorded Trash/Put Back/zero reclaim, injected consent revocation during retry, and cancellation/drain. It does not invoke the real asset service. Existing `--workspacecheck` now tests the non-mutating conversion rather than a direct Trash bypass.

## Checks actually performed

- Read AGENTS.md, CONTRIBUTING.md, capability ledger and implementation handoff. No repository `.agents` directory exists in this checkout.
- `git diff --check`: passed.
- Static call-site review: no `LocalModels.moveToTrash` calls remain; app passes shared ScanStore into the model page; asset-removal entry owns its gate; raw reset is private.
- `command -v swift`: no executable available in this Linux workspace. No Swift build or macOS diagnostic execution is claimed.

## Required native acceptance / remaining limits

Run the combined branch once on macOS with `swift build -c debug`, then `--workspacecheck`, `--reliabilitycheck`, `--safetycheck` and `--lifecyclecheck`. New fixtures must compile and pass before release. Inspect actual AI Models error/recovery UI and Apple Intelligence Undo/navigation with delayed replies on a supported test Mac. Real XPC acceptance, supported macOS versions, profile enforcement and actual model reclamation remain unverified. No real system service mutation, profile install, personal model removal, deployment, push or PR occurred here.

File identity validation inherits the shared executor's filesystem race and cross-volume recovery semantics; it is not an atomic filesystem transaction. Cancellation prevents subsequent service requests but cannot retract one macOS already accepted. A service timeout bounds the drain; macOS may continue processing the original request after timeout. This change is source hardening, not public-release certification.
