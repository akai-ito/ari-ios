import Foundation

// The share sheet's way to the server's share inbox: a share waits in the app group, its photos and
// files beside it, until the server has it, so a share made offline goes when Ari next opens. Each
// keeps the one id it was made with, so sending it again is always safe.

extension ItoClient {
    /// `POST /v0/shares`: a share for Kumo to place in a thread and answer there. Upload its photos
    /// and files first. Sending the same share again answers where it stands and changes nothing.
    public func share(_ share: SendShare) async throws(RequestError) -> ShareStatus {
        let result: ShareResult = try await call(
            HTTPRequest(.post, "/v0/shares", body: try Self.json(share)))
        return result.share
    }
}

/// Shares waiting for the server, oldest first, each a small JSON file written atomically and
/// named so the order survives a restart, with their photos and files in `attachments/`. Beside the
/// message outbox, in a folder of its own, so neither reads the other's files.
public struct ShareOutbox: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The photos and files, kept until they're uploaded, as the message outbox keeps them.
    private var files: OutboxStore { OutboxStore(directory: directory) }

    /// The shares still to send, oldest first. A file that isn't a share is deleted.
    public func load() -> [SendShare] {
        entries().compactMap { entry in
            guard let data = try? Data(contentsOf: entry.url),
                let share = try? JSONDecoder().decode(SendShare.self, from: data)
            else {
                try? FileManager.default.removeItem(at: entry.url)
                return nil
            }
            return share
        }
    }

    public func add(_ share: SendShare) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = entries()
        guard !existing.contains(where: { $0.id == share.id.rawValue }) else { return }
        let next = (existing.last?.sequence ?? 0) + 1
        let name = String(format: "%012d", next) + "-" + share.id.rawValue + ".json"
        try JSONEncoder().encode(share).write(
            to: directory.appending(path: name), options: Self.writing)
    }

    public func remove(_ id: MessageID) {
        for entry in entries() where entry.id == id.rawValue {
            try? FileManager.default.removeItem(at: entry.url)
        }
    }

    public func add(_ attachment: PendingAttachment) throws { try files.add(attachment) }
    public func attachments() -> [PendingAttachment] { files.attachments() }
    public func removeAttachment(_ id: AttachmentID) { files.removeAttachment(id) }

    /// Whether anything waits.
    public var isEmpty: Bool { entries().isEmpty && attachments().isEmpty }

    private static var writing: Data.WritingOptions {
        #if os(iOS)
            [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #else
            [.atomic]
        #endif
    }

    private func entries() -> [(sequence: Int, id: String, url: URL)] {
        let found =
            (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))
            ?? []
        return found.compactMap { url in
            let name = url.deletingPathExtension().lastPathComponent
            guard url.pathExtension == "json", let dash = name.firstIndex(of: "-"),
                let sequence = Int(name[..<dash])
            else { return nil }
            return (sequence, String(name[name.index(after: dash)...]), url)
        }
        .sorted { $0.sequence < $1.sequence }
    }
}

extension AppGroup {
    /// Where shares wait for the server's share inbox: by the share extension at once, or by Ari
    /// when it next opens. `nil` without the app group.
    public func shareOutbox() -> ShareOutbox? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
            .map {
                ShareOutbox(
                    directory: $0.appending(path: "Shares/Inbox", directoryHint: .isDirectory))
            }
    }
}

extension ShareDelivery {
    /// How sending the waiting shares went.
    public struct Report: Sendable, Equatable {
        /// The shares the server has, by id, as it answered.
        public var accepted: [MessageID: ShareStatus] = [:]
        /// Shares the server refused outright, which are dropped rather than tried forever.
        public var refused: [MessageID: RequestError] = [:]
        /// Why something still waits for a later try, such as being offline; `nil` once it all
        /// went.
        public var waiting: RequestError?
    }

    /// Sends the waiting shares: every photo and file first, then each share, oldest first, until
    /// one can't go now. A refusal that trying again won't change (one the server can't take)
    /// drops what it refused, so it never blocks the shares behind it.
    public static func deliver(_ outbox: ShareOutbox, with client: ItoClient) async -> Report {
        var report = Report()
        var lost: [AttachmentID: RequestError] = [:]
        for attachment in outbox.attachments() {
            do {
                _ = try await client.upload(
                    attachment.id, name: attachment.name, mediaType: attachment.mediaType,
                    bytes: attachment.bytes)
                outbox.removeAttachment(attachment.id)
            } catch  where Self.waits(error) {
                report.waiting = error
                return report
            } catch {
                // Too big, or a kind the server won't take: the share it's in can't go either.
                outbox.removeAttachment(attachment.id)
                lost[attachment.id] = error
            }
        }
        for share in outbox.load() {
            if let refusal = share.attachments?.lazy.compactMap({ lost[$0] }).first {
                report.refused[share.id] = refusal
                outbox.remove(share.id)
                continue
            }
            do {
                report.accepted[share.id] = try await client.share(share)
                outbox.remove(share.id)
            } catch  where Self.waits(error) {
                report.waiting = error
                return report
            } catch {
                report.refused[share.id] = error
                outbox.remove(share.id)
            }
        }
        return report
    }

    /// Whether a failure is worth waiting out: a lost connection, a busy server, a token it
    /// stopped taking, which Ari asks about when it opens, or a server too old for the share inbox,
    /// until it's updated.
    private static func waits(_ error: RequestError) -> Bool {
        error.isTemporary || error.status == 401 || error.status == 404
    }
}

/// Kumo's reply to a share, as the share sheet shows it: the thread it went to, by name once the
/// server has one, and the reply's first paragraph once Kumo has finished writing it.
public struct ShareReply: Sendable, Equatable {
    public let thread: ThreadID
    /// The thread's name; `nil` for a new thread Kumo hasn't named yet.
    public let title: String?
    /// The reply's first paragraph, in Markdown as Kumo wrote it; `nil` until it's written.
    public let text: String?

    public init(thread: ThreadID, title: String?, text: String?) {
        self.thread = thread
        self.title = title
        self.text = text
    }

    /// Follows a share the server has accepted until Kumo has answered it, for as long as the sheet
    /// stays open: where the share stands (asking with the same share, which changes nothing),
    /// then its thread. Returns what's known by the last look: the reply, the thread alone, or
    /// `nil` while Kumo is still sorting it. A slower reply comes as its notification. `seen` hears
    /// each step on the way, such as the thread it went to.
    public static func follow(
        _ share: SendShare, accepted: ShareStatus, with client: ItoClient, looks: Int = 8,
        every interval: Duration = .seconds(1),
        sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        seen: (ShareReply) async -> Void = { _ in }
    ) async -> ShareReply? {
        var thread = accepted.state == .placed ? accepted.thread : nil
        var known: ShareReply?
        for _ in 0..<looks {
            do {
                try await sleep(interval)
            } catch {
                return known
            }
            if thread == nil {
                guard let status = try? await client.share(share) else { continue }
                if status.state == .placed { thread = status.thread }
            }
            guard let thread, let page = try? await client.thread(thread) else { continue }
            let reply = ShareReply(
                thread: thread, title: page.thread.title,
                text: Self.reply(in: page.messages, to: share.id))
            if reply.text != nil { return reply }
            if reply != known { await seen(reply) }
            known = reply
        }
        return known
    }

    /// The first paragraph of Kumo's finished reply after the share, skipping a block the app
    /// draws, such as a table.
    static func reply(in messages: [Message], to share: MessageID) -> String? {
        guard let index = messages.firstIndex(where: { $0.id == share }) else { return nil }
        let answer = messages[(index + 1)...].first {
            $0.role == .agent && $0.kind == .reply && $0.outcome == .completed
        }
        guard let answer else { return nil }
        return answer.text.components(separatedBy: "\n\n").lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("```") }
    }
}

/// A link that opens Ito at a side thread, `ito://thread/<id>`: the share sheet's Open the thread.
public enum ThreadLink {
    public static func url(for thread: ThreadID) -> URL? {
        var components = URLComponents()
        components.scheme = "ito"
        components.host = "thread"
        components.path = "/" + thread.rawValue
        return components.url
    }

    /// The thread a link opens, or `nil` for any other link.
    public static func thread(from link: URL) -> ThreadID? {
        guard link.scheme == "ito", link.host() == "thread" else { return nil }
        let id = link.path(percentEncoded: false).trimmingCharacters(in: ["/"])
        return id.isEmpty ? nil : ThreadID(id)
    }
}
