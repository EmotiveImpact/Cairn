# Cairn website — QA history

## Current process and product tour — 30 September 2026

The rejected slab animation has been replaced with a branching diagram tied to Cairn’s actual workflow: discover data, inspect review candidates, keep known working state, and record the approved outcome. The original hero remains. The Orchestra-inspired product tour now changes its screenshot as the user scrolls through three desktop states; accordion clicks also reach those states. Mobile, short viewports, and reduced-motion users get manual switching. The original Three.js files and pre-change page are preserved but not loaded.

Both bundles build. `npm test` and `npm run test:storage` pass non-rendering checks, including forward/reverse scroll state, all holds, button and keyboard navigation, and product screenshot switching. Browser visual proof remains unavailable under the local file URL policy. Earlier entries below describe superseded versions.

## Implemented and checked
- Selected Living map concept translated to native Blender geometry, not an image plate.
- Refined after proof inspection: removed visible terrain edge, varied and thinned fibers, added native light junctions, subdued fragments and corrected the glass reveal pivot.
- Inspected native frames 1, 33, 65 and 96 and an encoded video frame.
- All 96 distinct native frames rendered at 1280 × 900; four-second H.264 output has 96 keyframes for seeking.
- Four-stage scroll/slider story installed in night.html; night-refined.html symlink verified.
- Soft fades on all four edges follow the latest supplied Linear reference; no replacement with copied Linear panels.
- `npm run test:story`: scroll and reverse slider seeking, no autoplay, keyboard chapters, hash links, reduced motion, compact/manual mode and media fallback.
- `npm test`: Radix previews, tabs, zoom, focus return, menu and modified-link checks.
- `npm run test:motion`: installed assets, previews, video metadata and refined-page alias.

## Remaining visual gate
An earlier automatic approval review prohibited rendering the local website and alternate rendering workarounds. No desktop/mobile website screenshots were produced. DOM checks and native render inspection do not prove browser layout, focus trapping or exact reference fidelity.

Intended browser comparison: desktop 1440 × 932 and mobile 390 × 844. Check crop, readable copy, sticky bounds, scrub responsiveness and fade transitions manually in the existing page.

final result: blocked

## Hero correction
The user clarified that the supplied Linear panel reference was for the hero. `hero-layered.css` and the hero markup now use overlapping flat Cairn Developer Cleanup / Overview images with feathered edges, replacing the previous rock background and framed single screenshot. Left-hand headline and existing app-preview actions retained. Previous page saved as `night-before-layered-hero.html`. DOM interaction checks pass; browser visual verification remains blocked by the earlier review.

## Current Three.js story
The current page replaces the native Blender video with a persistent 26-layer Three.js scene, custom scan/connection shaders, physical graphite and glass materials, and four scroll/slider stages. The original stone-seam hero image is restored. Current layout retained after the user clarified that the 2x2 complaint concerned the wrong demo. The latest reference correction uses broad rounded plate corners, thicker glass, denser fibers and a soft live reflection.

`npm run test:storage` passes geometry identity, retained layers, scroll/slider reversal, lazy initialization, offscreen pause, keyboard/hash navigation, reduced motion, mobile controls, data saver, unavailable-WebGL fallback and restored hero checks. `npm test` passes existing Radix interaction checks. These tests do not render the page or compile shaders on a GPU. Live screenshot requested from user for matching the reference; not yet received.

final result: blocked on browser visual verification; implementation and non-rendering checks complete.

## Product showcase relocation
User requested the layered hero screens become an explainer immediately before “The rest of your Mac.” The original single Overview figure was restored from `night-before-layered-hero.html`; stone background preserved. Layered Overview and Developer Cleanup screens moved into `#inside-cairn` with the same compound edge masks, responsive layout and preview actions. CSS is scoped in `screen-showcase.css`. Pre-edit page preserved in `night-before-screen-showcase.html`. Browser visual verification remains subject to the existing block.

## Cinematic sequence and next-section correction
Added a continuous camera path with a protection close-up, outward clearance for review candidates, three structured luminous route bundles, thresholded bloom and all-edge blending. Simplified the following screen showcase: less overlap, no inner screenshot crop, stronger visibility of both views. Existing non-rendering checks pass. Reference fidelity and GPU shader output remain unverified under the existing browser-review restriction.

## Scroll holds and effects — version 4
Four chapter holds added with native, reversible scroll transitions. Chapter buttons/hash targets land inside holds. Visible-only light animation capped at 30 fps; no geometric idle motion. Wider graphite shell, narrower glass core and connections extending to the base implemented. Built successfully; storage/hold and existing interaction checks pass.

Fresh browser inspection was explicitly approved by the user, then blocked by Browser Use URL policy for the local file URL. No browser capture, GPU shader verification or mockup-fidelity claim is available.

## Oversized hero screenshot — stylesheet version 17
User clarified the hero should have a large, flat screenshot extending partly beyond the viewport, following the supplied Linear reference. The desktop screenshot now expands beyond its grid column and right viewport edge; its caption stays within the content column. Copy remains vertically centred against the screenshot. The hero contains the horizontal overflow; the existing single-column tablet/mobile rules remain. Hero imagery, copy and the deferred 3D work are untouched.

Calculated desktop sizing confirms deliberate right-edge cropping: approximately 228px at 1256px wide and 133px at 1440px wide. These are layout calculations, not browser visual verification; local-file inspection remains blocked.

## Deck product-section reference — showcase version 3
Inspected the user's four Deck annotations and live page. Replaced the overlapping screenshot composition with two alternating copy/visual rows (Overview, Developer Cleanup), followed by two smaller side-by-side views (Changes, Activity & Recovery). Primary views sit against Cairn's existing stone imagery and deliberately crop inside their presentation frame on desktop. At 760px and below the rows become text-first and show the complete screenshot. Every preview retains its existing Radix action; sample-data disclosure remains. Hero and 3D scene unchanged. Previous page preserved in night-before-deck-showcase.html.

Local browser visual verification remains unavailable under the file-URL policy; layout is not visually certified.

## Orchestra replacement — showcase version 4
User rejected the Deck lower-section pass and selected Orchestra's numbered product explanation. Inspected the live reference, including switching its second step. Replaced the alternating rows and paired screens with one section: large left heading, three numbered Radix accordion steps and one matching, oversized real app screenshot on the right. Desktop image extends beyond the viewport; mobile shows the complete screen below the steps. Preview actions remain available. Original static six-feature grid and centred footer restored. Removed feature-tour mount/styles from the live page; source retained unused. Hero and deferred 3D unchanged.

Local rendered composition remains unverified due to the existing local-file browser restriction.
