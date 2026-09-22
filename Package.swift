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
    targets: [
        .target(name: "ShelfKit"),
        .testTarget(name: "ShelfKitTests", dependencies: ["ShelfKit"]),
    ]
)
