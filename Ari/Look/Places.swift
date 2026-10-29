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
