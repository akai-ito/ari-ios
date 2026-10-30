import AriKit
import MapKit
import SwiftUI

/// A trip, open: its cover, then Days, Map, Places, Travel and Stay, and what changed. Ari writes
/// all of it; you tick what's done, and that's yours.
struct TripView: View {
    let detail: MotionDetail
    let trip: Trip

    @State private var tab = Section.days
    @State private var openedPlace: Trip.Place?
    /// Scrolled past the tabs: a compact header holds the name and the tabs at the top.
    @State private var compact = false
    /// How far down the screen the status bar and the island reach.
    @State private var safeTop: CGFloat = 0
    @Namespace private var underline
    @Namespace private var compactUnderline

    enum Section: String, CaseIterable, Identifiable {
        case days = "Days"
        case map = "Map"
        case places = "Places"
        case travel = "Travel"
        case stay = "Stay"

        var id: String { rawValue }
    }

    /// Only the sections with something in them.
    private var sections: [Section] {
        Section.allCases.filter { section in
            switch section {
            case .days: true
            case .map:
                !TripReading.mapStops(trip).isEmpty || trip.stays.contains { $0.location != nil }
            case .places: !trip.places.isEmpty
            case .travel: !trip.travel.isEmpty
            case .stay: !trip.stays.isEmpty
            }
        }
    }

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    cover
                    tabRow(in: underline)
                    content
                        .padding(.top, 16)
                        .animation(.smooth(duration: 0.3), value: tab)
                    ChangesList(changes: detail.changes)
                        .id("changes")
                        .padding(.horizontal, 20)
                        .padding(.top, 36)
                        .padding(.bottom, 60)
                }
                .frame(maxWidth: Rhythm.column)
                .frame(maxWidth: .infinity)
            }
            .ignoresSafeArea(edges: .top)
            .onGeometryChange(for: CGFloat.self) {
                $0.safeAreaInsets.top
            } action: {
                safeTop = $0
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y > coverHeight - safeTop - Self.barHeight
            } action: { _, compact in
                withAnimation(.easeOut(duration: 0.2)) { self.compact = compact }
            }
            .overlay(alignment: .top) {
                if compact {
                    compactHeader.transition(.opacity)
                }
            }
            #if DEBUG
                .task {
                    if let name = DebugScript.motionTab, let section = Section(rawValue: name) {
                        tab = section
                    }
                    if DebugScript.motionTab == "changes" {
                        try? await Task.sleep(for: .milliseconds(600))
                        scroller.scrollTo("changes", anchor: .bottom)
                    }
                }
            #endif
            .task {
                // During the trip, it opens on today.
                guard let today = TripReading.openingDay(of: trip), today.id != trip.days.first?.id
                else { return }
                try? await Task.sleep(for: .milliseconds(500))
                withAnimation(.smooth(duration: 0.5)) {
                    scroller.scrollTo("day \(today.id)", anchor: .top)
                }
            }
        }
        .sheet(item: $openedPlace) { place in
            TripPlaceSheet(place: place, trip: trip, state: detail.state)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - The cover

    /// The compact header's bar, which leaves room for the close button at its leading end.
    private static let barHeight: CGFloat = 44

    private var coverHeight: CGFloat { trip.cover == nil ? 150 : 340 }

    private var cover: some View {
        ZStack(alignment: .bottomLeading) {
            if let photo = trip.cover {
                FoundPhoto(photo: photo, longest: 1600, creditAlignment: .topTrailing)
                    .frame(height: coverHeight)
                    .overlay {
                        LinearGradient(
                            colors: [.clear, .ariBackground.opacity(0.6), .ariBackground],
                            startPoint: .center, endPoint: .bottom
                        )
                        .allowsHitTesting(false)
                    }
            } else {
                Color.clear.frame(height: coverHeight)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(detail.motion.title).font(.ariTitle).foregroundStyle(.ariText)
                Text(TripReading.subtitle(trip)).font(.subheadline).foregroundStyle(.ariSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
        }
    }

    /// The trip's name and its tabs, held at the top once you've scrolled past them.
    private var compactHeader: some View {
        VStack(spacing: 0) {
            Text(detail.motion.title)
                .font(.headline)
                .foregroundStyle(.ariText)
                .lineLimit(1)
                .padding(.horizontal, 64)
                .frame(maxWidth: .infinity, minHeight: Self.barHeight)
            tabRow(in: compactUnderline)
            Rectangle().fill(.ariLine.opacity(0.6)).frame(height: 0.5)
        }
        .background(Color.ariBackground.ignoresSafeArea(edges: .top))
    }

    private func tabRow(in underline: Namespace.ID) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                ForEach(sections) { section in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            tab = section
                        }
                    } label: {
                        Text(section.rawValue)
                            .font(.subheadline.weight(section == tab ? .semibold : .regular))
                            .foregroundStyle(section == tab ? Color.ariText : .ariTertiary)
                            .padding(.vertical, 12)
                            .overlay(alignment: .bottom) {
                                if section == tab {
                                    Capsule()
                                        .fill(.ariBone)
                                        .frame(width: 28, height: 2)
                                        .matchedGeometryEffect(id: "underline", in: underline)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(section == tab ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
        }
        .background(.ariBackground)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .days:
            DaysSection(motion: detail.motion.id, trip: trip, state: detail.state) {
                openedPlace = $0
            }
            .padding(.horizontal, 20)
        case .map:
            TripMap(trip: trip, state: detail.state).padding(.horizontal, 12)
        case .places:
            PlacesCarousel(trip: trip, state: detail.state) { openedPlace = $0 }
        case .travel:
            TravelList(trip: trip, state: detail.state).padding(.horizontal, 20)
        case .stay:
            StayList(trip: trip, state: detail.state).padding(.horizontal, 20)
        }
    }
}

// MARK: - Days

/// What's left to do, then each day as a timeline: every stop with its time, its photo, where it
/// stands, and the way to the next.
private struct DaysSection: View {
    let motion: MotionID
    let trip: Trip
    let state: MotionState
    let openPlace: (Trip.Place) -> Void

    @Environment(Motions.self) private var motions: Motions?
    @State private var problem: String?
    @State private var ticks = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if !trip.todo.isEmpty { todo }
            ForEach(trip.days) { day in
                dayView(day).id("day \(day.id)")
            }
        }
        .sensoryFeedback(.selection, trigger: ticks)
    }

    private var todo: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("To do").font(.ariHeading).foregroundStyle(.ariText)
            ForEach(trip.todo) { item in
                let done = TripReading.isDone(item, in: state)
                Button {
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
                .accessibilityAddTraits(done ? .isSelected : [])
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

    private func tick(_ item: Trip.Todo, _ done: Bool) {
        ticks += 1
        Task {
            guard let motions else { return }
            if !(await motions.tick(motion, list: TripReading.todoList, item: item.id, done: done))
            {
                problem = "Couldn't tick that. Try again in a moment."
            }
        }
    }

    private func dayView(_ day: Trip.Day) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(TripReading.heading(of: day)).font(.ariHeading).foregroundStyle(.ariText)
                if let title = day.title {
                    Text("· \(title)").font(.subheadline).foregroundStyle(.ariSecondary)
                }
            }
            .padding(.bottom, 12)
            ForEach(Array(day.stops.enumerated()), id: \.element.id) { index, stop in
                StopRow(
                    stop: stop, place: TripReading.place(of: stop, in: trip),
                    booking: TripReading.booking(stop.booking, of: stop.id, in: trip, state: state),
                    isLast: index == day.stops.count - 1, openPlace: openPlace)
            }
        }
    }
}

/// One stop in a day's timeline.
private struct StopRow: View {
    let stop: Trip.Stop
    let place: Trip.Place?
    let booking: Trip.Booking?
    let isLast: Bool
    let openPlace: (Trip.Place) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(stop.time ?? "")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.ariTertiary)
                .frame(width: 40, alignment: .leading)
                .padding(.top, 15)
            VStack(spacing: 0) {
                Circle().fill(.ariBone).frame(width: 7, height: 7).padding(.top, 19)
                if !isLast || stop.next != nil {
                    Rectangle().fill(.ariLine).frame(width: 1).frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                // A stop without a place, such as landing, reads the same but opens nothing.
                if let place {
                    Button {
                        openPlace(place)
                    } label: {
                        card
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the place")
                } else {
                    card
                }
                if let next = stop.next {
                    Label(TripReading.move(next), systemImage: MotionSymbol.name(for: next.mode))
                        .font(.caption)
                        .foregroundStyle(.ariTertiary)
                        .padding(.vertical, 10)
                } else if !isLast {
                    Spacer().frame(height: 10)
                }
            }
        }
    }

    private var card: some View {
        HStack(spacing: 10) {
            if let photo = place?.photo {
                FoundPhoto(photo: photo, longest: 200, creditOnTap: false)
                    .frame(width: 44, height: 44)
                    .clipShape(.rect(cornerRadius: 10, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.title).font(.subheadline.weight(.semibold)).foregroundStyle(.ariText)
                if let line = detailLine {
                    Text(line).font(.caption).foregroundStyle(.ariSecondary).lineLimit(2)
                }
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            StatusChip.booking(booking)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ariSurface, in: .rect(cornerRadius: 14, style: .continuous))
        .animation(.smooth(duration: 0.3), value: booking?.status)
    }

    private var detailLine: String? {
        let words = stop.note ?? place?.why
        guard let reference = booking?.ref, booking?.status == .booked else { return words }
        return [words, "Ref \(reference)"].compactMap(\.self).joined(separator: " · ")
    }
}

// MARK: - Map

/// Every stop on Apple's map, numbered through the trip. The day you're looking at is in bone, its
/// route drawn; the others are grey. A pin raises its place, with the way there in Maps.
private struct TripMap: View {
    let trip: Trip
    let state: MotionState

    @State private var day: String?
    @State private var selected: String?
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        let stops = TripReading.mapStops(trip)
        let shownDay = day ?? TripReading.openingDay(of: trip)?.id
        VStack(alignment: .leading, spacing: 14) {
            Map(position: $camera, selection: $selected) {
                // The other days first, so the day you're looking at sits on top.
                ForEach(
                    stops.sorted { ($0.day == shownDay ? 1 : 0) < ($1.day == shownDay ? 1 : 0) }
                ) {
                    stop in
                    Annotation(stop.stop.title, coordinate: stop.location.coordinate) {
                        MapPin(number: stop.number, lit: stop.day == shownDay)
                    }
                    .annotationTitles(.hidden)
                    .tag(stop.stop.id)
                }
                let route = stops.filter { $0.day == shownDay }.map(\.location.coordinate)
                if route.count > 1 {
                    MapPolyline(coordinates: route)
                        .stroke(
                            .ariBone.opacity(0.85),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [2, 6]))
                }
                ForEach(trip.stays.filter { $0.location != nil }) { stay in
                    Annotation(stay.name, coordinate: stay.location!.coordinate) {
                        Image(systemName: "bed.double.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.ariText)
                            .frame(width: 28, height: 28)
                            .background(.ariSurface, in: Circle())
                            .overlay(Circle().strokeBorder(.ariLine))
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
            .environment(\.colorScheme, .dark)
            .frame(height: 440)
            .clipShape(.rect(cornerRadius: 20, style: .continuous))
            .overlay(alignment: .topLeading) { dayChips(selected: shownDay).padding(12) }
            .onAppear { camera = Self.fit(stops.filter { $0.day == shownDay }) }
            .onChange(of: day) { _, day in
                selected = nil
                withAnimation(.smooth(duration: 0.6)) {
                    camera = Self.fit(stops.filter { $0.day == day })
                }
            }
            if let selected, let stop = stops.first(where: { $0.stop.id == selected }) {
                PlaceCard(stop: stop, trip: trip, state: state)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: selected)
    }

    private func dayChips(selected: String?) -> some View {
        HStack(spacing: 8) {
            ForEach(trip.days) { day in
                let isOn = day.id == selected
                Button {
                    self.day = day.id
                } label: {
                    Text(TripReading.shortName(of: day))
                        .font(.footnote.weight(isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? Color.ariBackground : .ariSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(isOn ? Color.ariBone : .ariSurface.opacity(0.92), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    /// The camera around a day's stops, every one in view with room at the edges. A region, not a
    /// map rect: a rect could be cropped to the map's shape, leaving the first and last stops off
    /// the edges.
    static func fit(_ stops: [TripReading.MapStop]) -> MapCameraPosition {
        guard !stops.isEmpty else { return .automatic }
        let latitudes = stops.map(\.location.lat)
        let longitudes = stops.map(\.location.lon)
        let (south, north) = (latitudes.min()!, latitudes.max()!)
        let (west, east) = (longitudes.min()!, longitudes.max()!)
        let center = CLLocationCoordinate2D(
            latitude: (south + north) / 2, longitude: (west + east) / 2)
        // Half again around the stops, so the pins and their callouts clear the edges, and at
        // least a few streets for a single stop.
        let span = MKCoordinateSpan(
            latitudeDelta: max((north - south) * 1.5, 0.006),
            longitudeDelta: max((east - west) * 1.5, 0.006))
        return .region(MKCoordinateRegion(center: center, span: span))
    }

    /// The place a pin stands for, with the way there.
    private struct PlaceCard: View {
        let stop: TripReading.MapStop
        let trip: Trip
        let state: MotionState

        var body: some View {
            let place = TripReading.place(of: stop.stop, in: trip)
            let booking = TripReading.booking(
                stop.stop.booking, of: stop.stop.id, in: trip, state: state)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    if let photo = place?.photo {
                        FoundPhoto(photo: photo, longest: 300, creditOnTap: false)
                            .frame(width: 64, height: 64)
                            .clipShape(.rect(cornerRadius: 12, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(place?.name ?? stop.stop.title).font(.headline).foregroundStyle(
                            .ariText)
                        if let why = place?.why {
                            Text(why).font(.footnote).foregroundStyle(.ariSecondary)
                        }
                        StatusChip.booking(booking)
                    }
                }
                directions(
                    to: place?.name ?? stop.stop.title, at: stop.location, booking: booking)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ariSurface, in: .rect(cornerRadius: 22, style: .continuous))
        }
    }
}

/// A numbered pin: bone for the day you're looking at, quiet for the others.
private struct MapPin: View {
    let number: Int
    let lit: Bool

    var body: some View {
        Text("\(number)")
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(lit ? Color.ariBackground : .ariTertiary)
            .frame(width: 26, height: 26)
            .background(lit ? Color.ariBone : .ariSurface, in: Circle())
            .overlay(Circle().strokeBorder(lit ? Color.clear : .ariLine))
            .scaleEffect(lit ? 1 : 0.85)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: lit)
    }
}

/// The way to one of the trip's places, and booking it while it's still to book, or its website.
private func directions(
    to name: String, at location: Trip.Location?, booking: Trip.Booking? = nil,
    website: URL? = nil
) -> DirectionsButtons {
    let link: (title: String, url: URL)? =
        if booking?.status == .toBook, let url = booking?.url {
            ("Book", url)
        } else if let website {
            ("Website", website)
        } else {
            nil
        }
    return DirectionsButtons(
        item: location.map { .at(lat: $0.lat, lon: $0.lon, name: name) }, link: link)
}

extension Trip.Location {
    fileprivate var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

// MARK: - Places

/// The places Ari found, as a carousel: a photo where there's a good one, why Ari chose it, its
/// hours and price, and where it stands. A picked or booked place takes a bone edge.
private struct PlacesCarousel: View {
    let trip: Trip
    let state: MotionState
    let openPlace: (Trip.Place) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(trip.places) { place in
                    Button {
                        openPlace(place)
                    } label: {
                        card(place, status: TripReading.status(of: place, in: trip, state: state))
                    }
                    .buttonStyle(.plain)
                    .containerRelativeFrame(.horizontal) { width, _ in width * 0.8 }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, 20, for: .scrollContent)
    }

    private func card(_ place: Trip.Place, status: PlaceStatus) -> some View {
        let settled = status == .picked || status == .booked
        return VStack(alignment: .leading, spacing: 0) {
            if let photo = place.photo {
                FoundPhoto(photo: photo, longest: 900, creditOnTap: false)
                    .frame(height: 230)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(place.name).font(.ariHeading).foregroundStyle(.ariText)
                    Spacer(minLength: 8)
                    StatusChip.place(status)
                }
                Text(place.why)
                    .font(.subheadline)
                    .foregroundStyle(.ariSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                let facts = [place.hours, place.price].compactMap(\.self)
                if !facts.isEmpty {
                    Text(facts.joined(separator: " · ")).font(.caption).foregroundStyle(
                        .ariTertiary)
                }
            }
            .multilineTextAlignment(.leading)
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ariSurface)
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.ariBone.opacity(settled ? 0.7 : 0), lineWidth: 1.5)
        )
        .animation(.smooth(duration: 0.5), value: status)
    }
}

/// A place, in full: its photo with its credit, why Ari chose it, and the way there.
private struct TripPlaceSheet: View {
    let place: Trip.Place
    let trip: Trip
    let state: MotionState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let photo = place.photo {
                    FoundPhoto(photo: photo, longest: 1200, creditAlignment: .bottomLeading)
                        .frame(height: 240)
                        .clipShape(.rect(cornerRadius: 18, style: .continuous))
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(place.name).font(.ariHeading).foregroundStyle(.ariText)
                    Spacer()
                    StatusChip.place(TripReading.status(of: place, in: trip, state: state))
                }
                Text(place.why).font(.body).foregroundStyle(.ariSecondary)
                let facts = [place.hours, place.price, place.address].compactMap(\.self)
                if !facts.isEmpty {
                    Text(facts.joined(separator: " · ")).font(.footnote).foregroundStyle(
                        .ariTertiary)
                }
                directions(
                    to: place.name, at: place.location,
                    booking: TripReading.booking(
                        place.booking, of: place.id, in: trip, state: state),
                    website: place.url)
            }
            .padding(20)
        }
        .background(.ariBackground)
    }
}

// MARK: - Travel and stay

/// Getting there and around: each leg with its times, reference and booking.
private struct TravelList: View {
    let trip: Trip
    let state: MotionState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(trip.travel) { leg in
                let booking = TripReading.booking(leg.booking, of: leg.id, in: trip, state: state)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        SymbolDisc(symbol: MotionSymbol.name(for: leg.mode), size: 36)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(leg.title).font(.subheadline.weight(.semibold)).foregroundStyle(
                                .ariText)
                            if let route = Self.route(leg) {
                                Text(route).font(.footnote).foregroundStyle(.ariSecondary)
                            }
                            if let times = Self.times(leg) {
                                Text(times).font(.footnote).foregroundStyle(.ariSecondary)
                            }
                            if let reference = booking?.ref {
                                Text("Ref \(reference)").font(.caption).foregroundStyle(
                                    .ariTertiary)
                            }
                            if let note = leg.note {
                                Text(note).font(.caption).foregroundStyle(.ariTertiary)
                            }
                        }
                        Spacer(minLength: 0)
                        StatusChip.booking(booking)
                    }
                    if booking?.status == .toBook, let url = booking?.url {
                        Link("Book", destination: url).font(.subheadline).buttonStyle(.bordered)
                            .tint(.ariText)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ariSurface, in: .rect(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private static func route(_ leg: Trip.Leg) -> String? {
        switch (leg.from, leg.to) {
        case (let from?, let to?): "\(from) → \(to)"
        case (let from?, nil): "From \(from)"
        case (nil, let to?): "To \(to)"
        default: nil
        }
    }

    private static func times(_ leg: Trip.Leg) -> String? {
        switch (leg.depart, leg.arrive) {
        case (let depart?, let arrive?):
            "\(TripReading.when(depart)) → \(arrive.split(separator: "T").last.map(String.init) ?? arrive)"
        case (let depart?, nil): TripReading.when(depart)
        case (nil, let arrive?): "Arrives \(TripReading.when(arrive))"
        default: nil
        }
    }
}

/// Where you're staying: dates, address, check-in, reference, and the way there.
private struct StayList: View {
    let trip: Trip
    let state: MotionState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(trip.stays) { stay in
                let booking = TripReading.booking(stay.booking, of: stay.id, in: trip, state: state)
                VStack(alignment: .leading, spacing: 0) {
                    if let photo = stay.photo {
                        FoundPhoto(photo: photo, longest: 900).frame(height: 190)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(stay.name).font(.ariHeading).foregroundStyle(.ariText)
                            Spacer(minLength: 8)
                            StatusChip.booking(booking)
                        }
                        if let address = stay.address {
                            Text(address).font(.subheadline).foregroundStyle(.ariSecondary)
                        }
                        if let checkIn = stay.checkIn {
                            Text("Check in \(TripReading.when(checkIn))").font(.footnote)
                                .foregroundStyle(.ariSecondary)
                        }
                        if let checkOut = stay.checkOut {
                            Text("Check out \(TripReading.when(checkOut))").font(.footnote)
                                .foregroundStyle(.ariSecondary)
                        }
                        if let reference = booking?.ref {
                            Text("Ref \(reference)").font(.caption).foregroundStyle(.ariTertiary)
                        }
                        directions(
                            to: stay.name, at: stay.location, booking: booking, website: stay.url
                        )
                        .padding(.top, 4)
                    }
                    .padding(16)
                }
                .background(.ariSurface)
                .clipShape(.rect(cornerRadius: 22, style: .continuous))
            }
        }
    }
}
