import AriKit
import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// Small pictures of attachments, kept while Ari runs so scrolling back doesn't decode them again.
enum Thumbnails {
    private static let cache = NSCache<NSString, CGImage>()

    /// The picture at most `longest` pixels on its longer side: a cover filling the screen needs
    /// more than a thumbnail.
    static func image(
        for attachment: AttachmentID, longest: Int = 720, from bytes: () async -> Data?
    ) async -> CGImage? {
        let key = "\(attachment.rawValue)@\(longest)" as NSString
        if let kept = cache.object(forKey: key) { return kept }
        guard let data = await bytes() else { return nil }
        let image = await decode(data, longest: longest)
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    @concurrent private nonisolated static func decode(_ data: Data, longest: Int) async
        -> CGImage?
    {
        AttachmentMaker.image(from: data, longest: longest)
    }
}

/// The + beside the composer: photos from your library, a recording, or any file. Anything bigger
/// than one request takes goes up in chunks in the background, checked against the server's limits
/// before anything is sent.
struct AttachButton: View {
    /// How many more the message can carry.
    let room: Int
    let add: (PendingAttachment) -> Void
    let problem: (String) -> Void

    @State private var choosingPhotos = false
    @State private var choosingFiles = false
    @State private var choosingRecording = false
    @State private var picked: [PhotosPickerItem] = []
    @Environment(\.filesActions) private var files
    @Environment(BigUploads.self) private var uploads: BigUploads?

    var body: some View {
        Menu {
            Button("Photos", systemImage: "photo.on.rectangle") { choosingPhotos = true }
            Button("Recording", systemImage: "waveform") { choosingRecording = true }
            Button("Files", systemImage: "folder") { choosingFiles = true }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(room > 0 ? .ariSecondary : .ariTertiary)
                .frame(width: 36, height: 44)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .disabled(room == 0)
        .accessibilityLabel("Attach")
        .photosPicker(
            isPresented: $choosingPhotos, selection: $picked, maxSelectionCount: max(room, 1),
            matching: .images, preferredItemEncoding: .current
        )
        .fileImporter(
            isPresented: $choosingFiles, allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            Task {
                for url in urls.prefix(room) { await attach(url) }
            }
        }
        .background {
            // A second importer on its own view: two on one view don't both present.
            Color.clear.fileImporter(
                isPresented: $choosingRecording, allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                Task { await attach(url) }
            }
        }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            Task {
                for (index, item) in items.enumerated() {
                    let name = index == 0 ? "photo.jpg" : "photo-\(index + 1).jpg"
                    guard let data = try? await item.loadTransferable(type: Data.self),
                        let photo = await AttachmentMaker.photo(data, name: name)
                    else {
                        problem("Couldn't read that photo.")
                        continue
                    }
                    add(photo)
                }
            }
        }
    }

    /// A picked file: in one go when it's small, else in chunks, started at once and held in the
    /// composer like any other attachment.
    private func attach(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let session = files.session
        let limits = try? await session?.uploadLimits(refresh: true).limits
        guard BigAttachment.isBig(size: size, limits: limits) else {
            do {
                add(try await AttachmentMaker.file(at: url))
            } catch {
                problem("Couldn't read \(url.lastPathComponent).")
            }
            return
        }
        guard let limits, let uploads else {
            problem("Your server can't be reached to ask how big a file it takes. Try again soon.")
            return
        }
        switch await BigAttachment.upload(for: url, limits: limits) {
        case .failure(let refusal):
            problem(refusal.words)
        case .success(let upload):
            do {
                try uploads.prepare(upload, file: url)
            } catch {
                problem("Couldn't keep \(upload.name) on the phone to send: there may not be room.")
                return
            }
            add(
                PendingAttachment(
                    id: upload.id, name: upload.name, mediaType: upload.mediaType, bytes: Data()))
            Task { await uploads.begin(upload.id) }
        }
    }
}

/// What you've attached to the message you're writing, above the field: each uploads at once,
/// dimmed until the server has it, and can be taken off.
struct AttachedStrip: View {
    let attached: [PendingAttachment]
    let uploads: [AttachmentID: Session.Upload]
    let remove: (AttachmentID) -> Void

    @Environment(BigUploads.self) private var bigUploads: BigUploads?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(attached) { attachment in
                        item(attachment)
                    }
                }
                .padding(.top, 6)
                .padding(.trailing, 6)
            }
            .scrollIndicators(.hidden)
            ForEach(refusals, id: \.self) { refusal in
                Text(refusal)
                    .font(.footnote)
                    .foregroundStyle(.ariSecondary)
            }
        }
    }

    private func item(_ attachment: PendingAttachment) -> some View {
        let upload = uploads[attachment.id]
        return Group {
            if let big = bigUploads?.uploads[attachment.id] {
                BigChip(upload: big, sent: bigUploads?.sent(big.id) ?? big.received)
            } else if attachment.attachment.kind == .image {
                AttachmentImage(attachment: attachment.attachment, bytes: { attachment.bytes })
                    .frame(width: 60, height: 60)
                    .clipShape(.rect(cornerRadius: 12, style: .continuous))
            } else {
                FileChip(attachment: attachment.attachment, compact: true)
            }
        }
        .opacity(upload == .uploading ? 0.55 : 1)
        .overlay {
            if case .refused = upload {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.ariSecondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                remove(attachment.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.ariText)
                    .frame(width: 20, height: 20)
                    .background(.ariSurface, in: Circle())
                    .overlay(Circle().strokeBorder(.ariLine, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
            .accessibilityLabel("Remove \(attachment.name)")
        }
        .animation(.easeInOut(duration: 0.3), value: upload)
    }

    /// Why an attachment can't go, in the server's words.
    private var refusals: [String] {
        attached.compactMap { attachment in
            guard case .refused(let error) = uploads[attachment.id] else { return nil }
            let words = [error.serverError?.message, error.serverError?.detail].compactMap(\.self)
            return "\(attachment.name): "
                + (words.isEmpty ? "the server didn't take it." : words.joined(separator: " "))
        }
    }
}

/// The photos, recordings and files on one of your messages. Tap one to look at it in full: photos
/// sent together open together, to swipe through.
struct MessageAttachments: View {
    let attachments: [Attachment]
    /// Whether audio shows as a recording you sent, with its transcript, rather than a file.
    var recordings = true
    let bytes: (AttachmentID) async -> Data?

    @State private var looking: URL?
    @State private var batch: [URL] = []

    var body: some View {
        let images = attachments.filter { $0.kind == .image }
        let audio = recordings ? attachments.filter { $0.kind == .audio } : []
        // A kind Ari doesn't know yet shows as a file.
        let files = attachments.filter { $0.kind != .image && !audio.contains($0) }
        VStack(alignment: .trailing, spacing: 6) {
            if images.count == 1, let image = images.first {
                photo(image, in: images) {
                    AttachmentImage(attachment: image, bytes: { await bytes(image.id) })
                        .aspectRatio(Self.aspect(of: image), contentMode: .fit)
                        .frame(maxWidth: 240, maxHeight: 320)
                        .clipShape(.rect(cornerRadius: 18, style: .continuous))
                }
            } else if !images.isEmpty {
                PhotoBatch(images: images) { image, size in
                    photo(image, in: images) {
                        AttachmentImage(attachment: image, bytes: { await bytes(image.id) })
                            .frame(width: size.width, height: size.height)
                            .clipShape(.rect(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            ForEach(audio) { recording in
                RecordingCard(attachment: recording)
            }
            ForEach(files) { file in
                button(for: file) { FileChip(attachment: file, compact: false) }
            }
        }
        .quickLookPreview($looking, in: batch)
    }

    private func button(for attachment: Attachment, @ViewBuilder label: () -> some View)
        -> some View
    {
        Button {
            Task {
                guard let url = await file(for: attachment) else { return }
                batch = [url]
                looking = url
            }
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(attachment.name)
    }

    /// A photo that opens with the others sent with it.
    private func photo(
        _ image: Attachment, in images: [Attachment], @ViewBuilder label: () -> some View
    ) -> some View {
        Button {
            Task {
                var urls: [URL] = []
                for each in images {
                    if let url = await file(for: each) { urls.append(url) }
                }
                batch = urls
                looking = await file(for: image)
            }
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(image.name)
    }

    /// A copy under the attachment's own name, for Quick Look to open.
    private func file(for attachment: Attachment) async -> URL? {
        let folder = URL.temporaryDirectory.appending(path: "Attachments/\(attachment.id)")
        let url = folder.appending(path: attachment.name.replacingOccurrences(of: "/", with: "-"))
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) { return url }
        guard let data = await bytes(attachment.id) else { return nil }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (try? data.write(to: url, options: .atomic)) == nil ? nil : url
    }

    private static func aspect(of image: Attachment) -> CGFloat {
        guard let width = image.width, let height = image.height, width > 0, height > 0 else {
            return 4 / 3
        }
        return CGFloat(width) / CGFloat(height)
    }
}

/// Several photos sent together, read together: two side by side, three as one wide above two,
/// four in a square, and more as a square whose last tile says how many others there are.
private struct PhotoBatch<Tile: View>: View {
    let images: [Attachment]
    @ViewBuilder let tile: (Attachment, CGSize) -> Tile

    private let width: CGFloat = 240
    private let gap: CGFloat = 4

    var body: some View {
        let half = (width - gap) / 2
        VStack(alignment: .trailing, spacing: gap) {
            switch images.count {
            case 2:
                HStack(spacing: gap) {
                    ForEach(images) { tile($0, CGSize(width: half, height: half * 1.3)) }
                }
            case 3:
                tile(images[0], CGSize(width: width, height: half * 1.15))
                HStack(spacing: gap) {
                    ForEach(images[1...]) { tile($0, CGSize(width: half, height: half)) }
                }
            default:
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(images[row * 2..<min(row * 2 + 2, 4)]) { image in
                            tile(image, CGSize(width: half, height: half))
                                .overlay {
                                    if image == images[3], images.count > 4 {
                                        more(images.count - 4)
                                    }
                                }
                        }
                    }
                }
            }
        }
        .frame(width: width, alignment: .trailing)
    }

    private func more(_ count: Int) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.ariBackground.opacity(0.55))
            .overlay {
                Text("+\(count)").font(.title3.weight(.semibold)).foregroundStyle(.ariText)
            }
            .allowsHitTesting(false)
            .accessibilityLabel("\(count) more")
    }
}

/// A photo, once its bytes are here; a quiet tile until then.
struct AttachmentImage: View {
    let attachment: Attachment
    let bytes: () async -> Data?

    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.ariSurface)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .task(id: attachment.id) {
            let loaded = await Thumbnails.image(for: attachment.id, from: bytes)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}

/// A big file going up while you write: its name, and how much of it the server has.
private struct BigChip: View {
    let upload: BigUpload
    let sent: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: upload.mediaType.hasPrefix("audio/") ? "waveform" : "doc")
                .font(.system(size: 15))
                .foregroundStyle(.ariSecondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(upload.name)
                    .font(.footnote)
                    .foregroundStyle(.ariText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if upload.isSending {
                    ProgressView(value: Double(sent), total: Double(max(1, upload.size)))
                        .tint(.ariBone)
                        .frame(width: 90)
                }
                Text(
                    upload.isSending
                        ? "\(UploadLimits.sizeWords(sent)) of \(UploadLimits.sizeWords(upload.size))"
                        : UploadLimits.sizeWords(upload.size)
                )
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.ariTertiary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 60)
        .frame(maxWidth: 200, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.ariLine, lineWidth: 1))
    }
}

/// A file: its name and size, in a thin outline.
struct FileChip: View {
    let attachment: Attachment
    let compact: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc")
                .font(.system(size: compact ? 15 : 17))
                .foregroundStyle(.ariSecondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.name)
                    .font(compact ? .footnote : .subheadline)
                    .foregroundStyle(.ariText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(attachment.size.formatted(.byteCount(style: .file)))
                    .font(.caption)
                    .foregroundStyle(.ariTertiary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: compact ? 60 : 52)
        .frame(maxWidth: compact ? 180 : 240, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 12 : 16, style: .continuous)
                .strokeBorder(.ariLine, lineWidth: 1))
    }
}
