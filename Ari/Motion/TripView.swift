import AriKit
import MapKit
import SwiftUI

/// A trip, open: its cover, then Days, Map, Places, Travel and Stay. Ari writes all of it; you tick
/// what's done, and that's yours. What changed is a button on the cover, not a list under every
/// tab. A place opens as its own page, grown from what you tapped.
struct TripView: View {
    let detail: MotionDetail
    let trip: Trip

    @State private var tab = Section.days
    /// The place open on its own page.
    @State private var openedPlace: String?
    @Namespace private var placeSpace
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
                        .padding(.bottom, 60)
                        .animation(.smooth(duration: 0.3), value: tab)
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
                    if let place = DebugScript.motionPlace { openedPlace = place }
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
        .navigationDestination(item: $openedPlace) { id in
            if let place = trip.places.first(where: { $0.id == id }) {
                PlacePage(motion: detail.motion.id, place: place, trip: trip, state: detail.state)
                    .navigationTransition(.zoom(sourceID: "place \(id)", in: placeSpace))
            }
        }
    }

    // MARK: - The cover

    /// The compact header's bar, which leaves room for the close button at its leading end.
    private static let barHeight: CGFloat = 44

    /// Tall on Days, where the trip opens; slim on the other tabs, so their own photos lead.
    private var coverHeight: CGFloat {
        switch (trip.cover != nil, tab == .days) {
        case (true, true): 340
        case (true, false): 196
        case (false, _): 150
        }
    }

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
                Text(detail.motion.title)
                    .font(
                        tab == .days ? .ariTitle : .system(.title, design: .serif).weight(.semibold)
                    )
                    .foregroundStyle(.ariText)
                    .lineLimit(2)
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
            DaysSection(
                motion: detail.motion.id, trip: trip, state: detail.state, space: placeSpace
            ) {
                openedPlace = $0.id
            }
            .padding(.horizontal, 20)
        case .map:
            TripMap(trip: trip, state: detail.state) { openedPlace = $0.id }
                .padding(.horizontal, 12)
        case .places:
            PlaceRows(trip: trip, state: detail.state, space: placeSpace) { openedPlace = $0.id }
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
    let space: Namespace.ID
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
            // One text, so a long day title wraps under the date rather than in a column of its own.
            Text(
                "\(Text(TripReading.heading(of: day)).font(.ariHeading).foregroundStyle(.ariText))\(Text(day.title.map { "  ·  \($0)" } ?? "").font(.subheadline).foregroundStyle(.ariSecondary))"
            )
            .padding(.bottom, 12)
            ForEach(Array(day.stops.enumerated()), id: \.element.id) { index, stop in
                StopRow(
                    stop: stop, place: TripReading.place(of: stop, in: trip),
                    booking: TripReading.booking(stop.booking, of: stop.id, in: trip, state: state),
                    isLast: index == day.stops.count - 1, space: space, openPlace: openPlace)
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
    let space: Namespace.ID
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
                    .matchedTransitionSource(id: "place \(place.id)", in: space)
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
/// route drawn; the others are grey. Tapping a pin lifts its place right there, in a callout; tap
/// the callout for the place's page.
private struct TripMap: View {
    let trip: Trip
    let state: MotionState
    let openPlace: (Trip.Place) -> Void

    @State private var day: String?
    @State private var selected: String?
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        let stops = TripReading.mapStops(trip)
        let shownDay = day ?? TripReading.openingDay(of: trip)?.id
        MapReader { map in
            self.map(stops, shownDay: shownDay)
                // A pin near the edge pans into view, so its callout isn't cut off.
                .onChange(of: selected) { _, selected in
                    guard let stop = stops.first(where: { $0.stop.id == selected }),
                        let point = map.convert(stop.location.coordinate, to: .local),
                        point.x < 145 || point.x > mapWidth - 145 || point.y < 110
                    else { return }
                    withAnimation(.smooth(duration: 0.5)) {
                        camera = .camera(
                            MapCamera(
                                centerCoordinate: stop.location.coordinate, distance: distance))
                    }
                }
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { mapWidth = $0 }
                .onMapCameraChange { distance = $0.camera.distance }
        }
        .clipShape(.rect(cornerRadius: 20, style: .continuous))
        .overlay(alignment: .topLeading) { dayChips(selected: shownDay).padding(12) }
        .onAppear {
            camera = Self.fit(stops.filter { $0.day == shownDay })
            #if DEBUG
                selected = DebugScript.motionPin
            #endif
        }
        .onChange(of: day) { _, day in
            selected = nil
            withAnimation(.smooth(duration: 0.6)) {
                camera = Self.fit(stops.filter { $0.day == day })
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    @State private var mapWidth: CGFloat = 0
    @State private var distance: CLLocationDistance = 3000

    private func map(_ stops: [TripReading.MapStop], shownDay: String?) -> some View {
        Map(position: $camera, selection: $selected) {
            // The other days first, so the day you're looking at sits on top, and the pin you
            // tapped above them all.
            ForEach(
                stops.sorted { rank($0, shownDay) < rank($1, shownDay) }
            ) { stop in
                Annotation(stop.stop.title, coordinate: stop.location.coordinate, anchor: .bottom) {
                    VStack(spacing: 6) {
                        if selected == stop.stop.id {
                            callout(for: stop)
                                .transition(
                                    .scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                        }
                        MapPin(number: stop.number, lit: stop.day == shownDay)
                    }
                    .animation(.spring(response: 0.32, dampingFraction: 0.78), value: selected)
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
        // Most of the screen: with nothing under it any more, the map can have the room.
        .containerRelativeFrame(.vertical) { height, _ in max(440, height * 0.66) }
    }

    private func rank(_ stop: TripReading.MapStop, _ shownDay: String?) -> Int {
        stop.stop.id == selected ? 2 : stop.day == shownDay ? 1 : 0
    }

    /// The place a pin stands for, over it: its photo, name and when. Tap it for the place's page.
    @ViewBuilder
    private func callout(for stop: TripReading.MapStop) -> some View {
        let place = TripReading.place(of: stop.stop, in: trip)
        Button {
            if let place { openPlace(place) }
        } label: {
            HStack(spacing: 10) {
                if let photo = place?.photo {
                    FoundPhoto(photo: photo, longest: 200, creditOnTap: false)
                        .frame(width: 40, height: 40)
                        .clipShape(.rect(cornerRadius: 9, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(place?.name ?? stop.stop.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.ariText)
                        .lineLimit(1)
                    Text(
                        [stop.stop.time, stop.stop.title].compactMap(\.self).joined(
                            separator: " · ")
                    )
                    .font(.caption)
                    .foregroundStyle(.ariSecondary)
                    .lineLimit(1)
                }
                if place != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.ariTertiary)
                }
            }
            .padding(.leading, place?.photo == nil ? 12 : 6)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: 250)
            .background(.ariSurface, in: .rect(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.ariLine)
            )
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityHint(place == nil ? "" : "Opens the place")
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
        // Shifted up a little, so a callout over the top pin still fits.
        let center = CLLocationCoordinate2D(
            latitude: (south + north) / 2 + (north - south) * 0.12, longitude: (west + east) / 2)
        // Half again around the stops, so the pins and their callouts clear the edges, and at
        // least a few streets for a single stop.
        let span = MKCoordinateSpan(
            latitudeDelta: max((north - south) * 1.6, 0.006),
            longitudeDelta: max((east - west) * 1.5, 0.006))
        return .region(MKCoordinateRegion(center: center, span: span))
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

/// The way to one of the trip's places, opening its listing in Maps, and booking it while it's
/// still to book, or its website.
private func directions(
    to name: String, at location: Trip.Location?, address: String? = nil,
    booking: Trip.Booking? = nil, website: URL? = nil
) -> PlaceDirections {
    let link: (title: String, url: URL)? =
        if booking?.status == .toBook, let url = booking?.url {
            ("Book", url)
        } else if let website {
            ("Website", website)
        } else {
            nil
        }
    return PlaceDirections(
        name: name, address: address, location: location?.coordinate, link: link)
}

extension Trip.Location {
    fileprivate var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

// MARK: - Places

/// The trip's shortlist, by what you'd do there: a row each for Eat, See and Do, of cards all the
/// same size, so the choice reads at a glance. Ideas come first in each row, then what's in the
/// plan, then what's booked. A card opens the place as its own page.
private struct PlaceRows: View {
    let trip: Trip
    let state: MotionState
    let space: Namespace.ID
    let openPlace: (Trip.Place) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            ForEach(TripReading.placeRows(trip, state: state)) { row in
                VStack(alignment: .leading, spacing: 12) {
                    Text(row.title)
                        .font(.ariHeading)
                        .foregroundStyle(.ariText)
                        .padding(.horizontal, 20)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(row.places) { place in
                                Button {
                                    openPlace(place)
                                } label: {
                                    PlaceCard(
                                        place: place,
                                        status: TripReading.status(
                                            of: place, in: trip, state: state)
                                    )
                                    .opacity(row.title == "Passed" ? 0.55 : 1)
                                }
                                .buttonStyle(.plain)
                                .matchedTransitionSource(id: "place \(place.id)", in: space)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .contentMargins(.horizontal, 20, for: .scrollContent)
                }
            }
        }
    }
}

/// A place on the Places tab: its photo (or its kind in Ari's dots when there's none), its name and
/// where it stands. Every card is the same size, whatever Ari wrote about it.
private struct PlaceCard: View {
    let place: Trip.Place
    let status: PlaceStatus

    static let width: CGFloat = 172

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PlacePhoto(place: place, longest: 500)
                .frame(width: Self.width, height: Self.width * 3 / 4)
                .clipShape(.rect(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    PlaceChip(status: status).padding(8)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.ariText)
                    .lineLimit(1)
                Text([place.hours, place.price].compactMap(\.self).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.ariTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .frame(width: Self.width, alignment: .leading)
        .contentShape(.rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the place")
    }
}

/// Where a place stands, in plain words: an idea, in the plan, booked.
private struct PlaceChip: View {
    let status: PlaceStatus

    var body: some View {
        switch status {
        case .booked: chip("Booked", filled: true)
        case .picked: chip("In the plan", filled: true)
        case .shortlisted: chip("Idea", filled: false)
        case .passed: chip("Not for us", filled: false)
        default: EmptyView()
        }
    }

    private func chip(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(filled ? Color.ariBackground : .ariText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                filled ? AnyShapeStyle(Color.ariBone) : AnyShapeStyle(.ultraThinMaterial),
                in: Capsule()
            )
            .environment(\.colorScheme, .dark)
            .fixedSize()
    }
}

/// A place's photo, or, without one, its kind drawn in Ari's dots, so a card never looks empty.
private struct PlacePhoto: View {
    let place: Trip.Place
    var longest = 900
    var creditOnTap = false

    var body: some View {
        if let photo = place.photo {
            FoundPhoto(photo: photo, longest: longest, creditOnTap: creditOnTap)
        } else {
            Rectangle()
                .fill(.ariSurface)
                .overlay { DotGlyph(symbol: Self.symbol(for: place.category), side: 56) }
        }
    }

    static func symbol(for category: PlaceCategory) -> String {
        switch category {
        case .restaurant: "fork.knife"
        case .cafe: "cup.and.saucer.fill"
        case .bar: "wineglass.fill"
        case .museum: "building.columns.fill"
        case .sight: "binoculars.fill"
        case .park: "leaf.fill"
        case .shop: "bag.fill"
        case .activity: "figure.walk"
        default: "mappin"
        }
    }
}

/// A place, as its own page: its photo, why Ari chose it, your choice for it, the facts, where it
/// sits in the plan, and the way there. It follows the thing as it changes, so your choice and Ari
/// fitting it into a day show here at once.
private struct PlacePage: View {
    let motion: MotionID
    let place: Trip.Place
    let trip: Trip
    let state: MotionState

    @Environment(Motions.self) private var motions: Motions?
    @State private var problem: String?
    @State private var chosen = 0

    /// The thing as it is now: your choices and Ari's changes since the page opened.
    private var live: (trip: Trip, place: Trip.Place, state: MotionState) {
        guard let detail = motions?.details[motion], case .trip(let trip) = detail.content,
            let place = trip.places.first(where: { $0.id == place.id })
        else { return (trip, place, state) }
        return (trip, place, detail.state)
    }

    var body: some View {
        let (trip, place, state) = live
        let status = TripReading.status(of: place, in: trip, state: state)
        let booking = TripReading.booking(place.booking, of: place.id, in: trip, state: state)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PlacePhoto(place: place, longest: 1400, creditOnTap: true)
                    .frame(height: 340)
                    .overlay {
                        LinearGradient(
                            colors: [.clear, .clear, .ariBackground], startPoint: .top,
                            endPoint: .bottom
                        )
                        .allowsHitTesting(false)
                    }
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        PlaceChip(status: status)
                        Text(place.name).font(.ariTitle).foregroundStyle(.ariText)
                    }
                    // Ari's words, in its serif.
                    Text(place.why)
                        .font(.ariBody)
                        .foregroundStyle(.ariText)
                        .lineSpacing(Rhythm.ariLineSpacing)
                    if status != .booked {
                        choice(status, planned: TripReading.isPlanned(place.id, in: trip))
                    }
                    facts(place)
                    plan(place, in: trip)
                    directions(
                        to: place.name, at: place.location, address: place.address,
                        booking: booking, website: place.url)
                    if let photo = place.photo {
                        Link(destination: photo.sourceURL) {
                            Label("Photo: \(photo.credit)", systemImage: "camera")
                                .font(.caption)
                                .foregroundStyle(.ariTertiary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, -24)
                .padding(.bottom, 40)
                .frame(maxWidth: Rhythm.column, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(.ariBackground)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sensoryFeedback(.selection, trigger: chosen)
    }

    /// Your choice for the place: still an idea, in the plan, or not for you. Ari fits what you put
    /// in the plan into a day a few seconds later, and stops suggesting what you pass on. Booked is
    /// Ari's, so there's no choosing once it is.
    private func choice(_ status: PlaceStatus, planned: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(
                "Your choice",
                selection: Binding(
                    get: { status },
                    set: { choose($0) })
            ) {
                Text("Idea").tag(PlaceStatus.shortlisted)
                Text("In the plan").tag(PlaceStatus.picked)
                Text("Not for us").tag(PlaceStatus.passed)
            }
            .pickerStyle(.segmented)
            Text(problem ?? Self.line(for: status, planned: planned))
                .font(.footnote)
                .foregroundStyle(problem == nil ? Color.ariTertiary : .ariSecondary)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: status)
        }
    }

    private static func line(for status: PlaceStatus, planned: Bool) -> String {
        switch status {
        case .picked: planned ? "In the plan, below." : "\(LeadName.current) will fit it into a day."
        case .passed: "\(LeadName.current) won't suggest it again."
        default: "An idea for now."
        }
    }

    private func choose(_ status: PlaceStatus) {
        chosen += 1
        problem = nil
        Task {
            guard let motions else { return }
            if !(await motions.choose(motion, place: place.id, status: status)) {
                problem = "Couldn't save that. Try again in a moment."
            }
        }
    }

    /// Hours, price and address, a line each.
    @ViewBuilder
    private func facts(_ place: Trip.Place) -> some View {
        let lines: [(symbol: String, text: String)] = [
            place.hours.map { ("clock", $0) }, place.price.map { ("banknote", $0) },
            place.address.map { ("mappin.and.ellipse", $0) },
        ].compactMap(\.self)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(lines, id: \.text) { line in
                    Label(line.text, systemImage: line.symbol)
                        .font(.subheadline)
                        .foregroundStyle(.ariSecondary)
                }
            }
        }
    }

    /// Where it sits in the plan: each stop that goes there.
    @ViewBuilder
    private func plan(_ place: Trip.Place, in trip: Trip) -> some View {
        let stops = TripReading.stops(at: place.id, in: trip)
        if !stops.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("In the plan")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.ariTertiary)
                ForEach(stops, id: \.stop.id) { day, stop in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(.ariBone).frame(width: 6, height: 6)
                        Text(
                            [TripReading.shortName(of: day), stop.time, stop.title]
                                .compactMap(\.self).joined(separator: " · ")
                        )
                        .font(.subheadline)
                        .foregroundStyle(.ariText)
                    }
                }
            }
        }
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
                            to: stay.name, at: stay.location, address: stay.address,
                            booking: booking, website: stay.url
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
