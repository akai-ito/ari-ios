import AriKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Share to Ari: from any app's share sheet, a photo, a file, a link or some text goes to Ari, with
/// a note if you like. It's sent at once when it can be; otherwise it waits in the app group, and
/// Ari sends it the next time it opens.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareModel(
            providers: (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
                .flatMap { $0.attachments ?? [] },
            finish: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) },
            cancel: { [weak self] in
                self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
            })
        let host = UIHostingController(rootView: ShareView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

/// What's being shared, the note you add, and how sending went.
@Observable
final class ShareModel {
    /// Photos and files, ready to upload.
    private(set) var attachments: [PendingAttachment] = []
    /// Links and text, which go as the message's words, after your note.
    private(set) var words: [String] = []
    var note = ""
    private(set) var state = State.reading

    enum State: Equatable {
        case reading
        case ready
        case sending
        case sent
        /// Saved in the app group for Ari to send when it opens.
        case waiting
        case problem(String)
    }

    private let group = AppGroup.forThisApp()
    private let finish: () -> Void
    let cancel: () -> Void

    init(providers: [NSItemProvider], finish: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.finish = finish
        self.cancel = cancel
        Task { await read(providers) }
    }

    /// Whether Ari has a server to send to.
    var isConnected: Bool {
        group.address != nil
    }

    var canSend: Bool {
        state == .ready && isConnected
            && (!attachments.isEmpty || !text.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    /// The message's words: your note, then the links and text you shared.
    private var text: String {
        ([note.trimmingCharacters(in: .whitespacesAndNewlines)] + words)
            .filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    func send() {
        guard canSend, let shares = group.shares() else { return }
        state = .sending
        let message = SendMessage(
            id: MessageID(UUID().uuidString.lowercased()), text: text,
            attachments: attachments.map(\.id))
        do {
            for attachment in attachments { try shares.add(attachment) }
            try shares.add(message)
        } catch {
            state = .problem("Couldn't keep this for \(LeadName.current): \(error.localizedDescription)")
            return
        }
        Task {
            var sent = false
            if let address = group.address, let token = try? group.tokens.token(for: address) {
                let client = ItoClient(
                    address: address, token: token, transport: URLSessionTransport())
                sent = await ShareDelivery.deliver(shares, with: client)
            }
            state = sent ? .sent : .waiting
            try? await Task.sleep(for: .seconds(sent ? 0.8 : 1.6))
            finish()
        }
    }

    // MARK: - Reading what was shared

    private func read(_ providers: [NSItemProvider]) async {
        var problems: [String] = []
        for provider in providers.prefix(AttachmentMaker.mostPerMessage) {
            do {
                try await read(provider)
            } catch let error as AttachmentMaker.TooLarge {
                problems.append("\(error.name) is larger than Ito accepts: up to 20 MB.")
            } catch {
                problems.append("Couldn't read \(provider.suggestedName ?? "one of them").")
            }
        }
        state = problems.isEmpty ? .ready : .problem(problems.joined(separator: " "))
        if !problems.isEmpty, !(attachments.isEmpty && words.isEmpty) {
            // What could be read can still go.
            try? await Task.sleep(for: .seconds(3))
            state = .ready
        }
    }

    private func read(_ provider: NSItemProvider) async throws {
        let name = provider.suggestedName ?? "photo"
        if provider.registeredContentTypes.contains(where: { $0.conforms(to: .image) }) {
            let data = try await Self.data(provider, .image)
            guard let photo = await AttachmentMaker.photo(data, name: Self.jpegName(name)) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            attachments.append(photo)
        } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
            let url = try await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
            !url.isFileURL
        {
            words.append(url.absoluteString)
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            let item = try await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)
            if let text = item as? String {
                words.append(text)
            } else if let data = item as? Data, let text = String(data: data, encoding: .utf8) {
                words.append(text)
            }
        } else if let type = provider.registeredContentTypes.first {
            attachments.append(
                try await AttachmentMaker.file(at: try await Self.copy(provider, type)))
        }
    }

    private static func jpegName(_ name: String) -> String {
        let stem = (name as NSString).deletingPathExtension
        return (stem.isEmpty ? "photo" : stem) + ".jpg"
    }

    private nonisolated static func data(_ provider: NSItemProvider, _ type: UTType) async throws
        -> Data
    {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadDataRepresentation(for: type) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
    }

    /// A copy of the shared file, made before the system takes the original away, and only if it's
    /// small enough to send.
    private nonisolated static func copy(_ provider: NSItemProvider, _ type: UTType) async throws
        -> URL
    {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadFileRepresentation(for: type, openInPlace: false) { url, _, error in
                guard let url else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                    return
                }
                do {
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= AttachmentMaker.largest else {
                        throw AttachmentMaker.TooLarge(name: url.lastPathComponent)
                    }
                    let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
                    try FileManager.default.createDirectory(
                        at: folder, withIntermediateDirectories: true)
                    let copy = folder.appending(path: url.lastPathComponent)
                    try FileManager.default.copyItem(at: url, to: copy)
                    continuation.resume(returning: copy)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
