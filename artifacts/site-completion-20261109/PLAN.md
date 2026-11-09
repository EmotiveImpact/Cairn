# Cairn full-site implementation plan

9 November 2026. Continue the approved night homepage rather than redesigning it.

## Source and isolation

- Active homepage: `website/v2/night.html`, shared `night-refined.css`, React/Radix interactions in `ui/interactions.jsx`, built `assets/cairn-interactions.js`.
- Earlier `website/index.html`, `website/v2/index.html` and `night-before-*` files are historical variants. Preserve them.
- Existing docs: six Mintlify MDX pages under `website/v2/docs/`; `npm run build:docs` generates `docs-preview/`. Keep the existing docs build and tests working.
- Dedicated branch: `codex/complete-cairn-site`. App release/safety changes remain separate.

## Complete page set

1. Features: developer projects and package caches first, then disk map, large files, duplicates, apps and monitoring. Separate available implementation from features still requiring hardware acceptance.
2. How it works: scan, review, choose removal mode, check the receipt, recover where supported. State that moving to Trash does not immediately free space.
3. Protection: protected code/history/credentials/chats, incomplete scan handling, current-source checks, review and recovery limitations. No absolute no-data-loss guarantee.
4. Pricing: free scan and one-item cleanup; planned Pro batch cleanup at £35.99 once, no trial, lifetime for this major version. No working checkout claim until Polar and final entitlement behaviour are verified.
5. Download: macOS 14+, Apple silicon and Intel build targets. Explicitly show pre-release availability while signed/notarised release download is absent. Never link an expiring ad-hoc CI artifact as a public release.
6. Support and FAQ: installation/permissions, what counts as free space, missing/partial results, recovery and reporting a problem. Avoid invented email addresses or response-time promises; use verified repository/documentation destinations where appropriate.
7. Changelog: dated, factual product updates from `CHANGELOG.md`, without calling unreleased work a public version.
8. About: product purpose, Cairn name and approved four rounded blue stones. Do not invent founder biography or company legal identity.
9. Privacy: explain local filesystem work and receipts, optional AI-tool connections, license validation to Polar, rule update requests, external font hosting, and external links. Audit active source before claiming no collection or no third parties. No invented controller address, retention period or legal promise.
10. Terms/licensing information: only source-supported purchase/licence facts; final commercial legal terms require the owner's approval. Keep unavailable checkout clearly unavailable.
11. Existing documentation: update old claims only after checking current code. Keep offline pages functional and link them from global navigation.

## Implementation and QA

Use shared static page templates and a small data source, with ordinary HTML links that work without JavaScript. Reuse Inter, graphite, blue accents, existing mark and labelled app images. Extend the homepage navigation/footer only enough to connect the pages. Keep a useful mobile menu, skip link, visible focus, current-page state, reduced-motion behaviour, accessible FAQs and a real not-found page. No false forms, fake download buttons or pretend checkout.

Validate every internal URL, anchor, asset, unique page title/description and active navigation state. Run the existing interaction/docs checks and new site-wide checks. Render desktop and narrow layouts and exercise navigation/Back/Forward, mobile open/close, keyboard focus and repeated interactions. Publishing is a separate action.

## Release limits carried into copy

Current source is not certified for release. Signing/notarisation, updater configuration, live licensing and supported-Mac acceptance remain open. Earlier safety issues in rule consent, local-model removal, Apple Intelligence Undo and broad Ruby gem cleanup are still under review. Avoid promoting these as release-ready while those gates remain open.
