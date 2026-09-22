import LocalAuthentication
import SwiftUI
import os
#if canImport(UIKit)
import UIKit
#endif

/// When the app asks for Face ID (or the passcode) again. The raw values are what the apps
/// saved in their settings, so they must not change.
public enum LockMode: String, Codable, CaseIterable, Sendable {
    case off
    case immediately
    case afterOneMinute
    case afterFifteenMinutes

    public var label: String {
        switch self {
        case .off: "Off"
        case .immediately: "Immediately"
        case .afterOneMinute: "After 1 minute"
        case .afterFifteenMinutes: "After 15 minutes"
        }
    }

    /// How long the app may sit in the background before it locks.
    public var grace: TimeInterval {
        switch self {
        case .off: .infinity
        case .immediately: 0
        case .afterOneMinute: 60
        case .afterFifteenMinutes: 15 * 60
        }
    }
}

/// Where an app keeps its lock setting — its own settings object, under its own key.
@MainActor
public protocol LockSettings: AnyObject {
    var lockMode: LockMode { get set }
}

/// Face ID to open the app. Locked at launch when the lock is on, and again when it comes back
/// from the background after the grace period; the app switcher's snapshot is covered too.
///
/// The lock draws in a window of its own, above the app's. An overlay on the app's root view
/// sits *under* whatever the app presents — a full-screen reader, a player sheet — so the page
/// being read would show straight through it.
///
/// Call `sceneChanged(to:)` from the root view with `onChange(of: scenePhase, initial: true)`.
@MainActor @Observable
public final class AppLock {
    public private(set) var isLocked: Bool
    /// Covers the screen while the app isn't active, so the app switcher never shows a page.
    public private(set) var isCovered = false
    /// What the lock screen and Face ID prompt call the app ("Mango", "Earmark").
    public let appName: String
    @ObservationIgnored private let settings: any LockSettings
    @ObservationIgnored private var backgroundedAt: Date?
    @ObservationIgnored private var authenticating = false
    #if canImport(UIKit)
    @ObservationIgnored private var shield: UIWindow?
    @ObservationIgnored private weak var keyBeforeShield: UIWindow?
    #endif

    public init(appName: String, settings: any LockSettings) {
        self.appName = appName
        self.settings = settings
        isLocked = settings.lockMode != .off
    }

    /// Pure, for the tests: should coming back now ask for Face ID?
    public nonisolated static func shouldLock(mode: LockMode, backgroundedAt: Date?, now: Date) -> Bool {
        guard mode != .off else { return false }
        guard let backgroundedAt else { return true }
        return now.timeIntervalSince(backgroundedAt) >= mode.grace
    }

    public func sceneChanged(to phase: ScenePhase) {
        let lockOn = settings.lockMode != .off
        switch phase {
        case .background:
            backgroundedAt = backgroundedAt ?? .now
            isCovered = lockOn
        case .inactive:
            isCovered = lockOn
        case .active:
            if !isLocked, Self.shouldLock(mode: settings.lockMode, backgroundedAt: backgroundedAt, now: .now),
               backgroundedAt != nil {
                isLocked = true
                Logger.lock.info("[lock] locked after \(Date.now.timeIntervalSince(self.backgroundedAt ?? .now), format: .fixed(precision: 0))s away")
            }
            backgroundedAt = nil
            isCovered = false
        @unknown default:
            break
        }
        updateShield()
    }

    /// Asks for Face ID, or the device passcode when Face ID isn't set up or fails.
    public func unlock(reason: String = "Unlock your library") async {
        guard isLocked, !authenticating else { return }
        authenticating = true
        defer { authenticating = false }
        if await Self.authenticate(reason: reason) {
            isLocked = false
            Logger.lock.info("[lock] unlocked")
            updateShield()
        }
    }

    /// Face ID / passcode for something inside the app (a Hidden list) — true when allowed.
    public static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            Logger.lock.error("[lock] can't authenticate: \(error?.localizedDescription ?? "no passcode", privacy: .public)")
            return false
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            Logger.lock.notice("[lock] authentication declined: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Whether this device can lock at all — a passcode has to be set.
    public static var canLock: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Turning the lock on (or changing it) asks first, so it can't be set on someone else's
    /// behalf and then lock them out.
    public func setMode(_ mode: LockMode) async -> Bool {
        guard mode != settings.lockMode else { return true }
        guard await Self.authenticate(reason: mode == .off ? "Turn off the lock" : "Lock \(appName) with Face ID") else { return false }
        settings.lockMode = mode
        Logger.lock.info("[lock] mode → \(mode.rawValue, privacy: .public)")
        return true
    }

    // MARK: The shield window

    /// Shows or hides the window the lock draws in. Locked, it takes key status so VoiceOver and
    /// the keyboard can't reach the app underneath; merely covered, it's only drawn.
    private func updateShield() {
        #if canImport(UIKit)
        guard isLocked || isCovered else {
            guard let shield else { return }
            shield.isHidden = true
            self.shield = nil
            keyBeforeShield?.makeKey()
            Logger.lock.debug("[lock] shield down")
            return
        }
        if shield == nil {
            guard let scene = Self.appScene() else {
                Logger.lock.notice("[lock] no window scene to draw the lock in yet")
                return
            }
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert + 1
            window.rootViewController = UIHostingController(rootView: LockShield(lock: self))
            keyBeforeShield = scene.keyWindow
            shield = window
            Logger.lock.debug("[lock] shield up locked=\(self.isLocked) covered=\(self.isCovered)")
        }
        if isLocked { shield?.makeKeyAndVisible() } else { shield?.isHidden = false }
        #endif
    }

    #if canImport(UIKit)
    /// The phone's own scene — never CarPlay's, which has no windows to cover.
    private static func appScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.session.role == .windowApplication }
        return scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
            ?? scenes.first
    }
    #endif
}

/// What the shield window shows: the lock, or while inactive a plain cover for the switcher.
private struct LockShield: View {
    let lock: AppLock

    var body: some View {
        if lock.isLocked {
            LockView(lock: lock)
        } else {
            Rectangle().fill(.background).ignoresSafeArea()
                .overlay { Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(.tint) }
        }
    }
}

/// What a locked app shows: nothing of the library, and a way in.
public struct LockView: View {
    let lock: AppLock

    public init(lock: AppLock) {
        self.lock = lock
    }

    public var body: some View {
        ZStack {
            Rectangle().fill(.background).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("\(lock.appName) is locked")
                    .font(.title3.weight(.semibold))
                Button("Unlock") { Task { await lock.unlock() } }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            }
        }
        .accessibilityElement(children: .contain)
        .task { await lock.unlock() }
    }
}
