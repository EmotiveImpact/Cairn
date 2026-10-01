# Cairn — the space behind your work

## Current implementation

The four mockups in `cinematic-concepts/storage-story-mockups/` establish the visual direction. The website now uses actual Three.js geometry, physical metal/glass materials, and custom shaders. It does not display the mockup images as the animation.

`night.html` is the current page; `night-refined.html` remains its symlink. The original `assets/stone-seam.png` hero atmosphere and single Overview screenshot have been restored. The two layered product panels now form a dedicated explainer showcase immediately before “The rest of your Mac,” retaining their soft fade effect and Radix preview actions. The user clarified that the earlier 2×2 complaint referred to the wrong demo, so the current layout is retained.

## Story

1. Understand — a dense volume of graphite and blue glass layers; a slow light scan reveals its surface.
2. Review — an identifiable group of graphite layers separates for inspection, revealing the connected blue interior.
3. Protect — the same three glass layers stay connected while review candidates move farther aside.
4. Make room — reviewed groups withdraw; the retained base, glass layers and cap remain, alongside a small illustrative action record.

Twenty-six persistent layers are transformed continuously, including on reverse scroll. No invented free-space measurements are shown. The copy retains the distinction between reviewing candidates and approving action, and notes that Trash alone does not free space.

## Files

- `ui/storage/model.mjs`: geometry, deterministic chapter poses, scan shader, blue connections and glass detail.
- `ui/storage/view.mjs`: environment lighting, camera, shadows, adaptive resolution and WebGL lifecycle.
- `ui/storage/controller.mjs`: scroll progress, slider, chapter buttons, keyboard navigation, anchors, visibility and preferences.
- `storage-story.css`: responsive layout and lightweight static illustration fallback.
- `assets/cairn-storage-story.js`: self-contained bundle; no remote module or model fetch is required from file URLs.

`npm run build:story` rebuilds the scene bundle. `npm run test:storage` runs geometry and non-rendering interaction checks. `npm test` checks the existing Radix preview/menu interactions.

## Rendering behaviour

GPU resources initialize when the section is visible. The camera and geometry follow a hold-aware scroll timeline. Light scans, connection pulses and glass glints run at a capped 30 fps while visible; they do not rotate or move the held composition. Rendering pauses offscreen and when the document is hidden. Mobile/short screens use chapter buttons and slider without pinned scrolling. Reduced motion and data saver use the static illustration. WebGL initialization failure, shader failure or context loss exposes that illustration while preserving all controls and copy.

## Verification boundary

Geometry and non-rendering DOM checks pass. Numerical projection checks were performed for desktop and narrower artwork bounds. Those are not GPU render or browser layout evidence. An earlier automatic approval review blocked local website rendering and alternate rendering workarounds; no such rendering was attempted. Shader compilation, material appearance, final desktop/mobile composition and exact mockup fidelity still require visual checking in the user's browser.

Previous implementation preserved in `night-before-storage-story.html`, `scene-story.js`, `scene-story.css`, the old video and Blender assets.

## Reference correction

After the user reported the live result did not resemble the mockup, the plate geometry was rebuilt as extruded rounded rectangles. This gives the silhouette broad 0.28-unit corners independently of plate thickness, instead of the tiny corner rounding imposed by the previous thin rounded boxes. The glass is 0.18 units thick, compared with 0.112-unit graphite plates. Wider surfaces, stronger glass reflections, 100 persistent light strands, and a softly sampled live floor reflection were added. Review groups are spaced clear of the retained glass volume. Bundle URL advanced to version 2. A screenshot of the user's current rendered section was requested to distinguish a live scene/material mismatch from a fallback; not yet received.

## Cinematic choreography pass
The protection chapter now moves to a closer camera position while the upper and review groups move beyond the retained core. Nine tubular routes organise the finer connections into three bundles; scroll progress drives a light pulse along them. A thresholded bloom pass emphasises those light paths, with final tone mapping handled by OutputPass. Rendering remains on demand and reduced motion remains static. The next screen showcase uses less overlap, complete app screenshots and a quieter edge fade. Hero retained. Current bundle and scene CSS use version 3; showcase CSS uses version 2.

Geometry and DOM tests pass; no GPU/browser visual claim is made. The requested screenshot has not yet been supplied.

## Four chapter holds and living light — version 4

The scroll track is now 480svh. `ui/storage/timeline.mjs` maps scroll progress through holds at 0–12%, 28–42%, 58–72%, and 88–100%, with smooth geometric/camera transitions between them. Buttons and hash navigation target the hold positions; ordinary scrolling remains native and reversible. On compact screens the existing manual controls remain.

Graphite plates are wider than the blue glass core, matching the mockup proportions more closely. Fine connections extend from the retained base through the three glass layers. Slow scan light, travelling route pulses and staggered glass glints continue during holds. Rendering stops offscreen or in a hidden document; reduced-motion and data-saver modes remain static. Hero and screenshot showcase unchanged in this pass.

Build, four-hold/forward/reverse/navigation checks, offscreen pause, fallback and Radix interaction checks pass. These checks do not establish GPU shader success or visual fidelity.

The user explicitly authorised local preview inspection. A fresh CUA attempt was made, but the browser URL policy blocked access to the file URL. No alternate renderer was used. A screenshot of the user's current 3D state is still needed to compare actual appearance with the approved mockup.

## Slab collision correction — version 5

The previous motion paths intersected in two places: the glass core spread into the review stack during opening, and the closing cap passed through the upper stack. Review candidates now move fully sideways before the glass spreads. During the final transition the upper stack clears sideways before the cap descends. The light strands and glass glints follow the delayed core opening. Four chapter holds remain unchanged; reverse scrolling retraces the same paths.

A regression check samples all 325 slab pairs at 6,001 timeline positions using the actual extruded geometry bounds, including bevels. It reports no intersections. This conservative local-space check remains valid under the shared parent rotation. Rendering still requires browser visual verification.
