# Lifecycle validation completed

The original 12,000-result fixture emitted only two distinct paths. Current
PathDedupe correctly reduced these to two; the historical retained-result
expectation was invalid. It now creates 12,000 distinct disposable files.
An unpaced run then stopped at the bounded event buffer (3,250–3,450 retained),
and measured a 1.55-second main-actor gap. This was not a successful soak.

Production changes: PathDedupe indexes ancestor presence to avoid searching all
prior sibling findings on every admission. A 12,000-sibling regression completed
in 0.184 seconds on the paired Mac. ScanStore yields between groups of 32 result
applications and checks cancellation after each suspension.

The retained-result fixture now emits 100 results per 100 ms, independently of
the deliberate overload fixture. It retains the 12,000-result count, repetition,
memory and heartbeat gates. The current remote session is 47500, running in
/private/tmp/cairn-readiness.mzoBdc. Build and standard diagnostics precede the
lifecycle suite; native workspace tests and the review capture follow only on
success. Do not call this sequence passed before inspecting terminal output.

## Terminal results

The sequence completed with exit status 0. Native build and safety/workspace/
evidence/reliability passed. All 12 lifecycle rounds retained 12,000 results;
crash-boundary recovery fixtures passed. Soak baseline/peak sampled footprint
was 29/29 MiB, retained rounds 18–27 MiB, maximum heartbeat gap 0.229 seconds.
Eight native workspace rounds retained 12,000 results; baseline/peak 41/44 MiB,
maximum heartbeat gap 0.365 seconds, plateau gate passed.
The review capture was generated and inspected: controls and footer fit without
clipping at 1100×740. Preview disables interactions intentionally.

The subsequent Keychain-only rebuild passed in 19.39 seconds and reliability
checks again reported zero failures. No personal Keychain operation was executed
by the injected Security-status tests.
