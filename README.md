# Cairn

**Cairn finds the junk in your coding projects, and works with your AI coding tools.**

Cairn is a Mac app that shows you what is filling your disk and frees space safely. It is built for people who write code: it knows which caches, build folders and downloaded packages can be rebuilt, which projects you have not touched in weeks, and which things are yours and must never be touched.

> **Status: not released yet.** There is no public download. Cairn is being tested on one Mac. See [CHANGELOG.md](CHANGELOG.md) for what has changed and [BUGS-AND-FIXES.md](BUGS-AND-FIXES.md) for known problems.

## What Cairn does

- **Shows what you can free right now.** Home leads with one number: the space that is safe to free with one click, kept separate from things that need you to decide.
- **Finds junk in coding projects.** Build output, `node_modules`, Xcode leftovers, package caches and simulators, grouped by project, with how long each project has been idle.
- **Cleans each tool the proper way.** Docker, Homebrew, pnpm, Go, conda, git and Xcode simulators are cleaned with their own commands, so nothing breaks.
- **Proves what it freed.** Every clean leaves a receipt. When macOS confirms the free space went up, the receipt says Verified.
- **Keeps watch from the menu bar.** It shows space ready to free, idle projects and anything that has grown fast.
- **Makes room three ways.** The Make room page gives each big item one choice: the Bin, an external SSD or the cloud. Moves to a drive check every file before the original goes, and app data keeps a link so the app still finds it. iPhone backups, simulators, Docker, AI models and your own folders can all move, and come back later.
- **Plans the space you need.** Type how much room you need, or pick a macOS update, Xcode or Premiere, and Cairn picks the safest set that gets there, caches first.
- **Knows games and chat apps.** A Games page finds Steam, Epic and CrossOver games and the ones a launcher left behind. A Chat apps page measures WhatsApp and Telegram and opens their own storage screens; Cairn never deletes chats.
- **Puts idle projects to sleep.** Projects shows each repository's git state and warns about work that exists only on this Mac. Put a project to sleep and Cairn clears what it can rebuild and keeps a note of the command that brings it back.
- **Lists your local AI models.** Ollama, LM Studio, Hugging Face, Whisper, ComfyUI and more, with their sizes, and nothing picked for you.
- **Turns Apple Intelligence off, reversibly.** macOS 27 downloads 12 to 30 GB of Apple Intelligence models with no off switch. Cairn measures them, lets you choose which go, lists what stops working, and turns them off through a profile you approve in System Settings. One Undo brings everything back.
- **Maps the whole disk.** One bar shows macOS, System Data, apps, coding, your files and free space, with System Data broken down.
- **Runs cleaning rules you approve once**, such as old Xcode build files or package caches, on a schedule with a size limit, each run leaving a receipt.
- **Also covers the rest of your Mac**: large and old files, duplicates, apps (who made each one, when it was last opened, and what it leaves behind when it goes in the Bin) and general Mac health. Messages attachments are measured and reviewed in Apple's own Storage screen; Cairn never deletes them.

## Works with your AI coding tools

Cairn can link to AI coding tools that run on your Mac, so they can check your disk and tell you what can be freed. Connect them in one click from **Settings › AI tools**.

Supported: **Claude Code, Claude Desktop, Codex, Cursor, Gemini CLI, VS Code, Windsurf, Zed, opencode and Goose**, plus Cline, Roo Code, Kiro, Amazon Q, JetBrains Junie, LM Studio, Qwen Code and Amp.

Out of the box, AI tools can only look. You can also let them clean in **Settings › AI tools**: Off (the default), Ask me each time, or Let them clean safe junk. Only safe, rebuildable items qualify, and every plan lists each item, expires after 15 minutes and can be used once.

There is a **Claude Code plugin** (`/cairn:status`, `/cairn:free-space`, `/cairn:projects`, and a skill for "no space left on device") and a **Gemini CLI extension** with the same commands:

```sh
/plugin marketplace add Emotive-Impact-Studios/cairn-plugins
/plugin install cairn@cairn
gemini extensions install https://github.com/Emotive-Impact-Studios/cairn-plugins
```

Setup details are in [docs/CLAUDE-CODE.md](docs/CLAUDE-CODE.md).

## Keeping your things safe

- **You see everything first.** Every clean shows the exact files, their sizes and any command before anything runs.
- **You choose how things are removed** in each cleanup review, with a default in Settings › Cleaning. **Smart** deletes eligible rebuildable data and sends eligible personal files to Trash. **Delete now** requires acknowledgement for personal files; protected or unsupported items remain blocked. **Move to Trash** retains supported files for Put Back while they remain available. Trash does not immediately free space; receipts distinguish file-size estimates from measured capacity changes.
- **Some things are always off limits**, whatever you choose: system files, Apple's own caches, a macOS update in progress, passwords and keychains, Mail, Messages, Photos, iCloud, your source code history (`.git`), SSH keys and AI chat history.
- **Cleanup commands are restricted.** Destructive commands such as removing Docker volumes are blocked; permitted commands still appear in the review before execution.
- **Files are checked again** just before each action, in case anything changed since the scan.

## What's next

The actionable queue is in [the Claude handoff roadmap](docs/ROADMAP-CLAUDE.md).
Start with the installed Mac build and runtime acceptance gates, then release
preparation. The roadmap separates source implementation, checks actually run,
and work that still needs hardware, owner decisions or explicit authorization.

## For developers

Cairn is a native SwiftUI and AppKit app for macOS 14 or later. It is distributed directly, not through the Mac App Store, and is not sandboxed.

### Build and check

Needs a Swift toolchain on macOS. Recent checks used Swift 6.0.3 on Apple silicon. SQLite comes with macOS, and there are no third-party Swift packages to download.

```sh
swift build -c debug
BIN="$(swift build --show-bin-path)/Cairn"
"$BIN" --safetycheck
"$BIN" --workspacecheck
```

This builds the executable only. For normal use, run a packaged `Cairn.app`, since a raw executable does not get the same notification and permission identity. `build_local.sh` and `build_release.sh` package, sign and (for release) notarise the app; they need a Developer ID certificate. Each invocation writes a unique directory under `dist/` and prints its output path; existing builds are preserved. Read [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md) before using them.

### Command line

The same app binary works as a command line tool:

```sh
cairn status            # free space and recent cleans
cairn scan              # what can be freed
cairn projects          # coding projects and how long they have been idle
cairn rules             # everything Cairn looks for, as Markdown
cairn clean --safe      # preview only; review exact items in the app
cairn mcp               # link for AI coding tools
```

Add `--json` for machine-readable output.

### Repository map

| Location | Purpose |
| --- | --- |
| `Cairn/App/` | App entry, command line, AI tool link (MCP), menu bar and brand tokens |
| `Cairn/Core/` | Scanning, measurements, projects, receipts, storage moves and recovery |
| `Cairn/Safety/` | Cleanup rules and protected locations |
| `Cairn/Scanners/` | What each category looks for |
| `Cairn/UI/` | Screens and shared components |
| `Cairn/Diagnostics/` | Check suites run with `--safetycheck`, `--workspacecheck` and others |
| `Cairn/Resources/` | Icons and preview artwork |
| `Support/` | SQLite module and supporting checks |
| `website/` | Marketing website; the current page is `v2/night.html` |
| `docs/` | Product, design, implementation and release documents |
| `artifacts/` | Written evidence from checks; generated output stays local |
| `reference-prototype/` | Earlier Python version, not shipped |
| `tools/archive/` | Old icon experiments, not the approved brand |

### Further reading

- [Changelog](CHANGELOG.md) and [bugs and fixes](BUGS-AND-FIXES.md)
- [What Cairn looks for](docs/WHAT-CAIRN-LOOKS-FOR.md), written from the app itself
- [Third-party notices](THIRD-PARTY-NOTICES.md)
- [Current capabilities](docs/STORAGE-CONTROL-CAPABILITIES.md): what is built and what is still restricted
- [Release readiness](docs/RELEASE-READINESS-2026-10-01.md)
- [Product requirements](docs/CAIRN-STORAGE-CONTROL-PRD.md)
- [Documentation index](docs/README.md)
