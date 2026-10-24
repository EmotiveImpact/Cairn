# Cairn

**Cairn finds the junk in your coding projects, and works with your AI coding tools.**

Cairn is a Mac app that shows you what is filling your disk and frees space safely. It is built for people who write code: it knows which caches, build folders and downloaded packages can be rebuilt, which projects you have not touched in weeks, and which things are yours and must never be touched.

> **Status: not released yet.** There is no public download. Cairn is being tested on one Mac, and some of what is described below is still waiting in open pull requests. See [CHANGELOG.md](CHANGELOG.md) for what has changed and [BUGS-AND-FIXES.md](BUGS-AND-FIXES.md) for known problems.

## What Cairn does

- **Shows what you can free right now.** Home leads with one number: the space that is safe to free with one click, kept separate from things that need you to decide.
- **Finds junk in coding projects.** Build output, `node_modules`, Xcode leftovers, package caches and simulators, grouped by project, with how long each project has been idle.
- **Cleans each tool the proper way.** Docker, Homebrew, pnpm, Go, conda, git and Xcode simulators are cleaned with their own commands, so nothing breaks.
- **Proves what it freed.** Every clean leaves a receipt. When macOS confirms the free space went up, the receipt says Verified.
- **Keeps watch from the menu bar.** It shows space ready to free, idle projects and anything that has grown fast.
- **Moves big things to an external SSD.** Local AI models and Xcode archives can be moved to an encrypted drive and brought back later. Every file is checked before the original goes.
- **Also covers the rest of your Mac**: large and old files, duplicates, apps you no longer use and general Mac health.

## Works with your AI coding tools

Cairn can link to AI coding tools that run on your Mac, so they can check your disk and tell you what can be freed. Connect them in one click from **Settings › AI tools**.

Supported: **Claude Code, Claude Desktop, Codex, Cursor, Gemini CLI, VS Code, Windsurf, Zed, opencode and Goose**, plus Cline, Roo Code, Kiro, Amazon Q, JetBrains Junie, LM Studio, Qwen Code and Amp.

Out of the box, AI tools can only look. A pull request that is still open lets them also run a clean, but only if you turn that on, only for safe rebuildable items, and only from a list you can see. Setup details are in [docs/CLAUDE-CODE.md](docs/CLAUDE-CODE.md).

## Keeping your things safe

- **You see everything first.** Every clean shows the exact files, their sizes and any command before anything runs.
- **You choose how things are removed** in Settings › Cleaning. **Smart** (the default) deletes things that can be rebuilt, so the space comes back at once, and sends anything personal to the Trash. **Delete now** deletes everything you picked. **Move to Trash** keeps everything recoverable.
- **Some things are always off limits**, whatever you choose: system files, passwords and keychains, Mail, Messages, Photos, iCloud, your source code history (`.git`), SSH keys and AI chat history.
- **Nothing harmful runs.** Commands that would destroy data, such as removing Docker volumes, are never used.
- **Files are checked again** just before each action, in case anything changed since the scan.

## What's next

In rough order of priority:

1. **A proper download.** A signed and notarised app with automatic updates, then a small private beta.
2. **Match the approved designs exactly** on every screen, checked side by side with real screenshots.
3. **Merge the open work**: the Night look and honest numbers (PR #5), AI tools that can clean (PR #7) and the website hero (PR #6).
4. **Publish the Claude Code plugin and Gemini CLI extension** so others can install them.
5. **Update the website screenshots** to the new look.
6. **Projects:** put an idle project to sleep (clear its rebuildable files and keep a note to restore them) and show its git status. *Built, waiting to be merged.*
7. **AI models page** listing every local model and how big it is. *Built, waiting to be merged.*
8. **Disk map**: a picture of what is taking up space. *Built, waiting to be merged.*
9. **More SSD moves**: Docker, simulators and Xcode's DerivedData.
10. **Cleaning rules you approve once** and Cairn then runs on its own. *Built, waiting to be merged.*

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

This builds the executable only. For normal use, run a packaged `Cairn.app`, since a raw executable does not get the same notification and permission identity. `build_local.sh` and `build_release.sh` package, sign and (for release) notarise the app; they need a Developer ID certificate. Read [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md) before using them.

### Command line

The same app binary works as a command line tool:

```sh
cairn status            # free space and recent cleans
cairn scan              # what can be freed
cairn projects          # coding projects and how long they have been idle
cairn clean --safe      # preview a safe clean (add --yes to run it)
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
- [Current capabilities](docs/STORAGE-CONTROL-CAPABILITIES.md): what is built and what is still restricted
- [Release readiness](docs/RELEASE-READINESS-2026-10-01.md)
- [Product requirements](docs/CAIRN-STORAGE-CONTROL-PRD.md)
- [Documentation index](docs/README.md)
