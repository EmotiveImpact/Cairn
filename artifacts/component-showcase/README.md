# Native component proposal

Sample-only SwiftUI showcase, implemented in Cairn/UI/ComponentShowcase.swift.
Rendered at 1100 × 740; preview.png is captured from the actual NSHostingView, not image generation. Build passed and first capture visually inspected; replaced an unavailable SF Symbol with arrow.clockwise and re-rendered. Controls are isolated from production stores. No dependencies installed, production bundle changed, or personal file actions performed.

Run from repository root with `.build/arm64-apple-macosx/debug/Cairn --preview-ui --component-showcase --showcase-live` for the standalone interactive window. Omit --showcase-live to export the screenshot and exit. The sidebar and in-panel confirmation are presentation specimens, not production navigation or deletion. Review and Move to Trash show a preview-only alert; selections, menu, switch and scan-label toggle are local state.

This is a proposal, not a completed app-wide restyle or accessibility certification.
