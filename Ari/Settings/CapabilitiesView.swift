import AriKit
import SwiftUI

/// Settings › Capabilities: the domains of your life Ari can know about, and the hands it can act
/// with, each with where it stands. Drawn from what the server says, so a capability this Ari has
/// never heard of still shows, sets up and switches.
struct CapabilitiesView: View {
    let capabilities: Capabilities

    var body: some View {
        Form {
            switch capabilities.load {
            case .loading where capabilities.all.isEmpty:
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            case .failed(let error):
                Section {
                    Text("Couldn't reach your server: \(error.plainWords)")
                        .foregroundStyle(.ariSecondary)
                    Button("Try again") { Task { await capabilities.refresh() } }
                }
                .listRowBackground(Color.ariSurface)
            default:
                if !capabilities.domains.isEmpty {
                    Section {
                        ForEach(capabilities.domains) { row($0) }
                    } header: {
                        Text("Your life")
                    } footer: {
                        Text("What Ari can know about. Each one can draw on several services.")
                    }
                    .listRowBackground(Color.ariSurface)
                }
                if !capabilities.hands.isEmpty {
                    Section {
                        ForEach(capabilities.hands) { row($0) }
                    } header: {
                        Text("Ari's hands")
                    } footer: {
                        Text(
                            "What Ari can do. Anything that spends, sends or books asks you first.")
                    }
                    .listRowBackground(Color.ariSurface)
                }
                if capabilities.all.isEmpty {
                    Text("Your server has no capabilities yet.")
                        .foregroundStyle(.ariTertiary)
                        .listRowBackground(Color.ariSurface)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(.ariBackground)
        .navigationTitle("Capabilities")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await capabilities.refresh() }
        .refreshable { await capabilities.refresh() }
    }

    private func row(_ capability: Capability) -> some View {
        NavigationLink(value: SettingsRoute.capability(capability.id)) {
            CapabilityRow(capability: capability)
        }
    }
}

/// A place in Settings, for its navigation stack.
enum SettingsRoute: Hashable {
    case capabilities
    /// A capability's page, with its setup sheet open if `setup`.
    case capability(CapabilityID, setup: Bool = false)
}

/// A capability's row: its symbol, title and summary (or why it needs you), and its state.
struct CapabilityRow: View {
    let capability: Capability

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: capability.symbolName)
                .foregroundStyle(.ariSecondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(capability.title).foregroundStyle(.ariText)
                Text(
                    capability.state == .needsYou
                        ? capability.detail ?? capability.summary
                        : capability.summary
                )
                .font(.footnote)
                .foregroundStyle(capability.state == .needsYou ? .ariSecondary : .ariTertiary)
                .lineLimit(2)
            }
            Spacer(minLength: 8)
            CapabilityStateLabel(state: capability.state)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

/// On, Off, Set up, or Needs you with a small bone dot: the only warm thing in the list.
struct CapabilityStateLabel: View {
    let state: CapabilityState

    var body: some View {
        switch state {
        case .on:
            Text("On").foregroundStyle(.ariTertiary)
        case .setup:
            Text("Set up").foregroundStyle(.ariText)
        case .needsYou:
            HStack(spacing: 6) {
                Circle().fill(.ariBone).frame(width: 7, height: 7)
                Text("Needs you").foregroundStyle(.ariText)
            }
        default:
            Text("Off").foregroundStyle(.ariTertiary)
        }
    }
}

extension Capability {
    /// The server's symbol, or one for its kind.
    var symbolName: String {
        symbol ?? (kind == .domain ? "circle.grid.2x2" : "hand.raised")
    }
}

extension RequestError {
    /// What went wrong, briefly, for a footnote.
    var plainWords: String {
        switch self {
        case .network: "no connection."
        case .refused(_, let error?, _): error.message
        case .refused(let status, nil, _): "it answered \(status)."
        case .protocolMismatch: "it speaks a different version of Ito."
        case .unreadable: "its answer couldn't be read."
        }
    }
}
