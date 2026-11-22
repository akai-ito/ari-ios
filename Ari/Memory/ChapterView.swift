import AriKit
import SwiftUI

/// A chapter, open: its cover photo, its name and when, the story in Kumo's hand with photos
/// where it shows them and what changed, the pages it links to, and where it came from.
struct ChapterView: View {
    let page: MemoryPage
    let facts: ChapterFacts
    let memory: Memory?

    /// Scrolled past the cover, when the bar takes the chapter's name.
    @State private var isPast = false
    /// A page opened from a name in the words.
    @State private var opened: PageAddress?

    private static let coverHeight: CGFloat = 300

    var body: some View {
        let cover = page.photos.first
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ChapterCover(photo: cover, memory: memory, longest: 1600)
                    .frame(height: Self.coverHeight)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(alignment: .bottom) {
                        LinearGradient(
                            colors: [.clear, .ariBackground], startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: 90)
                    }
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("CHAPTER")
                            .font(.caption.weight(.semibold))
                            .tracking(1.4)
                            .foregroundStyle(.ariTertiary)
                        Text(page.title)
                            .font(.ariTitle)
                            .foregroundStyle(.ariText)
                        HStack(spacing: 6) {
                            if facts.ended == nil { GoingRing() }
                            Text(ChapterReading.span(began: facts.began, ended: facts.ended))
                                .font(.subheadline)
                                .foregroundStyle(.ariSecondary)
                        }
                    }
                    PageStory(page: page, memory: memory, leavingOut: cover?.name)
                    let chips = ChapterReading.chips(page.links)
                    if !chips.isEmpty {
                        WrappingStack(spacing: 8) {
                            ForEach(chips) { chip in
                                NavigationLink(value: chip.address) { PageChip(title: chip.title) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    Text(
                        "\(ChapterReading.provenance(facts, lead: LeadName.current)) To change it, just say so."
                    )
                    .font(.caption)
                    .foregroundStyle(.ariTertiary)
                }
                .padding(.horizontal, 22)
                .padding(.top, -24)
                .padding(.bottom, 30)
                .frame(maxWidth: Rhythm.column, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .ignoresSafeArea(edges: .top)
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > Self.coverHeight - 60
        } action: { _, past in
            withAnimation(.easeOut(duration: 0.2)) { isPast = past }
        }
        .background(.ariBackground)
        .navigationTitle(isPast ? page.title : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.ariBackground, for: .navigationBar)
        .toolbarBackground(isPast ? .visible : .hidden, for: .navigationBar)
        .opensPageLinks { opened = $0 }
        .navigationDestination(item: $opened) { PageView(memory: memory, address: $0) }
    }
}
