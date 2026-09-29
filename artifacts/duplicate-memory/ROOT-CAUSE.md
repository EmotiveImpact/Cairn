# Duplicate scan memory runaway — 29 September 2026

## Cause established by controlled reproduction

`DupHash.fingerprint` read file contents using `FileHandle.read(upToCount:)` in a long-running background task. Although each Swift `Data` variable left its loop scope, the bridged autoreleased read buffers survived until the worker's autorelease pool drained. The process accumulated file contents while computing hashes. This was not a growing list of duplicate findings.

The unchanged production reader was tested with one disposable 64 MiB file read repeatedly, retaining only one digest. Footprint rose 68 → 132 → 196 → 260 → 324 → 388 MiB; the diagnostic stopped the sixth pass at its growth ceiling. No SwiftUI views or result arrays participated. Evidence: `hash-before.txt`.

After placing both the read and hash update inside an autorelease pool per chunk, the same eight passes completed at a 10 MiB peak footprint (6 MiB growth). A known independently computed SHA-256 was checked. Two 64 MiB verified local fixture copies completed at 10–11 MiB footprint. Cancellation and a mid-read file mutation were rejected. Evidence: `hash-after.txt`, `hash-copy-final.txt`.

## Why earlier checks missed it

The 19-category scanner pipeline excludes the standalone duplicate finder. Earlier read-only and synthetic scan checks did not exercise this file-content hash reader. They also logged RSS, which excludes compressed memory and can decrease while pressure grows. The incident log showed duplicate scanning active, zero displayed duplicate groups, Smart Scan waiting at 0%, and falling RSS near the end. That history identifies the relevant operation; the controlled reproduction establishes the buffer-retention defect without requiring another real-machine overload.

## Changes

- Drain file-read buffers after every 1 MiB hash chunk, preserving full SHA-256 and before/after device/inode/size/mtime/ctime checks.
- Drain the same buffer pattern in the export copy loop; source/copy verification uses the corrected hasher too.
- Move duplicate enumeration's `nextObject()` into its per-entry pool.
- Bound retained duplicate candidates at 20,000, and examined entries at 300,000. Label limit-truncated comparisons as partial.
- Group by logical file length, the appropriate prerequisite for byte equality, rather than allocated disk blocks.
- Ignore progress/completion callbacks from cancelled or replaced duplicate runs; explain waiting for the shared disk-operation gate.
- Record physical footprint alongside RSS; footprint includes compressed memory charged to the task.

No offloading database or language rewrite was required to fix the reproduced cause.

## Actual native app validation

The fixed main app ran its actual stores and rendered workspaces against accessible internal files, with no cleanup operation:

- Duplicate scan completed in 108.25 seconds: 604 groups, no candidate/entry limit hit.
- Smart Scan completed in 65.45 seconds: 19/19 categories, 462 findings. Duplicate groups remained retained during this scan.
- Sampled footprint peaked at 65 MiB during scans; largest main-actor heartbeat gaps were 280 ms and 121 ms.
- Navigating back to Duplicates displayed the first 120 groups normally, with further groups paginated and no copies selected.
- A subsequent macOS `sample` reported 69.2M footprint, 72.2M process peak after result views were inspected. Evidence: `full-ui.txt`, `after-results.sample.txt`.

Build, strict local bundle signatures, 71 reliability assertions, 30 workspace assertions and 32 safety assertions passed. Fixtures check differing file middles, skipped symlinks, keeper preservation, no automatic duplicate selection, explicit comparison limits, recovery history and transfer failures. No personal file was deleted, moved or altered; only disposable test fixtures were created/removed. Normal app scan summaries were refreshed. No external drive writes or service shutdowns occurred.

This establishes and fixes a specific runaway-memory defect. Accessible-path completion is not a guarantee of complete filesystem coverage. Physical unplugging, overnight operation and every possible filesystem failure were not tested; this is not a blanket zero-bug certification.
