# Confirmed scroll homepage and complete site

## Owner's final direction

On 9 November 2026 the owner confirmed the cinematic `story.html` homepage: “This is it”, then explicitly requested “Exactly this” because “this is the site I want”. The prior `night.html` identification was based on stale README notes and is superseded. Beam/Wave is also an old study.

## Preservation boundary

- The homepage's main markup is byte-for-byte the saved October 24 markup after normalising only its hero CTA destination. A SHA-256 regression assertion covers it.
- `story.js`, `story.css`, `beam-hero.js`, and `beam-hero.css` are byte-for-byte unchanged and pinned by SHA-256 assertions.
- Every original scene, image, word, app capture, gallery, picture switch, cinematic transition and chapter is preserved.
- The only homepage changes are description metadata, an Explore menu in the existing pill header, a footer directory, and destinations for download/pricing CTAs. New menu scrolling does not advance the underlying story. Narrow navigation has a bounded, scrollable panel and Escape/focus restoration.
- The homepage’s existing marketing and licence copy was deliberately preserved under the owner's exact-design instruction. In particular its “typical” scan figures, absolute safety statements and two-year macOS-update promise remain unverified design copy. They are not approved public-release claims. Dedicated pricing, protection, download and licensing pages identify the current verified status. This is an owner-private review only.

## Complete pages

Features; How it works; Protection; Pricing; Download status; Support & FAQ; Changelog; About; Privacy information; Licensing information; and 404 recovery. Six existing generated documentation pages remain linked. New product pages use the confirmed homepage's floating pill header, Inter type, quiet graphite/blue surfaces and October app captures with sample labels. No new imagery or replacement homepage was generated.

Brand links, documentation return links and the exported root resolve to `story.html`. The old private-preview path `/v2/story.html` redirects to the current homepage. Archived night/Beam studies are omitted from the export. They remain preserved in source.

## Automated verification

- Site, documentation and existing interaction/storage bundles generated successfully.
- Existing `npm test`, `npm run test:docs`, `npm run test:storage` passed.
- Site checks pass across 18 active pages and 568 local references: titles/descriptions, landmarks, IDs, anchors, assets, current-page state, CSS parsing and no unverified purchase/download submissions.
- Eleven generated pages passed repeated mobile menu open/close, Escape/focus return, outside click, history/page-cache restoration, resize and directly linked FAQ checks.
- New `test:scroll-site` checks confirmed homepage preservation, unchanged original animation/style files, every new navigation destination, repeated Explore dismissal/focus/lifecycle, and wheel isolation from the scroll story.
- Generator is deterministic on consecutive runs. Source and exported checks pass. `git diff --check` passes.

## Rendered browser checks

Using the supported cloud-browser preview:

- Inspected desktop homepage, Explore menu, Features and Pricing.
- All twelve main HTML pages were loaded at frame widths 320, 390, 768 and 1024 pixels. Actual content widths 305, 375, 753 and 1009 pixels (scrollbar deducted) had no horizontal document overflow.
- Fixed and rechecked a narrow 320-pixel homepage header overlap caused by the inherited hidden menu's wrapper. The added Explore control is inside the header bounds.
- Mobile Explore links navigate to Features and Support. Escape closes both native Explore and content-page navigation; repeated DOM tests cover lifecycle behaviour.
- Native FAQ answers open with pointer and toggle with Enter; a direct `support.html#trash` visit opens its answer.
- A sandboxed no-JavaScript frame exposes the content-page navigation and normal page content. The QA-only harness applies sandbox before navigation and is excluded from publication.
- The original disk chapter was checked before and after PageDown: its selected junk disappears and free space grows visually from 42.6 to 81.2 GB. PageUp and chapter navigation remain connected. The original app chapter was also inspected.
- Browser Back/Forward preserved Features/Pricing routing. The 404 recovery link returns to the confirmed homepage. The prior `/v2/story.html` route resolves correctly.
- Dev console's recent errors were browser-extension metadata messages, not site-origin errors. This is not a full browser console audit.

## Limits and release gates

Desktop/phone-sized Chromium frames are not physical Safari/iPhone testing or macOS app acceptance. No native app, purchase, entitlement, notarisation, updater or public download was verified by website tests. Separate safety work is ongoing; its completion must not be inferred from this website. No public publication or merge is authorised here. The obsolete PR #26 must not be merged as the final design.

## Integration review

The archived `night.html` is restored to its unchanged master contents; the rejected old homepage is not modified by this corrected integration. An independent `npm run verify:site` rerun passed, followed by the existing interaction tests after restoring the archived file. App sources, packaging and workflow files are unchanged.
