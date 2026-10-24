# Changelog

What changed in Cairn, newest first. Cairn has not had a public release yet, so entries are grouped by date and pull request rather than by version number. The app reports itself as 1.0.0, but no signed build has been published.

Known problems and their fixes live in [BUGS-AND-FIXES.md](BUGS-AND-FIXES.md).

## Waiting to be merged

These are finished or nearly finished in open pull requests. None of it is on `master` yet. Make room (moving files to an SSD or the cloud) is in PR #9.

### Website beam options (PR #6)

- A copy of the website with a light beam landing on the app screenshot, three hero layouts to choose from, a Wave hero to compare, and an optional beam in the footer. The original page is unchanged.
- The scroll-story page (`website/v2/story.html`), with a footer ready for buying: Download for Mac and Buy Cairn Pro.
- **Pro is £35.99, one time, with no trial.** The app's price line changes to match and the 14-day trial is removed, so Pro features need a key. The amount charged is set in Polar and needs changing there too.
- **Harder to crack.** The developer switch that turned Pro on with one Terminal command is gone from the app that is sold. The saved licence is sealed to the Mac it was activated on, so a hand-made or copied record no longer unlocks Pro, and dates in the future are refused. Pro also stays off in a copy of Cairn whose code has been changed.
- **Website screenshots of the real app.** `--showcase` captures every screen with the logo, sharp at Retina size, with sample numbers that match the website. The scroll-story page now uses them (`website/v2/assets/app-shot-*.webp`); the old mock-ups are kept. On phones the window starts at its left edge so the Cairn logo stays in view.
- **The Done screen no longer warns "No Put Back recorded"** for files that were deleted outright. Those are gone on purpose, so the amber line only counts items really left in the Trash without a record.
- **The review sheet fits its list.** A short list no longer leaves an empty band above the buttons; a long one still scrolls.

## 23 October 2026

### AI tools can clean (PR #7)

- AI coding tools linked to Cairn can **plan a clean and, if you allow it, run it**. This is off by default. Settings › AI tools has three choices: Off, Ask me each time, or Let them clean safe junk.
- Only safe, rebuildable items qualify. Plans list every item, expire after 15 minutes and can be used once.
- **Claude Code plugin** with `/cairn:status`, `/cairn:free-space` and `/cairn:projects`, plus a skill that steps in when a build fails with "no space left on device".
- **Gemini CLI extension** with the same commands.
- Both add-ons install from the public [Emotive-Impact-Studios/cairn-plugins](https://github.com/Emotive-Impact-Studios/cairn-plugins) repository, which is built from `integrations/` with `integrations/publish.sh`.
- **One-click install links** for Cursor and VS Code, for the website.

### Night look and honest numbers (PR #5)

- **New look across the whole app.** A calm dark "Night" style with one soft ice-blue accent, replacing the stones. Home, Clean, Review, Projects, Activity, Files, Apps, Mac health, Settings and External storage were all rebuilt to the approved Night screens.
- **Home** shows the space ready to free, the free space graph (brought back, with a dotted forecast line), a This Mac bar, what grew, AI coding tools with their logos and a "Connect" link, and an SSD pill when a drive is plugged in.
- **Calmer motion.** Screens switch without sliding, sections fade in without moving anything else, and the big number counts up cleanly.
- **Done screen** sits beside the sidebar instead of in a pop-up, says where the space went, and can empty that clean's items from the Trash. Past receipts open as their own page.
- **Honest reporting.** `cairn status` and the AI tool link now read freed space from cleanup receipts, and say "moved to the Trash" when the space has not actually been freed yet. The scan shows "Ready to free" separately from things that need you.
- **The command line works while the app is open** for read-only commands (`status`, `scan`, `categories`, `help`). Cleaning still needs the app closed.
- **Faster answers for AI tools.** Cairn remembers each scan for ten minutes within a session and can answer straight from the last scan.
- **Connecting AI tools prefers the installed app** in `/Applications` over a test build.
- **Two numbers on Home.** The big number is only what is ready to free in one click, and it counts live during a scan. A second line says how much more there is to look through yourself, and opens the new **Look through** page.
- **Look through** groups everything else Cairn found (videos, archives, installers, old downloads, app leftovers, project folders) with one tick per group. A group tick only takes plain files that go to the Trash; anything fragile is picked one by one.
- **Nothing counted twice.** A file that two scanners both find (an installer that is also an old download) is listed once, in the app, the command line and the AI tool link.
- **Sidebar dots** rise higher the more space is ready to free, appear slowly, and settle down after a clean. **Projects** numbers now match their button.
- **Small touches:** the scanning line shimmers, the menu bar icon is a disk gauge (amber when nearly full) and builds the Cairn stone by stone during a scan, the free-space bar glows over freed space, an optional finish chime (off by default), and a friendly line on each receipt.
- **15 AI coding tools** can be connected, up from 7, including Cline, Roo Code, Kiro, Amazon Q, Junie, LM Studio, Qwen Code and Amp.
- **Full-width layout:** the content runs to the window edge with a flat sidebar.
- **Safer cleaning:** cleaning needs a click (Return no longer triggers it), the review says plainly that caches and build files can't be put back, and Cairn skips its own app, folders a running program uses, and build folders changed in the last 15 minutes.

### Cleaning coverage (PR #10)

- More one-click items, kept honest: idle Python environments, older Android NDKs, and installers for apps already installed (these go to the Trash, never straight to deletion).
- Git clean-up shows the estimated saving rather than the whole `.git` size.
- New finds: old simulator runtimes, extra Xcode copies, OrbStack and Colima disks, Mail attachment copies, `.pub-cache` and Conda packages, and leftovers from apps removed with Cairn.

## 21 October 2026

### One-click "Connect AI tools" (PR #4)

- **Settings › AI tools** lists Claude Code, Claude Desktop, Codex, Cursor, Gemini CLI, VS Code and Windsurf, shows whether each is connected, and connects or disconnects with one click.
- Your existing settings files are kept intact, and a backup of each is made the first time.

### Projects, AI tool link, menu bar and SSD offload (PR #2)

- **Projects** groups build output and dependencies by coding project, shows how long each has been idle, and lets you clear the ones you are not using.
- **`cairn mcp`** lets AI coding tools such as Claude Code ask Cairn how much space is free, what can be cleared and which projects are idle. It cannot delete anything.
- **Menu bar** shows space ready to free, idle projects and the biggest recent growth.
- **SSD offload** moves local AI models (Ollama, LM Studio) and Xcode archives to an encrypted external drive, checks every file, and leaves a link so the apps keep working. They can be brought back.
- Automatic build checks on macOS were added, and about 3,300 lines of unused old screens were removed.

### New look with verified results (PR #3)

- Home opens with the space ready to free and one "Review and free" button.
- Review groups items by tool with a simple label: Ready, Close app first, or Needs you.
- The result screen says "Freed X GB" and "Verified" when macOS measured the gain.
- Activity gains a 30-day free space chart.
- The sidebar went down to six places, and light mode was added.

### Cairn frees real space (PR #1)

- **Three ways to remove** in Settings › Cleaning: Smart (the default: deletes rebuildable caches straight away and sends personal files to the Trash), Delete now, and Move to Trash.
- **Tools clean themselves.** Docker, pnpm, Go, Homebrew, conda, Xcode simulators, git and Time Machine snapshots are cleaned with their own commands. Commands that would destroy data never run.
- Cairn can empty the Trash, and delete from the Trash the items it put there.
- Rebuildable caches, build output and `node_modules` can now be deleted. AI chat history, Documents, Photos, iCloud, Mail, Keychains, `.git` and `.ssh` stay protected.

## 1 October 2026

- Optional growth suggestions and safer storage inspection.
- The website moved into its own `website/` folder.
- Documentation, diagnostics and evidence reorganised.

## 29 September 2026

- A measured "make room" journey with a written record of every action.
- Interrupted actions can be reviewed without running them again.
- Reviewed sources and private storage records are guarded.
- Free space refreshes after you clean up in Finder.

## 26 July 2026

- **`cairn` command line**: `status`, `scan`, `clean --safe` and `categories`, with `--json` output.
- **Smart Triggers** clean a developer tool's caches when you quit it, and a **storage forecast** estimates when you will run out.
- Developer project scanning became 3.2 times faster, and a menu bar total was added.
- Fixed an app-wide freeze caused by the menu bar item, and limited memory use while moving between screens.
- First full version of the app: scanning engine, safety guard and premium design pass.
