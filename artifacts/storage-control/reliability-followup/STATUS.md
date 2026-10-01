# Reliability and action placement follow-up — 29 September 2026

Implemented: recovery JSON reads/encoding/conflict checks/writes now have one serialized actor owner. Versioned display snapshots prevent late responses replacing newer history. Concurrent appends merge against actor-owned state; conflicting recovery identities fail closed. All cleanup stores await recovery persistence, and restore/reconciliation preserve existing records and journal acknowledgement ordering.

Overview now puts Make room beside Scan in the top action group. History is a secondary link beside the chart. Check space is at the top of Make room. Overview leaves long observation gaps open, matching Changes. Native sample captures are in native-preview/. Existing brand and specialist screens preserved.

Validation: debug build, safety, reliability and workspace checks passed. Recovery fixtures include concurrent 6,000-record batches, 12,000-record reload and conflicting-ID refusal; maximum main-actor heartbeat gap during the history fixture was 12.6 ms. This is fixture evidence, not an overnight whole-app soak. Native default-size Overview and Make room images were inspected.

Incomplete checks: hash passes completed with bounded 11 MiB footprint, but copy fixture failed with ENOSPC (NSCocoaError 640 / POSIX 28). df then reported only 20 MiB available on the Data volume. The runner stopped before loadcheck; no heavy retry was attempted. The test's own defer blocks remove its disposable files. No personal cleanup was performed. Do not report the full suite as passing for this follow-up.

Independent Astra review has not occurred; this implementation/self-review is not independent assurance. New permanent reclaim remains disabled pending that review and explicit scope approval. Managed relocation, selective cleanup rules, update/payment integration and remaining PRD runtime/accessibility/hardware gates are still open. Main Cairn bundle/process unchanged; only isolated sample preview updated. No commit or release.
