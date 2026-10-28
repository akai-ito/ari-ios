import AriKit
import SwiftUI

/// The Library's front page, as Ari's notebook: what's going on now, in a few lines you can read at
/// a glance, the other pages always in mind, what Ari learnt lately, then the shelves, each with a
/// peek at what's on it.
struct LibraryHome: View {
    let memory: Memory

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                switch memory.load {
                case .failed(let error):
                    Text("Couldn't reach your server: \(error.plainWords)")
                        .foregroundStyle(.ariSecondary)
                case .loading:
                    ProgressView().frame(maxWidth: .infinity)
                case .loaded where memory.inMind.isEmpty && memory.shelves.isEmpty:
                    Text(
                        "Nothing yet. As you talk, Ari keeps what matters here, and you can see all of it."
                    )
                    .font(.ariBody)
                    .foregroundStyle(.ariTertiary)
                case .loaded:
                    inMind
                    lately
                    if !memory.shelves.isEmpty { shelves }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: Rhythm.column, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task { await memory.refresh() }
        .refreshable { await memory.refresh() }
    }

    @ViewBuilder
    private var inMind: some View {
        let now = memory.inMind.first { $0.shelf == "now" }
        let others = memory.inMind.filter { $0.shelf != "now" }
        VStack(alignment: .leading, spacing: 12) {
            if let now { NowCard(page: now) }
            if !others.isEmpty {
                WrappingStack(spacing: 8) {
                    Text(now == nil ? "In mind" : "Also in mind")
                        .font(.footnote)
                        .foregroundStyle(.ariTertiary)
                        .padding(.vertical, 6)
                    ForEach(others) { page in
                        NavigationLink(value: page.address) { PageChip(title: page.title) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// What Ari learnt lately, in its own notes: the newest note for each page, a few pages. Only
    /// changes with a note: a page's name alone says nothing about what changed.
    @ViewBuilder
    private var lately: some View {
        let changes = Self.latestNotes(memory.recent)
        if !changes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Lately, Ari learnt").font(.ariHeading).foregroundStyle(.ariText)
                VStack(spacing: 0) {
                    ForEach(changes) { change in
                        NavigationLink(value: change.address) {
                            Text(
                                "\(Text(change.title).fontWeight(.semibold).foregroundStyle(.ariText))  \(change.note ?? "")"
                            )
                            .font(.subheadline)
                            .foregroundStyle(.ariSecondary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if change.id != changes.last?.id {
                            Divider().overlay(Color.ariLine)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .background(.ariSurface, in: .rect(cornerRadius: 16, style: .continuous))
            }
        }
    }

    static func latestNotes(_ changes: [RecentChange]) -> [RecentChange] {
        var seen: Set<PageAddress> = []
        return changes.filter { change in
            guard change.note != nil, !seen.contains(change.address) else { return false }
            seen.insert(change.address)
            return true
        }
        .prefix(4)
        .map { $0 }
    }

    private var shelves: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shelves").font(.ariHeading).foregroundStyle(.ariText)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(Self.ordered(memory.shelves)) { shelf in
                    ShelfTile(shelf: shelf, peek: peek(shelf.shelf))
                }
            }
        }
    }

    /// A glimpse of what's on a shelf: its latest day, or who and what Ari touched lately, else
    /// the first few.
    private func peek(_ shelf: String) -> String? {
        guard let pages = memory.shelfPages[shelf], !pages.isEmpty else { return nil }
        if shelf == "journal" {
            guard let month = ShelfReading.months(pages).first, let day = month.days.first else {
                return nil
            }
            let date = DateComponents(
                calendar: Calendar(identifier: .gregorian), timeZone: .gmt, year: month.year,
                month: month.month, day: day.day
            ).date
            return date.map {
                "Latest: "
                    + $0.formatted(Date.FormatStyle(timeZone: .gmt).day().month(.abbreviated))
            }
        }
        let lately = ShelfReading.lately(pages)
        let names = (lately.isEmpty ? ShelfReading.everyone(pages) : lately).prefix(3).map(\.title)
        return names.joined(separator: ", ") + (pages.count > names.count ? "…" : "")
    }

    /// The shelves you'll reach for most first.
    private static func ordered(_ shelves: [Shelf]) -> [Shelf] {
        let order = ["people", "projects", "journal", "goals", "topics", "places"]
        return shelves.sorted {
            (order.firstIndex(of: $0.shelf) ?? order.count)
                < (order.firstIndex(of: $1.shelf) ?? order.count)
        }
    }

    static func title(ofShelf shelf: String) -> String {
        shelf.prefix(1).uppercased() + shelf.dropFirst()
    }

    static func ago(_ time: Timestamp) -> String {
        time.date.formatted(.relative(presentation: .named))
    }
}

/// Now, in its first lines: what's going on these days, at a glance. Opens the whole page.
private struct NowCard: View {
    let page: MemoryPage

    var body: some View {
        NavigationLink(value: page.address) {
            VStack(alignment: .leading, spacing: 10) {
                Text("NOW")
                    .font(.caption.weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(.ariTertiary)
                Text(Self.excerpt(page))
                    .font(.ariBody)
                    .foregroundStyle(.ariText)
                    .lineSpacing(Rhythm.ariLineSpacing)
                    .lineLimit(5)
                    .multilineTextAlignment(.leading)
                Text("Read it all")
                    .font(.footnote)
                    .foregroundStyle(.ariSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ariSurface, in: .rect(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// The first paragraph, as plain words, without its freshness stamp.
    private static func excerpt(_ page: MemoryPage) -> String {
        let document = ReplyDocument(markdown: page.markdown).quietingStamps()
        let first = document.blocks.first { $0.kind == .paragraph }
        return first?.runs.filter { !$0.style.contains(.stamp) }.map(\.text).joined() ?? ""
    }
}

/// A shelf on the front page: its name, how many pages, and a peek inside.
private struct ShelfTile: View {
    let shelf: Shelf
    let peek: String?

    var body: some View {
        NavigationLink(value: ShelfRoute(shelf: shelf.shelf)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(LibraryHome.title(ofShelf: shelf.shelf))
                        .font(.headline)
                        .foregroundStyle(.ariText)
                    Spacer(minLength: 4)
                    Text("\(shelf.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.ariTertiary)
                }
                Text(peek ?? "")
                    .font(.footnote)
                    .foregroundStyle(.ariSecondary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ariSurface, in: .rect(cornerRadius: 16, style: .continuous))
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
