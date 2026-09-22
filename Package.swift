// swift-tools-version: 6.0
import PackageDescription

// The plumbing Mango and Earmark share. App code — models, parsers, readers, players, UI —
// stays in each app; only code that is the same idea in both lives here.
let package = Package(
    name: "ShelfKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ShelfKit", targets: ["ShelfKit"]),
    ],
    targets: [
        .target(name: "ShelfKit"),
        .testTarget(name: "ShelfKitTests", dependencies: ["ShelfKit"]),
    ]
)
