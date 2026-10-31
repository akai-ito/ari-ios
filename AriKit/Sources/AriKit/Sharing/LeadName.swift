import Foundation

/// What you call Kumo, Ito's lead. You can rename it in Settings; the app, the share sheet, calls and
/// Siri's answers all use the same name, kept in the app group so the extensions see it too.
public enum LeadName {
    /// The name everyone starts with.
    public static let standard = "Kumo"

    private static let key = "leadName"

    /// The name as the server last told it, or Kumo.
    public static var current: String {
        let name = defaults?.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else { return standard }
        return name
    }

    /// Keeps the server's name for the lead, or forgets it when there's none.
    public static func remember(_ name: String?) {
        defaults?.set(name, forKey: key)
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroup.forThisApp().identifier)
    }
}
