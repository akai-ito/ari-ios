import MapKit
import SwiftUI

/// The way somewhere in Apple's Maps, with one button beside it: booking the place, its website,
/// or Maps itself. Directions shows once there's somewhere to go.
struct DirectionsButtons: View {
    let item: MKMapItem?
    /// The button beside Directions; without one, "Open in Maps".
    var link: (title: String, url: URL)?

    var body: some View {
        HStack(spacing: 10) {
            if let item {
                Button {
                    item.openInMaps(launchOptions: [
                        MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault
                    ])
                } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.ariText)
                .foregroundStyle(.ariBackground)
            }
            if let link {
                Link(destination: link.url) {
                    Text(link.title).font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(.ariText)
            } else if let item {
                Button {
                    item.openInMaps()
                } label: {
                    Text("Open in Maps").font(.subheadline).frame(
                        maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(.ariText)
            }
        }
    }
}

extension MKMapItem {
    /// A pin at a point, named.
    static func at(lat: Double, lon: Double, name: String) -> MKMapItem {
        let item = MKMapItem(location: CLLocation(latitude: lat, longitude: lon), address: nil)
        item.name = name
        return item
    }
}

/// A place's listing in Apple's Maps, with its photos, hours, website and reviews, rather than a bare
/// pin at its coordinates. Found once and kept while there's memory for it.
///
/// Only points of interest count: with the address in the query, Maps answered "Trumpington Street"
/// for Fitzbillies, the street rather than the bakery. So it searches by name first, then by name
/// and address, near where Ari put it, and a result far from there is a namesake elsewhere (the
/// other Fitzbillies, a Kricket in London), so it's turned down.
enum MapsListing {
    /// How far from Ari's coordinates a listing can be and still be the place.
    static let nearEnough: CLLocationDistance = 400

    private static let found = NSCache<NSString, MKMapItem>()

    static func find(name: String, address: String?, near coordinate: CLLocationCoordinate2D?)
        async -> MKMapItem?
    {
        let key =
            [name, address, coordinate.map { "\($0.latitude),\($0.longitude)" }]
            .compactMap(\.self).joined(separator: "|") as NSString
        if let kept = found.object(forKey: key) { return kept }
        let queries = [name] + (address.map { ["\(name), \($0)"] } ?? [])
        for query in queries {
            if let listing = await search(query, near: coordinate) {
                found.setObject(listing, forKey: key)
                return listing
            }
        }
        return nil
    }

    private static func search(_ query: String, near coordinate: CLLocationCoordinate2D?) async
        -> MKMapItem?
    {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        guard let coordinate else {
            return try? await MKLocalSearch(request: request).start().mapItems.first
        }
        request.region = MKCoordinateRegion(
            center: coordinate, latitudinalMeters: 2 * nearEnough,
            longitudinalMeters: 2 * nearEnough)
        guard let items = try? await MKLocalSearch(request: request).start().mapItems else {
            return nil
        }
        let there = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return
            items
            .map { (item: $0, distance: $0.location.distance(from: there)) }
            .filter { $0.distance <= nearEnough }
            .min { $0.distance < $1.distance }?.item
    }
}

/// Directions and Open in Maps for one of Ari's places. They open the place's listing in Maps, and
/// a pin at its coordinates only when Maps has no listing for it. While the listing is being found,
/// usually well under a second, the buttons wait rather than open the pin.
struct PlaceDirections: View {
    let name: String
    var address: String?
    let location: CLLocationCoordinate2D?
    /// The button beside Directions, such as Book or Website.
    var link: (title: String, url: URL)?

    @State private var listing: MKMapItem?
    @State private var looked = false

    var body: some View {
        DirectionsButtons(item: listing ?? pin, link: link)
            .disabled(!looked && location != nil)
            .task(id: name) {
                listing = await MapsListing.find(name: name, address: address, near: location)
                looked = true
            }
            // However slow Maps is, the pin is there after a few seconds.
            .task(id: name) {
                try? await Task.sleep(for: .seconds(4))
                looked = true
            }
    }

    private var pin: MKMapItem? {
        location.map { .at(lat: $0.latitude, lon: $0.longitude, name: name) }
    }
}
