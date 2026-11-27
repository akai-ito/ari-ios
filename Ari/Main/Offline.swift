import AriKit
import SwiftUI

/// Whether there's no network, so what's on screen is the copy Ari kept, and how fresh it is.
struct Offline: Equatable {
    var isOffline = false
    /// When Ari last heard from the server.
    var updatedAt: Date?

    init(isOffline: Bool = false, updatedAt: Date? = nil) {
        self.isOffline = isOffline
        self.updatedAt = updatedAt
    }

    init(_ session: Session) {
        self.init(isOffline: session.isOffline, updatedAt: session.updatedAt)
    }

    /// "Offline · updated 14:02".
    var words: String { OfflineNote.words(updatedAt: updatedAt) }
}

extension EnvironmentValues {
    @Entry var offline = Offline()
}

/// The quiet note that what's on screen is the copy Ari kept, with a struck-through cloud, in the
/// grey of the chat's "Reconnecting": "Offline · updated 14:02". On the Desk it's a small capsule
/// where the weather goes. Nothing while online.
struct OfflineLine: View {
    /// In a capsule, as at the top of the Desk.
    var capsule = false

    @Environment(\.offline) private var offline

    /// The struck-through cloud beside the words.
    static let symbol = "icloud.slash"

    var body: some View {
        if offline.isOffline {
            HStack(spacing: 6) {
                Image(systemName: Self.symbol).accessibilityHidden(true)
                Text(offline.words)
            }
            .font(capsule ? .caption : .subheadline)
            .foregroundStyle(.ariTertiary)
            .lineLimit(1)
            .padding(.horizontal, capsule ? 12 : 0)
            .padding(.vertical, capsule ? 6 : 0)
            .background {
                if capsule {
                    Capsule().fill(Color.ariSurface)
                        .overlay(Capsule().strokeBorder(Color.ariLine, lineWidth: 0.7))
                }
            }
            .accessibilityElement(children: .combine)
            .transition(.opacity)
        }
    }
}

extension View {
    /// Something the server has to answer at once, such as Undo: while offline it's dimmed and does
    /// nothing, rather than seeming done.
    func waitsForConnection() -> some View {
        modifier(WaitsForConnection())
    }
}

private struct WaitsForConnection: ViewModifier {
    @Environment(\.offline) private var offline

    func body(content: Content) -> some View {
        content
            .disabled(offline.isOffline)
            .opacity(offline.isOffline ? 0.45 : 1)
            .animation(.smooth(duration: 0.3), value: offline.isOffline)
    }
}
