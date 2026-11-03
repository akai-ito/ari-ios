import AriKit
import SwiftUI

/// Step 4, once you've talked about checking in: notifications, with an honest line about when they
/// come. Allow asks iOS; Not now is fine too.
struct OnboardingNotificationsStep: View {
    let model: OnboardingModel

    @State private var poses = PoseHistory(.asking)
    @State private var sending = DeskSending()

    var body: some View {
        OnboardingPage {
            VStack(alignment: .leading, spacing: 32) {
                OnboardingHeader(poses: poses, title: "Can I message you?")
                VStack(alignment: .leading, spacing: 10) {
                    DeskSectionLabel("Notifications")
                    Text(
                        "When I've something to tell you, it comes as a message, the moment I send it."
                    )
                    .font(.body)
                    .foregroundStyle(.ariText)
                    .fixedSize(horizontal: false, vertical: true)
                    Text(
                        "Your Focus decides what makes a sound. Only what can't wait breaks through."
                    )
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    if !model.serverSends {
                        // Said plainly: allowing them here is still worth it, but nothing arrives
                        // until the server can send.
                        Label(
                            "Your server can't send notifications yet: it needs an Apple push key (ito push setup on the server). Allow them now, and they'll start once it's set up.",
                            systemImage: "bell.slash"
                        )
                        .font(.footnote)
                        .foregroundStyle(.ariSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    if let choice = model.notifications {
                        chosen(choice).transition(.opacity)
                    }
                }
            }
            .animation(.smooth(duration: 0.35), value: model.notifications)
        } footer: {
            if model.notifications == nil {
                OnboardingButton("Allow notifications", busy: sending.key == "allow") {
                    go("allow") { await model.allowNotifications() }
                }
                OnboardingQuietButton("Not now") {
                    go("not now") { model.declineNotifications() }
                }
                .disabled(sending.isSending)
            } else {
                OnboardingButton("Continue") { model.advance() }
            }
        }
    }

    /// Where notifications stand, once you've chosen.
    private func chosen(_ choice: NotificationsChoice) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            switch choice {
            case .allowed:
                Image(systemName: "checkmark").foregroundStyle(.ariBone)
                Text("Notifications are on.")
            case .off:
                Image(systemName: "bell.slash").foregroundStyle(.ariTertiary)
                Text("Notifications are off for Ito. You can turn them on in Settings.")
            case .notNow:
                Image(systemName: "bell.slash").foregroundStyle(.ariTertiary)
                Text("No notifications for now. You can turn them on in Settings.")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.ariSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    /// Does what you chose, then moves on, unless iOS turned notifications down: then the step
    /// stays to say so honestly, with Continue.
    private func go(_ key: String, _ then: @escaping () async -> Void) {
        Task {
            await sending.send(key) { await then() }
            if model.notifications != .off { model.advance() }
        }
    }
}

#if DEBUG
    #Preview("4 · Notifications") {
        @Previewable @State var model = OnboardingSamples.model(
            step: .checkIn, connected: ["icloud"],
            progress: OnboardingProgress(read: 2480, total: 3100), talkedCheckIn: true)
        OnboardingFlow(model: model)
            .preferredColorScheme(.dark)
    }
#endif
