import Foundation
import LifeOSKit
import Observation
import UIKit
import UserNotifications

/// Push notifications. Everything stays hidden and nothing is requested
/// while the server reports push as switched off (`/api/v1/push/config`).
@MainActor
@Observable
final class PushManager {
    private(set) var config: PushConfig = .disabled
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var preferences: [String: Bool] = [:]
    private(set) var message: String?

    /// Set by `AppModel`; returns the backend the user is signed in to.
    @ObservationIgnored var serviceProvider: () -> LifeOSService = { DemoService() }
    /// Tapping a notification asks the app to open this path (`/productivity`, `/calendar`, …).
    @ObservationIgnored var openRoute: (String) -> Void = { _ in }

    @ObservationIgnored private var registeredToken: String?
    @ObservationIgnored private let tokenKey = "pushDeviceToken"

    static let tasksCategory = "TASKS_DUE"

    var isAvailable: Bool { config.enabled }
    var isAllowed: Bool { authorization == .authorized || authorization == .provisional }

    /// Called after sign-in. Re-registers the token on every launch, as
    /// Apple recommends, but only once the user has allowed notifications.
    func refresh() async {
        config = (try? await serviceProvider().pushConfig()) ?? .disabled
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard config.enabled else { return }
        registerCategories()
        if isAllowed { UIApplication.shared.registerForRemoteNotifications() }
        preferences = (try? await serviceProvider().pushPreferences()) ?? [:]
    }

    /// The user tapped "Mitteilungen erlauben" in the settings.
    func requestPermission() async {
        guard config.enabled else { return }
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            if granted { UIApplication.shared.registerForRemoteNotifications() }
        } catch {
            message = "Mitteilungen konnten nicht erlaubt werden."
        }
    }

    func didRegister(deviceToken: Data) {
        let token = PushDeviceRegistration.hex(deviceToken)
        guard config.enabled, token != registeredToken else { return }
        Task {
            do {
                #if DEBUG
                let environment = PushEnvironment.sandbox
                #else
                let environment = PushEnvironment.production
                #endif
                try await serviceProvider().registerPushDevice(PushDeviceRegistration(deviceToken: token, environment: environment, deviceName: UIDevice.current.name))
                registeredToken = token
                UserDefaults.standard.set(token, forKey: tokenKey)
            } catch {
                message = error.userMessage
            }
        }
    }

    func setPreference(_ kind: String, _ enabled: Bool) async {
        preferences[kind] = enabled
        do {
            preferences = try await serviceProvider().updatePushPreferences([kind: enabled])
        } catch {
            message = error.userMessage
        }
    }

    func sendTest() async {
        do {
            let devices = try await serviceProvider().sendTestPush()
            message = devices > 0 ? "Testmitteilung gesendet." : "Kein Gerät hat die Mitteilung angenommen."
        } catch {
            message = error.userMessage
        }
    }

    /// Before sign-out: this device should stop getting the account's notifications.
    func unregister() async {
        guard let token = registeredToken ?? UserDefaults.standard.string(forKey: tokenKey) else { return }
        try? await serviceProvider().unregisterPushDevice(token: token)
        registeredToken = nil
        UserDefaults.standard.removeObject(forKey: tokenKey)
        config = .disabled
        preferences = [:]
    }

    func handle(userInfo: [AnyHashable: Any]) {
        if let route = userInfo["route"] as? String { openRoute(route) }
    }

    private func registerCategories() {
        let open = UNNotificationAction(identifier: "OPEN_TASKS", title: "Aufgaben öffnen", options: [.foreground])
        let tasks = UNNotificationCategory(identifier: Self.tasksCategory, actions: [open], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([tasks])
    }
}

/// Receives the APNs token and notification taps.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set by `LifeOSApp` once the model exists.
    @MainActor static var push: PushManager?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in Self.push?.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Simulator without push or missing entitlement; push simply stays off.
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        await MainActor.run { Self.push?.handle(userInfo: userInfo) }
    }
}
