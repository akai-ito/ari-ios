import LocalAuthentication
import Observation
import SwiftUI

/// Whether the You tab shows. Hidden, you can show Ito to someone without your memory and journal
/// in reach: no tab, search result or step in the chat opens a page. It comes back only with Face
/// ID or the passcode. On this device only: nothing changes on the server.
@MainActor
@Observable
final class YouTab {
    static let shared = YouTab()

    private static let key = "hidesYouTab"
    private static let reason = "Show the You tab again"
    private let defaults: UserDefaults

    private(set) var isHidden: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isHidden = defaults.bool(forKey: Self.key)
    }

    /// Whether this iPhone can check it's you, so hiding never locks you out.
    var canCheck: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// How this iPhone checks it's you, in words: "Face ID or your passcode".
    var check: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID or your passcode"
        case .touchID: return "Touch ID or your passcode"
        case .opticID: return "Optic ID or your passcode"
        default: return "your passcode"
        }
    }

    func hide() {
        isHidden = true
        defaults.set(true, forKey: Self.key)
    }

    /// Shows the tab again once Face ID, or the passcode, says it's you. Returns what went wrong,
    /// in words for Settings; nothing when it shows, or when you cancelled.
    func show() async -> String? {
        let context = LAContext()
        var problem: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &problem) else {
            return LAError.Code(rawValue: problem?.code ?? 0) == .passcodeNotSet
                ? "Set a passcode for this iPhone in iOS Settings, then bring the You tab back."
                : "This iPhone can't check it's you right now, so the You tab stays hidden."
        }
        do {
            guard
                try await context.evaluatePolicy(
                    .deviceOwnerAuthentication, localizedReason: Self.reason)
            else { return nil }
        } catch let error as LAError
            where [.userCancel, .appCancel, .systemCancel].contains(error.code)
        {
            return nil
        } catch {
            return "That wasn't confirmed, so the You tab stays hidden."
        }
        isHidden = false
        defaults.set(false, forKey: Self.key)
        return nil
    }
}

extension EnvironmentValues {
    /// The You tab is hidden: nothing on screen opens a page of memory.
    @Entry var hidesYou = false
}

/// Settings' switch for hiding the You tab, saying honestly what it hides and what it doesn't.
struct YouTabSection: View {
    @State private var problem: String?

    var body: some View {
        let youTab = YouTab.shared
        let canCheck = youTab.canCheck
        Section {
            Toggle(
                "Hide the You tab",
                isOn: Binding(
                    get: { youTab.isHidden },
                    set: { hides in
                        problem = nil
                        if hides {
                            youTab.hide()
                        } else {
                            Task { problem = await youTab.show() }
                        }
                    })
            )
            // Hiding needs a way back that only you have.
            .disabled(!youTab.isHidden && !canCheck)
        } header: {
            Text("Showing Ito to someone")
        } footer: {
            Text(problem ?? footer(canCheck: canCheck, check: youTab.check))
        }
        .listRowBackground(Color.ariSurface)
    }

    private func footer(canCheck: Bool, check: String) -> String {
        let scope = "Hides the You tab; chat, Desk and notifications still show what they show."
        return canCheck
            ? "\(scope) \(check.prefix(1).uppercased() + check.dropFirst()) brings it back."
            : "\(scope) It needs a passcode on this iPhone, so only you can bring it back."
    }
}
