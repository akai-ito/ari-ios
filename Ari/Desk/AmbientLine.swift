import AriKit
import SwiftUI

/// The weather around you, small and quiet at the top of the Desk: the sky, the temperature, and
/// when the sun sets, with the town when the phone named it.
struct AmbientLine: View {
    let ambient: Ambient

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)
            Text(words)
        }
        .font(.caption)
        .foregroundStyle(.ariTertiary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken)
    }

    /// "London · 14° partly cloudy · sunset 16:21"; after sunset, the sunset goes.
    private var words: String {
        let weather = "\(ambient.temperature)° \(Self.name(ambient.condition))"
        var parts = [ambient.place, weather].compactMap { $0 }
        if ambient.isDay { parts.append("sunset \(ambient.sunset.date.formatted(DeskTime.time))") }
        return parts.joined(separator: " · ")
    }

    private var spoken: String {
        let place = ambient.place.map { "In \($0), " } ?? ""
        let sunset =
            ambient.isDay ? ", sunset at \(ambient.sunset.date.formatted(DeskTime.time))" : ""
        return "\(place)\(ambient.temperature) degrees, \(Self.name(ambient.condition))\(sunset)"
    }

    private var symbol: String {
        let day = ambient.isDay
        return switch ambient.condition.shown {
        case .clear: day ? "sun.max" : "moon.stars"
        case .partlyCloudy: day ? "cloud.sun" : "cloud.moon"
        case .fog: "cloud.fog"
        case .drizzle: "cloud.drizzle"
        case .rain: "cloud.rain"
        case .snow: "cloud.snow"
        case .thunder: "cloud.bolt"
        default: "cloud"
        }
    }

    static func name(_ weather: Weather) -> String {
        switch weather.shown {
        case .clear: "clear"
        case .partlyCloudy: "partly cloudy"
        case .fog: "fog"
        case .drizzle: "drizzle"
        case .rain: "rain"
        case .snow: "snow"
        case .thunder: "thunder"
        default: "cloudy"
        }
    }
}
