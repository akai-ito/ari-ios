#if DEBUG
    import AriKit
    import SwiftUI

    struct QuestionSample: Identifiable {
        var id: String { missing }
        let understands: String
        let missing: String
        let why: String
    }

    /// What tapping Kumo opens: how well it's getting to know you, as tracks, and the few things
    /// it would still like to understand, quietly. No counts that nag, nothing overdue.
    struct KnowYouPage: View {
        let opensQuestion: Bool

        @State private var asking = false

        static let tracks: [(String, Int)] = [
            ("Your mornings", 7), ("How you write", 5), ("Who matters", 6),
            ("What wears you out", 2), ("Money and bookings", 4),
        ]

        static let questions: [QuestionSample] = [
            QuestionSample(
                understands: "You keep mornings clear before 10.",
                missing: "Is that every day, or only on office days?",
                why: "So I can place calls without checking each time."),
            QuestionSample(
                understands: "Late calls leave you flat the next day.",
                missing: "Is it the hour, or who the call's with?",
                why: "So I know what to keep off your evenings."),
            QuestionSample(
                understands: "You like hearing about Mira's plans early.",
                missing: "How early is early: a week, or a month?",
                why: "So her birthday never sneaks up on you."),
        ]

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    HStack(spacing: 6) {
                        KumoFace(mood: .cosy, size: 54).frame(width: 64)
                        Text("Getting to know you")
                            .font(.ariHeading)
                            .foregroundStyle(.ariText)
                    }
                    VStack(spacing: 14) {
                        ForEach(Self.tracks, id: \.0) { name, lit in
                            HStack {
                                Text(name).font(.subheadline).foregroundStyle(.ariSecondary)
                                Spacer(minLength: 12)
                                NineDots(lit: lit)
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.ariTertiary)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        DeskSectionLabel("Understanding you")
                        ForEach(Self.questions) { question in
                            OpenQuestionCard(question: question)
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark").font(.caption2.weight(.bold))
                            Text("Settled lately: 4")
                            Image(systemName: "chevron.right").imageScale(.small)
                        }
                        .font(.footnote)
                        .foregroundStyle(.ariTertiary)
                        .padding(.top, 4)
                    }
                    Text("No rush on any of these. I'll sometimes ask in passing, one at a time.")
                        .font(.footnote)
                        .foregroundStyle(.ariTertiary)
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(.ariBackground)
            .sheet(isPresented: $asking) {
                QuestionSheet(question: Self.questions[0])
                    .presentationDetents([.fraction(0.8)])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.ariBackground)
            }
            .task {
                guard opensQuestion else { return }
                try? await Task.sleep(for: .milliseconds(700))
                asking = true
            }
        }
    }

    /// Nine dots in three groups of three, lit up to how far Kumo has come.
    struct NineDots: View {
        let lit: Int

        var body: some View {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { group in
                    HStack(spacing: 4.5) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .fill(group * 3 + i < lit ? Color.ariText.opacity(0.85) : .ariLine)
                                .frame(width: 6, height: 6)
                        }
                    }
                }
            }
        }
    }

    /// One open question, quietly: what Kumo knows, the piece it's missing, and why it'd help.
    struct OpenQuestionCard: View {
        let question: QuestionSample

        var body: some View {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(question.understands)
                        .font(.footnote)
                        .foregroundStyle(.ariTertiary)
                    Text(question.missing)
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(.ariText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(question.why)
                        .font(.footnote)
                        .foregroundStyle(.ariSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.ariTertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.ariBone.opacity(0.06)))
        }
    }

    /// Answering a question: the three parts in full, a few quick answers, writing or talking,
    /// and the gentle ways out.
    struct QuestionSheet: View {
        let question: QuestionSample

        var body: some View {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    DeskSectionLabel("What I understand")
                    Text(
                        "You keep mornings clear before 10. You've moved three calls out of them this month, and you sounded better on the days you did."
                    )
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(.ariSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    DeskSectionLabel("The missing piece")
                    Text(question.missing)
                        .font(.system(.title2, design: .serif))
                        .foregroundStyle(.ariText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    DeskSectionLabel("Why it'd help")
                    Text(
                        "I could place calls for you without checking each time, and keep the rest of your mornings yours."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.ariSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        QuickChoice("Every day")
                        QuickChoice("Office days only")
                    }
                    HStack(spacing: 8) {
                        QuickChoice("Mondays to Thursdays")
                        QuickChoice("It depends")
                    }
                }
                HStack(spacing: 10) {
                    Text("Or write it")
                        .foregroundStyle(.ariTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(.ariLine, lineWidth: 1))
                    Image(systemName: "waveform")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.ariText)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                HStack(spacing: 22) {
                    Text("Not now")
                    Text("None fit")
                    Text("Not sure")
                }
                .font(.subheadline)
                .foregroundStyle(.ariSecondary)
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.top, 30)
        }
    }

    /// A quick answer, outlined like a choice in the chat.
    struct QuickChoice: View {
        let title: String

        init(_ title: String) { self.title = title }

        var body: some View {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.ariText)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .overlay(Capsule().strokeBorder(Color.ariLine, lineWidth: 1))
        }
    }
#endif
