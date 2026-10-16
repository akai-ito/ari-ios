#if os(iOS)
    import AriKit
    import UIKit
    import UserNotifications

    /// Owns the model, so a notification answered from the lock screen can reach the server even
    /// when Ari launches in the background with no screen; and hears from the push service and the
    /// notification centre.
    final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
        let model = AppModel()

        func application(
            _ application: UIApplication,
            didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
        ) -> Bool {
            UNUserNotificationCenter.current().delegate = self
            #if DEBUG
                DebugScript.adoptNotificationKey(into: model.notifications)
            #endif
            model.restoreNotifications()
            return true
        }

        func application(
            _ application: UIApplication,
            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
        ) {
            model.didRegister(token: deviceToken)
        }

        func application(
            _ application: UIApplication,
            didFailToRegisterForRemoteNotificationsWithError error: any Error
        ) {
            model.failedToRegister(error)
        }

        /// While you're looking at the conversation, a notification about it would only repeat it.
        nonisolated func userNotificationCenter(
            _ center: UNUserNotificationCenter, willPresent notification: UNNotification
        ) async -> UNNotificationPresentationOptions {
            await model.isLooking ? [] : [.banner, .sound, .list]
        }

        /// An option or a typed answer goes to the server at once; a tap opens the conversation, at
        /// the reply it was about.
        nonisolated func userNotificationCenter(
            _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
        ) async {
            let info = response.notification.request.content.userInfo
            let action = response.actionIdentifier
            let typed = (response as? UNTextInputNotificationResponse)?.userText
            let options = info["options"] as? [String] ?? []
            let ask = (info["ask"] as? String).map(AskID.init(rawValue:))
            let message = (info["message"] as? String).map(MessageID.init(rawValue:))
            if let answer = AskActions.answer(action: action, typed: typed, options: options) {
                await model.answer(fromNotification: answer, ask: ask)
            } else {
                await MainActor.run { model.opening = message }
            }
        }
    }
#endif
