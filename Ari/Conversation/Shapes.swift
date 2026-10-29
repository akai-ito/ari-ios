import AriKit
import MapKit
import SwiftUI

#if os(iOS)
    import EventKitUI
#endif

/// What a reply's shapes can do: tick a plan, send a choice, show a picture. The conversation gives
/// it to each of Ari's replies; elsewhere, as on a page of memory, a shape only shows.
struct ReplyActions {
    /// The reply's ticks, each at its latest.
    var ticks: [Tick] = []
    /// Ticks an item, or unticks it: `true` once the server has it.
    var tick: ((_ part: Int, _ item: String, _ done: Bool) async -> Bool)?
    /// Sends a choice as your message; `nil` once the conversation has moved on.
    var choose: ((String) -> Void)?
    var image: ((AttachmentID) async -> Data?)?
}

extension EnvironmentValues {
    @Entry var replyActions = ReplyActions()
}

/// A block of a reply, drawn as what it is.
struct ShapeView: View {
    let shape: ReplyShape
    let part: Int

    var body: some View {
        switch shape {
        case .plan(let plan): PlanView(plan: plan, part: part)
        case .place(let place): PlaceView(place: place)
        case .time(let time): TimeView(time: time)
        case .compare(let compare): CompareView(compare: compare)
        case .choices(let choices): ChoicesView(choices: choices)
        case .images(let images): ImagesView(images: images)
        }
    }
}

/// Where a block will be, while Ari is still writing it: a quiet card, never its raw text.
struct ShapePlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ariSurface)
            .frame(height: 56)
            .accessibilityHidden(true)
    }
}

/// A card for a shape: Ari's surface, rounded, with room.
private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ariSurface, in: .rect(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - A plan you can tick

/// Something to do step by step. Each item ticks on a tap; every device sees it, and Ari hears
/// about it with your next message.
private struct PlanView: View {
    let plan: ReplyShape.Plan
    let part: Int

    @Environment(\.replyActions) private var actions
    /// Ticks on their way to the server, shown at once.
    @State private var pending: [String: Bool] = [:]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                if let title = plan.title {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.ariText)
                }
                ForEach(plan.items) { item in row(item) }
            }
        }
        .sensoryFeedback(.selection, trigger: pending)
    }

    private func row(_ item: ReplyShape.Plan.Item) -> some View {
        let done = isDone(item)
        return Button {
            tick(item, !done)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? Color.ariText : .ariTertiary)
                    .font(.body)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.text)
                        .foregroundStyle(done ? Color.ariSecondary : .ariText)
                        .strikethrough(done, color: .ariTertiary)
                    if let when = item.when {
                        Text(when).font(.caption).foregroundStyle(.ariTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .multilineTextAlignment(.leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(actions.tick == nil)
        .accessibilityAddTraits(done ? .isSelected : [])
    }

    private func isDone(_ item: ReplyShape.Plan.Item) -> Bool {
        pending[item.id]
            ?? actions.ticks.first { $0.part == part && $0.item == item.id }?.done
            ?? item.done
    }

    private func tick(_ item: ReplyShape.Plan.Item, _ done: Bool) {
        guard let tick = actions.tick else { return }
        pending[item.id] = done
        Task {
            _ = await tick(part, item.id, done)
            // The server's tick has arrived, or it failed and the item is as it was.
            pending[item.id] = nil
        }
    }
}

// MARK: - A place, a time

/// A place you might go, on a real map: the pin in the card, and a tap opens a map you can move
/// around, with Directions and Open in Maps, which go to the Maps app.
private struct PlaceView: View {
    let place: ReplyShape.Place

    @State private var item: MKMapItem?
    @State private var opens = false

    var body: some View {
        Button {
            opens = true
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                PlaceMap(item: item, interactive: false)
                    .frame(height: 150)
                    .allowsHitTesting(false)
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name).foregroundStyle(.ariText)
                        if let address = place.address {
                            Text(address).font(.footnote).foregroundStyle(.ariSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "map").font(.footnote).foregroundStyle(.ariTertiary)
                }
                .multilineTextAlignment(.leading)
                .padding(14)
            }
            .background(.ariSurface)
            .clipShape(.rect(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens a map")
        .task(id: place.name) { item = await Self.find(place) }
        .sheet(isPresented: $opens) {
            PlaceSheet(place: place, item: item)
        }
    }

    /// The place on the map: where Ari put it, or, without coordinates, what Maps finds for its
    /// name and address.
    static func find(_ place: ReplyShape.Place) async -> MKMapItem? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = [place.name, place.address].compactMap(\.self).joined(
            separator: ", ")
        if let lat = place.lat, let lon = place.lon {
            let center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            request.region = MKCoordinateRegion(
                center: center, latitudinalMeters: 400, longitudinalMeters: 400)
            if let found = try? await MKLocalSearch(request: request).start().mapItems.first {
                return found
            }
            let item = MKMapItem(
                location: CLLocation(latitude: lat, longitude: lon), address: nil)
            item.name = place.name
            return item
        }
        return try? await MKLocalSearch(request: request).start().mapItems.first
    }
}

/// The map itself: Apple's, dark like Ari, with the place's pin.
private struct PlaceMap: View {
    let item: MKMapItem?
    let interactive: Bool

    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        ZStack {
            Rectangle().fill(.ariSurface)
            if let item {
                Map(position: $camera, interactionModes: interactive ? .all : []) {
                    Marker(item: item)
                }
                .mapStyle(
                    .standard(
                        pointsOfInterest: .including([.restaurant, .museum, .publicTransport]))
                )
                .onAppear {
                    camera = .region(
                        MKCoordinateRegion(
                            center: item.location.coordinate, latitudinalMeters: 700,
                            longitudinalMeters: 700))
                }
            }
        }
        .environment(\.colorScheme, .dark)
    }
}

/// A place, full screen: the map to move around, and the way there in Maps.
private struct PlaceSheet: View {
    let place: ReplyShape.Place
    let item: MKMapItem?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PlaceMap(item: item, interactive: true)
                VStack(alignment: .leading, spacing: 12) {
                    Text(place.name).font(.headline).foregroundStyle(.ariText)
                    if let address = place.address {
                        Text(address).font(.subheadline).foregroundStyle(.ariSecondary)
                    }
                    HStack(spacing: 10) {
                        Button {
                            item?.openInMaps(launchOptions: [
                                MKLaunchOptionsDirectionsModeKey:
                                    MKLaunchOptionsDirectionsModeDefault
                            ])
                        } label: {
                            Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.ariText)
                        .foregroundStyle(.ariBackground)
                        Button {
                            item?.openInMaps()
                        } label: {
                            Text("Open in Maps").frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(.ariText)
                    }
                    .disabled(item == nil)
                    if let url = place.url {
                        Link("Website", destination: url).font(.footnote).foregroundStyle(
                            .ariSecondary)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ariBackground)
            }
            .ignoresSafeArea(edges: .top)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// A time worth keeping, in its own time zone; on the iPhone, Add to Calendar puts it in yours,
/// through the system's own sheet, so Ari never needs your calendar.
private struct TimeView: View {
    let time: ReplyShape.Time

    @State private var adding = false
    @State private var added = false

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar").font(.title3).foregroundStyle(.ariSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(time.title).foregroundStyle(.ariText)
                    Text(Self.describe(time)).font(.footnote).foregroundStyle(.ariSecondary)
                    if let location = time.location {
                        Text(location).font(.footnote).foregroundStyle(.ariTertiary)
                    }
                    #if os(iOS)
                        if time.dates != nil {
                            Button(added ? "Added to Calendar" : "Add to Calendar") {
                                adding = true
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.ariText)
                            .disabled(added)
                            .padding(.top, 6)
                        }
                    #endif
                }
                Spacer(minLength: 0)
            }
        }
        #if os(iOS)
            .sheet(isPresented: $adding) {
                EventEditor(time: time) { saved in
                    adding = false
                    if saved { added = true }
                }
                .ignoresSafeArea()
            }
        #endif
    }

    /// "Sat 7 Nov, 08:15–11:00", with the place's zone named when it isn't yours.
    static func describe(_ time: ReplyShape.Time) -> String {
        guard let dates = time.dates, let zone = TimeZone(identifier: time.timezone) else {
            return time.start
        }
        let day = Date.FormatStyle(timeZone: zone).weekday(.abbreviated).day().month(.abbreviated)
        guard !time.isAllDay else { return dates.start.formatted(day) }
        let clock = Date.FormatStyle(timeZone: zone).hour().minute()
        var text = dates.start.formatted(day) + ", " + dates.start.formatted(clock)
        if let end = dates.end { text += "–" + end.formatted(clock) }
        if zone.secondsFromGMT(for: dates.start)
            != TimeZone.current.secondsFromGMT(for: dates.start)
        {
            let city =
                zone.identifier.split(separator: "/").last.map(String.init) ?? zone.identifier
            text += ", \(city.replacingOccurrences(of: "_", with: " ")) time"
        }
        return text
    }
}

#if os(iOS)
    /// The system's sheet for adding an event, filled in from Ari's time.
    private struct EventEditor: UIViewControllerRepresentable {
        let time: ReplyShape.Time
        let done: (Bool) -> Void

        func makeCoordinator() -> Coordinator { Coordinator(done: done) }

        func makeUIViewController(context: Context) -> EKEventEditViewController {
            let store = EKEventStore()
            let event = EKEvent(eventStore: store)
            event.title = time.title
            event.location = time.location
            event.timeZone = TimeZone(identifier: time.timezone)
            event.isAllDay = time.isAllDay
            if let dates = time.dates {
                event.startDate = dates.start
                event.endDate =
                    dates.end ?? dates.start.addingTimeInterval(time.isAllDay ? 0 : 3_600)
            }
            let controller = EKEventEditViewController()
            controller.eventStore = store
            controller.event = event
            controller.editViewDelegate = context.coordinator
            return controller
        }

        func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

        final class Coordinator: NSObject, EKEventEditViewDelegate {
            let done: (Bool) -> Void

            init(done: @escaping (Bool) -> Void) { self.done = done }

            func eventEditViewController(
                _ controller: EKEventEditViewController,
                didCompleteWith action: EKEventEditViewAction
            ) {
                done(action == .saved)
            }
        }
    }
#endif

// MARK: - A comparison, choices

/// Options side by side, the same facts for each, with Ari's pick marked.
private struct CompareView: View {
    let compare: ReplyShape.Compare

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                if compare.options.count > 3 {
                    ScrollView(.horizontal, showsIndicators: false) { grid }
                } else {
                    grid
                }
                if let why = compare.why {
                    Text(why).font(.footnote).foregroundStyle(.ariSecondary)
                }
            }
        }
    }

    private var grid: some View {
        let keys = compare.options.first?.facts.map(\.key) ?? []
        return Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow(alignment: .top) {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                ForEach(compare.options.indices, id: \.self) { index in
                    let option = compare.options[index]
                    let picked = option.name == compare.pick
                    VStack(alignment: .leading, spacing: 1) {
                        Text(option.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(picked ? Color.ariText : .ariSecondary)
                        if picked {
                            Text("Ari's pick").font(.caption2).foregroundStyle(.ariTertiary)
                        }
                    }
                }
            }
            Divider().overlay(Color.ariLine)
            ForEach(keys, id: \.self) { key in
                GridRow {
                    Text(key).font(.footnote).foregroundStyle(.ariTertiary)
                    ForEach(compare.options.indices, id: \.self) { index in
                        let option = compare.options[index]
                        Text(option.facts.first { $0.key == key }?.value ?? "")
                            .font(.footnote)
                            .foregroundStyle(
                                option.name == compare.pick ? Color.ariText : .ariSecondary)
                    }
                }
            }
        }
    }
}

/// Short answers you might give next. A tap sends one as your message; once the conversation has
/// moved on, they stay as a record.
private struct ChoicesView: View {
    let choices: ReplyShape.Choices

    @Environment(\.replyActions) private var actions

    var body: some View {
        WrappingStack(spacing: 8) {
            ForEach(choices.options, id: \.self) { option in
                Button {
                    actions.choose?(option)
                } label: {
                    Text(option)
                        .font(.subheadline)
                        .foregroundStyle(actions.choose == nil ? Color.ariTertiary : .ariText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().strokeBorder(.ariLine, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(actions.choose == nil)
            }
        }
    }
}

// MARK: - Pictures

/// Pictures Ari found, a page at a time, each credited to where it came from.
private struct ImagesView: View {
    let images: ReplyShape.Images

    @Environment(\.replyActions) private var actions

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(images.images, id: \.attachment) { image in
                    VStack(alignment: .leading, spacing: 6) {
                        Picture(attachment: image.attachment, alt: image.alt) {
                            await actions.image?(image.attachment)
                        }
                        .aspectRatio(4 / 3, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 16, style: .continuous))
                        Link(destination: image.sourceURL) {
                            Text(image.credit).font(.caption2).foregroundStyle(.ariTertiary)
                                .lineLimit(1)
                        }
                    }
                    .containerRelativeFrame(.horizontal) { width, _ in
                        images.images.count > 1 ? width * 0.86 : width
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
    }
}

/// One picture, once its bytes are here from the server; a quiet tile until then.
private struct Picture: View {
    let attachment: AttachmentID
    let alt: String
    let bytes: () async -> Data?

    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.ariSurface)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(alt)
        .accessibilityAddTraits(.isImage)
        .task(id: attachment) {
            let loaded = await Thumbnails.image(for: attachment, from: bytes)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}
