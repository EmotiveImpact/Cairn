# Native Blender story — delivered locally

## Implemented
- Editable scene: `cinematic-concepts/blender/flow-3d/cairn-living-map-3d.blend`.
- Native animated geometry: fibers, 240 crystals, 150 light junctions, glass boundary, procedural terrain, camera and lights. No image textures or image plates.
- Four states: Understand → Review → Protect → Check.
- 96 distinct rendered frames, 1280 × 900, 24 fps. Web export: `assets/cairn-data-scene.mp4`, four seconds, 96 independently seekable keyframes.
- Scroll/slider controller installed in `night.html`; `night-refined.html` remains its symlink. No autoplay or loop.
- Top, bottom and side fades informed by the supplied Linear screenshot. Existing native story retained; the screenshot was treated as a presentation reference, not a request to replace the scene.
- Mobile/manual controls, keyboard chapters, reduced-motion chapter posters, media-error fallback and legacy anchors.
- Previous page preserved as `night-before-native-scene.html`.

## Verification
Native proofs 1, 33, 65 and 96 inspected; encoded video frame inspected. Saved Blender file reopened with four distinct evaluated geometry states and no image-texture nodes. All assets and app-preview links exist. DOM tests for scroll/slider interactions, Radix previews and navigation pass. Video frame count, dimensions and keyframes checked with ffprobe.

## Remaining limitation
Browser visual verification is blocked by an earlier automatic approval review prohibiting local page rendering and alternate rendering workarounds. No desktop/mobile browser capture or pixel-fidelity pass is claimed. Refresh the existing page manually and choose How it works to inspect the installed story.

## Reproduction
`build_flow_geometry.py` authors the scene. `run_render.py` resumes eight-frame batches and refuses to render below 2 GiB free. `deliver_scene.py --install` exports all frames, copies posters and installs the story. Rendering completed after two storage pauses; all progress was preserved.
