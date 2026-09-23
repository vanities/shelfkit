#if os(iOS)
import UIKit

/// What this device and its storage are called in Files: "iPhone" and "On My iPhone", or "iPad"
/// and "On My iPad". An iPhone app on an iPad lives in the iPad's Files app, so it must say iPad
/// there; every place that names the app's folder asks here.
@MainActor
public enum DeviceStorage {
    /// "iPhone" or "iPad".
    public static var device: String {
        UIDevice.current.model.hasPrefix("iPad") ? "iPad" : "iPhone"
    }

    /// "On My iPhone" or "On My iPad".
    public static var name: String { "On My \(device)" }

    /// The app's own folder in Files: "On My iPad › Earmark".
    public static func folder(_ appName: String) -> String { "\(name) › \(appName)" }
}
#endif
