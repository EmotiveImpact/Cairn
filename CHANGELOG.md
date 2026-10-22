# Changelog

What changed in Cairn, newest first. Cairn has not had a public release yet, so entries are grouped by date and pull request rather than by version number. The app reports itself as 1.0.0, but no signed build has been published.

Known problems and their fixes live in [BUGS-AND-FIXES.md](BUGS-AND-FIXES.md).

## Waiting to be merged

These are finished or nearly finished in open pull requests. None of it is on `master` yet.

### Night look and honest numbers (PR #5)

- **New look across the whole app.** A calm dark "Night" style with one soft ice-blue accent, replacing the stones. Home, Clean, Review, Projects, Activity, Files, Apps, Mac health, Settings and External storage were all rebuilt to the approved Night screens.
- **Home** shows the space ready to free, the free space graph (brought back, with a dotted forecast line), a This Mac bar, what grew, AI coding tools with their logos and a "Connect" link, and an SSD pill when a drive is plugged in.
- **Calmer motion.** Screens switch without sliding, sections fade in without moving anything else, and the big number counts up cleanly.
- **Done screen** sits beside the sidebar instead of in a pop-up, says where the space went, and can empty that clean's items from the Trash. Past receipts open as their own page.
- **Honest reporting.** `cairn status` and the AI tool link now read freed space from cleanup receipts, and say "moved to the Trash" when the space has not actually been freed yet. The scan shows "Ready to free" separately from things that need you.
- **The command line works while the app is open** for read-only commands (`status`, `scan`, `categories`, `help`). Cleaning still needs the app closed.
- **Faster answers for AI tools.** Cairn remembers each scan for ten minutes within a session and can answer straight from the last scan.
- **Connecting AI tools prefers the installed app** in `/Applications` over a test build.

### AI tools can clean (PR #7)

- AI coding tools linked to Cairn can **plan a clean and, if you allow it, run it**. This is off by default. Settings › AI tools has three choices: Off, Ask me each time, or Let them clean safe junk.
- Only safe, rebuildable items qualify. Plans list every item, expire after 15 minutes and can be used once.
- **Claude Code plugin** with `/cairn:status`, `/cairn:free-space` and `/cairn:projects`, plus a skill that steps in when a build fails with "no space left on device".
- **Gemini CLI extension** with the same commands.
- **One-click install links** for Cursor and VS Code, for the website.

### Website beam options (PR #6)

- A copy of the website with a light beam landing on the app screenshot, three hero layouts to choose from, a Wave hero to compare, and an optional beam in the footer. The original page is unchanged.

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
