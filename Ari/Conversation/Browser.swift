import SafariServices
import SwiftUI

/// A web page a reply links to, opened in place so the conversation is one swipe away.
struct WebPage: Identifiable {
    let url: URL
    var id: URL { url }

    /// Pages open in place; anything else, such as `mailto:`, goes to its own app.
    static func opens(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }
}

struct BrowserView: UIViewControllerRepresentable {
    let page: WebPage

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let browser = SFSafariViewController(url: page.url)
        browser.dismissButtonStyle = .close
        return browser
    }

    func updateUIViewController(_ browser: SFSafariViewController, context: Context) {}
}
