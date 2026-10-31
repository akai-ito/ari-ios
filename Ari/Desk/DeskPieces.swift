import AriKit
import SwiftUI

/// The Desk's quiet heading over a section: "COMING UP", with a count or a link on the right.
struct DeskSectionLabel: View {
    let text: String
    var trailing: String?

    init(_ text: String, trailing: String? = nil) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(.caption.weight(.semibold))
                .kerning(0.8)
                .textCase(.uppercase)
                .foregroundStyle(.ariTertiary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing).font(.caption.weight(.medium)).foregroundStyle(.ariSecondary)
            }
        }
    }
}

extension View {
    /// A card on the Desk: raised a step from the background, with a hairline edge.
    func deskCard(padding: CGFloat = 16, cornerRadius: CGFloat = 20) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ariSurface, in: .rect(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.ariLine.opacity(0.7), lineWidth: 1)
            }
    }
}

/// A button on a card: outlined, in your hand, or filled like Send when it's the one that goes
/// ahead. While its answer is on the way it holds its place with a small spinner.
struct DeskPill: View {
    let title: String
    var acts = false
    var busy = false
    /// What VoiceOver says, when the title alone isn't enough.
    var label: String?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(acts ? Color.ariBackground : .ariText)
                .opacity(busy ? 0 : 1)
                .overlay {
                    if busy {
                        ProgressView()
                            .controlSize(.small)
                            .tint(acts ? Color.ariBackground : .ariSecondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    if acts {
                        Capsule().fill(Color.ariText)
                    } else {
                        Capsule().strokeBorder(Color.ariLine, lineWidth: 1)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled || busy ? 1 : 0.45)
        .accessibilityLabel(label ?? title)
        .accessibilityValue(busy ? "Sending" : "")
    }
}

/// Why something didn't go through, in one quiet line.
struct DeskProblemLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.ariSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .transition(.opacity)
    }
}

/// The box is working on your answer, such as redrafting: said quietly, with a small spinner.
struct DeskWorkingLine: View {
    var text = "Working on it…"

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small).tint(.ariSecondary)
            Text(text).font(.footnote).foregroundStyle(.ariSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Sends an answer through a closure the screen gives: what's on its way meanwhile, so its button
/// can spin and the others wait, and a one-line problem if it didn't go through.
@Observable
final class DeskSending {
    /// Which answer is on its way, such as an option's label.
    private(set) var key: String?
    private(set) var problem: String?

    var isSending: Bool { key != nil }

    /// Sends one answer at a time; `true` once it went through.
    @discardableResult
    func send(
        _ key: String, failure: String = "Couldn't send that",
        _ deliver: () async throws -> Void
    ) async -> Bool {
        guard self.key == nil else { return false }
        self.key = key
        problem = nil
        defer { self.key = nil }
        do {
            try await deliver()
            return true
        } catch is CancellationError {
            return false
        } catch {
            problem = "\(failure): \(Self.words(for: error))"
            return false
        }
    }

    func clearProblem() { problem = nil }

    static func words(for error: any Error) -> String {
        (error as? RequestError)?.plainWords ?? "something went wrong."
    }
}

/// How a card's kind looks: its name and symbol, for its header or its row.
enum CardLook {
    static func name(_ kind: CardKind) -> String {
        switch kind {
        case .draft: "Draft"
        case .invite: "Invite"
        case .times: "Times"
        case .question: "Question"
        case .offer: "Offer"
        default: "Waiting"
        }
    }

    static func symbol(_ kind: CardKind) -> String {
        switch kind {
        case .draft: "envelope"
        case .invite: "calendar"
        case .times: "clock"
        case .question: "questionmark"
        case .offer: "plus.circle"
        default: "circle.dashed"
        }
    }
}

/// Times as the Desk writes them, in the reader's locale: "14:00", "Thu 12", "Mon 9 Nov".
enum DeskTime {
    static let time = Date.FormatStyle.dateTime.hour().minute()
    static let weekdayDay = Date.FormatStyle.dateTime.weekday(.abbreviated).day()
    static let weekdayDayMonth = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(
        .abbreviated)
}

extension When {
    /// When it is, as a date on this phone: a timed event's instant, or an all-day event's day from
    /// its start, in this calendar.
    var date: Date {
        if let instant { return instant }
        return day.flatMap { Calendar.current.date(from: $0) } ?? .distantFuture
    }
}
