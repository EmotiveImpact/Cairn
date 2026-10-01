# Approved component rollout — 1 October 2026

## Implemented
The approved showcase now shares the production ControlPanelButtonStyle/CairnControlSurface rather than carrying a separate look. Workspace controls and legacy Brand/White/Ghost buttons use the same 32-point minimum height, 7-point corners, blue primary gradient, white primary labels, subtle secondary surfaces and stationary press treatment. Hover feedback honors Reduce Motion; Increase Contrast strengthens outlines; disabled states remain visibly disabled. Legacy hover-button lift/scaling and item checkbox bounce were removed.

Shared status pills, row typography/spacing, quieter focused rows, menu-picker surfaces, state icon treatments and compact small confirmation geometry now follow that direction. Native pickers and toggles keep platform behaviour. Source changes are presentation-only except for the isolated preview capture runner; cleanup executors were not modified.

## Evidence
- Final debug build and git diff whitespace checks passed.
- Eleven actual AppShell routes rendered with sample data: Overview, Changes, Make room, Developer, Large files, Apps, Duplicates, Storage, Health, Activity and Settings. Renders visually inspected. Shared browser/general/AI/creative cleanup uses the DeveloperCleanupView system.
- Final Large Files and confirmation captures inspected after dropdown-indicator/dialog-height refinements. Files are in ../component-showcase/.
- Workspace and safety fixtures passed.
- Native workspace stress passed: eight cycles, 12,000 retained results each, baseline 7 MiB, peak 29 MiB, final 26 MiB, maximum main-actor gap 296 ms; memory plateau held. This ran before the final cosmetic dropdown indicator and confirmation sizing adjustments, which were rebuilt and rendered separately.
- Staged Developer ID signing and strict verification passed. dist/Cairn.app updated by rename; predecessor retained in previous/Cairn.app. No running user app was stopped or relaunched.

## Boundaries
These are sample-data renders and bounded workspace tests, not complete interactive VoiceOver/keyboard acceptance, hardware testing or public-release certification. Some sample app icons do not render from missing sample applications. Tall pages and expanded sidebar groups remain scrollable. No personal cleanup or configuration changes were performed. No dependencies installed, no notarization or publishing, no update/payment integration.
