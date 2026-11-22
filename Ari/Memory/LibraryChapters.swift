import AriKit
import SwiftUI

/// The chapters of your life Kumo noticed, as a row under Now: each a photo in Ari's halftone, a
/// name and when, those still going first with a dotted ring. "All" opens every chapter.
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
            ChapterCover(photo: chapter.cover, memory: memory, step: 4.5)
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

/// A chapter's cover in halftone, once its photo is here; a quiet dusk of dots until then, or for a
/// chapter without a photo.
struct ChapterCover: View {
    let photo: MemoryPhoto?
    let memory: Memory?
    var step: CGFloat = 5

    @State private var image: CGImage?

    var body: some View {
        HalftoneImage(image: image, step: step)
            .task(id: photo?.name) {
                guard let photo, let memory, let data = await memory.photo(photo) else { return }
                image = await Self.decode(data)
            }
    }

    @concurrent private nonisolated static func decode(_ data: Data) async -> CGImage? {
        AttachmentMaker.image(from: data, longest: 600)
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
                            ChapterCover(photo: chapter.cover, memory: memory, step: 3.5)
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
