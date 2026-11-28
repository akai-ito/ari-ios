import AriKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Share with Kumo: from any app's share sheet, a link, some text, photos and files go to the
/// server's share inbox, with a thought if you like. Kumo puts each share in the thread it belongs
/// in, or a new one it names, and answers it there; the sheet waits a few seconds for that answer,
/// and a slower one comes as its notification. A share that can't go now waits in the app group,
/// and Ari sends it the next time it opens. A recording, which starts a thread of its own, still
/// goes as a message, in chunks iOS carries in the background when it's big.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareModel(
            items: extensionContext?.inputItems as? [NSExtensionItem] ?? [],
            finish: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) },
            cancel: { [weak self] in
                self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
            },
            open: { [weak self] url in self?.openInIto(url) ?? false })
        let host = UIHostingController(rootView: ShareView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    /// Opens Ito at a link, such as Kumo's thread. A share extension can't call UIApplication's
    /// `open` directly, so it asks the application up the responder chain. Returns whether there
    /// was one to ask.
    private func openInIto(_ url: URL) -> Bool {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication, application.responds(to: selector) {
                typealias Open =
                    @convention(c) (
                        AnyObject, Selector, NSURL, NSDictionary, AnyObject?
                    ) -> Void
                let open = unsafeBitCast(application.method(for: selector), to: Open.self)
                open(application, selector, url as NSURL, NSDictionary(), nil)
                return true
            }
            responder = current.next
        }
        return false
    }
}

/// What's being shared, the thought you add, and how sending it went.
@Observable
final class ShareModel {
    /// Photos and files, ready to upload.
    private(set) var attachments: [PendingAttachment] = []
    /// The link, for its card and the share's `url`.
    private(set) var link: URL?
    /// The page's title, as the app sharing it gave it.
    private(set) var linkTitle: String?
    /// The page's picture, as the app sharing it gave one.
    private(set) var linkImage: UIImage?
    /// Text from the other app, for the share's `text`.
    private(set) var texts: [String] = []
    /// A recording, or another file too big for one request, which goes in chunks.
    private(set) var big: BigUpload?
    /// Where its copy waits until it's taken in.
    private var bigFile: URL?
    /// What the server takes and whether it can transcribe now, when it could be asked.
    private(set) var limits: UploadList?
    /// Kept while the share sheet is open, so iOS has every chunk before it closes.
    private var uploads: BigUploads?
    /// Following Kumo's answer while the sheet waits for it.
    private var following: Task<Void, Never>?
    var note = ""
    private(set) var state = State.reading

    enum State: Equatable {
        case reading
        case ready
        case sending
        /// The server has the share: Kumo is placing it and writing back. The thread, once known.
        case answering(ShareReply?)
        /// Kumo answered while the sheet was open.
        case replied(ShareReply)
        /// Kumo's taking longer than the sheet waits: its answer comes as a notification.
        case handedOff(ShareReply?)
        /// A recording on its way, or sent as a message.
        case sent
        /// Saved in the app group for Ari to send when it opens, and why.
        case waiting(String)
        case problem(String)
    }

    private let group = AppGroup.forThisApp()
    private let items: [NSExtensionItem]
    private let finish: () -> Void
    let cancel: () -> Void
    private let open: (URL) -> Bool

    init(
        items: [NSExtensionItem], finish: @escaping () -> Void, cancel: @escaping () -> Void,
        open: @escaping (URL) -> Bool
    ) {
        self.items = items
        self.finish = finish
        self.cancel = cancel
        self.open = open
        Task { await read(items) }
    }

    /// Whether Ari has a server to send to.
    var isConnected: Bool {
        group.address != nil
    }

    /// Whether this goes as a recording, which starts a thread of its own, rather than as a share.
    var isRecording: Bool { recording != nil }

    var canSend: Bool {
        state == .ready && isConnected
            && (!attachments.isEmpty || big != nil || link != nil || !texts.isEmpty
                || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// Whether the share has gone and the sheet now only shows how Kumo's answering.
    var isAnswering: Bool {
        switch state {
        case .answering, .replied, .handedOff: true
        default: false
        }
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

    /// Text from the other app, as one passage.
    private var sharedText: String? {
        texts.isEmpty ? nil : texts.joined(separator: "\n\n")
    }

    func send() {
        guard canSend else { return }
        if isRecording || big != nil {
            sendAsMessage()
        } else {
            sendShare()
        }
    }

    /// Done, once the share has gone: Kumo's answer, if it's still coming, comes as a notification.
    func done() {
        following?.cancel()
        finish()
    }

    /// Opens Kumo's thread in Ito, and closes the sheet.
    func openThread() {
        guard case .replied(let reply) = state, let url = ThreadLink.url(for: reply.thread) else {
            return
        }
        _ = open(url)
        done()
    }

    // MARK: - Sharing

    /// The share goes to the server's share inbox: its photos and files first, then the share
    /// with one id kept for every retry. It's saved in the app group first, so if it can't go
    /// now, Ari sends it when it opens.
    private func sendShare() {
        guard let outbox = group.shareOutbox() else {
            state = .problem("Couldn't keep this for \(LeadName.current).")
            return
        }
        let share = SendShare(
            id: MessageID(UUID().uuidString.lowercased()), url: link?.absoluteString,
            text: sharedText, note: note, attachments: attachments.map(\.id))
        state = .sending
        do {
            for attachment in attachments { try outbox.add(attachment) }
            try outbox.add(share)
        } catch {
            state = .problem(
                "Couldn't keep this for \(LeadName.current): \(error.localizedDescription)")
            return
        }
        Task {
            guard let client else {
                await wait("Ito will send this the next time it opens.")
                return
            }
            let report = await ShareDelivery.deliver(outbox, with: client)
            if let accepted = report.accepted[share.id] {
                state = .answering(nil)
                follow(share, accepted: accepted, with: client)
            } else if let refused = report.refused[share.id] {
                state = .problem(
                    "\(LeadName.current) couldn't take this: \(Self.words(for: refused))")
            } else if report.waiting?.status == 404 {
                await wait(
                    "Your box can't take shares yet. Ito sends this once it's updated.")
            } else {
                await wait("Ito will send this the next time it opens.")
            }
        }
    }

    /// Waits a few seconds for Kumo's answer, saying where it went as soon as that's known.
    private func follow(_ share: SendShare, accepted: ShareStatus, with client: ItoClient) {
        following = Task {
            let reply = await ShareReply.follow(
                share, accepted: accepted, with: client,
                seen: { [weak self] reply in self?.state = .answering(reply) })
            guard !Task.isCancelled else { return }
            if let reply, reply.text != nil {
                state = .replied(reply)
                return
            }
            state = .handedOff(reply)
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    private func wait(_ words: String) async {
        state = .waiting(words)
        try? await Task.sleep(for: .seconds(2))
        finish()
    }

    private static func words(for error: RequestError) -> String {
        switch error {
        case .refused(_, let error?, _): error.message
        case .refused(let status, nil, _): "it answered \(status)."
        case .network: "no connection."
        case .protocolMismatch: "your box speaks a different version of Ito."
        case .unreadable: "its answer couldn't be read."
        }
    }

    // MARK: - A recording, as a message

    /// The message's words, for a recording: your note, then any link and text you shared.
    private var words: String {
        ([note.trimmingCharacters(in: .whitespacesAndNewlines)] + [link?.absoluteString] + texts)
            .compactMap(\.self).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// A recording starts a thread of its own, as from the chat, wherever it's sent from.
    private func sendAsMessage() {
        guard let shares = group.shares() else { return }
        state = .sending
        let carried = attachments.map(\.attachment) + (big.map { [$0.attachment] } ?? [])
        let message = SendMessage(
            id: MessageID(UUID().uuidString.lowercased()), text: words,
            attachments: carried.map(\.id), newThread: Session.startsThread(carrying: carried))
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
            if let client { sent = await ShareDelivery.deliver(shares, with: client) }
            state = sent ? .sent : .waiting("Ito will send this the next time it opens.")
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

    private func read(_ items: [NSExtensionItem]) async {
        if let client {
            limits = try? await client.uploads()
        }
        var problems: [String] = []
        let providers = items.flatMap { $0.attachments ?? [] }
        for provider in providers.prefix(AttachmentMaker.mostPerMessage) {
            do {
                try await read(provider)
            } catch let refusal as BigAttachment.Refusal {
                problems.append(refusal.words)
            } catch {
                problems.append("Couldn't read \(provider.suggestedName ?? "one of them").")
            }
        }
        if link != nil { linkTitle = Self.title(of: items, link: link) }
        state = problems.isEmpty ? .ready : .problem(problems.joined(separator: " "))
        if !problems.isEmpty, !(attachments.isEmpty && link == nil && texts.isEmpty) {
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
            take(url)
            if linkImage == nil, link == url { linkImage = await Self.preview(of: provider) }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            let item = try await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)
            let text =
                (item as? String) ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
            else { return }
            // A link shared as text is still a link.
            if let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased()) {
                take(url)
            } else {
                texts.append(text)
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

    /// The share's one link: the first web link. Any other goes along as text.
    private func take(_ url: URL) {
        guard ["http", "https"].contains(url.scheme?.lowercased()) else { return }
        if link == nil {
            link = url
        } else if url != link {
            texts.append(url.absoluteString)
        }
    }

    /// The page's title, as the sharing app gave it with the item, unless that's only the link.
    private static func title(of items: [NSExtensionItem], link: URL?) -> String? {
        let candidates = items.flatMap {
            [$0.attributedContentText?.string, $0.attributedTitle?.string]
        }
        return candidates.lazy.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0 != link?.absoluteString && URL(string: $0)?.scheme == nil }
    }

    /// The picture the sharing app gave the link, such as the page's icon or a preview of it.
    private nonisolated static func preview(of provider: NSItemProvider) async -> UIImage? {
        await withCheckedContinuation { continuation in
            provider.loadPreviewImage(options: [:]) { item, _ in
                continuation.resume(returning: item as? UIImage)
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
