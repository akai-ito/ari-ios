import AriKit
import QuickLook
import SwiftUI

/// A page's words with the photos it keeps standing where the story shows them. Tap a photo to
/// see it full screen.
struct PageStory: View {
    let page: MemoryPage
    let memory: Memory?

    @State private var looking: URL?

    var body: some View {
        let pieces = ReplyDocument.pieces(of: page, reading: PageLink.reading(page))
        VStack(alignment: .leading, spacing: Rhythm.ariParagraphGap) {
            ForEach(pieces.indices, id: \.self) { index in
                switch pieces[index] {
                case .words(let document):
                    ReplyView(document: document, position: .infinity)
                case .photos(let photos):
                    PagePhotoGroup(photos: photos, memory: memory) { looking = $0 }
                }
            }
        }
        .quickLookPreview($looking)
    }
}

/// Photos side by side in the story: one fills the column at its own shape; more sit two to a row.
private struct PagePhotoGroup: View {
    let photos: [PagePhoto]
    let memory: Memory?
    let open: (URL) -> Void

    var body: some View {
        if photos.count == 1, let photo = photos.first {
            tile(photo)
                .aspectRatio(Self.aspect(of: photo.photo), contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 520)
        } else {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                spacing: 6
            ) {
                ForEach(photos) { photo in
                    tile(photo).aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }

    private func tile(_ photo: PagePhoto) -> some View {
        Button {
            Task {
                if let url = await file(for: photo.photo) { open(url) }
            }
        } label: {
            PagePhotoImage(photo: photo, memory: memory)
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
                .contentShape(.rect(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(photo.alt.isEmpty ? "Photo" : photo.alt)
        .accessibilityHint("Opens it full screen")
    }

    /// The photo as a file, for Quick Look: its name never changes what's in it, so a copy
    /// already there is the same photo.
    private func file(for photo: MemoryPhoto) async -> URL? {
        let folder = URL.temporaryDirectory.appending(path: "Memory")
        let url = folder.appending(path: photo.name)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) { return url }
        guard let data = await memory?.photo(photo) else { return nil }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (try? data.write(to: url, options: .atomic)) == nil ? nil : url
    }

    private static func aspect(of photo: MemoryPhoto) -> CGFloat {
        guard let width = photo.width, let height = photo.height, width > 0, height > 0 else {
            return 4 / 3
        }
        return CGFloat(width) / CGFloat(height)
    }
}

/// A photo, once its bytes are here; a quiet tile until then, and its words if it won't come.
private struct PagePhotoImage: View {
    let photo: PagePhoto
    let memory: Memory?

    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Rectangle().fill(.ariSurface)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else if failed {
                Text(photo.alt)
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
                    .multilineTextAlignment(.center)
                    .padding(12)
            }
        }
        .task(id: photo.photo.name) {
            guard let memory else { return }
            let loaded = await PagePhotoImages.image(for: photo.photo) { await memory.photo($0) }
            withAnimation(.easeOut(duration: 0.2)) {
                image = loaded
                failed = loaded == nil
            }
        }
    }
}

/// Memory's photos, decoded at most screen size and kept while Ari runs, so scrolling back through
/// the journal doesn't decode them again.
private enum PagePhotoImages {
    private static let cache = NSCache<NSString, CGImage>()
    private nonisolated static let longest = 1600

    static func image(
        for photo: MemoryPhoto, bytes: (MemoryPhoto) async -> Data?
    ) async -> CGImage? {
        let key = photo.name as NSString
        if let kept = cache.object(forKey: key) { return kept }
        guard let data = await bytes(photo) else { return nil }
        let image = await decode(data)
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    @concurrent private nonisolated static func decode(_ data: Data) async -> CGImage? {
        AttachmentMaker.image(from: data, longest: longest)
    }
}
