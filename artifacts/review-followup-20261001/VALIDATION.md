# Review follow-up — 1 October 2026

## Implemented
- Receipt storage rejects dangling symbolic links both at initial load and after loading an absent file. Previously fileExists followed the dangling link and treated it as absent, allowing the link itself to be replaced. Reads now use a no-follow descriptor, reject nonregular files, and cap bytes actually read at 8 MiB plus one sentinel byte. Existing corrupt/conflicting history remains fail-closed.
- Startup rejects conflicting diagnostic/CLI modes. Previously `--readonlycheck --safetycheck` could borrow the isolated-mode lease exemption before dispatching the live read-only scanner. Now conflicting modes exit 64 before touching live state.
- Activity offers an inline disclosure explaining individual permanent deletion in Finder using the existing per-item Show in Trash controls. It explicitly explains loss of Put Back, avoids blanket Empty Trash advice, links Apple documentation, and measures signed same-volume capacity change since opening Activity. Check available space also refreshes recovery availability.

## Verified
- Debug build and diff whitespace checks passed.
- Lifecycle suite passed including three added dangling-link assertions, restart/recovery and bounded repeated scans.
- Reliability, workspace and safety suites passed.
- After the isolated startup change, final build passed; three conflicting mode combinations all exited 64; standalone safety mode passed.
- Staged app signed with existing Developer ID and strict verification passed. Atomically replaced dist/Cairn.app; predecessor retained in this directory. Existing running app was not stopped.

## Boundaries
This is a focused in-task code review, not independent model signoff or full PRD certification. The new disclosure compiled but has not received rendered visual/VoiceOver acceptance. No personal file was removed, no Finder permanent deletion was executed, and no actual reclaim amount is claimed. The guided route is suitable for the beta journey; it does not certify an automatic reclaim adapter. npm remains guidance-only due to the unresolved writer contract. Updates, payments, managed relocation and unattended cleanup remain outside this pass. Same-user adversarial replacement between receipt validation and rename and forced-power-loss durability are not certified by these fixtures.

Apple reference: https://support.apple.com/guide/mac-help/mchlp1093/mac — documents Control-click → Delete Immediately for an individual Trash item. Reviewed 1 October 2026.
