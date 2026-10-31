# Changelog

What changed in Cairn, newest first. Cairn has not had a public release yet, so entries are grouped by date and pull request rather than by version number. The app reports itself as 1.0.0, but no signed build has been published.

Known problems and their fixes live in [BUGS-AND-FIXES.md](BUGS-AND-FIXES.md).

## 31 October 2026

### Fast-drop alert and a wider watch list

- **An alert when space goes fast.** The low-space alert only spoke once you were already below your reserve, so losing 20 GB in an hour while still above it said nothing. Settings › Monitoring now has **Alert when space drops fast** (off until you turn it on). While Cairn is open it checks free space every five minutes. If 5 GB or more goes within half an hour, or at that rate your reserve is less than two hours away, it quickly measures the usual places (30 seconds at most, quick ones first), compares each with its last size, and sends one notification such as "12.4 GB less free space in 25 minutes. Swap (memory kept on disk) grew by 6 GB and Docker disk grew by 4.2 GB." If none of them grew, it says the space most likely went somewhere Cairn doesn't watch, and if some places had no earlier size yet it says it can't tell rather than guessing. To have something to compare with, it keeps those places' sizes up to date while it's open. At most one alert an hour. During quiet hours the report still appears on Changes but no notification is sent, and a drop still going after 08:00 gets its notification then.
- **What it found stays on Changes** for a day, with when each place started growing. Each figure covers its own time, so they aren't added up to explain the whole drop. Nothing is removed, and swap and snapshots never become something to clean.
- **Swap and local Time Machine snapshots on Changes.** Known locations now starts with how big swap is and how many local snapshots there are, read straight from macOS, with a line saying macOS or Time Machine manages them.
- **Ten more places watched** for growth: iPhone and iPad simulators, Ollama, Hugging Face and LM Studio models, Docker's disk, OrbStack and Colima disks, Claude Code data (`~/.claude`), Cursor worktrees and Conductor workspaces. Claude Code data, worktrees and the virtual machine disks are watch-only: measuring them never makes anything inside them cleanable, and the worktree protection is unchanged. Docker and OrbStack disks are only measured with Full Disk Access, so macOS never asks about other apps' data in the background. Codex worktrees are already covered by Codex local data. Claude Code's own `--worktree` folders sit inside each project, so they aren't on the list yet.
- **Each watched place keeps its own history.** Saved readings are now capped per place (48 each) as well as overall, so a place that rarely changes, such as a model folder, keeps the size a later reading is compared with.
- **Build scripts tidy `dist/`.** `build_local.sh` and `build_release.sh` now keep this build and the two before it (set `KEEP_BUILDS` to change that) and remove older ones. A failed build is kept for a day so its error can be read, a build whose app is open is never touched, and nothing outside `dist/local.*` or `dist/release.*` is removed. The CI packaging check covers all three.
- Not yet tried on a real Mac: a real fast drop, the notification and the Changes card with live data. CI checks the rules, the wording, the watch list and the build script tidy-up with test data.

## 27 October 2026

Every open pull request landed today: #18 on its own, then #11, #12, #14, #15 and #6 together through PR #19, which fixed where they clashed with each other and with #16 and #17.

### Apple Intelligence off switch (PR #18)

- **Apple Intelligence page** under Clean. macOS 27 downloads 12 to 30 GB of Apple Intelligence models and has no single off switch. Cairn measures each set of models (main models, image models, Xcode code completion, Photos Clean Up, Spatial Photos), lets you tick which go, and lists what stops working before anything changes. Xcode code completion stays on by default when Xcode is installed.
- **How it turns off.** Cairn never deletes a file in `/System`. It makes a profile that System Settings asks you to approve; the profile switches the features off and stops their models downloading again. Then Cairn asks macOS to remove the models itself.
- **Undo.** One button opens System Settings to remove the profile, and everything comes back on. macOS downloads the models again the first time a feature needs them.
- **Removing Cairn.** If Cairn goes in the Bin while the profile is still on, it offers to open System Settings so Apple Intelligence can be turned back on first.
- **Measuring.** Cairn reads the sizes from macOS's own list of models. If that list comes back in a form it can't read, it asks each set for its size instead, and shows a dash when neither answers.
- Removing the models uses a part of macOS Apple doesn't publish, so a macOS update can stop it working. If it does, Cairn says so and removes nothing. It has been checked on a Mac without Apple Intelligence (macOS 14.5), where the page says so; it still needs a run on a Mac that has it.

### Sleeping projects, AI models, disk map and cleaning rules (PR #14)

- **Put a project to sleep.** Projects shows each repository's git state (branch, changed files, commits not pushed). An idle project with work that exists only on this Mac gets an amber "Not pushed" label. "Put to sleep" selects the project's rebuildable output for the normal review and keeps a note with the command that brings it back, such as `pnpm install`. Sleeping projects are listed under Asleep with a "Copy wake-up command" button. Cairn never runs that command itself.
- **AI models page.** Clean › AI Models lists every model from Ollama, LM Studio, Hugging Face, GPT4All, Jan, Whisper, PyTorch, ComfyUI, Stable Diffusion, Fooocus, InvokeAI, DiffusionBee and Draw Things, with its size and the date it was downloaded. Nothing is picked for you. A model can go to the Trash after a confirmation; Ollama models share files, so Cairn gives you the `ollama rm` command instead.
- **Disk map.** Files › Disk map draws the whole disk as one bar: macOS, System Data, apps, coding, your files and free space, with what is inside the part you choose. System Data is broken into swap, app caches, app support data, containers, Xcode and simulators, Mail, Messages, logs, the shared Library and what Cairn could not measure (such as local Time Machine snapshots). It only reads sizes and stops after two minutes.
- **Cleaning rules you approve once.** Settings › Rules has six rules: old Xcode build files, package manager caches, build output in idle projects, browser caches, app caches and old logs. All start off. Turning one on measures and shows what it would clear today before you approve it. Each has a schedule, an age, and a size limit per run, can be paused, uses the same safety checks and receipts as a normal clean, and only takes items an AI tool would also be allowed to clean. The same page has the single low-space warning from Monitoring.
- **AI tool link for Zed, opencode and Goose, and Cursor files with comments.** Cairn now connects to 18 tools. Settings files with comments (Cursor, Zed, opencode) are edited in place so the comments stay. Goose's YAML file gets one `cairn` extension and nothing else changes.

### Messages attachments (PR #15)

- Cairn now shows how much space **Messages attachments** take, split into videos, photos and other files, with how much is over a year old. It shows them in the scan and on Make room.
- Cairn never removes them itself, because deleting the files by hand leaves gaps in chats. A **Review in Storage** button opens System Settings, where Messages lists the largest attachments and deletes them properly. Messages stays on the protected list.
- Measuring them needs Full Disk Access. Without it, the row is simply left out.
- Make room's Bin choices now go through the normal review, limited to just those items.

### Review numbers that match, and no item that always fails (PR #12)

- The review now shows the same total as the button you pressed. A mix of caches and your own files reads "Clean 1.31 GB", with a line saying how much is freed straight away and how much goes to the Trash. Before, it showed only the part freed straight away ("Free 188.5 MB"), which looked like most of the selection had been dropped.
- Cairn no longer lists anything its own safety guard will refuse, such as a build folder inside `~/.cursor`. That item could be ticked and counted, then failed on every clean.
- Large Files reviews only the files picked on that screen, and its button shows their size.
- The Clean pages' total includes picks on other pages, matching the button.
- If the review's button can't be pressed (a scan or another clean is running), the sheet says why.

### Clean-up and hardening (PR #11)

- **About 1,100 lines of unused code removed:** old item rows, the old disk map, missions, the old sidebar device card, hero art and helpers nothing called. Two unused Mac pictures and three tool icons leave the app too.
- **Deleting is harder to trick.** Protected folders are matched whatever the capital letters, system folders are refused under both of macOS's spellings, an item swapped at the last instant is put back instead of deleted, and permission changes never follow a link. Apple's own caches and Ollama's shared store (from PR #16) are matched whatever the capital letters too.
- **Tools Cairn runs are pinned.** macOS tools always come from their system folder, other tool names must be plain names, and a program anyone could have replaced is refused.
- **AI tools cannot switch their own cleaning on.** The setting is sealed with a Keychain secret, so a `defaults write` from outside Cairn counts as Off.
- **Signature check covers the whole app** (every file and the hardened runtime), and the release build stops if the hardened runtime is off or an unsafe entitlement is present.
- **Pro is £35.99, one time, with no trial.** The 14-day trial is removed, so Pro features need a key. The amount charged is set in Polar and needs changing there too.
- **Harder to crack.** The developer switch that turned Pro on with one Terminal command is gone from the app that is sold. The saved licence is sealed to the Mac it was activated on, so a hand-made or copied record no longer unlocks Pro, and dates in the future are refused. Pro also stays off in a copy of Cairn whose code has been changed.
- **The Buy link and the share card read cairnmac.com.**
- [docs/SECURITY.md](docs/SECURITY.md) explains what is protected, what is realistic, the Polar settings to change, and how to set up signed Sparkle updates.

### Website beam options and real app screenshots (PR #6)

- A copy of the website with a light beam landing on the app screenshot, three hero layouts to choose from, a Wave hero to compare, and an optional beam in the footer. The original page is unchanged.
- The scroll-story page (`website/v2/story.html`), with a footer ready for buying: Download for Mac and Buy Cairn Pro.
- **Website screenshots of the real app.** `--showcase` captures every screen with the logo, sharp at Retina size, with sample numbers that match the website. The scroll-story page now uses them (`website/v2/assets/app-shot-*.webp`); the old mock-ups are kept. On phones the window starts at its left edge so the Cairn logo stays in view.
- **The Done screen no longer warns "No Put Back recorded"** for files that were deleted outright. Those are gone on purpose, so the amber line only counts items really left in the Trash without a record.
- **The review sheet fits its list.** A short list no longer leaves an empty band above the buttons; a long one still scrolls.

### Everything from the research (PR #17)

- **More junk found.** Test browsers from Playwright, Puppeteer and Cypress, Electron and Bazel downloads, Unity caches, Watchman state, older Ruby gem versions, old Command Line Tools and SDKs, SwiftUI preview simulators and Lightroom previews. The Logic sound library is sized as advice, and Adobe caches say where to set a size limit.
- **Games page.** Steam, Epic and CrossOver games and games from the App Store, with when each was last played. Folders a launcher has forgotten are marked "Left behind" and can go in the Bin; everything else is uninstalled in its own launcher.
- **Chat apps page.** How much WhatsApp and Telegram keep in photos and videos, with a button to open each app's own storage screen. Cairn never deletes chats.
- **"I need X GB".** Type the space you need, or pick macOS update, Xcode or Premiere, and Cairn picks the safest set that gets there, caches first, stopping once there is enough. Untick a row and it plans again.
- **Apps page.** Who made each app (from its signature), where it came from (App Store, Homebrew, downloaded or part of macOS), when it was last opened, and an "Intel only" filter for apps that stop working in macOS 28.
- **Leftovers when an app goes in the Bin.** Drag an app to the Bin in Finder and Cairn's menu bar shows what it left behind, to review. Can be turned off in Settings › General.
- **Faster Duplicates.** Hard links are no longer counted as copies, files are compared by their first part before a full read, and fingerprints are remembered between scans. The page now matches the approved design, suggests which copy to keep, and points to Apple's own Duplicates album for photos.
- **Share your clean.** The Done screen has a Share button with a picture of the space freed, the three biggest kinds of thing cleared (can be hidden) and the site address, cairnmac.com, to copy, save or share. It never shows file or folder names.
- **Held-back space explained.** When Cairn deleted more than free space rose by, the Done screen says how much has not shown up yet, and that macOS lets it go from snapshots or purgeable space on its own.
- **Docker's real size.** Docker's disk shows what it really uses next to the maximum Finder shows.
- **What Cairn looks for.** Settings › Scanning lists every place Cairn checks, written from the app itself, and `cairn rules` prints it as Markdown. The published copy is [docs/WHAT-CAIRN-LOOKS-FOR.md](docs/WHAT-CAIRN-LOOKS-FOR.md).
- **Cleaning rules updates (off for now).** Cairn can take new cache folders to look in from a list signed with Cairn's key, without a new version. It stays off until the key ships. A rule can only name one app's cache folder, and everything still goes through review and the Bin.
- **Send a report.** Settings › About shows the whole report first, to change or add to. It holds no file names, folder names or account name. Copy works now; Email appears once a support address is set.

## 25 October 2026

### Never touch Apple's own caches (PR #16)

- Cairn no longer lists or removes **Apple's own caches** in `~/Library/Caches`. A folder there can look like junk but hold something macOS needs: the Neural Engine keeps its compiled models in one, and clearing it breaks text recognition until a restart. Only Apple app caches the app rebuilds itself stay cleanable (Safari, Final Cut, Motion, Compressor, Logic, Xcode).
- **macOS Install Data** (an update in progress) is off limits, whatever its size.
- **Ollama models** can only be removed whole or with `ollama rm`. Ollama shares files between models, so removing part of its store could break another model.
- The same rules are checked again just before anything is removed, not only when the list is built.

## 24 October 2026

### Make room (PR #9)

- **One page to free space three ways.** Each big item gets one choice: the Bin, an external SSD or the cloud, with Cairn's suggestion picked. A footer shows the total and where it goes, and everything happens behind one confirmation.
- **Moves to a drive that really free space.** Every file is checked as it is copied and read back from the drive before the original goes. App data keeps a link so the app still finds it; your own files move without one. If Cairn stops mid-move, it finishes the move or puts the original back.
- **More can move:** Hugging Face models, iOS simulators, the Android SDK and emulators, Xcode build files, Docker (through its own setting, checked that it starts again) and your own files and folders.
- **Bring back** asks whether to remove the drive copy or keep it as a dated spare. Drives are known by their ID, and the menu bar names the drive to plug in when moved app data is away. Drives without a password get a warning before your own files go to them.
- **iPhone backups** can move to a drive or go to the Bin, never while a backup is running.
- **Cloud:** keep uploaded files online only, clear cloud caches and old sync folders, or move your own files to the cloud. Cairn waits for the upload and only then sends the original to the Bin, if it hasn't changed.

## 23 October 2026

### The rounded page is back (PR #13)

- Chosen from three layouts: the content sits in a rounded card inside the sidebar's frame again, and the sidebar dots still rise as before.

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
