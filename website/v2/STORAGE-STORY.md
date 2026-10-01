# Cairn process story

The current page is `night.html`; `night-refined.html` points to it. The rejected slab-based Three.js version is preserved in `STORAGE-STORY-3d-history.md` and its old source files.

## Current experience

The process section uses a scroll-driven branching diagram. Data found on the Mac enters one junction. Review candidates and known working-state locations take separate paths. The final state shows a recorded outcome. Labels match the page copy, and the visual never implies automatic removal.

The four chapters keep deliberate scroll holds, a scrubber, step buttons, keyboard controls and hash links. On compact screens and with reduced motion, the steps are manually controlled. The illustration is authored directly in `night.html` and styled by `flow-story.css`; `ui/storage/controller.mjs` drives the chapter state. The old 3D source is no longer loaded.

The following `#inside-cairn` section pins on desktop and switches between Overview, Developer Cleanup, and Activity & Recovery over three scroll zones. Clicking an accordion step scrolls to its matching zone. Mobile, short viewports, and reduced-motion users retain manual switching. Source: `ui/product-tour.jsx` and `screen-showcase.css`.

## Verification

`npm run build`, `npm run build:story`, `npm test`, and `npm run test:storage` pass. The tests cover forward and reverse scroll state, hold positions, chapter controls, product screen switching, compact and reduced-motion modes, and local asset references. They do not render the page. Browser layout and motion remain visually unverified because the local file URL was blocked by the browser use policy during this task.
