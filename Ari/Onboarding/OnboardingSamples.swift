#if DEBUG
    import AriKit
    import Foundation

    /// Onboarding as it looks for someone new, and for Divy, who comes with memory: for previews.
    /// The preview backer answers like the box would, a moment later, and moves to Kumo's next
    /// question from its list.
    enum OnboardingSamples {
        static let sources = [
            ConnectableSource(
                id: "icloud", title: "iCloud", detail: "Mail and Calendar", connected: false,
                symbol: "icloud"),
            ConnectableSource(
                id: "outlook", title: "Outlook", detail: "Mail", connected: false,
                symbol: "envelope"),
            ConnectableSource(
                id: "gmail", title: "Gmail", detail: "Mail", connected: false,
                symbol: "envelope.open"),
        ]

        static let questions = [
            KumoQuestion(
                id: "life",
                text:
                    "What's going on in your life right now? The big things, and anything quietly taking up room."
            ),
            KumoQuestion(id: "plate", text: "What would you most like off your plate?"),
            KumoQuestion(
                id: "manner",
                text:
                    "How do you like to be told things? Straight or gently, short or with the reasoning."
            ),
        ]

        static let beliefs = [
            Belief(id: "qrt", text: "You're in QRT's interview process."),
            Belief(id: "florence", text: "Florence with Janki on the 12th."),
            Belief(id: "5k", text: "Training for a sub-20 5K."),
            Belief(id: "bloomberg", text: "You're at Bloomberg, and looking for what's next."),
        ]

        static let reveal = OnboardingReveal(
            matters: [
                RevealMatter(
                    id: "job-search", title: "Job search",
                    line: "QRT interviews · Citadel screened · Optiver quiet", symbol: "target"),
                RevealMatter(
                    id: "florence", title: "Florence with Janki",
                    line: "12–15 Nov · hotel booked · 2 to book", symbol: "airplane"),
                RevealMatter(
                    id: "5k", title: "Sub-20 5K", line: "4 weeks left · Saturday parkrun",
                    symbol: "figure.run"),
                RevealMatter(
                    id: "dentist", title: "Dentist", line: "Fri 13 Nov 9:30 · bring the claim form",
                    symbol: "calendar"),
            ],
            added: [
                AddedEvent(title: "QRT technical interview", when: "Thu 5 Nov · 14:00"),
                AddedEvent(title: "Flight to Florence, BA 2610", when: "Thu 12 Nov · 19:05"),
                AddedEvent(title: "Hotel Orto, Florence", when: "12–15 Nov"),
            ])

        /// With nothing connected, Kumo starts from what you said alone.
        static let talkReveal = OnboardingReveal(
            matters: [
                RevealMatter(
                    id: "flat-move", title: "Flat move",
                    line: "You said it's eating your evenings", symbol: "shippingbox"),
                RevealMatter(
                    id: "italian", title: "Italian before Florence",
                    line: "Ten minutes a day, so you can order dinner", symbol: "text.bubble"),
            ])

        /// A model at `step`, with the sources whose ids are in `connected` connected.
        static func model(
            step: OnboardingModel.Step, connected: Set<String>,
            progress: OnboardingProgress? = nil,
            asking: KumoAsking = .asking(OnboardingSamples.questions[0]),
            beliefs: [Belief] = [], reveal: OnboardingReveal? = nil
        ) -> OnboardingModel {
            let sources = sources.map { source in
                var source = source
                source.connected = connected.contains(source.id)
                return source
            }
            var model: OnboardingModel?
            let actions = OnboardingActions(
                // Connecting starts the catch-up: the count rises, and the reveal comes at the end.
                connect: { source in
                    guard let model,
                        let index = model.sources.firstIndex(where: { $0.id == source.id })
                    else { return }
                    model.sources[index].connected = true
                    guard model.progress == nil else { return }
                    model.progress = OnboardingProgress(read: 0, total: 3100)
                    Task {
                        while let progress = model.progress, !progress.isDone {
                            try? await Task.sleep(for: .milliseconds(150))
                            model.progress?.read = min(progress.total, progress.read + 41)
                        }
                        model.reveal = Self.reveal
                    }
                },
                talk: {},
                answer: { id, _ in try await next(after: id) },
                skip: { id in try await next(after: id) },
                confirm: { _ in try await Task.sleep(for: .milliseconds(500)) },
                correct: { _, _ in try await Task.sleep(for: .milliseconds(500)) },
                setMorning: { _ in try await Task.sleep(for: .milliseconds(300)) },
                allowNotifications: {
                    try? await Task.sleep(for: .milliseconds(500))
                    return true
                },
                declineNotifications: {},
                finish: { try await Task.sleep(for: .seconds(1)) }
            )
            let made = OnboardingModel(
                step: step, sources: sources, progress: progress, asking: asking,
                beliefs: beliefs, reveal: reveal, actions: actions)
            model = made
            return made
        }

        /// Kumo's next question after `id`, a moment later, as if from the box.
        private static func next(after id: KumoQuestion.ID) async throws -> KumoQuestion? {
            try await Task.sleep(for: .milliseconds(700))
            guard let index = questions.firstIndex(where: { $0.id == id }),
                index + 1 < questions.count
            else { return nil }
            return questions[index + 1]
        }
    }
#endif
