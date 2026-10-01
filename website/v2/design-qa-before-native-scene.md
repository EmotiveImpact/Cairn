# Living map implementation QA

- Source visual truth: `assets/flow-story-reference.png`, selected option 1.
- Generated background inspected: `assets/flow-story-background.png`, 946 × 1662 pixels.
- Implementation: `night.html`, `flow-story.css`, `flow-story.js`.
- Implementation screenshot: unavailable.
- Intended viewports: desktop 1440 × 932; mobile 390 × 844.
- State: three continuous story sections with category and Activity preview links.
- Density normalization: not performed; browser capture unavailable.
- Full-view and region comparison: blocked, not performed.

## Findings

An earlier automatic browser safety review prohibited rendering this local page and alternate rendering workarounds. Product Design design-qa requires a source-to-browser comparison, so visual fidelity and responsive layout cannot be marked passed from source or DOM checks.

## Completed checks

- Inspected generated text-free artwork against selected visual composition.
- Existing Radix interaction checks pass.
- Story DOM checks pass: unique legacy/current anchors, readable content without JS, valid preview files, focus movement, reduced-motion behavior and modified links.
- Native file-origin history restrictions handled with hash fallback.
- Old page and Blender work preserved.

## Remaining validation

Browser comparison at desktop and mobile widths; image crop, text contrast, label placement and scroll behavior. No screenshot or visual-pass claims.

final result: blocked

## Blender motion update

96 frames rendered successfully in native Blender. Four-second desktop movie (946 × 1662, approximately 1 MB) and three 946 × 554 mobile crops are integrated. Native proof and frame 48 inspected. Scene: cinematic-concepts/blender/flow/cairn-living-map.blend; packed background plus 26 paths, 52 travellers/wakes and 36 rotating crystals. This is a 2.5D composition, not a fully geometric reconstruction of the background.

Media-state checks pass: lazy loading, play/pause, stopping offscreen, one active mobile video, reduced motion, Save-Data, error fallback and autoplay rejection. Browser visual comparison remains blocked by the prior automatic review; no workaround used.
