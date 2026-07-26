// swift-tools-version:5.9
import PackageDescription

// Cairn — developer-native disk cleaner for macOS.
// SwiftPM executable target; the .app is assembled + signed by build_local.sh /
// build_release.sh (see ../mac-apps/SIGNING.md). No Mac App Store: a full-disk
// cleaner can't be sandboxed and needs Full Disk Access.
let package = Package(
    name: "Cairn",
    platforms: [
        .macOS("14.0")
    ],
    targets: [
        .executableTarget(
            name: "Cairn",
            path: "Cairn",
            exclude: [
                "Cairn-dist.entitlements",
                "Info.plist",
                "Resources"   // icon + artwork are copied into the .app by build scripts, not SwiftPM
            ]
        )
    ]
)
