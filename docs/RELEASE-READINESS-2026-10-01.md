# Cairn: completion and Mac App Store readiness

Checked against current source and Apple documentation on 1 October 2026. This is a release plan, not evidence of App Store eligibility or approval.

## Current functionality
Native overview/history, reviewed file cleanup, duplicate verification, app-bundle removal, supported health findings, exact-path recovery, durable run receipts, opt-in observation/reserve alerts, and verified external copies exist. Build, fixture and bounded native stress evidence is recorded in artifacts. Broad CLI cleanup, permanent Trash deletion and all generic tool commands are disabled in the executor. External copies keep sources and do not free internal capacity.

## Remaining before a credible beta
- Independent review of current dirty/untracked implementation; resolve findings.
- Real first-run permissions, restart, low-space recovery, sleep/wake and notification acceptance; sustained machine/energy test.
- Keyboard, VoiceOver, disabled states and minimum-window acceptance for the new shared controls, including native custom-drawn segments.
- Validate the guided selected-file → Trash → explicit Finder deletion → capacity recheck journey using disposable data. Do not call this an automatic reclaim adapter.
- Privacy declarations, support/privacy policy, consented diagnostic plan, distribution packaging and supported architecture/OS validation.

## Later product features, not silently completed
Tool-managed immediate reclaim remains uncertified (npm writer contract unresolved). Managed SSD relocation and opt-in unattended rules remain unbuilt. Copy verification is not relocation or backup. These need their own validated scope and recovery guarantees. Updater work depends on distribution: Store updates for Store builds; a separately tested signed updater for direct builds.

## App Store feasibility
The current empty distribution entitlement file is intentionally unsandboxed and is not a Store target. Apple guideline 2.4.5 requires sandboxing and Store-delivered updates, and restricts elevated privileges and dependencies on optional installed technologies. Do not assume an external helper or Full Disk Access removes sandbox boundaries.

Sandboxed applications can use user-selected files/folders, including recursive folder access, and persist access with security-scoped bookmarks. Other filesystem/privacy restrictions still apply. Therefore file inventory, large files, duplicate review and selected-folder copies are plausible Store capabilities, not guaranteed accepted capabilities. Test Trash and Put Back permissions explicitly: access to an original folder must not be assumed to grant later access to a moved Trash item.

Required technical experiment: separate Store configuration; allowed folder selection and persistent grant registry; scanners restricted to granted roots; container-local evidence/recovery stores; stale/revoked bookmark handling; denied child-folder coverage; source/destination external grants; reviewed Trash/recovery and relaunch tests. No blanket home selection to promise unrestricted access. Preserve the existing direct build and history. Store/direct data migration and coexistence need deliberate design.

Feature decisions follow those results. Tool invocation, broad cross-app cache maintenance, app removal, monitoring and tool-settings relocation each need separate capability evidence. Do not preemptively remove the whole product or advertise whole-Mac coverage from a selected-folder scan.

## Submission steps
Create the macOS app record and distribution provisioning; implement/test sandbox target; archive and validate upload with a currently accepted Xcode/SDK; supply screenshots, description, support/privacy URLs, privacy answers, age rating and review instructions; test through TestFlight; choose release method and submit for review. No account changes, upload or public submission performed here.

Recommendation: finish the direct-build beta acceptance work while prototyping sandbox access separately in the same codebase. Decide the Store feature set from that evidence. Do not build payments or a direct updater as a prerequisite for proving sandbox feasibility.

Sources:
- https://developer.apple.com/app-store/review/guidelines/ (2.4.5)
- https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox
- https://developer.apple.com/documentation/Xcode/preparing-your-app-for-distribution
- https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/
