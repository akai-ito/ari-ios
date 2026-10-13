import AriKit
import SwiftUI

/// Stands in until Ari can connect to a server. It keeps the system's look, because Ari's own design
/// comes with the conversation screen.
struct PlaceholderView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Ari")
                .font(.title2.weight(.semibold))
            Text("There's nothing to do here yet: Ari can't connect to a server.")
                .foregroundStyle(.secondary)
            Text("Protocol \(ProtocolVersion.supported.description)")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    PlaceholderView()
}
