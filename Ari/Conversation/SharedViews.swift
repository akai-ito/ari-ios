import AriKit
import SwiftUI

/// What you shared from the share sheet, above your note in its thread: the link as a card, from
/// what the server read of the page (Ito never goes to the site to draw it), and text from another
/// app as a quote. A photo or file shared with nothing else is marked as shared.
struct SharedPieces: View {
    let share: Shared
    /// Whether the message carries photos or files, which show below as any message's do.
    let hasAttachments: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let link = share.link { SharedLinkCard(link: link) }
            if let text = share.text { SharedQuote(text: text) }
            if share.link == nil, share.text == nil, hasAttachments {
                Label("Shared", systemImage: "square.and.arrow.up")
                    .font(.caption)
                    .foregroundStyle(.ariTertiary)
                    .padding(.trailing, 6)
            }
        }
    }
}

/// A shared link: its title, its summary and its site, beside a quiet link mark. Tap it to open
/// the page.
struct SharedLinkCard: View {
    let link: SharedLink

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let address = link.address { openURL(address) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "link")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.ariSecondary)
                    .frame(width: 44, height: 44)
                    .background(.ariField, in: .rect(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(link.title ?? link.host)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.ariText)
                        .lineLimit(2)
                    if let summary = link.description {
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(.ariSecondary)
                            .lineLimit(2)
                    }
                    if link.title != nil || site != link.host {
                        Text(site)
                            .font(.caption)
                            .foregroundStyle(.ariTertiary)
                            .lineLimit(1)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: 320, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.ariLine, lineWidth: 1)
            )
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Shared link: \(link.title ?? link.host), \(site)")
        .accessibilityHint("Opens the page")
    }

    /// The site's name, with its host when that says something more: "Fernway · fernway.example".
    private var site: String {
        guard let name = link.site, name.lowercased() != link.host.lowercased() else {
            return link.host
        }
        return "\(name) · \(link.host)"
    }
}

/// Text you shared from another app, as a quote: a bone rule beside it, as Ito quotes elsewhere.
/// A long passage folds after six lines; tap it to read all of it.
struct SharedQuote: View {
    let text: String

    @State private var unfolded = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle().fill(.ariBone.opacity(0.7)).frame(width: 2)
            Text(text)
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(.ariSecondary)
                .lineLimit(unfolded ? nil : 6)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: 320, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { unfolded.toggle() } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Shared text: \(text)")
    }
}
