import AriKit
import SwiftUI

/// Settings › Places: whether places are on and, when they're off, why in plain words; a switch to
/// pause them; what's waiting on the phone and today's live GPS; seeding the past from photos; and
/// deleting a day, a range of days or everything.
struct PlacesPage: View {
    let model: AppModel

    @State private var asking = false
    @State private var choosingDelete = false
    @State private var deleting: Deleting?
    @State private var confirmingEverything = false
    @State private var note: String?
    /// What the box keeps, once it's said.
    @State private var held: LocationHeld?

    private var places: PlacesCollector { model.places }
    private var uploads: TrailUploads { model.places.uploads }

    enum Deleting: String, Identifiable {
        case day, range
        var id: String { rawValue }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Places", value: PlacesWords.state(places))
                    .foregroundStyle(.ariText)
                if places.access.isEnough {
                    Toggle(
                        "Keep places",
                        isOn: Binding(get: { !places.paused }, set: { places.setPaused(!$0) }))
                } else if places.access == .refused || places.askedAlways
                    || places.access == .allowed(always: true, precise: false)
                {
                    Button("Open iOS Settings", action: PlacesAsk.openSettings)
                } else {
                    Button("Turn on places…") { asking = true }
                }
            } footer: {
                Text(PlacesWords.why(places))
            }
            .listRowBackground(Color.ariSurface)

            Section {
                LabeledContent("Live GPS today", value: PlacesWords.liveToday(model.places.log))
                LabeledContent("Waiting to send", value: PlacesWords.waiting(uploads))
                if let held {
                    LabeledContent("On your box", value: PlacesWords.held(held))
                }
                if let problem = uploads.problem {
                    Text(PlacesWords.problem(problem)).font(.footnote).foregroundStyle(
                        .ariSecondary)
                }
            } header: {
                Text("On this phone")
            } footer: {
                Text(
                    "Live GPS runs only while you're moving. What's waiting goes to your box whenever it can be reached; nothing is lost offline."
                )
            }
            .listRowBackground(Color.ariSurface)

            PhotoSeedSection(seeding: model.photoSeeding, start: model.seedFromPhotos)

            Section {
                Button("Delete…", role: .destructive) { choosingDelete = true }
                if let note {
                    Text(note).font(.footnote).foregroundStyle(.ariSecondary)
                }
            } footer: {
                Text(
                    "Deleting takes it off your box, with the places and trips that came from it, and drops anything still waiting on this phone."
                )
            }
            .listRowBackground(Color.ariSurface)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(.ariBackground)
        .navigationTitle("Places")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $asking) {
            PlacesAsk(places: places) { asking = false }
        }
        .confirmationDialog(
            "Delete places", isPresented: $choosingDelete, titleVisibility: .visible
        ) {
            Button("A day…") { deleting = .day }
            Button("A range of days…") { deleting = .range }
            Button("Everything", role: .destructive) { confirmingEverything = true }
        }
        .alert("Delete everything?", isPresented: $confirmingEverything) {
            Button("Delete everything", role: .destructive) {
                Task { note = await model.forgetPlaces(.everything) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Every place, visit and point your box keeps, and your photos' places. This can't be undone."
            )
        }
        .sheet(item: $deleting) { kind in
            DeleteDaysSheet(range: kind == .range) { from, to in
                note = await model.forgetPlaces(from: from, to: to)
            }
        }
        .task {
            await uploads.send()
            held = try? await uploads.client?.location()
        }
    }
}

/// Picking a day, or the first and last of a range, to delete.
private struct DeleteDaysSheet: View {
    let range: Bool
    let delete: (Date, Date) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var from = Date.now
    @State private var to = Date.now
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        range ? "From" : "Day", selection: $from, in: ...Date.now,
                        displayedComponents: .date)
                    if range {
                        DatePicker(
                            "To", selection: $to, in: from...Date.now, displayedComponents: .date)
                    }
                } footer: {
                    Text(range ? "Both days are included." : "The whole day, midnight to midnight.")
                }
                .listRowBackground(Color.ariSurface)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(.ariBackground)
            .navigationTitle(range ? "Delete a range" : "Delete a day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", role: .destructive) {
                        working = true
                        Task {
                            await delete(from, range ? max(from, to) : from)
                            dismiss()
                        }
                    }
                    .disabled(working)
                }
            }
        }
        .presentationDetents([.medium])
        .tint(.ariText)
    }
}

/// Seeding the past from photos: the reason, then a quiet line of progress.
struct PhotoSeedSection: View {
    let seeding: PhotoSeeding
    let start: () -> Void

    var body: some View {
        Section {
            switch seeding.state {
            case .notStarted:
                Button("Add your past from photos", action: start)
            case .refused:
                Button("Allow Photos in iOS Settings…", action: PlacesAsk.openSettings)
            case .stopped(let why):
                Button("Carry on from photos", action: start).disabled(seeding.isRunning)
                Text(why).font(.footnote).foregroundStyle(.ariSecondary)
            case .finished(let photos, let on):
                LabeledContent(
                    "From photos",
                    value:
                        "\(photos.formatted()) · \(on.formatted(date: .abbreviated, time: .omitted))"
                )
                Button("Read them again", action: start).disabled(seeding.isRunning)
            case .reading, .naming, .sending:
                Text(PlacesWords.seeding(seeding.state))
                    .font(.subheadline).foregroundStyle(.ariSecondary)
            }
        } header: {
            Text("Your past")
        } footer: {
            Text(
                "Ito reads when and where each photo was taken, never the photos themselves, and sends that to your box, so your places and trips start before today."
                    + (seeding.limited ? " Only the photos you chose for Ito are read." : ""))
        }
        .listRowBackground(Color.ariSurface)
    }
}

/// The plain words for places' state.
enum PlacesWords {
    /// "On", "Paused", "Off".
    static func state(_ places: PlacesCollector) -> String {
        guard places.access.isEnough else { return "Off" }
        if places.paused { return "Paused" }
        return places.rhythm.mode == .stopsOnly ? "On · stops only" : "On"
    }

    /// Why it's in that state.
    static func why(_ places: PlacesCollector) -> String {
        switch places.access {
        case .notAsked:
            return "Places need your location, Always, with Precise Location on."
        case .refused:
            return "Location is off for Ito in iOS Settings, so places stay off."
        case .allowed(always: false, _):
            return
                "Ito has your location only while you're using it. Places need Always, so they stay off rather than drawing a trail full of gaps."
        case .allowed(always: true, precise: false):
            return
                "Precise Location is off, so places stay off: without it they'd blur to a few hundred metres."
        case .allowed(always: true, precise: true):
            if places.paused { return "Paused: nothing is kept until you turn places back on." }
            if places.rhythm.mode == .stopsOnly {
                return "Low Power Mode or a low battery: keeping only the stops for now."
            }
            return "Your stops, and the way between while you're moving, kept on your box."
        }
    }

    static func liveToday(_ log: LiveLog?) -> String {
        guard let day = log?.day(.now) else { return "None" }
        guard day.runs > 0 else { return "None" }
        let minutes = Int((day.live / 60).rounded())
        let time = minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
        return "\(time) · \(day.runs) \(day.runs == 1 ? "run" : "runs")"
    }

    static func waiting(_ uploads: TrailUploads) -> String {
        let count = uploads.waiting == 0 ? "Nothing" : uploads.waiting.formatted()
        guard let sent = uploads.lastSent else { return count }
        return "\(count) · sent \(sent.formatted(date: .omitted, time: .shortened))"
    }

    /// "1,240 points · 86 visits · since 3 Mar 2026".
    static func held(_ held: LocationHeld) -> String {
        var parts = ["\(held.samples.formatted()) points", "\(held.visits.formatted()) visits"]
        if held.photos > 0 { parts.append("\(held.photos.formatted()) photos") }
        if let first = held.firstDay.flatMap({
            try? Date($0, strategy: .iso8601.year().month().day())
        }) {
            parts.append("since \(first.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " · ")
    }

    static func problem(_ error: RequestError) -> String {
        if case .refused(status: 404, _, _) = error {
            return "Your box doesn't take places yet. Update Ito on it."
        }
        return "The box didn't take the last batch: \(error.plainWords)"
    }

    static func seeding(_ state: PhotoSeeding.State) -> String {
        switch state {
        case .reading: "Reading where your photos were taken…"
        case .naming(let done, let of): "Naming the places in them… \(done) of \(of)"
        case .sending(let done, let of): "Sending to your box… \(done) of \(of)"
        default: ""
        }
    }
}
