import Foundation
import os

// Internal on purpose: each app has its own `Stopwatch` and `Logger` categories, and a public
// copy here would make every call site in an app that imports ShelfKit ambiguous.

extension Logger {
    /// The app's own subsystem, so ShelfKit's lines sit with the app's in Console.
    static let shelfKitSubsystem = Bundle.main.bundleIdentifier ?? "ShelfKit"
    static let bookmarks = Logger(subsystem: shelfKitSubsystem, category: "bookmarks")
    static let keychain = Logger(subsystem: shelfKitSubsystem, category: "keychain")
    static let lock = Logger(subsystem: shelfKitSubsystem, category: "lock")
    static let move = Logger(subsystem: shelfKitSubsystem, category: "move")
    static let cloud = Logger(subsystem: shelfKitSubsystem, category: "cloud")
}

/// Elapsed time since creation, for `[scope] what in N ms` log lines.
struct Stopwatch {
    private let start = DispatchTime.now()
    var ms: Double { Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000 }
}
