# Cairn website content sources

Reviewed 9 November 2026. The website describes development work, not a certified public release. No payments, download artifacts or deployment were enabled by this task.

## Product and workflow

- `CHANGELOG.md`, entries 27 October–4 November 2026: project discovery, per-project evidence, sleeping/wake commands, cache measurements, disk map, apps, duplicates, monitoring, removal modes, measured receipts and recovery limits. The website changelog is a deliberately selective summary of these dated entries, not a public version history.
- `Cairn/Core/StorageHistory.swift`, `Cairn/Core/StorageTransfer.swift` and the existing six MDX documentation pages: local histories, recorded transfers, source retention and separation of candidate size, recorded action and measured free space.
- `Package.swift`: minimum macOS 14.0 target. Build configuration and release review establish Apple silicon and Intel build targets, not completed hardware acceptance.
- Existing approved `website/v2/night.html` and labelled native captures are retained. Captures contain sample data and are not represented as screenshots of every latest app feature.

## Availability and commercial information

- The site-completion plan, release review and source-backed product decision specify free scanning and one-item cleanup, with planned Pro batch cleanup at £35.99 once, no trial and lifetime for this major version.
- `Cairn/Licensing/Licensing.swift` and the 3 November changelog: saved licence checks, Keychain storage and a 30-day offline allowance for a previously verified licence. Older security documentation says 14 days and is superseded for this specific implementation detail.
- Live Polar checkout/activation, final executor entitlement behaviour, device allowance, tax treatment, refunds, support commitments and final legal documents are not certified. The site explicitly leaves checkout unavailable.
- The release worker confirmed no public GitHub release or signed, notarised public download. Ad-hoc CI artifacts are not linked or presented as public releases. Sparkle/update delivery is not configured.

## Safety boundaries

- Normal cleanup path checking is described without universal guarantees. Known-location protection is not a backup or a claim that every valuable file can be recognised.
- The release review identifies unresolved scheduled-rule consent, local-model scanned-identity/journaling, Apple Intelligence cancellation and broad Ruby gem cleanup issues. Features and Protection explicitly do not call these release-ready.
- The existing documentation's broad unattended-cleanup wording was updated to distinguish normal review from opt-in, still-unvalidated automation.
- The app-release worker subsequently reported PR #25 merged to master, with the same tree as its full-CI-green reviewed package-link fix. That does not resolve the four older safety gates and does not make the product publicly released. This website task does not modify app code.

## Privacy and support

- `Cairn/Licensing/Licensing.swift`, `PolarClient.activate`, `validate`, `deactivate`: activation sends a licence key, organisation ID, device label and hardware UUID to `api.polar.sh`; later checks use the key, organisation and activation ID.
- `Cairn/Core/RuleUpdates.swift`: `publicKey` is nil, disabling the rules feed. The future request target is the Cairn-hosted rules list and detached signature.
- `Cairn/Core/ProblemReport.swift`: support email is nil; report copy is supported. Report content includes app/OS versions, hardware and memory, permissions, scan/cleanup summaries and limited crash details. The site asks the user to inspect and redact instead of promising perfect anonymisation.
- `Cairn/Core/StorageHistory.swift` and `StorageTransfer.swift`: local records include paths, sizes, timestamps and outcomes. Licence records use Keychain.
- Optional local AI-tool connection can expose storage results to the connected client, which may send them to its provider. The site does not equate a local socket with wholly local processing.
- Active HTML requests Google Fonts at `fonts.googleapis.com` and `fonts.gstatic.com`. The active source contains no analytics, signup, payment or support-submission form. Hosting logs remain unverified.
- No operator legal identity, controller address, retention promise, refund policy, invented support email or response-time promise was added. Privacy and Licensing are clearly labelled implementation/planning information pending owner-approved final policies.
