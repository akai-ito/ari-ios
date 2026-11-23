import AriKit
import EventKit
import EventKitUI
import MapKit
import SwiftUI

// Replies that show: picks, tables with verdicts, the number that matters, and action cards for an
// event, a place, a Desk item and a person. Each is a view of its own, so a page Kumo made, or any
// other screen, can show one too.

// MARK: - Verdict chips

/// Kumo's take on one thing, as a chip: three strengths of bone and a quiet grey, so the eye finds
/// "Must try" first without a rainbow of colours.
struct VerdictChip: View {
    let verdict: ReplyShape.Verdict

    var body: some View {
        Text(verdict.label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background {
                switch verdict.tone {
                case .strong: Capsule().fill(Color.ariBone)
                case .good: Capsule().strokeBorder(Color.ariBone.opacity(0.8), lineWidth: 1)
                case .quiet: Capsule().strokeBorder(Color.ariLine, lineWidth: 1)
                default: Capsule().fill(Color.ariField)
                }
            }
            .fixedSize()
    }

    private var foreground: Color {
        switch verdict.tone {
        case .strong: .ariBackground
        case .good: .ariBone
        case .quiet: .ariTertiary
        default: .ariText
        }
    }
}

// MARK: - A table that fits a phone

/// A row per thing: its name and a line under it on the left, up to two short values, and Kumo's
/// verdict as a chip on the right. Nothing scrolls sideways.
struct PhoneTableView: View {
    let table: ReplyShape.Table

    private var hasVerdicts: Bool { table.rows.contains { $0.verdict != nil } }

    var body: some View {
        VStack(spacing: 0) {
            if !table.columns.isEmpty {
                HStack(spacing: 12) {
                    Text(table.columns.first ?? "")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(Array(table.columns.dropFirst().enumerated()), id: \.offset) {
                        _, heading in
                        Text(heading)
                    }
                }
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(.ariTertiary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .accessibilityHidden(true)
            }
            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                Rectangle().fill(Color.ariLine).frame(height: 1)
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.ariText)
                        if let detail = row.detail {
                            Text(detail)
                                .font(.footnote)
                                .foregroundStyle(.ariSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(row.values.prefix(2).enumerated()), id: \.offset) { _, value in
                        Text(value)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.ariSecondary)
                            .fixedSize()
                    }
                    if let verdict = row.verdict {
                        VerdictChip(verdict: verdict)
                    } else if hasVerdicts {
                        Color.clear.frame(width: 1, height: 1)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }
        }
        .background(.ariSurface.opacity(0.5), in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.ariLine, lineWidth: 1))
    }
}

// MARK: - A pick list

/// Kumo's ranked picks: a picture with its number, the name with its price or time, and one line
/// on why, in Kumo's hand.
struct PickListView: View {
    let picks: ReplyShape.Picks

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title = picks.title {
                Text(title)
                    .font(.ariHeading)
                    .foregroundStyle(.ariText)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(Array(picks.picks.enumerated()), id: \.offset) { index, pick in
                HStack(alignment: .top, spacing: 14) {
                    picture(pick, number: index + 1)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(pick.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.ariText)
                            Spacer(minLength: 8)
                            if let detail = pick.detail {
                                Text(detail)
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.ariSecondary)
                            }
                        }
                        Text(pick.why)
                            .font(.system(.subheadline, design: .serif))
                            .foregroundStyle(.ariText)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(index + 1). \(pick.name)\(pick.detail.map { ", \($0)" } ?? ""). \(pick.why)")
            }
        }
    }

    @ViewBuilder
    private func picture(_ pick: ReplyShape.Picks.Pick, number: Int) -> some View {
        let badge = Text("\(number)")
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(.ariBackground)
            .frame(width: 20, height: 20)
            .background(Color.ariBone, in: Circle())
        if let image = pick.image {
            FoundPhoto(photo: image, longest: 240, creditOnTap: false)
                .frame(width: 76, height: 76)
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topLeading) { badge.offset(x: -6, y: -6) }
        } else {
            badge.padding(.top, 1)
        }
    }
}

// MARK: - A number that matters

/// One number with its context: what it is, the number large, and what it's made of.
struct KeyNumberView: View {
    let number: ReplyShape.KeyNumber

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(number.label)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.1)
                .foregroundStyle(.ariBone)
            Text(number.value)
                .font(.system(size: 40, weight: .semibold, design: .serif).monospacedDigit())
                .foregroundStyle(.ariText)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let context = number.context {
                Text(context)
                    .font(.footnote)
                    .foregroundStyle(.ariSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.ariBone.opacity(0.55), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - An event

/// An event Kumo would put in your calendar: its day on a leaf, when and where, and Add, which
/// opens the phone's own event sheet filled in. Nothing is added until you add it there.
struct EventActionCard: View {
    let event: ReplyShape.CalendarEvent

    @State private var adding = false
    @State private var added = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            DateLeaf(date: event.start)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).font(.ariName).foregroundStyle(.ariText)
                Text(Self.when(event)).font(.subheadline).foregroundStyle(.ariSecondary)
                if let place = event.place {
                    Text(place).font(.footnote).foregroundStyle(.ariTertiary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            if event.onCalendar || added {
                Label(added ? "Added" : "On your calendar", systemImage: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.ariSecondary)
                    .labelStyle(.titleAndIcon)
            } else {
                DeskPill(title: "Add", acts: true, label: "Add \(event.title) to your calendar") {
                    adding = true
                }
            }
        }
        .deskCard(padding: 12, cornerRadius: 18)
        .sheet(isPresented: $adding) {
            EventEditor(event: event) { saved in
                adding = false
                if saved { added = true }
            }
            .ignoresSafeArea()
        }
    }

    /// "Thursday, 19:30 – 21:30", or the day alone for an all-day event.
    static func when(_ event: ReplyShape.CalendarEvent) -> String {
        let day = event.start.formatted(.dateTime.weekday(.wide))
        guard !event.allDay else { return day }
        let start = event.start.formatted(.dateTime.hour().minute())
        guard let end = event.end else { return "\(day), \(start)" }
        return "\(day), \(start) – \(end.formatted(.dateTime.hour().minute()))"
    }
}

/// A day on a small calendar leaf: the month in bone, the day large, the weekday under it.
struct DateLeaf: View {
    let date: Date

    var body: some View {
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.month(.abbreviated)).uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.ariBackground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .background(Color.ariBone)
            Text(date.formatted(.dateTime.day()))
                .font(.system(.title2, design: .serif).weight(.semibold))
                .foregroundStyle(.ariText)
                .padding(.top, 2)
            Text(date.formatted(.dateTime.weekday(.abbreviated)))
                .font(.caption2)
                .foregroundStyle(.ariTertiary)
                .padding(.bottom, 4)
        }
        .frame(width: 50)
        .background(.ariField, in: .rect(cornerRadius: 10, style: .continuous))
        .clipShape(.rect(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// The phone's own sheet for a new event, filled in from Kumo's. On iOS 17 and later it runs
/// outside the app, so adding an event this way needs no access to your calendars.
private struct EventEditor: UIViewControllerRepresentable {
    let event: ReplyShape.CalendarEvent
    let done: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let new = EKEvent(eventStore: store)
        new.title = event.title
        new.startDate = event.start
        new.endDate = event.end ?? event.start.addingTimeInterval(event.allDay ? 0 : 3600)
        new.isAllDay = event.allDay
        new.location = event.place
        new.notes = event.notes
        let editor = EKEventEditViewController()
        editor.eventStore = store
        editor.event = new
        editor.editViewDelegate = context.coordinator
        return editor
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let done: (Bool) -> Void

        init(done: @escaping (Bool) -> Void) { self.done = done }

        func eventEditViewController(
            _ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction
        ) {
            done(action == .saved)
        }
    }
}

// MARK: - A place

/// A place, in a reply or on a page: a picture (or its spot on the map), its name and what's useful,
/// and Directions, straight to Maps. Tapping the card opens the map to look around.
struct PlaceActionCard: View {
    let place: ReplyShape.Place

    @State private var opens = false
    @State private var listing: MKMapItem?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let image = place.image {
                    FoundPhoto(photo: image, longest: 200, creditOnTap: false)
                } else {
                    PlaceMapThumbnail(place: place)
                }
            }
            .frame(width: 54, height: 54)
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.ariText)
                if let detail = Self.detail(place) {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.ariSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            DeskPill(title: "Directions", acts: true, label: "Directions to \(place.name)") {
                Task {
                    let item: MKMapItem? =
                        if let listing { listing } else { await PlaceLookup.find(place) }
                    item?.openInMaps(launchOptions: [
                        MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault
                    ])
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { opens = true }
        .deskCard(padding: 12, cornerRadius: 18)
        .accessibilityElement(children: .contain)
        .accessibilityHint("Opens a map")
        .task(id: place.name) { listing = await PlaceLookup.find(place) }
        .sheet(isPresented: $opens) { PlaceSheet(place: place) }
    }

    /// "Cromwell Road · open till 17:45".
    static func detail(_ place: ReplyShape.Place) -> String? {
        let parts = [place.address, place.note].compactMap(\.self).filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - A Desk item

/// What the chat can do with the Desk: find a card as it is now, and answer it. The app gives it
/// from the session; elsewhere a Desk item only says where it is.
struct DeskItems {
    enum Lookup {
        /// The Desk hasn't come yet.
        case loading
        case waiting(DeskCard)
        /// It's off the Desk: answered, dropped or cleared.
        case settled
    }

    var card: (CardID) -> Lookup = { _ in .loading }
    var answer: ((CardID, CardAnswer) async throws -> Void)?
}

extension EnvironmentValues {
    @Entry var deskItems = DeskItems()
}

/// A card waiting on your Desk, in the chat: the same card with its own buttons (a draft has Open
/// in Mail, Change… and Drop, and never Send), marked as on the Desk too. One item, two views:
/// answer it here or there. Once it's settled, a quiet line says so.
struct DeskItemCard: View {
    let item: ReplyShape.DeskItem

    @Environment(\.deskItems) private var desk
    @Environment(Hands.self) private var hands: Hands?

    var body: some View {
        switch desk.card(item.card) {
        case .waiting(let card):
            DeskCardView(card: card, context: Self.marker(card)) { answer in
                try await desk.answer?(card.id, answer)
            }
            .disabled(desk.answer == nil)
        case .settled:
            // A one-tap card you pressed keeps its still, and says what you did.
            if let card = hands?.commits[item.card],
                let state = hands?.state(of: item.card, on: nil)
            {
                CommitCardView(card: card, state: state) { _ in }
            } else {
                settled
            }
        case .loading:
            ShapePlaceholder()
        }
    }

    private var settled: some View {
        Label("Settled on your Desk", systemImage: "checkmark")
            .font(.footnote)
            .foregroundStyle(.ariTertiary)
    }

    /// The card's corner: a draft lives in your Drafts; anything else is on the Desk too.
    static func marker(_ card: DeskCard) -> String {
        card.kind == .draft ? "In your Drafts" : "Also on your Desk"
    }
}

// MARK: - A person

/// Someone Kumo keeps a page about, as a small card: the same one a tapped name opens.
struct PersonActionCard: View {
    let person: ReplyShape.Person

    var body: some View {
        NameCardContent(name: .memory(person.page))
            .deskCard(padding: 16, cornerRadius: 20)
    }
}
