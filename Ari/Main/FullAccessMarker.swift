import SwiftUI

/// While Kumo has full access: a small open lock in the main chat's corner, opposite the gear, for
/// as long as it lasts. Tap it for Settings, where it turns off. Only the main chat shows it.
struct FullAccessMarker: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "lock.open.fill").font(.caption2.weight(.semibold))
                Text("Full access").font(.caption.weight(.semibold))
            }
            .foregroundStyle(.ariBone)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Capsule().fill(Color.ariBone.opacity(0.12)))
            .overlay(Capsule().strokeBorder(Color.ariBone.opacity(0.4), lineWidth: 0.7))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Full access is on")
        .accessibilityHint("Opens Settings, where you can turn it off")
    }
}
