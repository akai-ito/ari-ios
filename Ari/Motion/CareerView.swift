import AriKit
import SwiftUI

/// One role, open: Kumo's line, the pipeline with when each stage came, the next step with its
/// source to open, the key facts, and Kumo's notes folded at the bottom.
struct CareerView: View {
    let detail: MotionDetail
    let career: Career

    @Environment(\.openURL) private var openURL

    var body: some View {
        MotionPage {
            MotionPageHead(
                art: .career,
                kicker: "Career · \(career.stage.rawValue)",
                title: career.org,
                subtitle: [career.role, career.where].compactMap(\.self).joined(separator: " · "))
            KumoLine(detail.motion.summary).padding(.top, 16)

            Pipeline(
                stage: CareerReading.position(of: career), node: 12, line: 3,
                labels: ["lead", "talking", "interviewing", "offer"],
                dates: CareerReading.dates(of: career), faded: career.stage == .ended
            )
            .padding(.top, 28)

            if let next = career.next {
                MotionLabel("Next", trailing: next.at.map { CareerReading.countdown(to: $0) })
                    .padding(.top, 30)
                NextCard(next: next) { openURL($0) }.padding(.top, 10)
            } else if let waiting = career.waitingOn {
                MotionLabel("Waiting").padding(.top, 30)
                MotionCard {
                    Text("On \(waiting.who), since \(CareerReading.short(waiting.since))")
                        .font(.subheadline)
                        .foregroundStyle(.ariSecondary)
                }
                .padding(.top, 10)
            }

            if !career.rounds.isEmpty || !career.facts.isEmpty {
                MotionLabel("Key facts").padding(.top, 30)
                VStack(spacing: 0) {
                    if !career.rounds.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Rounds").font(.subheadline).foregroundStyle(.ariTertiary)
                            Pipeline(
                                stage: roundPosition, node: 8, line: 2,
                                labels: career.rounds.map(\.title))
                        }
                        .padding(.vertical, 12)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            "Rounds: "
                                + career.rounds.map { "\($0.title), \($0.status.rawValue)" }
                                .joined(separator: "; "))
                    }
                    ForEach(career.facts) { fact in
                        if fact.id != career.facts.first?.id || !career.rounds.isEmpty {
                            Hairline()
                        }
                        FactRow(label: fact.label, value: fact.value)
                    }
                }
                .padding(.horizontal, 14)
                .background(.ariSurface, in: .rect(cornerRadius: 20, style: .continuous))
                .padding(.top, 10)
            }

            KumoNotes(notes: detail.extras.notes).padding(.top, 30)
        }
    }

    /// The round that's next, or the last one done.
    private var roundPosition: Int {
        if let next = career.rounds.firstIndex(where: { $0.status == .next }) { return next }
        return career.rounds.lastIndex { $0.status == .done } ?? -1
    }
}

/// The next step: its day as a calendar leaf, what it is and when, and its source to open.
struct NextCard: View {
    let next: MotionNext
    let open: (URL) -> Void

    var body: some View {
        MotionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    if let at = next.at {
                        VStack(spacing: 0) {
                            Text(at.date().formatted(.dateTime.month(.abbreviated)).uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .kerning(0.6)
                                .foregroundStyle(.ariBackground)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 2)
                                .background(.ariBone)
                            Text(at.date().formatted(.dateTime.day()))
                                .font(.system(size: 22, weight: .semibold, design: .serif))
                                .foregroundStyle(.ariText)
                                .frame(maxHeight: .infinity)
                        }
                        .frame(width: 46, height: 50)
                        .background(.ariField)
                        .clipShape(.rect(cornerRadius: 9, style: .continuous))
                        .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(next.text).font(.headline).foregroundStyle(.ariText)
                        if let when {
                            Text(when).font(.subheadline).foregroundStyle(.ariSecondary)
                        }
                        if let detail = next.detail {
                            Text(detail).font(.subheadline).foregroundStyle(.ariTertiary)
                        }
                    }
                }
                if let link = next.link {
                    DeskPill(title: link.label) { open(link.url) }
                }
            }
        }
    }

    /// "Mon · 14:00–15:15".
    private var when: String? {
        guard let at = next.at else { return nil }
        let day = at.date().formatted(.dateTime.weekday(.abbreviated))
        guard let start = CareerReading.time(at) else { return day }
        let end = next.end.flatMap { CareerReading.time($0) }
        return "\(day) · \(start)\(end.map { "–\($0)" } ?? "")"
    }
}
