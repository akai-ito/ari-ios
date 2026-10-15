import AriKit
import SwiftUI

#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

/// The system pasteboard, on either platform.
enum Pasteboard {
    static func copy(_ text: String) {
        #if os(iOS)
            UIPasteboard.general.string = text
        #else
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

/// A small grey label under a message: Sending, Waiting to send, Read, Next, Stopped, Interrupted.
struct Tag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.ariTertiary)
    }
}

/// The date at the start of each day: "Today 09:41", "Yesterday 22:14", "Friday 26 September".
struct DayLabel: View {
    let date: Date

    var body: some View {
        Text(Self.describe(date))
            .font(.caption)
            .foregroundStyle(.ariTertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }

    static func describe(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return "Today \(time)" }
        if calendar.isDateInYesterday(date) { return "Yesterday \(time)" }
        let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
        let style = Date.FormatStyle().weekday(.wide).day().month(.wide)
        return sameYear ? date.formatted(style) : date.formatted(style.year())
    }
}

/// Your message, in a thin outline.
struct YourMessage: View {
    let text: String
    let tag: String?

    var body: some View {
        Text(text)
            .foregroundStyle(.ariText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(
                    .ariLine, lineWidth: 1)
            )
            .overlay(alignment: .bottomTrailing) {
                if let tag {
                    // Its own width, even under a short message such as a code's dots.
                    Tag(text: tag).fixedSize().padding(.trailing, 6).offset(y: 18)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: tag)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 52)
            .textSelection(.enabled)
    }
}

/// Why a reply couldn't finish, in the server's words, with Try again and Details.
struct FailureLine: View {
    let message: String
    let canTryAgain: Bool
    let tryAgain: () -> Void
    let details: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.ariSecondary)
            HStack(spacing: 18) {
                if canTryAgain {
                    Button("Try again", action: tryAgain)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.ariText)
                }
                Button("Details", action: details)
                    .font(.subheadline)
                    .foregroundStyle(.ariTertiary)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The pill above the composer: tap it for the live end.
struct Pill: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(text).font(.subheadline)
                Image(systemName: "arrow.down").font(.caption.weight(.semibold))
            }
            .foregroundStyle(.ariText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ariBackground, in: Capsule())
            .overlay(Capsule().strokeBorder(.ariLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// The technical cause of a failure, for acting on or reporting.
struct DetailsSheet: View {
    let error: ServerError

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Details").font(.headline).foregroundStyle(.ariText)
                Spacer()
                Button("Copy") { Pasteboard.copy(technical) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.ariText)
                    .buttonStyle(.plain)
            }
            Text(technical)
                .font(.footnote.monospaced())
                .foregroundStyle(.ariSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(22)
        .presentationDetents([.medium])
        .presentationBackground(.ariSurface)
    }

    private var technical: String {
        [error.code.rawValue, error.detail ?? error.message].joined(separator: "\n")
    }
}

/// A reply's text, selectable in part, for when you want only some of it.
struct SelectTextSheet: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.ariBody)
                .lineSpacing(Rhythm.ariLineSpacing)
                .foregroundStyle(.ariText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ariSurface)
    }
}

/// Something a sheet shows: a failure's details, or a reply to select from.
enum SheetItem: Identifiable {
    case details(ServerError)
    case selecting(String)

    var id: String {
        switch self {
        case .details(let error): "details \(error.code.rawValue) \(error.message)"
        case .selecting(let text): "selecting \(text)"
        }
    }
}
