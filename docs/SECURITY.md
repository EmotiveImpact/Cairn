# How Cairn protects itself and your files

Written 23 October 2026, before the first signed download. Plain English first; the file and function names are there for whoever works on the code next.

## The honest starting point

No Mac app is impossible to crack or misuse. Anything that runs on someone's own Mac can, with enough skill and time, be taken apart and changed. What Cairn can do is:

1. Make sure the copy people download is exactly the one Emotive Impact built, and that macOS refuses to run it if anyone changes it.
2. Make sure nothing slipped into Cairn can borrow its Full Disk Access.
3. Make sure Cairn never deletes something it should not, even when another program or an AI tool tries to trick it.
4. Make the licence check hard enough to beat that buying it for £35.99 is far easier than cracking it.

The first three protect customers and matter most. The fourth protects sales and is a deterrent rather than a wall: a determined cracker who rewrites the app can still get past it, as they can with every paid Mac app.

## 1. The download cannot be changed

- `build_release.sh` signs Cairn with the Developer ID certificate (team FC88M2P4F9), turns on Apple's **hardened runtime**, has Apple **notarise** it and staples the result.
- The build now **stops** if the hardened runtime is off, or if any entitlement that weakens it is present (`disable-library-validation`, `allow-dyld-environment-variables`, `allow-unsigned-executable-memory`, `allow-jit`, `disable-executable-page-protection`, `get-task-allow`). `Cairn/Cairn-dist.entitlements` must stay empty.
- With the hardened runtime and no exceptions, macOS refuses to load code into Cairn that Apple or we did not sign, ignores `DYLD_*` tricks and stops other programs attaching to it.
- If anyone edits a file inside Cairn.app, the signature no longer matches. macOS will not open the downloaded copy, and it will not hand the changed copy Cairn's Full Disk Access, because that permission belongs to our signature.

## 2. Cairn checks itself

`AppIntegrity.signedByUs()` in `Cairn/Licensing/Licensing.swift` runs once, away from the main thread. It checks that:

- the running code is Cairn (`com.emotiveimpact.cairn`), signed with a **Developer ID** certificate from our team;
- the whole app on disk still matches its signature: every architecture, `Info.plist` and every resource;
- the hardened runtime is on.

If any check fails, Pro stays off and Settings says the copy has been changed. Debug builds skip the check.

## 3. Cleaning cannot be turned against you

Everything that removes a file passes `SafePaths` and `Cleaner`. This pass added:

- **Capital letters no longer dodge the protected list.** The Mac's disk treats `~/library/keychains` and `~/Library/Keychains` as the same folder, so every protected location, AI chat folder and Settings exclusion is now matched ignoring case.
- **Both spellings of system folders.** macOS shows some folders with and without `/private`. `/var/db`, `/private/var/db`, `/etc`, `/private/etc`, `/var/root`, `/dev` and `/cores` are all refused, and the protected list is checked against both the path as given and where it really leads.
- **No last-second swaps.** Cairn checks the item again immediately before moving it, after the slow safety walk. After the move it checks that what reached the Trash is the very file it scanned. If something was swapped in at the last instant (the usual way a link attack works), Cairn puts it straight back and deletes nothing.
- **Permission changes never follow links.** When Cairn has to unlock a read-only folder to delete it, it uses a call that never follows a link to somewhere else.
- **Tools Cairn runs are pinned.** A program Cairn starts shares Cairn's Full Disk Access, so `tmutil`, `xcrun`, `diskutil` and `pgrep` always come from their macOS system folders, never a look-alike earlier on your PATH. Other tools (docker, npm, pnpm and so on) must be plain names, and Cairn refuses a program owned by another user or writable by everyone.

## 4. AI tools stay inside their lane

The `cairn mcp` link lets AI coding tools measure, plan and, if you allow it, clean safe rebuildable junk. It was already careful: plans list every item, run once, expire after 15 minutes, and the app re-checks every item through the same safety guard.

The gap was the on/off switch. It lived in an ordinary preference that any program, or an AI tool told to run `defaults write`, could flip to "Let them clean". Now the choice is saved with a seal made from a secret only Cairn can read from your login Keychain (`Cairn/Core/SettingsSeal.swift`). A value changed outside Cairn has no valid seal, so it counts as **Off**, and Settings shows Off and explains why.

Only programs running as you can reach the link at all (`getpeereid` on a socket in Cairn's private folder).

## 5. The licence

- There is **no trial** and no developer switch in the app that is sold. The old `cairn.devPro` setting exists only in debug builds.
- Pro is activated online with Polar against this Mac. The saved record is **sealed to this Mac** and to what Polar last said, so a record typed in by hand, edited or copied from another Mac does not unlock Pro. A date in the future is refused. Pro keeps working offline for 14 days, then needs one check with Polar.
- Pro stays off in a changed copy (section 2).

What this does not stop: someone who rewrites the app's code to skip the check, and is happy to run it without our signature and without Full Disk Access. That is true of every paid Mac app. The answer is that £35.99 is cheaper than the effort.

**Needs doing in Polar (Edem):**

- Set the price to £35.99.
- On the licence key benefit, set an **activation limit** (2 or 3 Macs per key is common). That stops one key being shared around.

**Worth knowing:** today Pro does not yet unlock anything the free version cannot do. Before taking payments, decide which features Pro unlocks, and make the cleaning code (not just the screens) check it.

## 6. Signed updates (when Sparkle is added)

Sparkle is the standard way Mac apps update themselves. Set it up like this so nobody can push a fake update:

1. Run Sparkle's `generate_keys` once on Edem's Mac. The **private** EdDSA key stays in that Mac's Keychain, with a backup in a password manager. It never goes in the repository, CI or a shared folder.
2. Put the **public** key in `Cairn/Info.plist` as `SUPublicEDKey`. Sparkle then refuses any update not signed with the private key.
3. Serve the update feed and downloads over **HTTPS** only (`SUFeedURL`).
4. Turn on `SUVerifyUpdateBeforeExtraction` and `SURequireSignedFeed`, so Sparkle checks the download before unpacking it and the feed itself is signed. `generate_appcast` signs the feed and release notes; re-run it after any edit.
5. Sign and notarise every update with `build_release.sh`. Sparkle also checks that the new version carries the same Apple signature as the one installed.

With both the EdDSA signature and Apple's signature required, a fake update would need our private key **and** our Developer ID certificate.

## Known limits, on purpose

- **Your shell start-up files.** To find tools installed with nvm, asdf or mise, Cairn asks your login shell where they are, which runs your `.zshrc`. A program that can already edit your shell files can already run as you; pinning system tools and refusing world-writable programs keeps the risk small.
- **Certificate pinning for Polar** is not used. Pinning breaks every customer's licence the day Polar changes certificates. Anyone able to fake Polar's server on their own Mac only fools their own copy, and only for Pro.
- **The AI tool link accepts any program running as you.** It cannot be narrowed to signed callers usefully, because anything running as you can start `cairn mcp` itself. The protection is that the link can only ask; the app decides, using the sealed setting and the safety guard.
