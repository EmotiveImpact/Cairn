# Cairn identity — selected 29 September 2026

Applied after explicit user approval in the main app task.

- Dock, Finder and About: dark graphite tile with four carved blue stones. `Cairn/Resources/CairnMark.png` is the selected transparent 1024 px redraw; `Cairn.icns` contains standard 16–1024 px macOS representations.
- Sidebar: four simple blue elliptical stones drawn by `CairnLogo` in `Cairn/UI/CairnArt.swift`. No tile, facets, extra panel or selection decoration.
- Menu bar: the same shape rendered with opaque black and `isTemplate = true`; macOS supplies the foreground colour. No semitransparent stones in the template mask.
- Name and bundle identifiers remain Cairn and their existing values.

The selected redraw and its reproducible AppKit source came from the branding task's `selected` directory. Source retained in `tools/make_carved_icon.swift`. Run from the repository root with `swift tools/make_carved_icon.swift Cairn/Resources/CairnMark.png`; standard icon sizes can then be encoded with `sips` and `iconutil`. Current size set is in `artifacts/brand-integration/Cairn.iconset`.

Build scripts already copy both resources into the app bundle. No image service or remote resource is used at runtime.
