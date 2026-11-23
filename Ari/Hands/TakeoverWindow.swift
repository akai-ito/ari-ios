import AriKit
import SwiftUI
import UIKit

/// The takeover in a window of its own, above everything Ari shows: a notification opens straight
/// into it, whatever was on screen, a thread or a sheet included, and it keeps the keyboard.
@MainActor
final class TakeoverWindow {
    static let shared = TakeoverWindow()

    private var window: UIWindow?

    /// Shows or hides the takeover as `hands` says.
    func follow(_ hands: Hands, session: Session?) {
        if hands.showsTakeover { show(hands, session: session) } else { hide() }
    }

    private func show(_ hands: Hands, session: Session?) {
        guard window == nil,
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .normal + 1
        window.overrideUserInterfaceStyle = .dark
        let host = UIHostingController(rootView: TakeoverRoot(hands: hands, session: session))
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.backgroundColor = .clear
        window.makeKeyAndVisible()
        // In from below, as a full-screen cover comes.
        host.view.transform = CGAffineTransform(translationX: 0, y: window.bounds.height)
        UIView.animate(
            withDuration: 0.38, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0
        ) {
            host.view.transform = .identity
        }
        self.window = window
    }

    private func hide() {
        guard let window else { return }
        self.window = nil
        window.endEditing(true)
        UIView.animate(withDuration: 0.3) {
            window.rootViewController?.view.transform = CGAffineTransform(
                translationX: 0, y: window.bounds.height)
        } completion: { _ in
            window.isHidden = true
            window.windowScene?.windows.first { $0.windowLevel == .normal }?.makeKey()
        }
    }
}

/// The takeover's window's content: the screen, told when the keyboard is up.
private struct TakeoverRoot: View {
    let hands: Hands
    let session: Session?

    @State private var keyboard = false

    var body: some View {
        TakeoverScreen(hands: hands, session: session)
            .environment(\.keyboardShown, keyboard)
            .preferredColorScheme(.dark)
            .tint(.ariText)
            .onReceive(
                NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            ) { _ in keyboard = true }
            .onReceive(
                NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            ) { _ in keyboard = false }
    }
}
