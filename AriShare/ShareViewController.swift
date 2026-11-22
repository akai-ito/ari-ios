import AriKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Share to Ari: from any app's share sheet, a photo, a file, a link or some text goes to Ari, with
/// a note if you like. It's sent at once when it can be; otherwise it waits in the app group, and
/// Ari sends it the next time it opens. A recording, or any file too big for one request, is handed
/// to iOS to carry in the background in chunks, so the sheet can close at once; Ari finishes it
/// and sends its message when iOS wakes it.
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
    /// A recording, or another file too big for one request, which goes in chunks.
    private(set) var big: BigUpload?
    /// Where its copy waits until it's taken in.
    private var bigFile: URL?
    /// What the server takes and whether it can transcribe now, when it could be asked.
    private(set) var limits: UploadList?
    /// Kept while the share sheet is open, so iOS has every chunk before it closes.
    private var uploads: BigUploads?
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
            && (!attachments.isEmpty || big != nil
                || !text.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    /// The recording being shared, big or small, for its card.
    var recording: (name: String, detail: String)? {
        if let big, big.mediaType.hasPrefix("audio/") {
            return (big.name, recordingDetail(seconds: big.durationSeconds, bytes: big.size))
        }
        guard let audio = attachments.first(where: { $0.mediaType.hasPrefix("audio/") }) else {
            return nil
        }
        return (audio.name, recordingDetail(seconds: nil, bytes: audio.bytes.count))
    }

    private func recordingDetail(seconds: Double?, bytes: Int) -> String {
        (["Recording"] + [seconds.map { "\(Int(($0 / 60).rounded())) min" }].compactMap(\.self)
            + [UploadLimits.sizeWords(bytes)]).joined(separator: " · ")
    }

    private var client: ItoClient? {
        guard let address = group.address, let token = try? group.tokens.token(for: address) else {
            return nil
        }
        return ItoClient(address: address, token: token, transport: URLSessionTransport())
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
            attachments: attachments.map(\.id) + (big.map { [$0.id] } ?? []))
        if let big, let bigFile {
            sendBig(big, from: bigFile, with: message, shares: shares)
            return
        }
        do {
            for attachment in attachments { try shares.add(attachment) }
            try shares.add(message)
        } catch {
            state = .problem(
                "Couldn't keep this for \(LeadName.current): \(error.localizedDescription)")
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

    /// The big file goes to iOS in chunks, with the message waiting on it; small photos alongside go
    /// first, as any share's do. If the server can't be reached now, Ari carries on when it opens.
    private func sendBig(
        _ big: BigUpload, from file: URL, with message: SendMessage, shares: OutboxStore
    ) {
        guard let store = BigUploadStore.shared(group), let client else {
            state = .problem("Couldn't keep this for \(LeadName.current).")
            return
        }
        var upload = big
        upload.message = message
        let carrier = BackgroundChunkCarrier(
            identifier: group.identifier + ".uploads.share", sharedContainer: group.identifier)
        let uploads = BigUploads(store: store, client: client, carrier: carrier, name: "share")
        carrier.uploads = uploads
        self.uploads = uploads
        Task {
            for attachment in attachments { try? shares.add(attachment) }
            _ = await ShareDelivery.deliver(shares, with: client)
            do {
                try await uploads.start(upload, file: file)
            } catch {
                state = .problem(
                    "Couldn't keep \(upload.name) on the phone to send: there may not be room.")
                return
            }
            try? FileManager.default.removeItem(at: file)
            if case .refused(let error) = uploads.uploads[upload.id]?.state {
                state = .problem(error.message)
                return
            }
            state = .sent
            try? await Task.sleep(for: .seconds(1))
            finish()
        }
    }

    // MARK: - Reading what was shared

    private func read(_ providers: [NSItemProvider]) async {
        if let client {
            limits = try? await client.uploads()
        }
        var problems: [String] = []
        for provider in providers.prefix(AttachmentMaker.mostPerMessage) {
            do {
                try await read(provider)
            } catch let refusal as BigAttachment.Refusal {
                problems.append(refusal.words)
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
            let copy = try await Self.copy(provider, type)
            let size = (try? copy.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard BigAttachment.isBig(size: size, limits: limits?.limits) else {
                attachments.append(try await AttachmentMaker.file(at: copy))
                return
            }
            // One big file a share: a recording goes on its own.
            guard big == nil else { throw BigAttachment.Refusal(words: "One recording at a time.") }
            switch await BigAttachment.upload(for: copy, limits: limits?.limits) {
            case .success(let upload):
                big = upload
                bigFile = copy
            case .failure(let refusal):
                throw refusal
            }
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

    /// A copy of the shared file, made before the system takes the original away: a big one is
    /// copied, never read into memory.
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
