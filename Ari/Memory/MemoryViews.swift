import AriKit
import SwiftUI

/// The Library tab: Memory, what Ari knows about you. Recently changed first, then the three pages
/// always in mind, then the shelves. Read-only: to change anything, you tell Ari.
struct LibraryView: View {
    let memory: Memory?
    let openSettings: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if let memory {
                    MemoryList(memory: memory)
                } else {
                    Text("Connect to your server to see what Ari knows.")
                        .font(.ariBody)
                        .foregroundStyle(.ariTertiary)
                        .multilineTextAlignment(.center)
                        .padding(40)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(.ariBackground)
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Settings", systemImage: "gearshape", action: openSettings)
                }
            }
            .navigationDestination(for: PageAddress.self) { address in
                PageView(memory: memory, address: address)
            }
            .navigationDestination(for: ShelfRoute.self) { route in
                ShelfView(memory: memory, shelf: route.shelf)
            }
        }
    }
}

/// A shelf, as a navigation value.
struct ShelfRoute: Hashable {
    let shelf: String
}

private struct MemoryList: View {
    let memory: Memory

    var body: some View {
        Form {
            switch memory.load {
            case .failed(let error):
                Section {
                    Text("Couldn't reach your server: \(error.plainWords)")
                        .foregroundStyle(.ariSecondary)
                }
                .listRowBackground(Color.ariSurface)
            case .loading:
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            case .loaded where memory.inMind.isEmpty && memory.recent.isEmpty:
                Text(
                    "Nothing yet. As you talk, Ari keeps what matters here, and you can see all of it."
                )
                .font(.ariBody)
                .foregroundStyle(.ariTertiary)
                .listRowBackground(Color.clear)
            case .loaded:
                if !memory.recent.isEmpty {
                    Section {
                        ForEach(memory.recent.prefix(6)) { page in
                            NavigationLink(value: page.address) {
                                LabeledContent(
                                    page.title, value: page.changedAt.map(Self.ago) ?? "")
                            }
                        }
                    } header: {
                        heading("Recently changed")
                    }
                    .listRowBackground(Color.ariSurface)
                }
                Section {
                    ForEach(memory.inMind) { page in
                        NavigationLink(value: page.address) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(page.title).foregroundStyle(.ariText)
                                    Text(Self.blurb(for: page))
                                        .font(.footnote)
                                        .foregroundStyle(.ariTertiary)
                                }
                            } icon: {
                                Image(systemName: Self.symbol(for: page)).foregroundStyle(
                                    .ariTertiary)
                            }
                        }
                    }
                } header: {
                    heading("Always in mind")
                }
                .listRowBackground(Color.ariSurface)
                if !memory.shelves.isEmpty {
                    Section {
                        ForEach(memory.shelves) { shelf in
                            NavigationLink(value: ShelfRoute(shelf: shelf.shelf)) {
                                LabeledContent(
                                    Self.title(ofShelf: shelf.shelf), value: "\(shelf.count)"
                                )
                                .monospacedDigit()
                            }
                        }
                    } header: {
                        heading("Shelves")
                    }
                    .listRowBackground(Color.ariSurface)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .task { await memory.refresh() }
        .refreshable { await memory.refresh() }
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.ariHeading)
            .foregroundStyle(.ariText)
            .textCase(nil)
    }

    static func title(ofShelf shelf: String) -> String {
        shelf.prefix(1).uppercased() + shelf.dropFirst()
    }

    private static func symbol(for page: MemoryPage) -> String {
        switch page.shelf {
        case "portrait": "person.crop.circle"
        case "now": "sun.max"
        default: "hand.raised"
        }
    }

    private static func blurb(for page: MemoryPage) -> String {
        switch page.shelf {
        case "portrait": "Who you are"
        case "now": "What's going on these days"
        case "helping-you": "What Ari has learnt"
        default: "Updated \(ago(page.changedAt))"
        }
    }

    static func ago(_ time: Timestamp) -> String {
        time.date.formatted(.relative(presentation: .named))
    }
}

/// The pages on one shelf, most recently changed first.
struct ShelfView: View {
    let memory: Memory?
    let shelf: String

    @State private var pages: [PageSummary]?
    @State private var problem: String?

    var body: some View {
        Form {
            if let problem {
                Text(problem).foregroundStyle(.ariSecondary).listRowBackground(Color.ariSurface)
            } else if let pages {
                ForEach(pages) { page in
                    NavigationLink(value: page.address) {
                        LabeledContent(page.title, value: page.changedAt.map(MemoryList.ago) ?? "")
                    }
                }
                .listRowBackground(Color.ariSurface)
            } else {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(.ariBackground)
        .navigationTitle(MemoryList.title(ofShelf: shelf))
        .task {
            guard let memory else { return }
            do throws(RequestError) {
                pages = try await memory.pages(on: shelf)
            } catch {
                problem = "Couldn't load this shelf: \(error.plainWords)"
            }
        }
    }
}

/// One page, read-only, drawn from Ari's Markdown: the present first, then *Earlier*, then links.
struct PageView: View {
    let memory: Memory?
    let address: PageAddress

    @State private var page: MemoryPage?
    @State private var problem: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let page {
                    ReplyView(document: ReplyDocument(markdown: page.markdown), position: .infinity)
                    Text(
                        "\(MemoryList.title(ofShelf: page.shelf)) · as of \(MemoryList.ago(page.changedAt))"
                    )
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
                    if !page.links.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Linked").font(.subheadline.weight(.semibold))
                                .foregroundStyle(.ariSecondary)
                            ForEach(page.links) { link in
                                NavigationLink(value: link) {
                                    Text(link.plainName + " ›").font(.footnote)
                                        .foregroundStyle(.ariSecondary)
                                }
                            }
                        }
                    }
                    Text("Ari keeps this page. To change it, just tell Ari.")
                        .font(.caption)
                        .foregroundStyle(.ariTertiary)
                        .padding(.top, 8)
                } else if let problem {
                    Text(problem).foregroundStyle(.ariSecondary)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .frame(maxWidth: Rhythm.column, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(.ariBackground)
        .navigationTitle(page?.title ?? "")
        .task {
            guard let memory else { return }
            do throws(RequestError) {
                page = try await memory.page(address)
            } catch {
                problem = "Couldn't load this page: \(error.plainWords)"
            }
        }
    }
}

/// Tapping Ari's presence: the three pages that go into every reply, as they are right now.
struct InMindSheet: View {
    let memory: Memory

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(
                        "These go into every reply. Everything else, Ari looks up when it needs it."
                    )
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
                    ForEach(memory.inMind) { page in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(page.title).font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.ariText)
                                Spacer()
                                Text("Updated \(MemoryList.ago(page.changedAt))").font(.caption)
                                    .foregroundStyle(.ariTertiary)
                            }
                            ReplyView(
                                document: ReplyDocument(markdown: page.markdown),
                                position: .infinity,
                                tone: .note)
                        }
                    }
                    if memory.inMind.isEmpty {
                        Text("Nothing in mind yet. Ari fills these in as it gets to know you.")
                            .font(.ariBody)
                            .foregroundStyle(.ariTertiary)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 6)
                .padding(.bottom, 30)
            }
            .background(.ariBackground)
            .navigationTitle("In mind")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .task { await memory.refresh() }
    }
}

/// What one memory update changed: the page's present as it now reads, and what moved to
/// *Earlier*. Fetched when you open the step, since the trail never carries a page's words.
struct PageChangeView: View {
    let memory: Memory?
    let change: String

    @State private var loaded: PageChange?
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let loaded {
                if loaded.after == nil {
                    Text("Forgotten.").font(.footnote).foregroundStyle(.ariTertiary)
                } else {
                    ReplyView(
                        document: ReplyDocument(markdown: loaded.present), position: .infinity,
                        tone: .note)
                }
                let moved = loaded.movedToEarlier
                if !moved.isEmpty {
                    Divider().overlay(Color.ariLine)
                    Text("Moved to Earlier").font(.caption.weight(.semibold))
                        .foregroundStyle(.ariTertiary)
                    ForEach(moved, id: \.self) { line in
                        Text(line.trimmingPrefix("- ")).font(.footnote).foregroundStyle(
                            .ariTertiary)
                    }
                }
            } else if let problem {
                Text(problem).font(.footnote).foregroundStyle(.ariTertiary)
            } else {
                ProgressView()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ariSurface, in: .rect(cornerRadius: 12, style: .continuous))
        .task {
            guard let memory, loaded == nil else { return }
            do throws(RequestError) {
                loaded = try await memory.change(change)
            } catch {
                problem = "Couldn't load what changed: \(error.plainWords)"
            }
        }
    }
}
