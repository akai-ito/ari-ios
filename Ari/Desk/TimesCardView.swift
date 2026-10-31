import AriKit
import SwiftUI

/// Free times to check against what Kumo can't see, your work calendar: tick the ones that are
/// clear, then Draft it, and Kumo drafts with those and holds them.
struct TimesCardView: View {
    let card: DeskCard
    /// Unused: what the times are for takes the header's corner. Here so every card is made alike.
    var context: String?
    var presentation = CardPresentation.card
    let answer: (CardAnswer) async throws -> Void

    /// The ticked slots, by their place in the card's list: that's how the answer names them.
    @State private var ticked: Set<Int> = []
    @State private var sending = DeskSending()
    @ScaledMetric(relativeTo: .subheadline) private var dayWidth: CGFloat = 96

    init(
        card: DeskCard, context: String? = nil, presentation: CardPresentation = .card,
        answer: @escaping (CardAnswer) async throws -> Void
    ) {
        self.card = card
        self.context = context
        self.presentation = presentation
        self.answer = answer
    }

    var body: some View {
        if let times = card.times {
            // What the times are for takes the header's corner; inline, where there's no header, it
            // leads the question.
            CardShell(kind: card.kind, context: times.purpose, presentation: presentation) {
                if presentation == .inline {
                    Text(times.purpose).font(.caption).foregroundStyle(.ariTertiary)
                }
                Text("Which are clear at work?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.ariText)
                VStack(spacing: 0) {
                    ForEach(Array(times.slots.enumerated()), id: \.offset) { index, slot in
                        row(slot, at: index)
                    }
                }
                .disabled(sending.isSending || card.isWorking)
                if card.isWorking { DeskWorkingLine(text: "Drafting…") }
                if let problem = sending.problem { DeskProblemLine(text: problem) }
                footer(times)
            }
            .animation(.smooth(duration: 0.3), value: sending.problem)
        } else {
            UnknownCardView(card: card, presentation: presentation)
        }
    }

    private func row(_ slot: TimeSlot, at index: Int) -> some View {
        let on = ticked.contains(index)
        return Button {
            if on { ticked.remove(index) } else { ticked.insert(index) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(on ? Color.ariBone : .ariTertiary)
                    .contentTransition(.symbolEffect(.replace))
                Text(slot.start.date, format: DeskTime.weekdayDayMonth)
                    .font(.subheadline)
                    .foregroundStyle(.ariText)
                    .frame(minWidth: dayWidth, alignment: .leading)
                Text(slot.start.date, format: DeskTime.time)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.ariText)
                Spacer(minLength: 8)
                if let note = slot.note { StatusChip(text: note) }
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: on)
        .accessibilityLabel(Self.spoken(slot))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint(on ? "Unticks it" : "Ticks it as clear at work")
    }

    private func footer(_ times: TimesCard) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Free in your calendar; your work one is invisible to Kumo.")
                .font(.caption)
                .foregroundStyle(.ariTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            DeskPill(
                title: "Draft it", acts: true, busy: sending.key == "slots",
                label: "Draft it with the ticked times"
            ) {
                // In the order they're offered, not the order you ticked them.
                let slots = ticked.sorted()
                Task {
                    await sending.send("slots", failure: "Couldn't send the times") {
                        try await answer(CardAnswer(slots: slots))
                    }
                }
            }
            .disabled(ticked.isEmpty || sending.isSending || card.isWorking)
        }
    }

    /// "Monday 9 November, 10:00 to 11:00, WFH", for VoiceOver.
    static func spoken(_ slot: TimeSlot) -> String {
        let day = slot.start.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let from = slot.start.date.formatted(DeskTime.time)
        let to = slot.end.date.formatted(DeskTime.time)
        return [day, "\(from) to \(to)", slot.note].compactMap(\.self).joined(separator: ", ")
    }
}

#if DEBUG
    #Preview("Times") {
        ScrollView {
            TimesCardView(card: DeskSamples.qrtTimes, context: nil) { _ in
                try await Task.sleep(for: .seconds(1))
            }
            .padding(16)
        }
        .background(.ariBackground)
        .preferredColorScheme(.dark)
    }
#endif
