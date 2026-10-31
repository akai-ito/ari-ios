import AriKit
import SwiftUI

/// A pursuit, open: what you're after and how you play it, as Kumo wrote them from what you said,
/// then each option on a card of its own with where it stands and what's next. Nothing here is
/// tapped: to change it, you tell Kumo.
struct PursuitView: View {
    let detail: MotionDetail
    let pursuit: Pursuit

    var body: some View {
        let leading = PursuitReading.leading(in: pursuit)
        MatterPage {
            VStack(alignment: .leading, spacing: 6) {
                MatterEyebrow(kind: "Pursuit", motion: detail.motion)
                Text(detail.motion.title)
                    .font(.ariTitle)
                    .foregroundStyle(.ariText)
                    .accessibilityAddTraits(.isHeader)
            }
            MatterSection(title: "What you're after") {
                Text(pursuit.after)
                    .font(.ariBody)
                    .foregroundStyle(.ariText)
                    .lineSpacing(Rhythm.ariLineSpacing)
            }
            if !pursuit.play.isEmpty {
                MatterSection(title: "How you play it") {
                    VStack(alignment: .leading, spacing: Rhythm.listItemGap) {
                        ForEach(Array(pursuit.play.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("·").foregroundStyle(.ariTertiary).accessibilityHidden(true)
                                Text(line).foregroundStyle(.ariText)
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
            if !pursuit.options.isEmpty {
                VStack(spacing: 10) {
                    ForEach(pursuit.options) { option in
                        OptionCard(option: option, leads: leading.contains(option.id))
                    }
                }
                .animation(.smooth(duration: 0.4), value: pursuit.options)
            }
            MatterFootnote()
        }
    }
}

/// One option: its name in Kumo's hand with the role or organisation beside it, where it stands on a
/// chip (filled for the option furthest along), a thin bar of its stages, and what's next.
private struct OptionCard: View {
    let option: Pursuit.Option
    let leads: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stage = PursuitReading.stage(of: option)
        VStack(alignment: .leading, spacing: 10) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    heading
                    StatusChip(text: option.stage, filled: leads)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    heading
                    Spacer(minLength: 8)
                    StatusChip(text: option.stage, filled: leads)
                }
            }
            if let stage {
                StageBar(reached: stage.index, of: stage.count)
            }
            if let line = PursuitReading.line(of: option) {
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
            }
        }
        .matterCard()
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            [stage.map { "Stage \($0.index + 1) of \($0.count)" }, leads ? "Furthest along" : nil]
                .compactMap(\.self).joined(separator: ", "))
    }

    /// The name, and the role and organisation beside it, as one text so a long role wraps under.
    private var heading: some View {
        let beside = [option.role, option.org].compactMap(\.self).joined(separator: " · ")
        return Text(
            "\(Text(option.name).font(.ariHeading).foregroundStyle(.ariText))\(Text(beside.isEmpty ? "" : "  \(beside)").font(.footnote).foregroundStyle(.ariSecondary))"
        )
    }
}

/// An option's stages as a thin bar of segments, bone up to the one it's reached.
private struct StageBar: View {
    let reached: Int
    let of: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<of, id: \.self) { index in
                Capsule()
                    .fill(index <= reached ? Color.ariBone : .ariLine)
                    .frame(height: 3)
            }
        }
        .animation(.smooth(duration: 0.6), value: reached)
        .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview("Job search") {
        MatterPreview {
            PursuitView(detail: PursuitSample.detail, pursuit: PursuitSample.jobSearch)
        }
    }

    #Preview("Job search, largest type") {
        MatterPreview {
            PursuitView(detail: PursuitSample.detail, pursuit: PursuitSample.jobSearch)
        }
        .dynamicTypeSize(.accessibility2)
    }

    /// Divy's job search, as in the approved still.
    private enum PursuitSample {
        static let stages = ["Screened", "Interviews", "Awaiting answer", "Offer"]

        static let jobSearch = Pursuit(
            after: "AI engineering or C++ HFT systems, at quant firms, in London or Amsterdam.",
            play: [
                "New reach-out: why you're excited, CV, offer a call.",
                "Interviews a week or two out if the type is new to you.",
                "Calls on WFH days; check work with you first.",
                "Off-target recruiters: a kind note on what you do want.",
            ],
            options: [
                .init(
                    id: "qrt", name: "QRT", role: "Senior AI Engineer", stage: "Awaiting answer",
                    stages: stages, people: [.init(name: "Poppy", role: "Recruiter")],
                    note: "Technical done today"),
                .init(
                    id: "citadel", name: "Citadel", role: "AI Engineering, FI",
                    stage: "Interviews", stages: stages,
                    people: [.init(name: "Katia", role: "Recruiter")],
                    next: .init(text: "Second round", at: .day(17, at: 14))),
                .init(
                    id: "optiver", name: "Optiver", role: "Software Engineer", stage: "Test done",
                    stages: ["Test done", "Interviews", "Awaiting answer", "Offer"],
                    waitingOn: .init(who: "them", since: .day(-43, at: 10))),
            ])

        static let detail = MotionDetail(
            motion: Motion(
                id: "job-search", kind: .pursuit, title: "Job search",
                summary: "QRT awaiting answer · Citadel second round", startedAt: .day(-60, at: 9)
            ),
            content: .pursuit(jobSearch))
    }
#endif
