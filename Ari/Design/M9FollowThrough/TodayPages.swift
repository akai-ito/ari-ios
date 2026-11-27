#if DEBUG
    import AriKit
    import SwiftUI

    // MARK: - Samples

    struct DreamGroupSample: Identifiable {
        var id: String { title }
        let title: String
        let lines: [String]
    }

    struct PlanSample: Identifiable {
        var id: String { title + time }
        let time: String
        let title: String
        var repeats: String?
    }

    struct DoneSample: Identifiable {
        var id: String { text }
        let text: String
        let time: String
    }

    enum TodaySamples {
        static let lastNight: [DreamGroupSample] = [
            DreamGroupSample(
                title: "Planned",
                lines: [
                    "Your run moves to 07:30, before the rain",
                    "Half an hour for Halcyon prep at 11:00",
                    "Dropped Friday's boiler reminder; it's fixed",
                ]),
            DreamGroupSample(
                title: "Tidied",
                lines: [
                    "Leo's two pages are one now",
                    "Twelve Northwind notes, folded into its page",
                    "Monday's journal, written",
                ]),
            DreamGroupSample(
                title: "Noticed",
                lines: ["Three late nights in a row", "Mira's birthday is a week on Friday"]),
            DreamGroupSample(
                title: "Saved for you",
                lines: [
                    "Sam at Halcyon's notes, ready for 11:00",
                    "A gift idea for Mira, from the shop she loved",
                ]),
        ]

        static let manual: [DreamGroupSample] = [
            DreamGroupSample(
                title: "Planned", lines: ["A quiet half hour after Northwind, at 15:15"]),
            DreamGroupSample(
                title: "Tidied", lines: ["This morning's notes, into today's journal"]),
            DreamGroupSample(
                title: "Noticed", lines: ["You've not eaten since breakfast"]),
        ]

        static let morningPlans: [PlanSample] = [
            PlanSample(time: "11:00", title: "Prep for Halcyon, half an hour"),
            PlanSample(time: "13:30", title: "A calm five minutes before Northwind"),
            PlanSample(time: "18:45", title: "Ask how Northwind went"),
            PlanSample(time: "23:45", title: "Aligner change", repeats: "Tuesdays · 4 left"),
        ]

        static let afternoonPlans: [PlanSample] = [
            PlanSample(time: "18:45", title: "Ask how Northwind went"),
            PlanSample(time: "21:30", title: "Nudge you toward bed"),
            PlanSample(time: "23:45", title: "Aligner change", repeats: "Tuesdays · 4 left"),
        ]

        static let morningDone: [DoneSample] = [
            DoneSample(text: "Told Leo the run's at 07:30", time: "07:02"),
            DoneSample(text: "Cleared 14 newsletters", time: "07:15"),
            DoneSample(text: "Confirmed Kiln for 19:30", time: "07:31"),
        ]

        static let afternoonDone: [DoneSample] = [
            DoneSample(text: "Moved Sam's call to Thursday", time: "15:40"),
            DoneSample(text: "Sent Mira the Kiln booking", time: "16:05"),
            DoneSample(text: "Cleared 14 newsletters", time: "07:15"),
        ]
    }

    // MARK: - The moon or sun's page

    /// What the moon opens (and the sun, once you've looked): last night's dream when it's new,
    /// short lines in four groups, each with its detail and Undo a tap away; then today's plans
    /// and what's done; Dream now at the foot.
    struct NightPage: View {
        let shown: NightShown

        @State private var detail: DetailShown?

        enum DetailShown: String, Identifiable {
            case dreamLine, done
            var id: String { rawValue }
        }

        private var morning: Bool { shown != .manual && shown != .doneDetail }

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        header
                        if shown == .replay { ReplayStrip() }
                        if morning {
                            dream(groups: TodaySamples.lastNight)
                        } else if shown == .manual {
                            dream(groups: TodaySamples.manual)
                        }
                        Rectangle().fill(Color.ariLine).frame(height: 1).padding(.vertical, -6)
                        plans
                        done
                        foot
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(shown == .lower ? .bottom : .top)
                .background(.ariBackground)
                .toolbar(.hidden, for: .navigationBar)
            }
            .sheet(item: $detail) { detail in
                Group {
                    switch detail {
                    case .dreamLine: WorkDetailSheet.dreamLine
                    case .done: WorkDetailSheet.done
                    }
                }
                .presentationDetents([.fraction(0.6)])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ariBackground)
            }
            .task {
                try? await Task.sleep(for: .milliseconds(700))
                switch shown {
                case .dreamLine: detail = .dreamLine
                case .doneDetail: detail = .done
                default: break
                }
            }
        }

        @ViewBuilder
        private var header: some View {
            if morning {
                PageHeader(title: "Last night", subtitle: "Dreamt at 04:00 · while you slept") {
                    SkyGlyph(kind: .moon, side: 46)
                }
            } else {
                PageHeader(title: "Today", subtitle: "Tuesday 1 December") {
                    SkyGlyph(kind: .sun, side: 46)
                }
            }
        }

        private func dream(groups: [DreamGroupSample]) -> some View {
            VStack(alignment: .leading, spacing: 24) {
                if shown == .manual {
                    HStack(spacing: 8) {
                        SkyGlyph(kind: .moon, side: 22)
                        Text("Dreamt at 14:20")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.ariSecondary)
                        Text("· you asked").font(.footnote).foregroundStyle(.ariTertiary)
                    }
                }
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        DeskSectionLabel(group.title)
                        ForEach(group.lines, id: \.self) { line in
                            DreamLineRow(text: line)
                        }
                    }
                }
            }
        }

        private var plans: some View {
            VStack(alignment: .leading, spacing: 14) {
                DeskSectionLabel("Plans today")
                ForEach(morning ? TodaySamples.morningPlans : TodaySamples.afternoonPlans) { plan in
                    PlanSampleRow(plan: plan)
                }
                MoreLink(text: "Later this week · 6 more")
            }
        }

        private var done: some View {
            VStack(alignment: .leading, spacing: 14) {
                DeskSectionLabel("Done today")
                ForEach(morning ? TodaySamples.morningDone : TodaySamples.afternoonDone) { entry in
                    DoneSampleRow(entry: entry)
                }
                MoreLink(text: morning ? "Everything I've done" : "and 4 more")
            }
        }

        private var foot: some View {
            VStack(alignment: .leading, spacing: 10) {
                DeskPill(title: "Dream now") {}
                Text(
                    shown == .manual
                        ? "Dreamt at 14:20. I'll still dream at 04:00 tonight. Change the time in Settings."
                        : "I dream at 04:00 each night. Change the time in Settings."
                )
                .font(.footnote)
                .foregroundStyle(.ariTertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)
        }
    }

    /// A line from the dream: what Kumo did, plainly; a tap opens why, and Undo.
    struct DreamLineRow: View {
        let text: String

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.ariText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.ariTertiary)
            }
        }
    }

    /// A plan: its time, its plain title, and how it repeats.
    struct PlanSampleRow: View {
        let plan: PlanSample
        var timeWidth: CGFloat = 46

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(plan.time)
                    .monospacedDigit()
                    .foregroundStyle(.ariTertiary)
                    .frame(width: timeWidth, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.title).foregroundStyle(.ariText)
                    if let repeats = plan.repeats {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.trianglehead.2.clockwise")
                                .font(.caption2.weight(.semibold))
                            Text(repeats)
                        }
                        .font(.footnote)
                        .foregroundStyle(.ariTertiary)
                    }
                }
                Spacer(minLength: 8)
            }
            .font(.subheadline)
        }
    }

    /// Something done: a tick and one line; detail on tap.
    struct DoneSampleRow: View {
        let entry: DoneSample

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.ariSecondary)
                    .frame(width: 16)
                Text(entry.text).foregroundStyle(.ariText)
                Spacer(minLength: 8)
                Text(entry.time).monospacedDigit().font(.footnote).foregroundStyle(.ariTertiary)
            }
            .font(.subheadline)
        }
    }

    struct MoreLink: View {
        let text: String

        var body: some View {
            HStack(spacing: 4) {
                Text(text)
                Image(systemName: "chevron.right").imageScale(.small)
            }
            .font(.footnote)
            .foregroundStyle(.ariTertiary)
        }
    }

    /// Last night's weave, small at the top of the page; a tap replays it.
    struct ReplayStrip: View {
        var body: some View {
            ZStack(alignment: .bottomLeading) {
                WeaveCanvas(stage: .tomorrow, compact: true)
                    .padding(.vertical, 14)
                HStack(spacing: 6) {
                    Image(systemName: "play.fill").font(.caption2)
                    Text("Replay last night · 12 s")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.ariText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular.interactive(), in: Capsule())
                .padding(10)
            }
            .frame(height: 200)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.ariText.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.ariLine.opacity(0.7), lineWidth: 1)
            )
            .clipShape(.rect(cornerRadius: 20, style: .continuous))
        }
    }

    // MARK: - Detail sheets

    /// The detail behind a line: what happened, why, and what you can do about it.
    struct WorkDetailSheet: View {
        let title: String
        let when: String
        let sections: [(String, String)]
        var link: String?
        let actions: [String]
        var footnote: String?
        var upcoming: [String] = []

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.system(.title2, design: .serif))
                            .foregroundStyle(.ariText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(when).font(.footnote).foregroundStyle(.ariTertiary)
                    }
                    ForEach(sections, id: \.0) { label, text in
                        VStack(alignment: .leading, spacing: 8) {
                            DeskSectionLabel(label)
                            Text(text)
                                .font(.subheadline)
                                .foregroundStyle(.ariSecondary)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !upcoming.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            DeskSectionLabel("Coming up")
                            HStack(spacing: 0) {
                                ForEach(Array(upcoming.enumerated()), id: \.offset) { i, date in
                                    VStack(spacing: 6) {
                                        Circle()
                                            .fill(
                                                i == 0 ? Color.ariText : .ariSecondary.opacity(0.6)
                                            )
                                            .frame(width: i == 0 ? 8 : 6, height: i == 0 ? 8 : 6)
                                        Text(date)
                                            .font(.caption2)
                                            .foregroundStyle(
                                                i == 0 ? Color.ariSecondary : .ariTertiary)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            .background(alignment: .top) {
                                DottedRule().frame(height: 2).padding(.top, 3).padding(
                                    .horizontal, 30)
                            }
                        }
                    }
                    if let link { MoreLink(text: link) }
                    HStack(spacing: 10) {
                        ForEach(actions, id: \.self) { action in
                            DeskPill(title: action) {}
                        }
                    }
                    if let footnote {
                        Text(footnote).font(.footnote).foregroundStyle(.ariTertiary)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 28)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(.ariBackground)
        }

        static let dreamLine = WorkDetailSheet(
            title: "Your run moves to 07:30, before the rain",
            when: "Planned in last night's dream · 04:12",
            sections: [
                (
                    "Why",
                    "Rain from 08:00, and Northwind at 2 leaves no room later. Leo's free at 07:30 too."
                ),
                ("What changed", "Run with Leo, 08:15 → 07:30. I told Leo; he said fine."),
            ],
            actions: ["Undo", "That was wrong"],
            footnote: "Undo puts it back at 08:15 and lets Leo know.")

        static let done = WorkDetailSheet(
            title: "Cleared 14 newsletters",
            when: "Done at 07:15",
            sections: [
                (
                    "What I did",
                    "Archived 14 newsletters you hadn't opened in a month. Kept Northwind's and Kiln's."
                ),
                ("Why", "You said newsletters can wait unless they're from somewhere you book."),
            ],
            link: "See them in Mail",
            actions: ["Undo", "That was wrong"])

        static let plan = WorkDetailSheet(
            title: "Aligner change",
            when: "Tuesdays at 23:45 · 4 left",
            sections: [
                (
                    "Why",
                    "You're on tray 9 of 12. Quillfield Dental said to switch weekly, late, so each one settles overnight."
                ),
                (
                    "What I'll do",
                    "Message you at 23:45 with the next tray's number, and tick it off on your Health page when you say done."
                ),
            ],
            actions: ["Move…", "Skip tonight", "Stop all four"],
            upcoming: ["Tonight", "8 Dec", "15 Dec", "22 Dec"])
    }

    struct DottedRule: View {
        var body: some View {
            Canvas { canvas, size in
                var dots = Path()
                for x in stride(from: 0, through: size.width, by: 5) {
                    dots.addEllipse(
                        in: CGRect(x: x - 0.8, y: size.height / 2 - 0.8, width: 1.6, height: 1.6))
                }
                canvas.fill(dots, with: .color(.ariTertiary.opacity(0.6)))
            }
        }
    }

    // MARK: - Plans

    /// All of Kumo's plans, with plain titles: one-offs by when, and each repeat once, grouped.
    struct PlansPage: View {
        let opensDetail: Bool

        @State private var detail = false

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        section(
                            "Today",
                            [
                                PlanSample(time: "18:45", title: "Ask how Northwind went"),
                                PlanSample(time: "21:30", title: "Nudge you toward bed"),
                                PlanSample(
                                    time: "23:45", title: "Aligner change",
                                    repeats: "Tuesdays · 4 left"),
                            ])
                        section(
                            "Tomorrow",
                            [
                                PlanSample(
                                    time: "09:00", title: "Water the basil", repeats: "Every 3 days"
                                ),
                                PlanSample(time: "10:00", title: "See if Sam at Halcyon replied"),
                            ])
                        section(
                            "Later this week",
                            [
                                PlanSample(time: "Thu 12:00", title: "Order Mira's birthday gift"),
                                PlanSample(
                                    time: "Fri 18:00", title: "Look back on the week with you",
                                    repeats: "Fridays"),
                            ], wide: true)
                        repeating
                        Text(
                            "Long-press a plan to move or cancel it. Tell me to change anything else."
                        )
                        .font(.footnote)
                        .foregroundStyle(.ariTertiary)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
                .background(.ariBackground)
                .navigationTitle("Plans")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Image(systemName: "chevron.left").fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $detail) {
                WorkDetailSheet.plan
                    .presentationDetents([.fraction(0.66)])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.ariBackground)
            }
            .task {
                guard opensDetail else { return }
                try? await Task.sleep(for: .milliseconds(700))
                detail = true
            }
        }

        private func section(_ title: String, _ plans: [PlanSample], wide: Bool = false)
            -> some View
        {
            VStack(alignment: .leading, spacing: 14) {
                DeskSectionLabel(title)
                ForEach(plans) { plan in
                    PlanSampleRow(plan: plan, timeWidth: wide ? 72 : 46)
                }
            }
        }

        private var repeating: some View {
            VStack(alignment: .leading, spacing: 14) {
                DeskSectionLabel("Repeating")
                repeatRow("Aligner change", "Tuesdays 23:45 · 4 left")
                repeatRow("Water the basil", "Every 3 days, 09:00")
                repeatRow("Look back on the week", "Fridays 18:00")
                repeatRow("Nudge you toward bed", "Weeknights 21:30")
            }
        }

        private func repeatRow(_ title: String, _ when: String) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "arrow.trianglehead.2.clockwise")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.ariTertiary)
                    .frame(width: 16)
                Text(title).foregroundStyle(.ariText)
                Text("·").foregroundStyle(.ariTertiary)
                Text(when).foregroundStyle(.ariSecondary)
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .lineLimit(1)
        }
    }
#endif
