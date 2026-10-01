// swift-tools-version:5.9
import PackageDescription

// Native storage manager. Direct distribution is the current build target.
// A sandboxed Store edition requires separate capability and commerce testing.
let package = Package(
    name: "Cairn",
    platforms: [
        .macOS("14.0")
    ],
    targets: [
        .systemLibrary(name: "CSQLite", path: "Support/CSQLite"),
        .executableTarget(
            name: "Cairn",
            dependencies: ["CSQLite"],
            path: "Cairn",
            exclude: [
                "Cairn-dist.entitlements",
                "Info.plist",
                "Resources"   // icon + artwork are copied into the .app by build scripts, not SwiftPM
            ]
        )
    ]
)
