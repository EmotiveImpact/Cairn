# Living map — selected concept 1

Implemented in `night.html`, using `flow-story.css` and `flow-story.js`.

## Visual target and assets

- Selected target: `assets/flow-story-reference.png` (first displayed concept).
- Built-in Image Gen edit: `assets/flow-story-background.png`, 946 × 1662.
- Web delivery: `assets/flow-story-background.webp`, approximately 229 KB.
- Prompt: remove every text/UI element from the selected reference, reconstruct the underlying artwork, preserve flowing blue fibers, crystals, protection boundary and graphite path, retain dark left negative space; no stones, no oversized glow; one continuous cinematic composition.

## Implementation

One continuous image spans Understand, Protect and Check. Text, labels and navigation are HTML; Radix library icons are used for labels. The protection section is merged into the story. The ending follows an open activity trail rather than repeating the stones. The original parallax-only treatment was replaced by a Blender-rendered animation. The approved illustration is a packed background plate, with 26 editable paths, 52 moving mesh travellers and wakes, and 36 rotating crystal fragments. This is a 2.5D composite, not a fully modeled replacement of the illustration. Reduced motion retains the still and disables smooth scrolling. Mobile uses three separately encoded crops and decodes only the visible chapter. A sticky pause control stops playback; offscreen and hidden-page playback pauses automatically. All chapters remain readable without JavaScript.

Category and activity links open the existing Radix app previews. Protected labels describe guarded locations without claiming every file is safe. No fabricated cleanup figures. Moving to Trash is explicitly distinguished from freeing space.

Previous page preserved as `night-before-flow.html`; Blender project and movies remain intact.

## Checks

`npm test`: existing Radix preview, tab, focus-return and menu checks pass.
`npm run test:story`: anchors, no-JS content, assets, navigation focus, reduced motion and modified links pass.
`npm run test:motion`: lazy loading, playback, pause/resume, offscreen pause, mobile selection, reduced motion, Save-Data, autoplay and media-error fallback pass.

Browser visual verification remains blocked by an earlier automatic approval review that prohibits local page rendering and alternate rendering workarounds. No desktop/mobile screenshot comparison has been performed. Refresh the existing page manually to inspect.

## Blender motion source

`cinematic-concepts/blender/flow/cairn-living-map.blend` contains the packed scene. See that folder’s README and scene-manifest.json for render/export status. Source rebuild: build_flow.py; bounded CPU render: render_flow.py; web export: export_flow.py.

Render completed: 96/96 frames; all four-second H.264 movies exported and integrated. Desktop 1,018,063 bytes; mobile 458,507 / 408,185 / 191,952 bytes.
