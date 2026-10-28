import AriKit
import CoreSpotlight

/// Ari's pages in your device's search: each by its title and Ari's line on what it is now, opening
/// straight to the page. The index stays on the device, and holds only the server Ari is
/// connected to now.
enum Spotlight {
    static let domain = "memory"

    /// Indexes every page Ari knows of, in place of what was there.
    static func index(_ memory: Memory) async {
        var items = memory.inMind.map { page in
            item(page.address, title: page.title, line: page.gist ?? firstLine(page.markdown))
        }
        for pages in memory.shelfPages.values {
            items += pages.map { item($0.address, title: $0.title, line: $0.gist) }
        }
        guard !items.isEmpty else { return }
        let index = CSSearchableIndex.default()
        try? await index.deleteSearchableItems(withDomainIdentifiers: [domain])
        try? await index.indexSearchableItems(items)
    }

    /// The page a search result opens, from the activity Spotlight hands Ari.
    static func page(from activity: NSUserActivity) -> PageAddress? {
        (activity.userInfo?[CSSearchableItemActivityIdentifier] as? String).map(PageAddress.init)
    }

    private static func item(_ address: PageAddress, title: String, line: String?)
        -> CSSearchableItem
    {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = title
        attributes.contentDescription = line
        return CSSearchableItem(
            uniqueIdentifier: address.rawValue, domainIdentifier: domain,
            attributeSet: attributes)
    }

    /// A page's first paragraph, as plain words, for a page Ari hasn't written a line for.
    private static func firstLine(_ markdown: String) -> String? {
        let document = ReplyDocument(markdown: markdown).quietingStamps()
        return document.blocks.first { $0.kind == .paragraph }.map { block in
            block.runs.filter { !$0.style.contains(.stamp) }.map(\.text).joined()
        }
    }
}
