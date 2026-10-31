import AriKit
import SwiftUI

/// The Library tab: what Ari knows about you, as Ari's notebook. Read-only: to change anything, you
/// tell Ari.
struct LibraryView: View {
    let memory: Memory?
    /// Where the Library is: kept by the app, so a search result can open a page in it.
    @Binding var path: NavigationPath
    let openSettings: () -> Void

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let memory {
                    LibraryHome(memory: memory)
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

extension LibraryView {
    /// Where the Library opens: at the top, or, in debug builds, at the page `ARI_PAGE` names.
    static var startingPath: NavigationPath {
        var path = NavigationPath()
        #if DEBUG
            if let shelf = DebugScript.shelf { path.append(ShelfRoute(shelf: shelf)) }
            if let page = DebugScript.page { path.append(page) }
        #endif
        return path
    }
}

/// A shelf, as a navigation value.
struct ShelfRoute: Hashable {
    let shelf: String
}

/// One page, read-only, drawn from Ari's Markdown: the pages it links to as chips on top, then
/// the present, then *Earlier*. Names in the words open their pages.
struct PageView: View {
    let memory: Memory?
    let address: PageAddress

    @State private var page: MemoryPage?
    @State private var problem: String?
    /// A page opened from a name in the words.
    @State private var opened: PageAddress?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let page {
                    if !page.links.isEmpty {
                        WrappingStack(spacing: 8) {
                            ForEach(page.links, id: \.address) { link in
                                NavigationLink(value: link.address) {
                                    PageChip(title: link.title)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    ReplyView(document: PageLink.reading(page), position: .infinity)
                    Text(
                        "\(LibraryHome.title(ofShelf: page.shelf)) · as of \(LibraryHome.ago(page.changedAt))"
                    )
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
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
        .opensPageLinks { opened = $0 }
        .navigationDestination(item: $opened) { PageView(memory: memory, address: $0) }
        // Again once there's a server to ask, when the page opened first.
        .task(id: memory != nil) {
            guard let memory else { return }
            do throws(RequestError) {
                page = try await memory.page(address)
            } catch {
                problem = "Couldn't load this page: \(error.plainWords)"
            }
        }
    }
}

/// A linked page, named: outlined like an option, in your hand.
struct PageChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.footnote)
            .foregroundStyle(.ariSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().strokeBorder(.ariLine, lineWidth: 1))
            .contentShape(Capsule())
    }
}

/// A link from a page's words to another page: `ari-page:` and its address.
enum PageLink {
    static let scheme = "ari-page"

    static func url(_ address: PageAddress) -> URL? {
        URL(string: "\(scheme):\(address.rawValue)")
    }

    static func address(_ url: URL) -> PageAddress? {
        guard url.scheme == scheme else { return nil }
        return PageAddress(String(url.absoluteString.dropFirst(scheme.count + 1)))
    }

    /// A page's words as the Library shows them: stamps quiet, and each linked page linked where
    /// the words first name it, by its title or another name.
    static func reading(_ page: MemoryPage) -> ReplyDocument {
        ReplyDocument(markdown: page.markdown)
            .quietingStamps()
            .linking(
                page.links.compactMap { link in
                    url(link.address).map { ([link.title] + link.aliases, $0) }
                })
    }
}

extension View {
    /// Opens a page of memory when its name is tapped in the words; any other link opens as usual.
    func opensPageLinks(_ open: @escaping (PageAddress) -> Void) -> some View {
        environment(
            \.openURL,
            OpenURLAction { url in
                guard let address = PageLink.address(url) else { return .systemAction }
                open(address)
                return .handled
            })
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
