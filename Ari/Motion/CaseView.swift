import AriKit
import SwiftUI

/// A case, open: the problem in Kumo's words, where it stands and who it's waiting on, what's next,
/// and what's happened so far, newest first. Nothing here is tapped: to change it, you tell Kumo.
struct CaseView: View {
    let detail: MotionDetail
    let file: CaseFile

    var body: some View {
        MatterPage {
            VStack(alignment: .leading, spacing: 6) {
                MatterEyebrow(kind: "Case", motion: detail.motion)
                Text(detail.motion.title)
                    .font(.ariTitle)
                    .foregroundStyle(.ariText)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(file.problem)
                .font(.ariBody)
                .foregroundStyle(.ariText)
                .lineSpacing(Rhythm.ariLineSpacing)
            standing
            if let next = file.next {
                MatterSection(title: "Next") {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "arrow.turn.down.right")
                            .foregroundStyle(.ariBone)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(next.text).foregroundStyle(.ariText)
                            if let at = next.at {
                                Text(MatterReading.when(at))
                                    .font(.footnote)
                                    .foregroundStyle(.ariSecondary)
                            }
                        }
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                }
            }
            if !file.timeline.isEmpty {
                MatterSection(title: "What's happened") {
                    CaseTimeline(entries: CaseReading.timeline(file))
                }
            }
            MatterFootnote()
        }
    }

    /// Where it stands, and who it's waiting on.
    private var standing: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(file.status)
                .font(.headline)
                .foregroundStyle(.ariText)
            if let waiting = file.waitingOn {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "hourglass")
                        .foregroundStyle(.ariBone)
                        .accessibilityHidden(true)
                    Text(MatterReading.waiting(waiting))
                        .foregroundStyle(.ariSecondary)
                }
                .font(.subheadline)
            }
        }
        .matterCard()
        .accessibilityElement(children: .combine)
    }
}

/// What's happened, on a rail like What changed: the newest at the top, in bone.
private struct CaseTimeline: View {
    let entries: [CaseFile.Entry]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(index == 0 ? Color.ariBone : .ariDusk)
                            .frame(width: 7, height: 7)
                            .padding(.top, 6)
                        if index < entries.count - 1 {
                            Rectangle().fill(.ariLine).frame(width: 1)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.text)
                            .font(.subheadline)
                            .foregroundStyle(.ariText)
                        Text(MatterReading.day(entry.at))
                            .font(.caption)
                            .foregroundStyle(.ariTertiary)
                    }
                    .padding(.bottom, 16)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

#if DEBUG
    #Preview("Boiler repair") {
        MatterPreview {
            CaseView(detail: CaseSample.detail, file: CaseSample.boiler)
        }
    }

    /// The boiler, waiting on the landlord.
    private enum CaseSample {
        static let boiler = CaseFile(
            problem: "The boiler cuts out after ten minutes, so there's no hot water past a "
                + "short shower.",
            status: "Reported to the landlord",
            waitingOn: .init(who: "the landlord", since: .day(-8, at: 10)),
            timeline: [
                .init(
                    id: "fault", at: .day(-9, at: 19),
                    text: "The boiler showed fault F28; you reset it twice"),
                .init(
                    id: "emailed", at: .day(-8, at: 10),
                    text: "Emailed the landlord the fault code and your video"),
                .init(id: "chased", at: .day(-4, at: 9), text: "Chased: no reply yet"),
            ],
            next: .init(
                text: "Chase the letting agency if there's still no reply", at: .day(2, at: 9)))

        static let detail = MotionDetail(
            motion: Motion(
                id: "boiler", kind: .caseFile, title: "Boiler repair",
                summary: "Waiting on the landlord", startedAt: .day(-9, at: 19)),
            content: .caseFile(boiler))
    }
#endif
