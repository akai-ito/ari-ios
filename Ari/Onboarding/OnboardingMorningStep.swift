import SwiftUI

/// Step 4: the morning's "not before" time, and notifications, with an honest line about how loud
/// Kumo may be. Allow asks iOS; Not now is fine too. Either way the time is saved on the way out.
struct OnboardingMorningStep: View {
    let model: OnboardingModel

    @State private var poses = PoseHistory(.asking)
    @State private var sending = DeskSending()

    var body: some View {
        OnboardingPage {
            VStack(alignment: .leading, spacing: 32) {
                OnboardingHeader(poses: poses, title: "When can I bring you the morning?")
                VStack(alignment: .leading, spacing: 10) {
                    DatePicker("Not before", selection: time, displayedComponents: .hourAndMinute)
                        .font(.body)
                        .foregroundStyle(.ariText)
                        .deskCard(padding: 14, cornerRadius: 16)
                    Text(
                        "Kumo brings the morning card at the first calm moment after this: when you open Ito, or the first gap in your calendar."
                    )
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 10) {
                    DeskSectionLabel("Notifications")
                    Text(
                        "At most one with sound an hour; the rest arrive quietly. Urgent things always sound."
                    )
                    .font(.body)
                    .foregroundStyle(.ariText)
                    .fixedSize(horizontal: false, vertical: true)
                    Text("Nothing sounds during an event in your calendar, and Focus is respected.")
                        .font(.footnote)
                        .foregroundStyle(.ariTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let choice = model.notifications {
                        chosen(choice).transition(.opacity)
                    }
                }
            }
            .animation(.smooth(duration: 0.35), value: model.notifications)
        } footer: {
            if let problem = sending.problem { DeskProblemLine(text: problem) }
            if model.notifications == nil {
                OnboardingButton("Allow notifications", busy: sending.key == "allow") {
                    go("allow") { await model.allowNotifications() }
                }
                OnboardingQuietButton("Not now") {
                    go("not now") { model.declineNotifications() }
                }
                .disabled(sending.isSending)
            } else {
                OnboardingButton("Continue", busy: sending.key == "continue") {
                    go("continue") {}
                }
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

    /// Saves the morning time, then does what you chose, then moves on, unless iOS turned
    /// notifications down: then the step stays to say so honestly, with Continue.
    private func go(_ key: String, _ then: @escaping () async -> Void) {
        Task {
            let done = await sending.send(key, failure: "Couldn't save your morning time") {
                try await model.saveMorning()
                await then()
            }
            if done, key == "continue" || model.notifications != .off { model.advance() }
        }
    }

    /// The morning time as the picker wants it: today at that hour.
    private var time: Binding<Date> {
        Binding {
            Calendar.current.date(
                bySettingHour: model.morning.hour ?? 7, minute: model.morning.minute ?? 30,
                second: 0, of: .now) ?? .now
        } set: { date in
            model.morning = Calendar.current.dateComponents([.hour, .minute], from: date)
        }
    }
}

#if DEBUG
    #Preview("4 · Morning and notifications") {
        @Previewable @State var model = OnboardingSamples.model(
            step: .morning, connected: ["icloud"],
            progress: OnboardingProgress(read: 2480, total: 3100))
        OnboardingFlow(model: model)
            .preferredColorScheme(.dark)
    }
#endif
