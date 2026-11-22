import AriKit
import SwiftUI

/// A project, open: what it's for, its parts as a bar and a list, what's next, why it changed, and
/// Kumo's notes folded.
struct ProjectView: View {
    let detail: MotionDetail
    let project: Project

    var body: some View {
        MotionPage {
            MotionPageHead(kicker: "Project", title: detail.motion.title, subtitle: project.aim)
            KumoLine(detail.motion.summary).padding(.top, 16)
            if !project.parts.isEmpty {
                MotionLabel(
                    "Parts",
                    trailing:
                        "\(project.parts.filter { $0.status == .done }.count) of \(project.parts.count)"
                )
                .padding(.top, 28)
                PartsList(parts: project.parts).padding(.top, 10)
            }
            NextAndMore(detail: detail, next: project.next)
        }
    }
}

/// Something being learnt, open: the aim and the habit, its steps, the practice so far, and Kumo's
/// notes folded.
struct LearningView: View {
    let detail: MotionDetail
    let learning: Learning

    var body: some View {
        MotionPage {
            MotionPageHead(
                kicker: ["Learning", learning.habit].compactMap(\.self).joined(separator: " · "),
                title: detail.motion.title, subtitle: learning.aim)
            KumoLine(detail.motion.summary).padding(.top, 16)
            if !learning.steps.isEmpty {
                MotionLabel("Steps").padding(.top, 28)
                PartsList(parts: learning.steps).padding(.top, 10)
            }
            if !learning.log.isEmpty {
                MotionLabel("Practice", trailing: total).padding(.top, 28)
                MotionCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(learning.log.reversed()) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(CareerReading.short(entry.date))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.ariTertiary)
                                    .frame(width: 48, alignment: .leading)
                                Text(entry.text).font(.subheadline).foregroundStyle(.ariText)
                                Spacer(minLength: 6)
                                if let minutes = entry.minutes {
                                    Text("\(Int(minutes.rounded())) min").font(
                                        .caption.monospacedDigit()
                                    )
                                    .foregroundStyle(.ariSecondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .padding(.top, 10)
            }
            NextAndMore(detail: detail, next: learning.next)
        }
    }

    /// The practice's time all told, when it's known.
    private var total: String? {
        let minutes = learning.log.compactMap(\.minutes)
        return minutes.isEmpty ? nil : BodyReading.duration(minutes.reduce(0, +))
    }
}

/// Something with no shape yet, open: what it is and where it stands, who it's waiting on, what's
/// left to do, the back-and-forth, and Kumo's notes folded.
struct OtherView: View {
    let detail: MotionDetail
    let other: OtherMatter

    @Environment(Motions.self) private var motions: Motions?

    var body: some View {
        MotionPage {
            MotionPageHead(kicker: "Other", title: detail.motion.title, subtitle: other.about)
            KumoLine(detail.motion.summary).padding(.top, 16)
            if let status = other.status {
                Text(status).font(.subheadline).foregroundStyle(.ariSecondary).padding(.top, 8)
            }
            if let waiting = other.waitingOn {
                Text("Waiting on \(waiting.who), since \(CareerReading.short(waiting.since))")
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
                    .padding(.top, 6)
            }
            if !other.todo.isEmpty {
                MotionLabel("To do").padding(.top, 28)
                MotionCard(padding: 6) {
                    VStack(spacing: 0) {
                        ForEach(other.todo) { todo in
                            todoRow(todo)
                        }
                    }
                }
                .padding(.top, 10)
            }
            if !other.timeline.isEmpty {
                MotionLabel("So far").padding(.top, 28)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(other.timeline.reversed()) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(CareerReading.short(entry.at))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.ariTertiary)
                                .frame(width: 48, alignment: .leading)
                            Text(entry.text).font(.subheadline).foregroundStyle(.ariText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, 10)
            }
            NextAndMore(detail: detail, next: other.next)
        }
    }

    private func todoRow(_ todo: Trip.Todo) -> some View {
        let done = detail.state[OtherMatter.todoList]?[todo.id]?.done ?? todo.done
        return Button {
            Task {
                _ = await motions?.tick(
                    detail.motion.id, list: OtherMatter.todoList, item: todo.id, done: !done)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? Color.ariBone : .ariTertiary)
                Text(todo.text)
                    .font(.subheadline)
                    .foregroundStyle(done ? Color.ariTertiary : .ariText)
                    .strikethrough(done, color: .ariTertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(done ? "Done" : "Not done")
    }
}

/// Parts in order, each marked as the bar draws it.
private struct PartsList: View {
    let parts: [MotionPart]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Segments(parts: parts.map(\.status))
            MotionCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(parts) { part in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Segments(parts: [part.status], height: 8).frame(width: 14)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(part.title)
                                    .font(.subheadline)
                                    .foregroundStyle(
                                        part.status == .dropped ? Color.ariTertiary : .ariText
                                    )
                                    .strikethrough(part.status == .dropped, color: .ariTertiary)
                                if let note = part.note {
                                    Text(note).font(.footnote).foregroundStyle(.ariTertiary)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(part.status.rawValue)
                    }
                }
            }
        }
    }
}

/// What every kind ends its page with: what's next, why the plan changed, and Kumo's notes.
struct NextAndMore: View {
    let detail: MotionDetail
    let next: MotionNext?

    @Environment(\.openURL) private var openURL

    var body: some View {
        if let next {
            MotionLabel("Next", trailing: next.at.map { CareerReading.countdown(to: $0) }).padding(
                .top, 28)
            NextCard(next: next) { openURL($0) }.padding(.top, 10)
        }
        if !detail.extras.reasons.isEmpty {
            MotionLabel("Why it changed").padding(.top, 30)
            ReasonsList(reasons: detail.extras.reasons).padding(.top, 12)
        }
        KumoNotes(notes: detail.extras.notes).padding(.top, 30)
    }
}
