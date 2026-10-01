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

- File actions require exact-item review and revalidation.
- Known sessions, repositories, credentials and recovery data are protected from generic cleanup.
- Moving files to Trash does not immediately free space. Capacity readings and file-size estimates are separate.
- External storage currently provides verified copies with originals retained—not managed relocation or backup.
- Generic tool cleanup, permanent Trash deletion and unattended cleanup remain disabled.

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
