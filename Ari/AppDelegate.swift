#if os(iOS)
    import AppIntents
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
            // Siri's and Shortcuts' intents send through the same model.
            let model = model
            AppDependencyManager.shared.add(dependency: model)
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
            _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
            withCompletionHandler completionHandler:
                @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            let done = Handler(completionHandler)
            Task { @MainActor in
                done.call(model.isLooking ? [] : [.banner, .sound, .list])
            }
        }

        /// An option or a typed answer goes to the server at once; a tap opens the conversation, at
        /// the reply it was about. iOS's completion handler must be called on the main thread:
        /// called from the async version's background task, it made UIKit abort, so tapping a
        /// notification crashed Ari.
        nonisolated func userNotificationCenter(
            _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
            withCompletionHandler completionHandler: @escaping () -> Void
        ) {
            let info = response.notification.request.content.userInfo
            let typed = (response as? UNTextInputNotificationResponse)?.userText
            let answer = AskActions.answer(
                action: response.actionIdentifier, typed: typed,
                options: info["options"] as? [String] ?? [])
            let ask = (info["ask"] as? String).map(AskID.init(rawValue:))
            let message = (info["message"] as? String).map(MessageID.init(rawValue:))
            let done = Handler(completionHandler)
            Task { @MainActor in
                if let answer {
                    await model.answer(fromNotification: answer, ask: ask)
                } else {
                    model.opening = message
                }
                done.call(())
            }
        }

        /// A completion handler from iOS, carried to the main actor and called there, once.
        private nonisolated struct Handler<Value>: @unchecked Sendable {
            let call: (Value) -> Void
            init(_ call: @escaping (Value) -> Void) { self.call = call }
        }
    }
#endif
