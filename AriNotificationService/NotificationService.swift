import AriKit
import UserNotifications

/// Decrypts each push on the iPhone, so Apple only ever carries ciphertext. A reply shows its first
/// line; an ask shows the question, with its options (and a typed answer, when it takes one) as the
/// notification's actions. When anything goes wrong, the push's own plain words show instead:
/// "Ari replied", "Ari asked you something".
final class NotificationService: UNNotificationServiceExtension {
    private var deliver: ((UNNotificationContent) -> Void)?
    private var fallback: UNNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        deliver = contentHandler
        fallback = request.content
        let store = NotificationStore.forThisApp()
        guard let sealed = SealedNotification(payload: request.content.userInfo),
            let notification = try? sealed.open(with: store.keys(), device: store.deviceID),
            let content = request.content.mutableCopy() as? UNMutableNotificationContent
        else {
            contentHandler(request.content)
            return
        }
        content.body =
            notification.ask.map { AskActions.body(for: notification.text, ask: $0) }
            ?? notification.text
        content.threadIdentifier = "conversation"
        var info = content.userInfo
        info["kind"] = notification.kind.rawValue
        info["message"] = notification.message?.rawValue
        info["ask"] = notification.ask?.id.rawValue
        info["options"] = notification.ask?.options
        content.userInfo = info
        guard let ask = notification.ask else {
            contentHandler(content)
            return
        }
        // The options change with every ask, so each gets its own category, registered just before
        // the notification shows.
        let category = AskActions.category(for: ask)
        content.categoryIdentifier = category.identifier
        let delivery = Delivery(handler: contentHandler, content: content, category: category)
        Task {
            await AskActions.register(delivery.category)
            delivery.handler(delivery.content)
        }
    }

    /// The system may call the content handler from any thread, once.
    private struct Delivery: @unchecked Sendable {
        let handler: (UNNotificationContent) -> Void
        let content: UNNotificationContent
        let category: UNNotificationCategory
    }

    override func serviceExtensionTimeWillExpire() {
        if let deliver, let fallback { deliver(fallback) }
    }
}
