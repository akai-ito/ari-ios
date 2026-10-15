import AriKit
import ImageIO
import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// Turns what you picked into attachments. Photos are scaled to about 2048 pixels on the long edge,
/// as JPEG, roughly what the model looks at, and lose their location and other metadata on the
/// way. Files go as they are, except images the model can't read, such as HEIC, which become JPEG.
enum AttachmentMaker {
    /// The most a message carries.
    static let mostPerMessage = 10
    /// Anything larger isn't read at all; the server refuses a little less than this.
    nonisolated static let largest = 20 * 1024 * 1024

    struct TooLarge: Error {
        let name: String
    }

    @concurrent nonisolated static func photo(_ data: Data, name: String) async
        -> PendingAttachment?
    {
        guard let jpeg = jpeg(from: data, longest: 2048) else { return nil }
        return PendingAttachment(name: name, mediaType: "image/jpeg", bytes: jpeg)
    }

    @concurrent nonisolated static func file(at url: URL) async throws -> PendingAttachment {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= largest else { throw TooLarge(name: name) }
        let data = try Data(contentsOf: url)
        let type = UTType(filenameExtension: url.pathExtension)
        if let type, type.conforms(to: .image), !seen.contains(where: type.conforms(to:)),
            let jpeg = jpeg(from: data, longest: 2048)
        {
            let stem = url.deletingPathExtension().lastPathComponent
            return PendingAttachment(name: stem + ".jpg", mediaType: "image/jpeg", bytes: jpeg)
        }
        return PendingAttachment(
            name: name, mediaType: type?.preferredMIMEType ?? "application/octet-stream",
            bytes: data)
    }

    /// The images the agent sees as they are.
    private nonisolated static let seen: [UTType] = [.jpeg, .png, .gif, .webP]

    nonisolated static func jpeg(from data: Data, longest: Int) -> Data? {
        guard let image = image(from: data, longest: longest) else { return nil }
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    /// The image, upright, at most `longest` pixels on its long edge.
    nonisolated static func image(from data: Data, longest: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longest,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Small pictures of attachments, kept while Ari runs so scrolling back doesn't decode them again.
enum Thumbnails {
    private static let cache = NSCache<NSString, CGImage>()

    static func image(for attachment: AttachmentID, from bytes: () async -> Data?) async
        -> CGImage?
    {
        if let kept = cache.object(forKey: attachment.rawValue as NSString) { return kept }
        guard let data = await bytes() else { return nil }
        let image = await decode(data)
        if let image { cache.setObject(image, forKey: attachment.rawValue as NSString) }
        return image
    }

    @concurrent private nonisolated static func decode(_ data: Data) async -> CGImage? {
        AttachmentMaker.image(from: data, longest: 720)
    }
}

/// The + beside the composer: photos from your library, or any file.
struct AttachButton: View {
    /// How many more the message can carry.
    let room: Int
    let add: (PendingAttachment) -> Void
    let problem: (String) -> Void

    @State private var choosingPhotos = false
    @State private var choosingFiles = false
    @State private var picked: [PhotosPickerItem] = []

    var body: some View {
        Menu {
            Button("Photos", systemImage: "photo.on.rectangle") { choosingPhotos = true }
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
                for url in urls.prefix(room) {
                    do {
                        add(try await AttachmentMaker.file(at: url))
                    } catch let error as AttachmentMaker.TooLarge {
                        problem("\(error.name) is larger than Ito accepts: up to 20 MB.")
                    } catch {
                        problem("Couldn't read \(url.lastPathComponent).")
                    }
                }
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
}

/// What you've attached to the message you're writing, above the field: each uploads at once,
/// dimmed until the server has it, and can be taken off.
struct AttachedStrip: View {
    let attached: [PendingAttachment]
    let uploads: [AttachmentID: Session.Upload]
    let remove: (AttachmentID) -> Void

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
            if attachment.attachment.kind == .image {
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

/// The photos and files on one of your messages. Tap one to look at it in full.
struct MessageAttachments: View {
    let attachments: [Attachment]
    let bytes: (AttachmentID) async -> Data?

    @State private var looking: URL?

    var body: some View {
        let images = attachments.filter { $0.kind == .image }
        // A kind Ari doesn't know yet shows as a file.
        let files = attachments.filter { $0.kind != .image }
        VStack(alignment: .trailing, spacing: 6) {
            if images.count == 1, let image = images.first {
                button(for: image) {
                    AttachmentImage(attachment: image, bytes: { await bytes(image.id) })
                        .aspectRatio(Self.aspect(of: image), contentMode: .fit)
                        .frame(maxWidth: 240, maxHeight: 320)
                        .clipShape(.rect(cornerRadius: 18, style: .continuous))
                }
            } else if !images.isEmpty {
                LazyVGrid(
                    columns: [
                        GridItem(.fixed(118), spacing: 4), GridItem(.fixed(118), spacing: 4),
                    ],
                    alignment: .trailing, spacing: 4
                ) {
                    ForEach(images) { image in
                        button(for: image) {
                            AttachmentImage(attachment: image, bytes: { await bytes(image.id) })
                                .frame(width: 118, height: 118)
                                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
                .frame(width: 240)
            }
            ForEach(files) { file in
                button(for: file) { FileChip(attachment: file, compact: false) }
            }
        }
        .quickLookPreview($looking)
    }

    private func button(for attachment: Attachment, @ViewBuilder label: () -> some View)
        -> some View
    {
        Button {
            Task { looking = await file(for: attachment) }
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(attachment.name)
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
