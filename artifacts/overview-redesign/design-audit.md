# Overview refinement — 28 September 2026

Scope: native Overview and launch geometry. Implemented in the existing app; existing cleanup engines preserved.

## Current-screen audit

Evidence: `01-before.png`, captured from the running native app and inspected from disk.

- High: main content duplicated sidebar destinations with empty size values; no priorities or history.
- High: source default was 1440 × 900; snapshot automation forced 1487 × 1030 and could leave a large restored frame. The before screenshot was already manually smaller, not evidence of the default launch size.
- Medium: generic inspector repeated capacity and instructions, consuming roughly a third of the workspace.
- Medium: weak visual hierarchy left the user to infer where to start.

## Implemented

- Composed capacity summary with available-space history, period filter and measured change.
- Ranked scan findings link to existing tools. Counts are candidates, not guaranteed savings or a whole-disk breakdown.
- Contextual next steps and activity/recovery entry; no automatic removal actions.
- Preview data visibly labelled. Live mode uses volume metadata, stored scan results and recorded daily samples. Fewer than two samples produces an honest history empty state.
- 1120 × 740 opening size, 1024 × 680 floor, narrower sidebar and inspectors. Removed duplicate rescan/inspector controls from Overview.
- StorageHistory.load no longer creates its support directory; the write path creates it when recording.

## Verification and limits

`02-after.png`: final native default-size overview. `03-developer-compact.png`: existing cleanup screen at compact size. `04-minimum.png`: successful manual resize to 1024 × 680, with vertical scrolling for remaining content. Initial Picker wrapping bug found visually and corrected before final capture.

Search for browser filtered findings; clearing restored them. 30-day selection changed selected control state. Clicking Xcode finding opened Developer with existing selection and inspector. Live scanning/cleanup was not invoked. Build, safety fixtures, transfer fixtures and signature checks passed; logs saved here.

Daily readings do not establish which app caused growth. They are not continuous monitoring, and no time-to-full prediction is shown. No full accessibility, long-duration stability, live transfer or release certification is claimed. All other route features remain subject to existing BUILD_STATUS release gates.

## Chart edge correction

User reported graph clipping. Reproduced truncated final date and a cramped 74pt chart in native preview. Increased plot height to 104pt, inset plotted end points, added a latest-reading marker and moved exact start/end dates into a dedicated label row. Build, ad-hoc signature and diff whitespace checks passed. Visually checked default 1120 × 740 and minimum 1024 × 680 sizes: dates, scale and endpoint fit. Evidence: `05-chart-fixed.png`, `06-chart-minimum.png`. Source data and cleanup behavior unchanged.
