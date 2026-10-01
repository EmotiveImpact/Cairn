# Archived stone animation

The user selected the Living map redesign. Active night.html now uses FLOW-STORY.md; the Blender files and this implementation are preserved in night-before-flow.html.

# Cairn cinematic story

Completed 2026-09-29: all 96 frames rendered and exported; 4.0 seconds, 4.46 MiB. The complete movie and four rendered chapter posters are integrated into night.html. Native key frames inspected; DOM checks passed. Browser visual QA remains blocked as described below.

The active `night.html` uses a real Blender-rendered film in the four-chapter process section. Copy and controls remain accessible HTML. The original page is preserved as `night-before-blender.html`.

## Assets and source

- Editable packed source: `cinematic-concepts/blender/cairn-story-animated.blend`.
- Authoring: `cinematic-concepts/blender/animate_story.py`.
- Resume remaining frames: `cinematic-concepts/blender/resume_story.py` (four-frame isolated processes; requires at least 2 GiB free before each batch).
- Export and integrate: `python3 cinematic-concepts/blender/export_story.py`.
- Delivery: `assets/cairn-story.mp4`, H.264, 1280 × 908, 24 fps, all intra frames for seeking, no audio.
- Posters: `assets/cairn-story-{understand,review,protect,verify}.jpg`.
- Runtime: `cinema-story.js`, `cinema-story.css`.

The saved animation has 96 frames. `animation-manifest.json` records actual rendered/exported status. Interrupted exports remain explicitly partial; unavailable ranges display a chapter still instead of mapping to the wrong frame. The completed export script checks all frames before replacing the movie and updating page metadata.

## Behavior

Desktop scroll scrubs the film through Understand, Review, Protect and Verify. Compact screens use chapter buttons. Buttons support arrow keys, Home and End. Media loads near the section; reduced-motion and Save-Data preferences retain stills. Error fallback, deep links, coalesced seeking and partial export bounds have non-rendering DOM checks (`npm run test:cinema`).

## Verification boundary

Native rendered frames can be inspected, and DOM interaction checks pass. Local website browser rendering remains blocked by an earlier automatic safety review, including alternate renderer workarounds. No desktop/mobile visual QA pass is claimed.

This is an authored 3D reconstruction with generated color textures packed into Blender. It differs from the selected AI image in translucency and fine fracture distribution. Protection-section background remains the exact separate image supplied by the user.
