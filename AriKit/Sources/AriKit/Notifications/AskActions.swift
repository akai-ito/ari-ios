import UserNotifications

/// An ask's options as a notification's actions, so you can answer from the lock screen: each
/// option as a button, and a typed answer when the ask takes one.
public enum AskActions {
    public static let type = "type"

    public static func option(_ index: Int) -> String { "option.\(index)" }

    /// A category of its own for this ask, since every ask's options differ.
    public static func category(for ask: PushNotification.AskSummary) -> UNNotificationCategory {
        var actions: [UNNotificationAction] = ask.options.enumerated().map { index, label in
            UNNotificationAction(identifier: option(index), title: label, options: [])
        }
        if ask.allowsText || ask.options.isEmpty {
            actions.append(
                UNTextInputNotificationAction(
                    identifier: type, title: "Type an answer…", options: [],
                    textInputButtonTitle: "Send", textInputPlaceholder: "Answer Ari"))
        }
        return UNNotificationCategory(
            identifier: "ask." + ask.id.rawValue, actions: actions, intentIdentifiers: [],
            options: [])
    }

    /// Registers the category beside the others, keeping only the most recent asks' categories.
    public static func register(_ category: UNNotificationCategory) async {
        let center = UNUserNotificationCenter.current()
        var categories = await center.notificationCategories().filter {
            $0.identifier != category.identifier
        }
        let asks = categories.filter { $0.identifier.hasPrefix("ask.") }
        if asks.count >= 20 { categories.subtract(asks.prefix(asks.count - 19)) }
        categories.insert(category)
        center.setNotificationCategories(categories)
        // Setting categories returns before iOS has them: wait until it does, or the notification
        // can show before its buttons exist, and then has none.
        for _ in 0..<20 {
            if await center.notificationCategories().contains(where: {
                $0.identifier == category.identifier
            }) {
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// The text an ask's notification shows: the question, then its options, so they can be read
    /// before the notification is opened for its buttons.
    public static func body(for text: String, ask: PushNotification.AskSummary) -> String {
        guard !ask.options.isEmpty else { return text }
        return text + "\n" + ask.options.joined(separator: " · ")
    }

    /// What an action answers with: an option's label, the typed text, or `nil` to open Ari.
    public static func answer(action: String, typed: String?, options: [String]) -> String? {
        if action == type { return typed }
        guard action.hasPrefix("option."), let index = Int(action.dropFirst("option.".count)),
            options.indices.contains(index)
        else { return nil }
        return options[index]
    }
}
