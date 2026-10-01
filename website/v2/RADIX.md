# Cairn interaction layer

Installed locally: React, React DOM, Radix Primitives (`radix-ui`), esbuild, and jsdom for non-rendering interaction checks. Exact versions are pinned in package-lock.json.

## Build and check

- `npm ci`
- `npm run build`
- `npm test`

`ui/interactions.jsx` builds to `assets/cairn-interactions.js`, a bundled classic script that works with the existing file-based page and does not need a development server or runtime CDN. `night.html` loads it and `ui/interactions.css`. The original interaction script remains preserved; the active page no longer loads it.

## Applied components

- Dialog: app preview, dismissal, focus management and return to originating link.
- Tabs: five native app captures and keyboard selection.
- Popover: responsive mobile navigation, dismissal and resize closure.
- Tooltip: seven tool marks with coverage descriptions and section links.
- Collapsible: footer explanation of the name.

Motion uses custom Cairn styling: eased overlay/panel entrances, short exits, screen fades, menu-line transition, hover and press feedback. Reduced motion disables these transitions and smooth scrolling. Existing content, brand and cinematic canvas remain intact.

Source docs: https://www.radix-ui.com/primitives/docs/overview/introduction and https://www.radix-ui.com/primitives/docs/components/dialog

## Verification boundary

Build and jsdom checks cover interaction logic, semantic attributes and focus-return state. They do not prove browser rendering, layout, native focus trapping or animation quality. Local website browser rendering remains blocked by the earlier safety-review decision.
