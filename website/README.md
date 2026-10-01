# Cairn website

The active website is [v2/night.html](v2/night.html). Source, assets and package scripts live in `v2/`; its documentation source is `v2/docs/`.

This folder is separate from the native app in `Cairn/`. The root HTML/CSS files are the earlier version-one concept, retained because historical references link to them. The original brand-exploration workspace was copied, not moved or deleted.

For a local static preview, run `python3 -m http.server 4173 --directory website` from the repository root, then open `http://localhost:4173/v2/night.html`. To develop the bundled interactions, run `npm ci` in `website/v2` and use its package scripts. No dependencies were installed as part of this import. The existing documentation and interaction checks passed using the original workspace’s installed dependencies. Local Blender/cinematic experiments are preserved on disk but excluded from Git; they are not loaded by the active page.

This is an in-development website, not a deployed site or public app download. Earlier design alternatives remain in v2 for reference; the active page is night.html.

---

# Cairn website concept

Open `index.html` in a browser to review the direct, dark homepage. It uses the confirmed app icon and existing Cairn native preview captures. The app screenshots contain labelled sample data.

The September 29 refinement places a transparent header over the hero, uses [Instrument Sans](https://fonts.google.com/specimen/Instrument+Sans) throughout, and gives the headline, app preview, and product explanation a quieter layout. The [daylight](v2/index.html) and new [editorial night](v2/night.html) pages provide further directions for comparison.

The page is intentionally a concept: navigation anchors and the Overview/Storage switcher are wired locally, but browser interaction has not been verified. It does not claim a downloadable public build, take email addresses, or connect to a service. No site was published.

Static checks passed for local links, assets, image alternatives, CSS parsing, and JavaScript syntax. The task's browser policy blocked opening the local HTML URL, so desktop and phone rendering still need a visual check before this is treated as a finished site.

The content focuses on three points: the app explains storage in measured terms, changes require review, and known source/session/credential locations are protected. A short section explains the UK/US pronunciations of “cairn” and its trail-marker meaning.

Design reasoning and tokens are in `design-plan.md`. The source app currently lives at `/Users/augustusedem/Downloads/SSD/cairn-native`; this concept does not modify it.
