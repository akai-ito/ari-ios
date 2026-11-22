import Foundation
import Observation
import os

/// Sends big files, such as a recorded conversation, in chunks that survive a dropped connection, a
/// closed app and a restart. It says what's coming (`POST /v0/uploads`), hands the chunks to a
/// carrier (iOS in the background, or this process), checks what the server has once they're done,
/// sends the rest or finishes, and then sends the message waiting for it.
///
/// The server is the truth for how much has arrived: after any doubt, the upload asks it and goes on
/// from there. Repeating a chunk, a finish or a message is always safe.
@MainActor
@Observable
public final class BigUploads {
    /// Every upload this phone has going or recently finished, by id.
    public private(set) var uploads: [AttachmentID: BigUpload] = [:]
    /// Bytes of a chunk on their way now, past what the server has confirmed, for a smooth bar.
    public private(set) var inChunk: [AttachmentID: Int] = [:]

    /// Told whenever an upload's record changes: the session follows finishing and refusals.
    @ObservationIgnored public var changed: ((BigUpload) -> Void)?

    @ObservationIgnored public let store: BigUploadStore
    @ObservationIgnored public let client: ItoClient
    @ObservationIgnored private let carrier: any ChunkCarrier
    /// Which carrier this is, kept on each upload it starts: `app` or `share`.
    @ObservationIgnored private let carrierName: String
    @ObservationIgnored private var busy: Set<AttachmentID> = []
    /// Rounds in a row that carried nothing further, so a stuck upload waits rather than spins.
    @ObservationIgnored private var stalls: [AttachmentID: Int] = [:]
    /// Where the last round of chunks started, to tell a round that got somewhere.
    @ObservationIgnored private var carriedFrom: [AttachmentID: Int] = [:]
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored private var watching: Task<Void, Never>?

    private static let log = Logger(subsystem: "io.github.akai-ito.ari", category: "uploads")

    public init(
        store: BigUploadStore, client: ItoClient, carrier: any ChunkCarrier, name: String = "app"
    ) {
        self.store = store
        self.client = client
        self.carrier = carrier
        carrierName = name
        for upload in store.all() { uploads[upload.id] = upload }
    }

    /// How much of an upload the server has, with the chunk going now: for its bar.
    public func sent(_ id: AttachmentID) -> Int {
        guard let upload = uploads[id] else { return 0 }
        return min(upload.size, upload.received + (inChunk[id] ?? 0))
    }

    // MARK: - What Ari asks

    /// Starts uploading `file` as `upload`: it's copied in first, so it survives the picker or the
    /// share sheet letting go of the original.
    public func start(_ upload: BigUpload, file: URL) async throws {
        try prepare(upload, file: file)
        await begin(upload.id)
    }

    /// Takes in the file and keeps the record, without sending anything yet, so the conversation
    /// knows the upload before its first chunk goes; ``begin(_:)`` then sends it.
    public func prepare(_ upload: BigUpload, file: URL) throws {
        var upload = upload
        upload.carriedBy = carrierName
        try store.take(upload, from: file)
        record(upload)
    }

    /// The message that waits for an upload, so whoever is awake when it finishes sends it.
    public func send(_ message: SendMessage, after id: AttachmentID) {
        guard var upload = uploads[id] else { return }
        upload.message = message
        record(upload)
        if case .finished = upload.state { Task { await deliver(id) } }
    }

    /// You took it off before sending, or gave up: what the server has goes too.
    public func cancel(_ id: AttachmentID) async {
        carrier.cancel(id)
        uploads[id] = nil
        inChunk[id] = nil
        store.remove(id)
        try? await client.cancelUpload(id)
    }

    /// Ari is in front again, or the network is back: every upload that isn't moving moves.
    /// Uploads the share extension handed to iOS are watched, and taken over if they stall.
    public func resume() async {
        store.sweep()
        reload()
        let flying = await carrier.inFlight()
        for upload in uploads.values.sorted(by: { $0.startedAt < $1.startedAt }) {
            switch upload.state {
            case .sending where flying.contains(upload.id):
                continue
            case .sending where upload.carriedBy != carrierName:
                watch()
            case .sending:
                stalls[upload.id] = nil
                carriedFrom[upload.id] = nil
                await begin(upload.id)
            case .finished:
                await deliver(upload.id)
            case .refused:
                continue
            }
        }
    }

    /// Takes in what the share extension wrote while Ari wasn't looking: new uploads, and further
    /// progress on ones it knows.
    private func reload() {
        for stored in store.all() {
            guard let known = uploads[stored.id] else {
                record(stored)
                continue
            }
            let moved = stored.received > known.received || !stored.isSending && known.isSending
            if moved || stored.messageSent && !known.messageSent { record(stored) }
        }
    }

    /// Ari left the screen: stop watching uploads someone else carries.
    public func pause() {
        watching?.cancel()
        watching = nil
    }

    // MARK: - What the carrier says

    /// A chunk is partway: `sent` of its bytes have gone.
    public func progressed(_ id: AttachmentID, offset: Int, sent: Int) {
        guard let upload = uploads[id] else { return }
        inChunk[id] = max(0, offset + sent - upload.received)
    }

    /// A chunk's answer.
    public func heard(_ id: AttachmentID, offset: Int, _ answer: Result<UploadStatus, RequestError>)
    {
        store.removeChunk(at: offset, of: id)
        guard var upload = uploads[id], upload.isSending else { return }
        inChunk[id] = nil
        switch answer {
        case .success(let status):
            upload.heard(status)
        case .failure(let error):
            // An offset mismatch only means a chunk arrived early; the settling sorts it out.
            if let refusal = Self.refusal(error) { upload.state = .refused(refusal) }
        }
        record(upload)
    }

    /// Nothing of the upload is in flight any more: finish it, or carry what's missing.
    public func settled(_ id: AttachmentID) async {
        guard let upload = uploads[id], upload.isSending, !busy.contains(id) else { return }
        busy.insert(id)
        defer { busy.remove(id) }
        if upload.received >= upload.size {
            await finish(id)
        } else {
            await check(id, carryingOn: true)
        }
    }

    // MARK: - The steps

    /// Says what's coming (or asks where it stands, which is the same call), then carries the rest.
    public func begin(_ id: AttachmentID) async {
        guard let upload = uploads[id], upload.isSending, !busy.contains(id) else { return }
        busy.insert(id)
        defer { busy.remove(id) }
        do {
            let status = try await client.createUpload(
                CreateUpload(
                    id: id, name: upload.name, mediaType: upload.mediaType, size: upload.size))
            hear(id, status)
        } catch {
            failed(id, error)
            return
        }
        await carryOn(id)
    }

    /// Asks the server what it has, and carries on from there.
    private func check(_ id: AttachmentID, carryingOn: Bool) async {
        do {
            hear(id, try await client.uploadStatus(id))
        } catch {
            if error.status == 404 {
                // The server swept it, unfinished for two days: start over.
                if var upload = uploads[id] {
                    upload.received = 0
                    record(upload)
                }
                busy.remove(id)
                await begin(id)
                return
            }
            failed(id, error)
            return
        }
        if carryingOn { await carryOn(id) }
    }

    private func carryOn(_ id: AttachmentID) async {
        guard let upload = uploads[id], upload.isSending else {
            await deliver(id)
            return
        }
        if upload.received >= upload.size {
            await finish(id)
            return
        }
        // A round that got nowhere counts; three in a row and it waits for Ari to come back.
        let rounds = upload.received > (carriedFrom[id] ?? -1) ? 0 : stalls[id, default: 0] + 1
        stalls[id] = rounds
        carriedFrom[id] = upload.received
        guard rounds < 3 else {
            Self.log.info("An upload stalled; it waits for Ari to come back")
            return
        }
        var carried = upload
        if carried.carriedBy != carrierName {
            carried.carriedBy = carrierName
            record(carried)
        }
        carrier.carry(carried.remainingChunks, of: carried, to: self)
    }

    private func finish(_ id: AttachmentID) async {
        do {
            let attachment = try await client.finishUpload(id)
            guard var upload = uploads[id] else { return }
            upload.received = upload.size
            upload.state = .finished(attachment)
            record(upload)
            store.tidy(id)
            stalls[id] = nil
        } catch {
            if case .refused(409, _, _) = error {
                // Not every byte arrived: ask what's there and send the rest.
                await check(id, carryingOn: true)
                return
            }
            if case .refused(422, _, _) = error, var upload = uploads[id] {
                // It arrived damaged and the server started over.
                upload.received = 0
                record(upload)
                await carryOn(id)
                return
            }
            failed(id, error)
            return
        }
        await deliver(id)
    }

    /// Sends the message that waited for the upload, once.
    private func deliver(_ id: AttachmentID) async {
        guard let upload = uploads[id], case .finished = upload.state,
            let message = upload.message, !upload.messageSent
        else { return }
        do {
            _ = try await client.send(message)
            mark(id, sent: true)
        } catch {
            if error.isTemporary {
                later()
            } else {
                // Ari's outbox says why, when it has the message too.
                Self.log.error("The server refused a message after its upload")
                mark(id, sent: true)
            }
        }
    }

    private func mark(_ id: AttachmentID, sent: Bool) {
        guard var upload = uploads[id] else { return }
        upload.messageSent = sent
        record(upload)
    }

    private func hear(_ id: AttachmentID, _ status: UploadStatus) {
        guard var upload = uploads[id] else { return }
        upload.heard(status)
        record(upload)
    }

    /// A step failed: a refusal ends the upload; anything else waits and tries again.
    private func failed(_ id: AttachmentID, _ error: RequestError) {
        if let refusal = Self.refusal(error), var upload = uploads[id] {
            upload.state = .refused(refusal)
            record(upload)
        } else {
            later()
        }
    }

    /// What the server refused for good, in its words; `nil` for anything worth trying again.
    static func refusal(_ error: RequestError) -> ServerError? {
        switch error {
        case .refused(409, _, _):
            // An offset mismatch or an unfinished upload: where it stands sorts it out.
            return nil
        case .refused(let status, let refusal, _) where status == 507 || !error.isTemporary:
            return refusal
                ?? ServerError(
                    code: ErrorCode(rawValue: "refused"),
                    message: "Your server didn't take it (\(status)).")
        case .protocolMismatch, .unreadable:
            return ServerError(
                code: ErrorCode(rawValue: "unreadable"),
                message: "Your server's answer didn't read.")
        default:
            return nil
        }
    }

    /// Tries everything again in a while, as long as Ari runs.
    private func later() {
        guard retry == nil else { return }
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !Task.isCancelled else { return }
            self.retry = nil
            await self.resume()
        }
    }

    /// Follows uploads iOS carries for the share extension from what the server has, and takes one
    /// over when it hasn't moved for half a minute, such as after the system dropped it.
    private func watch() {
        guard watching == nil else { return }
        watching = Task { [weak self] in
            var lastMoved: [AttachmentID: (received: Int, at: ContinuousClock.Instant)] = [:]
            while !Task.isCancelled {
                guard let self else { return }
                let others = self.uploads.values.filter {
                    $0.isSending && $0.carriedBy != self.carrierName
                }
                if others.isEmpty { break }
                for upload in others {
                    guard let status = try? await self.client.uploadStatus(upload.id) else {
                        continue
                    }
                    self.hear(upload.id, status)
                    let now = ContinuousClock.now
                    if let last = lastMoved[upload.id], last.received == status.received {
                        if now - last.at > .seconds(30), var taken = self.uploads[upload.id] {
                            taken.carriedBy = self.carrierName
                            self.record(taken)
                            await self.begin(upload.id)
                        }
                    } else {
                        lastMoved[upload.id] = (status.received, now)
                    }
                    if case .finished = self.uploads[upload.id]?.state {
                        await self.deliver(upload.id)
                    }
                }
                try? await Task.sleep(for: .seconds(4))
            }
            self?.watching = nil
        }
    }

    private func record(_ upload: BigUpload) {
        uploads[upload.id] = upload
        try? store.save(upload)
        changed?(upload)
    }
}

/// Carries an upload's chunks to the server and reports each answer to ``BigUploads``.
@MainActor
public protocol ChunkCarrier: AnyObject {
    /// Starts carrying these chunks, in order. Each answer goes to ``BigUploads/heard(_:offset:_:)``,
    /// and once none of the upload's is left in flight, ``BigUploads/settled(_:)`` follows.
    func carry(_ chunks: [BigUpload.Chunk], of upload: BigUpload, to uploads: BigUploads)
    func cancel(_ id: AttachmentID)
    /// The uploads with chunks in flight now.
    func inFlight() async -> Set<AttachmentID>
}

/// Carries chunks from this process, one after another, while it runs: for tests, and wherever a
/// background session isn't available.
@MainActor
public final class DirectChunkCarrier: ChunkCarrier {
    private var tasks: [AttachmentID: Task<Void, Never>] = [:]

    public init() {}

    public func carry(_ chunks: [BigUpload.Chunk], of upload: BigUpload, to uploads: BigUploads) {
        tasks[upload.id]?.cancel()
        let id = upload.id
        tasks[id] = Task {
            for chunk in chunks {
                guard !Task.isCancelled else { return }
                let bytes: Data
                do {
                    bytes = try uploads.store.read(chunk, of: id)
                } catch {
                    uploads.heard(id, offset: chunk.offset, .failure(.unreadable("\(error)")))
                    break
                }
                do throws(RequestError) {
                    let status = try await uploads.client.sendChunk(
                        id, offset: chunk.offset, bytes: bytes)
                    uploads.heard(id, offset: chunk.offset, .success(status))
                } catch {
                    uploads.heard(id, offset: chunk.offset, .failure(error))
                    break
                }
            }
            guard !Task.isCancelled else { return }
            tasks[id] = nil
            await uploads.settled(id)
        }
    }

    public func cancel(_ id: AttachmentID) {
        tasks[id]?.cancel()
        tasks[id] = nil
    }

    public func inFlight() async -> Set<AttachmentID> {
        Set(tasks.keys)
    }
}
