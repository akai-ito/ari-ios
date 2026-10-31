import AriKit
import SwiftUI

/// The first connection: the server's address and either a pairing code from `ito pair` (scanned
/// from its QR code, opened from the Camera, or typed) or a token. Every problem is named in plain
/// words: an address Ari won't use, nothing answering, something that isn't Ito, a protocol
/// mismatch (and which side to update), or a code or token the server didn't accept.
struct ConnectView: View {
    /// A pairing link to use at once, such as one the Camera opened.
    var pairing: PairingLink?
    /// Back to the conversation, when a pairing link brought you here from it.
    var cancel: (() -> Void)?
    let connected: (Connection) -> Void

    @State private var address: String
    @State private var token = ""
    @State private var problem: String?
    @State private var reached: String?
    @State private var connecting = false
    @State private var poses = PoseHistory()
    @State private var scanning = false
    @FocusState private var focus: Field?

    private enum Field { case address, token }

    init(
        address: String, pairing: PairingLink? = nil, cancel: (() -> Void)? = nil,
        connected: @escaping (Connection) -> Void
    ) {
        _address = State(initialValue: pairing?.address ?? address)
        _token = State(initialValue: pairing?.code ?? "")
        self.pairing = pairing
        self.cancel = cancel
        self.connected = connected
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            PresenceView(history: poses, size: 64)
            VStack(spacing: 6) {
                Text("Ito")
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
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                OutlinedField(title: "Pairing code or token") {
                    SecureField("", text: $token, prompt: prompt("From ito pair, or a token"))
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
            if CodeScanner.isAvailable {
                Button("Scan the code from ito pair", systemImage: "qrcode.viewfinder") {
                    scanning = true
                }
                .font(.subheadline)
                .foregroundStyle(.ariSecondary)
                .buttonStyle(.plain)
            }
            if let cancel {
                Button("Not now", action: cancel)
                    .font(.subheadline)
                    .foregroundStyle(.ariSecondary)
                    .buttonStyle(.plain)
            }
            Spacer()
            Text("Ito speaks protocol \(ProtocolVersion.supported.description)")
                .font(.caption)
                .foregroundStyle(.ariTertiary)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ariBackground)
        .animation(.easeInOut(duration: 0.25), value: problem)
        // A whole pairing link pasted as the address carries its code with it.
        .onChange(of: address) { _, text in
            guard let link = URL(string: text.trimmingCharacters(in: .whitespaces)),
                let pairing = Connector.pairing(from: link)
            else { return }
            use(PairingLink(address: pairing.address, code: pairing.code))
        }
        .task {
            if let pairing { use(pairing) }
        }
        .sheet(isPresented: $scanning) {
            ScanSheet { text in
                guard let link = URL(string: text), let pairing = Connector.pairing(from: link)
                else { return false }
                scanning = false
                use(PairingLink(address: pairing.address, code: pairing.code))
                return true
            }
        }
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

    private func use(_ pairing: PairingLink) {
        address = pairing.address
        token = pairing.code
        connect()
    }

    private func connect() {
        guard !connecting, !address.isEmpty, !token.isEmpty else { return }
        connecting = true
        problem = nil
        poses.set(.thinking)
        let secret = token.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                // A short code from ito pair becomes a token of this device's own.
                let connection =
                    Connector.isPairingCode(secret)
                    ? try await Connector().pair(
                        address: address, code: secret, deviceName: Self.deviceName)
                    : try await Connector().connect(to: address, token: Token(secret))
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
            "Ito only connects over HTTPS, except to this device."
        case .unreachable:
            "Nothing answered at that address. Is the server running, and on your tailnet?"
        case .notIto:
            "Something answered, but it isn't an Ito server."
        case .protocolMismatch(let mismatch):
            switch mismatch.update {
            case .ari: "This server speaks a newer protocol than this Ito. Update Ito."
            case .server:
                "This server speaks an older protocol than Ito. Update Ito on your server."
            }
        case .pairingCodeRejected(let refusal):
            [refusal?.message, refusal?.detail].compactMap(\.self).joined(separator: " ").nonEmpty
                ?? "That pairing code has expired or was already used. Run ito pair for a new one."
        case .tokenRejected(let refusal):
            refusal?.message
                ?? "The server didn't accept that token. Check it, or make a new one with ito token new."
        case .refused(let status, let refusal):
            refusal?.message ?? "The server refused, with status \(status)."
        }
    }
}

extension ConnectView {
    /// What the server calls this device in its list of paired devices.
    fileprivate static var deviceName: String {
        UIDevice.current.name
    }
}

/// The address and code from `ito pair`'s QR code: `ito://pair?address=…&code=…`.
struct PairingLink: Equatable, Sendable {
    let address: String
    let code: String
}

extension String {
    fileprivate var nonEmpty: String? { isEmpty ? nil : self }
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
