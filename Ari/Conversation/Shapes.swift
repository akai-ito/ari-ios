import AriKit
import MapKit
import SwiftUI

/// What a reply's shapes can do: send a choice. The conversation gives it to each of Ari's replies;
/// elsewhere, as on a page of memory, a shape only shows.
struct ReplyActions {
    /// Sends a choice as your message; `nil` once the conversation has moved on.
    var choose: ((String) -> Void)?
}

extension EnvironmentValues {
    @Entry var replyActions = ReplyActions()
}

/// A block of a reply, drawn as what it is.
struct ShapeView: View {
    let shape: ReplyShape

    var body: some View {
        switch shape {
        case .place(let place): PlaceView(place: place)
        case .choices(let choices): ChoicesView(choices: choices)
        case .images(let images): ImagesView(images: images)
        case .motion(let line): CompactMotionLine(line: line)
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

// MARK: - A place

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
            return .at(lat: lat, lon: lon, name: place.name)
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
                    DirectionsButtons(item: item)
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

// MARK: - Choices

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

/// Pictures Ari found, a page at a time. A tap shows who took one.
private struct ImagesView: View {
    let images: ReplyShape.Images

    /// Pictures that couldn't be loaded: they leave the reply rather than stay as empty boxes.
    @State private var failed: Set<AttachmentID> = []

    var body: some View {
        let shown = images.images.filter { !failed.contains($0.attachment) }
        if !shown.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(shown, id: \.attachment) { photo in
                        FoundPhoto(photo: photo, longest: 900) {
                            withAnimation(.smooth(duration: 0.3)) {
                                _ = failed.insert(photo.attachment)
                            }
                        }
                        .aspectRatio(4 / 3, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 16, style: .continuous))
                        .containerRelativeFrame(.horizontal) { width, _ in
                            shown.count > 1 ? width * 0.86 : width
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }
}
