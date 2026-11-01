import AriKit
import SwiftUI

/// What Kumo says for the moment, at the top of the Desk: one or two sentences, right for now. It
/// changes only when the moment does, or something important happens, and never repeats the cards
/// below it. Otherwise it's all quiet, in words the app puts together without a model.
struct KumoMoment: Identifiable, Equatable {
    let id: String
    /// Kumo's own words: one or two sentences.
    let text: String
    /// A quieter line under them, such as the plan under a free day.
    var detail: String?
    /// Small actions under it, where they fit.
    var actions: [Action] = []
    /// The day's one question: labelled as such, and skippable.
    var asks = false
    /// Your answer, while Kumo acts on it.
    var answered: String?

    struct Action: Identifiable, Equatable {
        var id: String { title }
        let title: String
        /// Leads somewhere, such as Reply: drawn with a chevron.
        var opens = false
    }
}

extension KumoMoment {
    /// Reply, which opens a field for words when Kumo's line takes them.
    static let reply = Action(title: "Reply", opens: true)

    /// Kumo's line as the box sends it: its quieter line under it, its options as short replies,
    /// and Reply, or what the box calls it, when words fit. The day's question can be skipped.
    init(_ moment: Moment) {
        let reply = moment.replyLabel.map { Action(title: $0, opens: true) } ?? Self.reply
        self.init(
            id: moment.id.rawValue, text: moment.text, detail: moment.detail,
            actions: moment.options.map { Action(title: $0.label) }
                + (moment.allowsText ? [reply] : []),
            asks: moment.kind == .question,
            answered: moment.isWorking ? (moment.answer?.option ?? moment.answer?.text ?? "") : nil)
    }

    /// All quiet: no model's words, only how much Kumo handled today. With cards still waiting,
    /// nothing new has come since Kumo last spoke.
    static func quiet(handled: Int, waiting: Bool) -> KumoMoment {
        let things = handled == 1 ? "1 small thing" : "\(handled) small things"
        let start = waiting ? "Nothing new." : "All quiet."
        return KumoMoment(id: "quiet", text: handled == 0 ? start : "\(start) I handled \(things).")
    }
}

/// Whether Kumo is keeping up: reading, with when the last mail came in, or something's wrong; or
/// nothing to say, with no mail connected.
enum KumoLiveness: Equatable {
    case reading(lastMail: Date)
    case wrong
    case idle

    /// From the Desk and the server's problems.
    init(lastMail: Timestamp?, hasProblems: Bool) {
        if hasProblems {
            self = .wrong
        } else if let lastMail {
            self = .reading(lastMail: lastMail.date)
        } else {
            self = .idle
        }
    }
}

/// The top of the Desk: Kumo's face, a tiny line on how it is, and what it says for the moment.
/// Tapping the face, or the line while all's well, opens Kumo's work.
struct KumoSays: View {
    let moment: KumoMoment?
    let liveness: KumoLiveness
    let openWork: () -> Void
    let openSettings: () -> Void
    /// Opens what's wrong, from "Something's wrong ›".
    let openProblem: () -> Void
    var act: (KumoMoment.Action) -> Void = { _ in }
    var skip: () -> Void = {}
    /// Your answer on its way, and why it didn't go through.
    var sending = DeskSending()

    @State private var presence = PoseHistory()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                Button(action: openWork) {
                    PresenceView(history: presence, size: 44)
                        .frame(width: 64, height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(LeadName.current)'s work")
                .accessibilityHint(
                    "Shows what \(LeadName.current) did today, and how much it checks with you"
                )
                .padding(.bottom, 2)
                KumoStatusLine(
                    liveness: liveness, open: liveness == .wrong ? openProblem : openWork)
                if let moment {
                    MomentView(moment: moment, sending: sending, act: act, skip: skip)
                        .id(moment.id)
                        .transition(
                            reduceMotion
                                ? .opacity : .opacity.combined(with: .offset(y: 6))
                        )
                        .padding(.top, 16)
                }
            }
            .frame(maxWidth: .infinity)
            SettingsButton(action: openSettings)
        }
        .padding(.top, 12)
        .animation(.smooth(duration: 0.4), value: moment)
        .onChange(of: pose, initial: true) { _, pose in presence.set(pose) }
    }

    /// Asking, with its question mark, when Kumo asks you something; awake and looking at you when
    /// it has something for you to act on; a quiet stone when all's quiet; a little off when
    /// something's wrong.
    private var pose: Pose {
        if liveness == .wrong { return .unwell }
        guard let moment else { return .resting }
        if moment.answered != nil { return .thinking }
        if moment.asks || moment.text.hasSuffix("?") { return .asking }
        return moment.actions.isEmpty ? .resting : .noticed
    }
}

/// How Kumo is, in one tiny line under its face: "Reading · last mail 2 min ago", or, when
/// something's wrong, "Something's wrong ›", which opens what.
struct KumoStatusLine: View {
    let liveness: KumoLiveness
    let open: () -> Void

    var body: some View {
        if liveness != .idle { line }
    }

    private var line: some View {
        Button(action: open) {
            switch liveness {
            case .idle:
                EmptyView()
            case .reading(let lastMail):
                // The timeline's date is the minute's start; the line says what the clock says.
                TimelineView(.everyMinute) { _ in
                    Text("Reading · last mail \(Self.ago(lastMail, now: .now))")
                        .foregroundStyle(.ariTertiary)
                }
            case .wrong:
                Text("Something's wrong \(Text("›").foregroundStyle(.ariTertiary))")
                    .fontWeight(.semibold)
                    .foregroundStyle(.ariBone)
            }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .accessibilityHint(
            liveness == .wrong ? "Shows what's wrong" : "Shows \(LeadName.current)'s work")
    }

    /// "just now", "2 min ago", or the time, past an hour.
    static func ago(_ date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        return "at \(date.formatted(DeskTime.time))"
    }
}

/// Kumo's words for the moment, in its own hand and a size up from the cards, with the small
/// actions under them. The day's question carries a small label and a Skip.
private struct MomentView: View {
    let moment: KumoMoment
    let sending: DeskSending
    let act: (KumoMoment.Action) -> Void
    let skip: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if moment.asks {
                Text("Today's question")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.ariBone)
                    .padding(.bottom, -4)
            }
            Text(moment.text)
                .font(.system(.title3, design: .serif))
                .foregroundStyle(.ariText)
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = moment.detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.ariSecondary)
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let answered = moment.answered {
                // Your answer, then Kumo at work on it, as on a card.
                VStack(alignment: .leading, spacing: 8) {
                    DeskAnswerLine(text: answered)
                    DeskWorkingLine(text: "\(LeadName.current)'s on it…")
                }
                .padding(.top, 2)
            } else if !moment.actions.isEmpty || moment.asks {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { buttons }
                    VStack(spacing: 8) { buttons }
                }
                .disabled(sending.isSending)
                .padding(.top, 2)
            }
            if let problem = sending.problem { DeskProblemLine(text: problem) }
        }
        .frame(maxWidth: 340)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var buttons: some View {
        ForEach(moment.actions) { action in
            DeskPill(
                title: action.opens ? "\(action.title) ›" : action.title,
                busy: sending.key == action.title, label: action.title
            ) {
                act(action)
            }
        }
        if moment.asks {
            Button("Skip", action: skip)
                .font(.subheadline)
                .foregroundStyle(.ariTertiary)
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .accessibilityHint("Skips today's question")
        }
    }
}

/// Done on the Desk: one line, how much Kumo handled today. A tap opens Kumo's work.
struct DeskDoneLine: View {
    let handled: Int
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            DeskSectionLabel("Done", trailing: "handled \(handled) ›")
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Done: handled \(handled) today")
        .accessibilityHint("Shows \(LeadName.current)'s work")
    }
}
