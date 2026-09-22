// swift-tools-version: 6.2
import PackageDescription

// The plumbing Mango and Earmark share. App code — models, parsers, readers, players, UI —
// stays in each app; only code that is the same idea in both lives here.
let package = Package(
    name: "ShelfKit",
    // iOS 26 for Liquid Glass (the lock's button); both apps require it anyway.
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "ShelfKit", targets: ["ShelfKit"]),
    ],
    dependencies: [
        // SMB, for NASClient. It's a dynamic framework: each app also lists it and embeds it
        // (`embed: true`), or the app dies at launch on a device.
        .package(url: "https://github.com/amosavian/AMSMB2.git", from: "4.0.3"),
    ],
    targets: [
        .target(name: "ShelfKit", dependencies: [.product(name: "AMSMB2", package: "AMSMB2")]),
        .testTarget(name: "ShelfKitTests", dependencies: ["ShelfKit"]),
    ]
)
