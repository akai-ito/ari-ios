import AriKit
import SwiftUI

/// An occasion, open: when and where it is and who's there, what to prepare, which you tick, and
/// whether Kumo will check in after. Kumo writes the rest.
struct OccasionView: View {
    let detail: MotionDetail
    let occasion: Occasion

    @Environment(Motions.self) private var motions: Motions?
    @State private var problem: String?
    @State private var ticks = 0

    var body: some View {
        MatterPage {
            VStack(alignment: .leading, spacing: 6) {
                MatterEyebrow(kind: "Occasion", motion: detail.motion)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(detail.motion.title)
                        .font(.ariTitle)
                        .foregroundStyle(.ariText)
                        .accessibilityAddTraits(.isHeader)
                    if Calendar.current.isDateInToday(occasion.start.date) {
                        StatusChip(text: "Today", filled: true)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                MatterFact(symbol: "calendar", text: OccasionReading.when(occasion))
                if let place = occasion.place {
                    placeFact(place)
                }
                if let people = OccasionReading.people(occasion) {
                    MatterFact(symbol: "person.2", text: people)
                }
            }
            if !occasion.prep.isEmpty {
                MatterSection(title: "Prep") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(occasion.prep) { item in
                            prepRow(item)
                        }
                        if let problem {
                            Text(problem).font(.footnote).foregroundStyle(.ariSecondary)
                                .task(id: problem) {
                                    try? await Task.sleep(for: .seconds(4))
                                    if !Task.isCancelled { self.problem = nil }
                                }
                        }
                    }
                }
            }
            if occasion.checkIn {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "bubble.left")
                        .foregroundStyle(.ariBone)
                        .accessibilityHidden(true)
                    Text("Kumo will check in after.")
                        .foregroundStyle(.ariSecondary)
                }
                .font(.subheadline)
            }
            MatterFootnote()
        }
        .sensoryFeedback(.selection, trigger: ticks)
    }

    /// Where it is, opening Apple Maps on a search for it.
    @ViewBuilder
    private func placeFact(_ place: String) -> some View {
        if let url = Self.maps(place) {
            Link(destination: url) {
                MatterFact(symbol: "mappin.and.ellipse", text: place)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens it in Maps")
        } else {
            MatterFact(symbol: "mappin.and.ellipse", text: place)
        }
    }

    /// Apple Maps, searching for a place by its words.
    private static func maps(_ place: String) -> URL? {
        var maps = URLComponents(string: "https://maps.apple.com/")
        maps?.queryItems = [URLQueryItem(name: "q", value: place)]
        return maps?.url
    }

    private func prepRow(_ item: Occasion.Prep) -> some View {
        let done = OccasionReading.isDone(item, in: detail.state)
        return Button {
            tick(item, !done)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? Color.ariBone : .ariTertiary)
                    .contentTransition(.symbolEffect(.replace))
                Text(item.text)
                    .foregroundStyle(done ? Color.ariTertiary : .ariText)
                    .strikethrough(done, color: .ariTertiary)
                    .multilineTextAlignment(.leading)
            }
            .font(.subheadline)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.25), value: done)
        .accessibilityValue(done ? "Done" : "Not done")
        .accessibilityAddTraits(done ? .isSelected : [])
    }

    private func tick(_ item: Occasion.Prep, _ done: Bool) {
        ticks += 1
        Task {
            guard let motions else { return }
            let ticked = await motions.tick(
                detail.motion.id, list: OccasionReading.prepList, item: item.id, done: done)
            if !ticked { problem = "Couldn't tick that. Try again in a moment." }
        }
    }
}

#if DEBUG
    #Preview("Dentist") {
        MatterPreview {
            OccasionView(detail: OccasionSample.detail, occasion: OccasionSample.dentist)
        }
    }

    #Preview("Birthday, whole day") {
        MatterPreview {
            OccasionView(detail: OccasionSample.birthdayDetail, occasion: OccasionSample.birthday)
        }
    }

    /// A dentist appointment, moved to a Friday morning, with one prep item ticked.
    private enum OccasionSample {
        static let dentist = Occasion(
            start: .day(13, at: 9, 30), end: .day(13, at: 10, 15),
            place: "Bright Smile Dental, 14 Upper Street", people: [.init(name: "Dr Shah")],
            prep: [
                .init(id: "forms", text: "Fill in the new-patient form"),
                .init(id: "insurance", text: "Bring your Bupa card", done: true),
                .init(id: "list", text: "Note the tooth that's been sensitive since September"),
            ],
            checkIn: true)

        static let detail = MotionDetail(
            motion: Motion(
                id: "dentist", kind: .occasion, title: "Dentist",
                summary: "Fri 13 Nov, 09:30", startedAt: .day(-10, at: 8)),
            content: .occasion(dentist))

        static let birthday = Occasion(
            start: .day(14, at: 0), allDay: true, people: [.init(name: "Janki")],
            prep: [.init(id: "gift", text: "Pick up the print from the framer")], checkIn: true)

        static let birthdayDetail = MotionDetail(
            motion: Motion(
                id: "janki-birthday", kind: .occasion, title: "Janki's birthday",
                summary: "Sat 14 Nov", startedAt: .day(-3, at: 20)),
            content: .occasion(birthday))
    }
#endif
