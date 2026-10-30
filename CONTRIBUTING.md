# Developing Cairn

Read [AGENTS.md](AGENTS.md), the [capability ledger](docs/STORAGE-CONTROL-CAPABILITIES.md) and [implementation handoff](docs/CAIRN-STORAGE-CONTROL-HANDOFF.md) first.

## Working safely

Preserve local modifications and untracked files. Use generated disposable fixtures for filesystem checks. Do not run cleanup on personal data, replace running app executables, enable dormant destructive commands or publish builds as a side effect of development.

Make a coherent change, then run the relevant checks. Do not rerun every suite after each small edit. Distinguish source implementation, fixture verification, rendered UI evidence and release certification.

## Compile and check

```sh
swift build -c debug
BIN="$(swift build --show-bin-path)/Cairn"
"$BIN" --workspacecheck
"$BIN" --safetycheck
```

Additional bounded checks live in `Cairn/Diagnostics/`: `--reliabilitycheck`, `--lifecyclecheck`, `--hashmemorycheck`, `--loadcheck`, `--evidencecheck` and `--native-reliability-check`. Select checks appropriate to the change. Native checks need a macOS graphical session; filesystem event checks may require a less restrictive test environment. Do not substitute legacy `--selftest` or personal `--readonlycheck` for disposable fixture checks.

## Native component preview

```sh
"$BIN" --preview-ui --component-showcase --showcase-live
```

Run from the repository root. This opens sample components, not real cleanup actions. Without `--showcase-live`, it exports `artifacts/component-showcase/preview.png` and exits.

## Packaging and release

`build_local.sh` assembles and signs a local bundle; `build_release.sh` additionally invokes notarization. Both are operational scripts, not ordinary compile checks. Each invocation writes a unique `dist/local.XXXXXX` or `dist/release.XXXXXX` directory, leaving previous bundles and archives untouched. Failed builds keep an `INCOMPLETE` marker; only artifacts without that marker passed all script checks. Compilation defaults to two workers; set `BUILD_JOBS` to override. The release script refuses to proceed if signed entitlements cannot be inspected. Use the exact output path printed by the script. Installation and publishing remain separate operations.

Signing/notarization credentials are machine-local. Never commit key files, keychain exports or environment secrets. Public upload, App Store submission and personal cleanup require a separate explicit instruction.

## Evidence

Keep concise Markdown reports under `artifacts/<topic>/`, stating what passed and what remains unverified. Captures, binaries, logs and previous app bundles stay local and are ignored. Existing historical reports can reference local-only files; their links are not promises that raw evidence is hosted on GitHub.

A macOS build is required after source changes. Documentation-only work needs link/path and whitespace checks, not a complete runtime test cycle.
