# Cairn workspace instructions

- Preserve the existing working tree, untracked files, recovery data, protected sessions, repositories and credentials. Do not reset, clean, stage, remove or overwrite them as a shortcut.
- For a coherent implementation request, inspect the relevant code, make the complete related change, and **run the appropriate build and tests once at the end**. Do not rerun the full suites after each small edit. Repeat a check only when its failure, a subsequent code change, or an unresolved gate makes that necessary.
- Use focused disposable fixtures for filesystem, memory, cancellation and recovery checks. Do not perform personal cleanup, external-drive writes, tool-location changes, service shutdowns, payments or releases without explicit authorization for the concrete action.
- Keep safety enforcement in the executor, not only the interface. A preview, copying to an external drive and moving to Trash must not be reported as immediate internal space freed.
- Keep Cairn native, preserve the approved dark tile with four rounded blue stones, and distinguish local builds from notarized public releases.
- For the storage-control direction, read `docs/CAIRN-STORAGE-CONTROL-PRD.md` and `docs/CAIRN-STORAGE-CONTROL-HANDOFF.md`. Record what was built, tested and remains unverified separately.
