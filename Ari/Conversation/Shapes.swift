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

/// A place you might go: a still picture of it on Apple's map in the card, and a tap opens a map you
/// can move around, with Directions and Open in Maps, which go to the Maps app. The card's map is a
/// picture, not a live map: a live map in every card, each searching Maps as it appeared, made a
/// long conversation heavy to scroll.
private struct PlaceView: View {
    let place: ReplyShape.Place

    @State private var coordinate: CLLocationCoordinate2D?
    @State private var opens = false

    var body: some View {
        Button {
            opens = true
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                MapPicture(coordinate: coordinate)
                    .frame(height: 150)
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
        .task(id: place.name) { coordinate = await Self.coordinate(of: place) }
        .sheet(isPresented: $opens) {
            PlaceSheet(place: place)
        }
    }

    /// Where the place is: where Ari put it, or, without coordinates, where Maps finds it.
    static func coordinate(of place: ReplyShape.Place) async -> CLLocationCoordinate2D? {
        if let lat = place.lat, let lon = place.lon {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return await find(place)?.location.coordinate
    }

    /// The place in Maps, for the way there: its listing, found by name and address near where Ari
    /// put it, or a pin there when Maps has none.
    static func find(_ place: ReplyShape.Place) async -> MKMapItem? {
        let near = place.lat.flatMap { lat in
            place.lon.map { CLLocationCoordinate2D(latitude: lat, longitude: $0) }
        }
        if let listing = await MapsListing.find(
            name: place.name, address: place.address, near: near)
        {
            return listing
        }
        return near.map { .at(lat: $0.latitude, lon: $0.longitude, name: place.name) }
    }
}

/// A still picture of somewhere on Apple's map, dark like Ari, with a pin in Ari's bone. Made once
/// for each place and size, and kept while there's memory for it (`NSCache` lets them go under
/// memory pressure), so a row scrolling back into view shows it at once.
private struct MapPicture: View {
    let coordinate: CLLocationCoordinate2D?

    @Environment(\.displayScale) private var scale
    @State private var size: CGSize = .zero
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(.ariSurface)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
                }
            }
            .clipped()
            .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
            .task(id: Key(coordinate: coordinate, size: size)) {
                guard let coordinate, size.width > 0 else { return }
                let made = await Self.picture(at: coordinate, size: size, scale: scale)
                withAnimation(.easeOut(duration: 0.2)) { image = made }
            }
            .accessibilityHidden(true)
    }

    private struct Key: Equatable {
        let coordinate: CLLocationCoordinate2D?
        let size: CGSize

        static func == (a: Key, b: Key) -> Bool {
            a.size == b.size && a.coordinate?.latitude == b.coordinate?.latitude
                && a.coordinate?.longitude == b.coordinate?.longitude
        }
    }

    private static let pictures = NSCache<NSString, UIImage>()

    static func picture(at coordinate: CLLocationCoordinate2D, size: CGSize, scale: CGFloat)
        async -> UIImage?
    {
        let key =
            "\(coordinate.latitude),\(coordinate.longitude) \(Int(size.width))x\(Int(size.height))@\(scale)"
            as NSString
        if let kept = pictures.object(forKey: key) { return kept }
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: coordinate, latitudinalMeters: 700, longitudinalMeters: 700)
        options.size = size
        options.scale = scale
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        options.pointOfInterestFilter = MKPointOfInterestFilter(
            including: [.restaurant, .museum, .publicTransport])
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else {
            return nil
        }
        let point = snapshot.point(for: coordinate)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            snapshot.image.draw(at: .zero)
            // The pin: a bone dot with a dark ring, as on a trip's map.
            let ring = UIBezierPath(
                ovalIn: CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18))
            UIColor(Color.ariBackground).setFill()
            ring.fill()
            let dot = UIBezierPath(
                ovalIn: CGRect(x: point.x - 6.5, y: point.y - 6.5, width: 13, height: 13))
            UIColor(Color.ariBone).setFill()
            dot.fill()
        }
        pictures.setObject(image, forKey: key)
        return image
    }
}

/// The map itself, live: Apple's, dark like Ari, with the place's pin. Only in the sheet.
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

    @Environment(\.dismiss) private var dismiss
    /// The place in Maps, looked up as the sheet opens, not as the card scrolls by.
    @State private var item: MKMapItem?

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
        .task { item = await PlaceView.find(place) }
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
