import AriKit
import SwiftUI

/// Stands in for the conversation until Ari can connect: the agent's presence, its name, and the
/// protocol this build speaks.
struct PlaceholderView: View {
    var body: some View {
        VStack(spacing: 14) {
            Orb()
                .frame(width: 76, height: 76)
            Text("Ari")
                .font(.system(size: 16, weight: .semibold))
            Text("Protocol \(ProtocolVersion.supported.description)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 11 / 255, green: 11 / 255, blue: 13 / 255))
        .preferredColorScheme(.dark)
    }
}

/// A still stand-in for the agent's living presence.
private struct Orb: View {
    private static let colors: [Color] = [
        Color(red: 0x7E / 255, green: 0xF9 / 255, blue: 0xFF / 255),
        Color(red: 0x9D / 255, green: 0x8C / 255, blue: 0xFF / 255),
        Color(red: 0xFF / 255, green: 0x8A / 255, blue: 0xD8 / 255),
        Color(red: 0xFF / 255, green: 0xD2 / 255, blue: 0x7A / 255),
        Color(red: 0x7D / 255, green: 0xFF / 255, blue: 0xB5 / 255),
        Color(red: 0x7E / 255, green: 0xF9 / 255, blue: 0xFF / 255),
    ]

    var body: some View {
        Circle()
            .fill(AngularGradient(colors: Self.colors, center: .center, angle: .degrees(120)))
            .saturation(0.75)
            .shadow(color: Self.colors[1].opacity(0.35), radius: 18)
    }
}

#Preview {
    PlaceholderView()
}
