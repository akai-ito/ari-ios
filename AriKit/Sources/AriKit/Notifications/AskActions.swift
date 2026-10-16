import UserNotifications

/// An ask's options as a notification's actions, so you can answer from the lock screen: each
/// option as a button, a typed answer when the ask takes one, and for a secret only "Open Ari",
/// since a secret can't be typed into a notification safely.
public enum AskActions {
    public static let type = "type"
    public static let open = "open"

    public static func option(_ index: Int) -> String { "option.\(index)" }

    /// A category of its own for this ask, since every ask's options differ.
    public static func category(for ask: PushNotification.AskSummary) -> UNNotificationCategory {
        var actions: [UNNotificationAction] = []
        if ask.secret {
            actions = [
                UNNotificationAction(identifier: open, title: "Open Ari", options: [.foreground])
            ]
        } else {
            actions = ask.options.enumerated().map { index, label in
                UNNotificationAction(identifier: option(index), title: label, options: [])
            }
            if ask.allowsText || ask.options.isEmpty {
                actions.append(
                    UNTextInputNotificationAction(
                        identifier: type, title: "Type an answer…", options: [],
                        textInputButtonTitle: "Send", textInputPlaceholder: "Answer Ari"))
            }
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
