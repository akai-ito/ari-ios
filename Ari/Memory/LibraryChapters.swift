import AriKit
import SwiftUI
import Vision

/// The chapters of your life Kumo noticed, as a row under Now: each its photo, a name and when,
/// those still going first with a dotted ring. "All" opens every chapter.
struct ChaptersRow: View {
    let memory: Memory

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Chapters").font(.ariHeading).foregroundStyle(.ariText)
                Spacer()
                if memory.chapters.count > 1 {
                    NavigationLink(value: ChaptersRoute()) {
                        Text("All \(memory.chapters.count)")
                            .font(.footnote)
                            .foregroundStyle(.ariSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            if memory.chapters.isEmpty {
                Text(
                    "As your weeks take shape, \(LeadName.current) names them here: a trip, a job hunt, a new routine."
                )
                .font(.footnote)
                .foregroundStyle(.ariTertiary)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(memory.chapters) { chapter in
                            NavigationLink(value: chapter.address) {
                                ChapterCard(chapter: chapter, memory: memory)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
        }
    }
}

/// Every chapter, as a navigation value.
struct ChaptersRoute: Hashable {}

/// A chapter in the row: its cover, its name and when.
private struct ChapterCard: View {
    let chapter: Chapter
    let memory: Memory

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ChapterCover(photo: chapter.cover, memory: memory)
                .frame(width: 220, height: 104)
                .clipped()
            VStack(alignment: .leading, spacing: 4) {
                Text(chapter.title)
                    .font(.ariName)
                    .foregroundStyle(.ariText)
                    .lineLimit(1)
                ChapterWhen(chapter: chapter)
            }
            .padding(12)
        }
        .frame(width: 220, alignment: .leading)
        .background(.ariSurface)
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .contentShape(.rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

/// When a chapter was, with a dotted ring while it's still going.
struct ChapterWhen: View {
    let chapter: Chapter

    var body: some View {
        HStack(spacing: 5) {
            if chapter.isGoing { GoingRing() }
            Text(ChapterReading.when(began: chapter.began, ended: chapter.ended))
                .font(.caption)
                .foregroundStyle(.ariTertiary)
                .lineLimit(1)
        }
    }
}

/// A small dotted ring in bone: something still going.
struct GoingRing: View {
    var body: some View {
        Circle()
            .strokeBorder(Color.ariBone, style: StrokeStyle(lineWidth: 1.3, dash: [1.4, 1.5]))
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }
}

/// A chapter's cover: its photo as it is, in full colour, filling the frame and cropped around
/// what the eye goes to, so the subject stays at a card's size. A quiet dusk until the photo is
/// here, or for a chapter without one.
struct ChapterCover: View {
    let photo: MemoryPhoto?
    let memory: Memory?
    /// The longest side to decode, in pixels: enough to fill the frame at the screen's scale.
    var longest = 900

    @State private var cover: Cover?

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.ariSurface, .ariDusk.opacity(0.3)], startPoint: .top,
                    endPoint: .bottom)
            )
            .overlay {
                if let cover {
                    FocusedPhoto(image: cover.image, focus: cover.focus).transition(.opacity)
                }
            }
            .clipped()
            .task(id: photo?.name) {
                guard let photo, let memory, let data = await memory.photo(photo) else { return }
                let loaded = await Self.cover(from: data, longest: longest)
                withAnimation(.easeOut(duration: 0.25)) { cover = loaded }
            }
            .accessibilityHidden(true)
    }

    nonisolated private struct Cover: Sendable {
        let image: CGImage
        let focus: UnitPoint
    }

    @concurrent private nonisolated static func cover(from data: Data, longest: Int) async
        -> Cover?
    {
        guard let image = AttachmentMaker.image(from: data, longest: longest) else { return nil }
        return Cover(image: image, focus: focus(of: image))
    }

    /// Where the eye goes in a photo: the middle of what Vision finds salient. When it finds
    /// nothing, the middle, a little high on a tall photo, where a subject usually stands.
    private nonisolated static func focus(of image: CGImage) -> UnitPoint {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil,
            let objects = request.results?.first?.salientObjects, !objects.isEmpty
        else {
            return UnitPoint(x: 0.5, y: image.height > image.width ? 0.4 : 0.5)
        }
        let box = objects.map(\.boundingBox).reduce(CGRect.null) { $0.union($1) }
        // Vision measures from the bottom left.
        return UnitPoint(x: box.midX, y: 1 - box.midY)
    }
}

/// A photo filling its frame, cropped to keep its focus as near the middle as the photo allows.
private struct FocusedPhoto: View {
    let image: CGImage
    let focus: UnitPoint

    var body: some View {
        GeometryReader { frame in
            let size = frame.size
            let scale = max(
                size.width / CGFloat(max(image.width, 1)),
                size.height / CGFloat(max(image.height, 1)))
            let drawn = CGSize(
                width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            Image(decorative: image, scale: 1)
                .resizable()
                .frame(width: drawn.width, height: drawn.height)
                .offset(
                    x: -Self.shift(
                        focus.x * drawn.width - size.width / 2, room: drawn.width - size.width),
                    y: -Self.shift(
                        focus.y * drawn.height - size.height / 2, room: drawn.height - size.height))
        }
        .clipped()
    }

    /// How far to move the photo to centre its focus, without showing past its edge.
    private static func shift(_ wanted: CGFloat, room: CGFloat) -> CGFloat {
        min(max(wanted, 0), max(room, 0))
    }
}

/// Every chapter Kumo noticed, those still going first, then the latest to end.
struct ChapterListView: View {
    let memory: Memory?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(memory?.chapters ?? []) { chapter in
                    NavigationLink(value: chapter.address) {
                        HStack(spacing: 14) {
                            ChapterCover(photo: chapter.cover, memory: memory, longest: 400)
                                .frame(width: 64, height: 64)
                                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(chapter.title)
                                    .font(.ariName)
                                    .foregroundStyle(.ariText)
                                    .multilineTextAlignment(.leading)
                                ChapterWhen(chapter: chapter)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(.ariSurface, in: .rect(cornerRadius: 16, style: .continuous))
                        .contentShape(.rect(cornerRadius: 16))
                        .accessibilityElement(children: .combine)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: Rhythm.column, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(.ariBackground)
        .navigationTitle("Chapters")
    }
}
