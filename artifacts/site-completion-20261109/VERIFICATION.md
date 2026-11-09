# Cairn full-site verification

9 November 2026. Branch: `codex/complete-cairn-site`.

## Delivered

- Ten substantive pages: Features, How it works, Protection, Pricing, Download status, Support & FAQ, Changelog, About, Privacy information and Licensing information.
- A 404 page with useful recovery links; the portable export includes root-based resolution for this page. A future host must map unknown routes to it with HTTP 404.
- Shared source/template, CSS and small progressive-enhancement script under `website/v2/site/`.
- Approved `night.html` composition preserved. Its global navigation and footer connect the rest of the site. Historical variants are untouched.
- Six existing documentation pages remain functional. FAQ/review copy now distinguishes normal review from optional, still-unvalidated automation; docs link back to Support and Privacy.
- Static export script produces a complete portable site in a new directory, refusing to overwrite existing output. Exporting does not publish.

## Passed

- `npm run build:site`: generated all 11 new pages and connected the homepage.
- `npm run build:docs`: regenerated six pages from MDX.
- `npm run build` and `npm run build:story`: existing production bundles built successfully, with no bundle changes to commit.
- `npm test`: existing Radix dialog, five preview screens, product tour, keyboard controls, menu, focus-return and tooltip checks. The page-navigation click in this DOM test now prevents native navigation at document level because jsdom cannot navigate between pages; it still verifies the mobile link and close behaviour.
- `npm run test:docs`: six source/output routes, local references and homepage entry points.
- `npm run test:storage`: scene scroll, controls, keyboard/hash, compact/reduced-motion logic and assets.
- `npm run test:site`: 18 active pages; 539 local links, assets and anchors; unique titles/descriptions/IDs; main/h1 structure; image alt attributes; current navigation; CSS parsing; commercial/download safeguards; 11 repeated menu/resize/Escape/focus/lifecycle/FAQ flows.
- `node site/check.cjs <export-directory>`: the same checks passed on the portable static export.
- Repeated site generation produced identical hashes for every generated page and homepage navigation.
- `git diff --check`: passed.

The first aggregate test run exposed the expected jsdom navigation limitation after replacing old hash links with real pages. The harness was corrected, then the affected test and all remaining suites passed. No product test was silenced or ignored.

## Browser verification

The official managed preview served a local export; no public deployment was created.

- Visually inspected desktop Features, Pricing and Download pages in Chrome. The approved graphite/Inter/blue visual language, four-stone icon and labelled native captures render correctly.
- All 12 main routes (homepage, ten content pages and 404) rendered at 320, 390, 768 and 1024 px frame widths, with no document horizontal overflow or overflow in the checked header/main/footer/headings/panels. Scrollbar-adjusted content widths were 305, 375, 753 and 1009 px.
- Visually inspected the narrow Features page and the 320 px Support navigation and FAQ layout.
- Verified mobile menu opening, repeated interaction, Escape closing and focus return; navigated from the mobile menu to Pricing and confirmed the destination starts with a closed menu.
- Verified native FAQ expansion by pointer and keyboard and collapse by keyboard.
- Verified desktop Back/Forward between Features and Pricing.
- Verified 404 page recovery to Features and onward to Download status.
- In a sandboxed preview with scripts disabled, navigation remained available, the Support page had no horizontal overflow and a native FAQ opened using the keyboard.
- The responsive QA harness is preview-only and excluded from source control/export generation. Its initial oversized iframe caused the browser automation to scroll an outer viewport over the menu; fitting that harness to the browser viewport resolved the testing issue without changing site code.

## Remaining limits

- No public deployment, DNS change, release, checkout or support email activation was performed.
- HTTP 404 routing belongs to the eventual host and is not certified by opening the 404 document locally.
- Browser checks cover Chrome and controlled responsive frames, not physical iPhones, Safari/VoiceOver or every browser.
- No formal contrast audit, screen-reader acceptance, cross-browser certification or production hosting/network-log audit was performed.
- App signing/notarisation, actual supported-Mac acceptance, live licensing, final commercial policies and the four existing experimental safety gates remain separate release work. The website explicitly describes those limits.

## Review locally

Open `website/v2/night.html` or any of the new HTML pages. Run `npm run verify:site` from `website/v2` to regenerate and check the source. Run `npm run export:site -- /absolute/new/directory` to create a self-contained static copy. The generated output contains `index.html` as the active homepage.
