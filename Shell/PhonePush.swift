// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

// The phone's own part of push (Push.swift): iOS's question to the person,
// Apple's registration, and what iOS tells the app of a notification: that
// one arrived while the app is on the screen, and that the person tapped
// one. Each is passed to the push library, which tells the page's streams;
// nothing of a notification is printed or kept here. The whole file is the
// phone's: the desktop app compiles none of it.
#if os(iOS)
import UIKit
import UserNotifications

/// The person's answer and Apple's registration, on a phone.
final class PhonePush: NSObject, PushPhone, UNUserNotificationCenterDelegate {
    static let shared = PhonePush()
    /// The library the page reaches, which is told of taps: one for the
    /// app's life, as this is.
    private(set) lazy var library = PushLibrary(phone: self)
    /// The registrations that wait for Apple's answer.
    private var registering: [(Result<Data, NativeError>) -> Void] = []

    func permission(_ done: @escaping (PushPermission) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let said = Self.permission(settings.authorizationStatus)
            DispatchQueue.main.async { done(said) }
        }
    }

    func askPermission(_ done: @escaping (PushPermission) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { allowed, _ in
            DispatchQueue.main.async { done(allowed ? .allowed : .refused) }
        }
    }

    /// iOS's word in the gene's: a person who allowed it in any form
    /// (quietly, or for an app clip's time) has allowed it.
    static func permission(_ status: UNAuthorizationStatus) -> PushPermission {
        switch status {
        case .notDetermined: return .notAsked
        case .denied: return .refused
        default: return .allowed
        }
    }

    func registerWithApple(_ done: @escaping (Result<Data, NativeError>) -> Void) {
        registering.append(done)
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Apple's answer, for every registration that waits for it.
    func registered(_ result: Result<Data, NativeError>) {
        let waiting = registering
        registering = []
        waiting.forEach { $0(result) }
    }

    var environment: PushEnvironment {
        #if targetEnvironment(simulator)
        return PushEnvironment.of(profile: nil, simulator: true)
        #else
        let profile = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision").flatMap { try? Data(contentsOf: $0) }
        return PushEnvironment.of(profile: profile, simulator: false)
        #endif
    }

    var app: String { Bundle.main.bundleIdentifier ?? "" }

    /// The library is the main thread's, as the page's bridge is; iOS does
    /// not say which thread it tells the app of a notification on.
    private static func onMain<T>(_ work: () -> T) -> T {
        Thread.isMainThread ? work() : DispatchQueue.main.sync(execute: work)
    }

    // MARK: what iOS tells the app of a notification

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let told = Self.onMain { self.library.arrived(notification.request.content.userInfo) }
        #if DEBUG
        // a development build says so, never what the notification says
        print(told ? "shell: a notification arrived with the app on the screen; the page was told, and iOS shows nothing"
                   : "shell: a notification arrived with the app on the screen and no page listens; iOS shows it")
        #endif
        completionHandler(told ? [] : [.banner, .list, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // the tap itself, not a notification swept away
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            #if DEBUG
            print("shell: a notification was tapped") // never what it says
            #endif
            Self.onMain { self.library.tapped(response.notification.request.content.userInfo) }
        }
        completionHandler()
    }
}

/// The app's delegate: iOS hands Apple's registration to it, and a tap on
/// a notification to the notification centre's delegate, which must be set
/// before the app has finished launching, or a tap that opened the app is
/// never told.
final class ShellAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = PhonePush.shared
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PhonePush.shared.registered(.success(deviceToken))
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("shell: Apple did not register this phone for push: \(error.localizedDescription)")
        #endif
        PhonePush.shared.registered(.failure(NativeError(message: "push: Apple did not register this phone")))
    }
}
#endif
