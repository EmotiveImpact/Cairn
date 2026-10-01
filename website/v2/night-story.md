# Cairn night page: developer story

## Person and moment

The primary reader is a developer or AI-assisted builder whose Mac is running low on space during active work. Their repository, local sessions, credentials, and recovery history matter more than a large cleanup number. The page follows one illustrative case: 9.9 GB available, a user-selected 30 GB target, and a mix of build output, package caches, source-control state, and session data. The values come from labelled native sample captures, not a measured customer outcome.

## Positioning

Lead with “A Mac cleaner built for developers.” Keep the developer promise visible in the title, hero, product caption, feature introduction, and footer. The distinctive evidence is the page's treatment of working state: measured changes, exact-path review, protected source and sessions, and a separate outcome reading.

Do not claim Cairn is the chronological “first” developer cleaner. Existing products already make that claim or serve this audience, including [DevCleaner](https://devcleaner.app/docs/) and [SparkClean](https://github.com/georgekhananaev/spark-clean) (checked 29 September 2026). The goal is to make Cairn's developer focus unmistakable without an unsupported market-first claim.

## Current presentation

The current refinement condenses the same four-step scenario into one keyboard-accessible walkthrough. Protection and feature breadth follow it as shorter sections. The problem heading now reads “The disk is filling up. Your build can’t wait.” All preview buttons use “View app preview,” and the viewer offers Actual size for reading native UI details. The full prior layout is preserved in `night-before-refinement.html`; `refinement-notes.md` records the active design.

## Narrative

1. **Recognize the problem.** A full disk threatens the next build. Files on the same Mac have different consequences.
2. **Understand.** Cairn shows dated capacity and compatible measured changes, including coverage gaps.
3. **Plan.** The user sets a final available-space target and sees eligible options to review. Trash moves are not counted as immediate space gains.
4. **Review and protect.** Exact paths and requirements are visible; known source-control, session, credential, and recovery locations are guarded.
5. **Verify.** Activity and capacity readings report affected file size, recovery, and observed available space separately.
6. **Broaden the scope.** The same care extends to apps, duplicates, browser/creative caches, AI model stores, eligible external export copies, and optional reserve alerts.

## Reference lessons

[Save.design](https://save.design/?ref=saaspo.com) informed the editorial night canvas and vivid image stage. [Giga](https://giga.ai/) informed the single concrete scenario, numbered journey, and result. [Deck](https://deck.co/?ref=saaspo.com) informed the translucent sticky menu, split section introductions, full-width product stages, and expanded footer. [Payload](https://payloadcms.com/?ref=saaspo.com) reinforces putting a real interface near the opening claim and giving core developer capabilities more weight than secondary breadth; the latest hero now pairs its headline with a single large, flat Overview screen, and all product screenshots open an expanded five-screen preview. The first two feature cards lead the grid. Following the user's latest correction, the lighter concept's four-stone image now sits behind the opening hero. The footer returns to a dark CTA and navigation composition with light rising from the bottom, without the oversized wordmark. The preceding page and stylesheet are preserved as `night-before-screen-hero.html` and `night-before-screen-hero.css`. Cairn uses its own graphite/blue identity, approved icon, native app captures, and storage-specific language. Footer links stay inside the local page because public destinations do not exist yet.

## Product truth

The native screenshots in this page are sample-only captures from `cairn-native/artifacts/storage-control/native-preview`. The current local implementation has capacity history, Changes, Make room, reviewed cleanup, Activity & Recovery, and opt-in alert-only reserve checks, with remaining release and validation gates in `cairn-native/artifacts/storage-control/VALIDATION.md`. The website does not present a public download, guaranteed reclaimed space, automatic cleanup, general external-drive migration, or completed release certification.
