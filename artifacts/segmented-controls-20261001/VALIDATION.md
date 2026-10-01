# Segmented control refinement

Replaced six segmented Picker presentations with shared CairnSegmentedControl: Changes, Overview history, Apps, state preview, Transparency and legacy results view. Uses NSSegmentedControl target/action and select-one behaviour with a custom stationary surface, 32-point height and accessible group label. Visible redundant Period labels removed. Selected outline appears only for Increase Contrast. No press scaling or animation.

Build and whitespace checks passed. Changes and Apps rendered with sample data. Initial capture exposed intrinsic sizing overflow; explicit SwiftUI sizing and stable segment widths fixed it, and Changes was visually verified again. Native keyboard/accessibility handling is retained, but a complete interactive VoiceOver matrix was not run. No scanner or executor changes.

Signed staged app and strict verification passed; dist updated by rename, previous bundle retained. Running user copies were not restarted. Final captures: ../component-showcase/changes.png and apps.png.
