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

/// The quiet note under what's on screen while it's the copy Ari kept, in the grey of the chat's
/// "Reconnecting": "Offline · updated 14:02". Nothing while online.
struct OfflineLine: View {
    @Environment(\.offline) private var offline

    var body: some View {
        if offline.isOffline {
            Text(offline.words)
                .font(.subheadline)
                .foregroundStyle(.ariTertiary)
                .lineLimit(1)
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
