// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Snapboard",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Snapboard", targets: ["Snapboard"])
    ],
    targets: [
        // Pure logic: zone layouts, coordinate maths, the widget grid and the Lifeboard feed.
        // No AppKit, so it is easy to test.
        .target(name: "SnapboardCore"),
        // The Mac app: menu bar, window moving, overlays, editor, widgets, settings.
        .executableTarget(name: "Snapboard", dependencies: ["SnapboardCore"]),
        .testTarget(name: "SnapboardCoreTests", dependencies: ["SnapboardCore"])
    ]
)
