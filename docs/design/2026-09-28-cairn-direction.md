# Cairn direction: understand, decide, recover

A design proposal, not a claim that these capabilities already ship.

## Product opportunity

A native Mac storage control centre for people whose work spans browsers, creative apps, developer tools and external drives. Overview explains measured change; existing specialist screens retain depth. Avoid adding unrelated utility features before this loop is useful.

1. Understand: current available capacity, dated history, comparison of the same scan categories and scopes. Explain missing permissions, incomplete scans, unmatched growth and changes in scope. Do not attribute all disk growth to the categories Cairn can measure.
2. Decide: inspect exact paths, expected benefit and consequences (rebuild/download, app must close, offline availability). Offer review, supported path configuration or application-aware export only where supported.
3. Recover: record every attempted action with outcome and actual recovery availability. Moving to Trash is not guaranteed free space; a synchronized or verified copy is not automatically a backup.

Keep memory/swap observations distinct from file capacity. An external SSD provides storage, not additional RAM. Google Drive and remote compute may have distinct roles in a future design; do not put them in a single interchangeable RAM/storage pool.

## Visual direction

Preserve compact native window, charcoal identity, recognizable icons, sidebar and translucent toolbar. Give each screen a purpose rather than forcing all screens into the same list plus inspector. Overview prioritizes a complete, readable history plot and meaningful changes. Review prioritizes consequences. Storage prioritizes data locations and drive availability. Use actual measurements, clear empty states and visible concept labels on mocks.

The user's cropped chart screenshot shows a cut right edge. The current full-window capture showed both controls and the endpoint visible. Do not infer a newly reproduced clipping bug from the crop alone. The compositional problem remains: chart competes with an oversized capacity block and needs independent space.

## Recommended implementation order

- Refine Overview composition from the selected visual concept.
- Implement trustworthy scan comparison with compatible category/scope identifiers, timestamps and partial-scan handling. A missing measurement must never become zero growth or a promised saving.
- Connect changed categories to existing path review with required conditions.
- Improve activity and recovery explanations for each supported action.
- Expand external-storage adapters only after supported configuration, volume identity, disconnect behaviour and rollback can be verified per tool.

Existing available-space history samples once per launch day. Continuous monitoring and per-app growth attribution are not currently implemented. Native build/signature and fixture tests do not prove long-duration stability or live migration safety.

## Generated visual explorations (display order)

1. `/Users/augustusedem/.codex/generated_images/01a0e383-8d4b-7ed2-af4b-eca87bb9a5ad/exec-66ceec80-a260-419c-8593-69a32a6c85dd.png`
2. `/Users/augustusedem/.codex/generated_images/01a0e383-8d4b-7ed2-af4b-eca87bb9a5ad/exec-0d282685-d91f-4760-aa02-8c2f9865ae88.png`
3. `/Users/augustusedem/.codex/generated_images/01a0e383-8d4b-7ed2-af4b-eca87bb9a5ad/exec-6eca859b-d469-4b43-83e8-04ac41ed4986.png`

No visual selection or code changes in this ideation turn. Before implementation correct image-generated inconsistencies: the second image's capacity-bar proportions do not match its labels; replace blanket 'Your Mac is safe' with an exact operation/check state. Third-image sample paths are illustrative, not an authoritative allowlist or migration target. Verify tool-specific paths in implementation. These are views of one product, not separate apps.

## Implementation follow-through

User selected displayed image 1 for Overview and image 3 for Storage, explicitly requested building both, then said “get to work.” Both are implemented in `Cairn/UI/OverviewWorkspace.swift` and `Cairn/UI/StorageWorkspace.swift`. The comparison engine is `Cairn/Core/ScanComparison.swift`; current verified scope and limits are in `BUILD_STATUS.md` and `design-qa.md`. No separate product or new repository was created.
