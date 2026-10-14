import AriKit
import SwiftUI

/// The first connection: the server's address and the token `ito serve` printed. Every problem is
/// named in plain words: an address Ari won't use, nothing answering, something that isn't Ito, a
/// protocol mismatch (and which side to update), or a token the server didn't accept.
struct ConnectView: View {
    let connected: (Connection) -> Void

    @State private var address: String
    @State private var token = ""
    @State private var problem: String?
    @State private var reached: String?
    @State private var connecting = false
    @State private var poses = PoseHistory()
    @FocusState private var focus: Field?

    private enum Field { case address, token }

    init(address: String, connected: @escaping (Connection) -> Void) {
        _address = State(initialValue: address)
        self.connected = connected
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            PresenceView(history: poses, size: 64)
            VStack(spacing: 6) {
                Text("Ari")
                    .font(.system(.largeTitle, design: .serif))
                    .foregroundStyle(.ariText)
                Text(reached ?? "Connect to your Ito server")
                    .font(.subheadline)
                    .foregroundStyle(.ariSecondary)
                    .contentTransition(.opacity)
            }
            VStack(spacing: 12) {
                OutlinedField(title: "Server address") {
                    TextField("", text: $address, prompt: prompt("studio.your-tailnet.ts.net"))
                        .focused($focus, equals: .address)
                        .submitLabel(.next)
                        .onSubmit { focus = .token }
                        #if os(iOS)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                }
                OutlinedField(title: "Token") {
                    SecureField("", text: $token, prompt: prompt("The token ito serve printed"))
                        .focused($focus, equals: .token)
                        .submitLabel(.go)
                        .onSubmit(connect)
                }
                if let problem {
                    Text(problem)
                        .font(.subheadline)
                        .foregroundStyle(.ariSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }
            }
            Button(action: connect) {
                Text(connecting ? "Connecting…" : "Connect")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.ariBackground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.ariText, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(connecting || address.isEmpty || token.isEmpty)
            .opacity(address.isEmpty || token.isEmpty ? 0.5 : 1)
            Spacer()
            Text("Ari speaks protocol \(ProtocolVersion.supported.description)")
                .font(.caption)
                .foregroundStyle(.ariTertiary)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ariBackground)
        .animation(.easeInOut(duration: 0.25), value: problem)
        #if DEBUG
            .task {
                guard let debug = DebugScript.connection else { return }
                address = debug.address
                token = debug.token
                connect()
            }
        #endif
    }

    private func prompt(_ text: String) -> Text {
        Text(text).foregroundStyle(.ariTertiary)
    }

    private func connect() {
        guard !connecting, !address.isEmpty, !token.isEmpty else { return }
        connecting = true
        problem = nil
        poses.set(.thinking)
        Task {
            do {
                let connection = try await Connector().connect(to: address, token: Token(token))
                let server = connection.server
                reached =
                    "Reached Ito \(server.version) on \(server.name) · protocol \(server.protocolVersion)"
                poses.set(.resting)
                try? await Task.sleep(for: .seconds(1.2))
                connected(connection)
            } catch let error as ConnectError {
                problem = Self.describe(error)
                poses.set(.resting)
            } catch {
                problem = "Couldn't connect: \(error.localizedDescription)"
                poses.set(.resting)
            }
            connecting = false
        }
    }

    /// Each problem in plain words, saying what to do about it where there's something to do.
    static func describe(_ error: ConnectError) -> String {
        switch error {
        case .address(.empty):
            "Enter your server's address."
        case .address(.notAnAddress):
            "That doesn't look like an address. Try one like studio.your-tailnet.ts.net:8787."
        case .address(.insecure):
            "Ari only connects over HTTPS, except to this device."
        case .unreachable:
            "Nothing answered at that address. Is the server running, and on your tailnet?"
        case .notIto:
            "Something answered, but it isn't an Ito server."
        case .protocolMismatch(let mismatch):
            switch mismatch.update {
            case .ari: "This server speaks a newer protocol than this Ari. Update Ari."
            case .server:
                "This server speaks an older protocol than Ari. Update Ito on your server."
            }
        case .tokenRejected(let refusal):
            refusal?.message
                ?? "The server didn't accept that token. Check it, or make a new one with ito token new."
        case .refused(let status, let refusal):
            refusal?.message ?? "The server refused, with status \(status)."
        }
    }
}

/// A field in a thin outline, with its name above it.
struct OutlinedField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.ariTertiary)
            content
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(.ariText)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.ariLine, lineWidth: 1))
        }
    }
}

#Preview {
    ConnectView(address: "") { _ in }
}
