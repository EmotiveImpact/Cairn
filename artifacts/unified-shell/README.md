# Cairn unified native workspace · 30 September 2026

The approved direction has one rounded dark workspace within the same graphite surround as the sidebar. Page titles, controls and footers live inside that workspace; the native title bar carries only window controls. The sidebar remains visible and has no dividing border or collapse control.

`native-preview/` contains sample-data screenshots captured from the compiled SwiftUI app at 1120 × 740. Some predate the last specialist refinements; final Apps, Settings, Health, Duplicates, Smart Scan and Developer Clean were inspected directly in the native preview. These demonstrate layout, not live scan or cleanup behavior. `concepts/` contains design targets for Clean, Apps, Storage, Health, Make room, Smart Scan, Duplicates and Settings. A concept is not evidence that its depicted feature is implemented.

The actual screens retain their existing safety and action flows. In particular, moving files to Trash does not immediately free internal space; a file labeled a cache is not automatically safe to remove; duplicate removal chooses individual copies; and a preview must not imply measured live findings. Where a concept conflicts with these rules, the native app's behavior and wording take precedence.

The shared shell, Overview, Changes, Large Files, Activity and selected specialist refinements are implemented in source. See `BUILD_STATUS.md` for the exact validation boundary and remaining work.
