import AriKit
import SwiftUI

/// Onboarding, backed by the box: the steps fill in from the session's `onboarding` as Kumo reads,
/// Kumo's questions are its messages in the chat, and what you do goes to the box.
struct OnboardingHost: View {
    let session: Session
    let app: AppModel

    @State private var model: OnboardingModel?
    @State private var connecting = false
    @State private var capabilities: Capabilities?
    /// Calls with Kumo: answering Kumo's questions out loud, in the same conversation.
    @Environment(Talk.self) private var talk: Talk?

    var body: some View {
        Group {
            if let model { OnboardingFlow(model: model) }
        }
        .task {
            if model == nil { model = makeModel() }
            if capabilities == nil { capabilities = app.client().map(Capabilities.init(client:)) }
        }
        .onChange(of: session.onboarding, initial: true) { _, onboarding in update(onboarding) }
        .onChange(of: latestQuestion) { _, _ in updateAsking() }
        .sheet(isPresented: $connecting, onDismiss: { Task { await refreshSources() } }) {
            if let capabilities { ConnectSheet(capabilities: capabilities) }
        }
        // A call opened from here shows over onboarding, not behind it.
        .fullScreenCover(
            isPresented: Binding(get: { talk?.showsCall ?? false }, set: { talk?.showsCall = $0 })
        ) {
            if let talk, let call = talk.call { CallView(talk: talk, call: call, session: session) }
        }
    }

    // MARK: - From the box

    private func update(_ onboarding: Onboarding?) {
        guard let model, let onboarding else { return }
        model.progress = onboarding.progress.map {
            OnboardingProgress(read: $0.mailsRead, total: $0.mailsTotal)
        }
        model.beliefs = (onboarding.proposal?.beliefs ?? []).map {
            Belief(id: $0.id.rawValue, text: $0.text)
        }
        if onboarding.state == .ready, let proposal = onboarding.proposal {
            model.reveal = OnboardingReveal(
                matters: proposal.motions.compactMap { id in
                    session.motions?.all.first { $0.id == id }.map {
                        RevealMatter(
                            id: $0.id.rawValue, title: $0.title, line: $0.summary,
                            symbol: MotionSymbol.name(for: $0.kind))
                    }
                },
                added: proposal.added.map {
                    AddedEvent(title: $0.title, when: InviteCardView.when($0))
                })
        }
        updateAsking()
    }

    /// Kumo's latest message while you're getting to know each other, as the question it asks.
    private var latestQuestion: Conversation.Entry? {
        session.conversation.entries.last { $0.role == .agent && $0.isShown && $0.outcome != nil }
    }

    private func updateAsking() {
        guard let model else { return }
        if session.onboarding?.state == .ready {
            model.asking = .finished
        } else if session.conversation.turn != nil {
            model.asking = .waiting
        } else if let entry = latestQuestion {
            model.asking = .asking(KumoQuestion(id: entry.id.rawValue, text: entry.text))
        }
    }

    // MARK: - To the box

    private func makeModel() -> OnboardingModel {
        let morning = app.server?.briefing.time ?? (hour: 7, minute: 30)
        return OnboardingModel(
            sources: Self.sources,
            morning: DateComponents(hour: morning.hour, minute: morning.minute),
            actions: OnboardingActions(
                connect: { _ in connecting = true },
                talk: { talk?.start() },
                answer: { _, text in try await say(text) },
                skip: { _ in try await say("Let's skip that one.") },
                confirm: { id in
                    try await session.answerBelief(BeliefID(rawValue: id), answer: .confirmed)
                },
                correct: { id, text in
                    try await session.answerBelief(
                        BeliefID(rawValue: id), answer: .correction(text))
                },
                setMorning: { parts in
                    guard let client = app.client() else { return }
                    let time = BriefingTime(hour: parts.hour ?? 7, minute: parts.minute ?? 30)
                    _ = try await client.setBriefing(time)
                    app.refreshServer()
                },
                allowNotifications: { await app.turnOnNotifications() },
                declineNotifications: { app.declineNotifications() },
                finish: { try await session.finishOnboarding() }))
    }

    /// Sends an answer and waits for Kumo's next question: `nil` once Kumo has what it needs.
    private func say(_ text: String) async throws -> KumoQuestion? {
        guard let sent = session.send(text) else { return nil }
        for _ in 0..<240 {
            try await Task.sleep(for: .milliseconds(250))
            if session.onboarding?.state == .ready { return nil }
            let entries = session.conversation.entries
            guard let index = entries.firstIndex(where: { $0.id == sent }),
                session.conversation.turn == nil
            else { continue }
            if let reply = entries[(index + 1)...].last(where: { $0.role == .agent && $0.isShown })
            {
                return KumoQuestion(id: reply.id.rawValue, text: reply.text)
            }
        }
        return nil
    }

    private func refreshSources() async {
        guard let model, let capabilities else { return }
        await capabilities.refresh()
        let on = Set(capabilities.all.filter { $0.state == .on }.map(\.id.rawValue))
        for index in model.sources.indices {
            model.sources[index].connected = on.contains(model.sources[index].id)
        }
    }

    /// Where Kumo can read from. Each opens its setup in Settings › Capabilities.
    private static let sources = [
        ConnectableSource(
            id: "icloud", title: "iCloud", detail: "Mail and Calendar", connected: false,
            symbol: "icloud"),
        ConnectableSource(
            id: "outlook", title: "Outlook", detail: "Mail", connected: false, symbol: "envelope"),
        ConnectableSource(
            id: "gmail", title: "Gmail", detail: "Mail", connected: false, symbol: "envelope.open"),
    ]
}

/// Settings › Capabilities on its own, for connecting mail and calendar during onboarding.
private struct ConnectSheet: View {
    let capabilities: Capabilities

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CapabilitiesView(capabilities: capabilities)
                .navigationDestination(for: SettingsRoute.self) { route in
                    if case .capability(let id, let setup) = route {
                        CapabilityView(capabilities: capabilities, id: id, opensSetup: setup)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
                .task { await capabilities.refresh() }
        }
    }
}
