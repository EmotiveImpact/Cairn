# Cairn

A native macOS storage manager built with SwiftUI and AppKit. Cairn helps explain disk usage, review cleanup candidates and keep an accountable record of file actions.

**Status: local development / pre-release.** The current build targets direct distribution. It is not an approved Mac App Store release, and the full product roadmap is not complete.

## Start here

- [Current capabilities](docs/STORAGE-CONTROL-CAPABILITIES.md) — what is implemented and what remains restricted.
- [Release readiness](docs/RELEASE-READINESS-2026-10-01.md) — remaining verification and App Store considerations.
- [Product requirements](docs/CAIRN-STORAGE-CONTROL-PRD.md) — intended behaviour and acceptance criteria.
- [Development guide](CONTRIBUTING.md) — build, checks and preservation rules.
- [Documentation index](docs/README.md) — current plans, design references and historical material.

## Build

Requires macOS 14 or later and a Swift toolchain compatible with the project. Recent local validation used Swift 6.0.3 on Apple silicon. SQLite is provided by macOS; no third-party Swift package download is required.

```sh
swift build -c debug
```

This compiles the executable. For normal use, launch a packaged `Cairn.app`; a raw executable does not have the same notification and permission identity. Packaging scripts require a Developer ID certificate. Read the development guide before using them.

## Safety model

- Every cleanup is reviewed first: exact paths, sizes and any tool command are shown before anything runs.
- Removal mode (Settings › Cleaning): **Smart** (default) deletes rebuildable caches and build output so the space is freed straight away and sends personal files to Trash; **Delete now** deletes everything selected; **Move to Trash** keeps Put Back for everything.
- Tool-owned stores are cleaned with the tool's own command (`docker … prune`, `pnpm store prune`, `go clean -modcache`, `brew cleanup`, `conda clean`, `xcrun simctl delete unavailable`, `git gc`, `tmutil deletelocalsnapshots`). Commands that destroy data, such as `docker system prune --volumes`, never run.
- Trash items can be emptied from Clean, and items Cairn moved to Trash can be deleted from Activity to release their space.
- System files, credentials, Mail, Messages, Photos, iCloud, source repositories and AI conversation history are protected by the shared safety guard whichever mode is chosen. File identity is rechecked immediately before each action.
- External storage provides verified copies with originals retained, not managed relocation or backup.

## Repository map

| Location | Purpose |
| --- | --- |
| `Cairn/App/` | Application entry, CLI, menu bar and brand tokens |
| `Cairn/Core/` | Scanning state, measurements, persistence, transfers and recovery |
| `Cairn/Safety/` | Cleanup enforcement and protected-path policy |
| `Cairn/Scanners/` | Category-specific discovery |
| `Cairn/UI/` | Native screens and shared components |
| `Cairn/Diagnostics/` | Executable diagnostic and fixture suites |
| `Cairn/Resources/` | Shipped icons and preview artwork |
| `Support/` | SQLite module and supporting checks |
| `website/` | Marketing website, assets and website documentation; active page `v2/night.html` |
| `docs/` | Product, implementation, design and release documentation |
| `artifacts/` | Versioned written evidence; generated output stays local |
| `reference-prototype/` | Historical Python reference, not shipped |
| `tools/archive/` | Historical icon experiments, not the approved brand source |

Build products (`.build/`, `dist/`) and generated test output are ignored. Previously committed output remains in Git history; this cleanup does not rewrite history.
