# Project Decisions

> Historical record. Some entries describe disabled actions or superseded product decisions. Use [the current PRD](CAIRN-STORAGE-CONTROL-PRD.md) and [capability map](STORAGE-CONTROL-CAPABILITIES.md) for active behaviour and restrictions.

Decisions locked for the Mac cleaner app. Updated as we go.

## 2026-06-30 — Kickoff decisions

1. **Framework: Native SwiftUI rebuild.** Rewrite as a native macOS SwiftUI app, porting the
   Python prototype's scanner domain knowledge (dev-cache target lists, Xcode targets, severity
   model, safe-delete guard). Rejected the "SwiftUI shell + bundled Python engine" hybrid because
   bundling a Python runtime bloats the app, makes Developer-ID signing/notarization fragile, and
   is brittle across macOS versions. Native = one small signed binary that works for every customer.

2. **Positioning wedge: the cleaner built for developers.** Lead with reclaiming developer space
   (node_modules, Docker, Xcode DerivedData/simulators, package-manager caches, language runtimes),
   then cover general categories (app/browser caches, logs, installers, trash, orphaned data,
   large/old files). Anti-bloat, trustworthy, no scare tactics — the opposite of MacKeeper.

3. **Name: TBD.** "MacSweep" is taken (an existing GitHub project does the same thing). Will pick a
   brandable name in the Emotive Impact family (Vlume / LoudMix / Tapio / Mixly) from the naming
   research, confirm with Augustus, then apply. Using a provisional codename until then.

4. **Monetization: subscription.** Yearly primary, possibly a small monthly option — a change from
   the studio's usual one-time Polar model. Likely freemium: free to scan + basic safe clean; paid
   unlocks the developer tools / deep clean / automation. Billing via Polar (supports subscriptions).
   Final tier/price set after the pricing research.

5. **Distribution: Developer ID + notarized, shipped as a stapled zip.** Reuse the studio signing
   pipeline (Team `FC88M2P4F9`, `vlume-notary` profile). No Mac App Store (a full-disk cleaner can't
   be sandboxed and needs Full Disk Access).

6. **Safety first.** Trash-by-default (never permanent unless explicitly confirmed), SAFE/REVIEW/RISKY
   severity tiers, exclusions, and a Full Disk Access onboarding so totals are never silently wrong.
   See [BUGS-AND-FIXES.md](../BUGS-AND-FIXES.md).

## Workspace layout
- `reference-prototype/` — the archived Python prototype (mined for IP, not shipped).
- `docs/` — spec, decisions, architecture.
- `BUGS-AND-FIXES.md` — living bug/safety log.
- (app source scaffolded once the name is chosen.)
