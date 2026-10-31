import AriKit
import SwiftUI
import UIKit

/// The system pasteboard, on either platform.
enum Pasteboard {
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
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

    /// The day, as the conversation names it: with the time it began, unless `time` is false.
    static func describe(
        _ date: Date, now: Date = .now, calendar: Calendar = .current, time showsTime: Bool = true
    ) -> String {
        let time = showsTime ? " " + date.formatted(date: .omitted, time: .shortened) : ""
        if calendar.isDate(date, inSameDayAs: now) { return "Today\(time)" }
        if calendar.isDateInYesterday(date) { return "Yesterday\(time)" }
        let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
        let style = Date.FormatStyle().weekday(.wide).day().month(.wide)
        return sameYear ? date.formatted(style) : date.formatted(style.year())
    }
}

/// Where the subject changed: Ari's quiet label above the message that changed it, with a hairline
/// running on after it. A heading, so VoiceOver can jump between topics.
struct TopicLabel: View {
    let label: String
    /// Opens the conversation's topics, to jump between them.
    var open: (() -> Void)?

    var body: some View {
        Button {
            open?()
        } label: {
            line
        }
        .buttonStyle(.plain)
        .disabled(open == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHint(open == nil ? "" : "Shows all the topics")
        .accessibilityAddTraits(.isHeader)
    }

    private var line: some View {
        HStack(spacing: 10) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.ariTertiary)
                .lineLimit(1)
            Rectangle().fill(.ariLine).frame(height: 1)
        }
        .padding(.top, 10)
        .contentShape(Rectangle())
    }
}

/// The conversation's days and their topics, newest first, to jump between: from the title at the
/// top, or a topic's label. Each day is a short rail, like the trail; the subject you're reading is
/// lit. Older history comes in as you ask for it.
struct TopicsSheet: View {
    struct Mark: Identifiable, Equatable {
        let id: String
        let label: String
        let isTopic: Bool
    }

    let marks: [Mark]
    /// The subject at the top of the screen, lit in the list.
    var current: String?
    let hasEarlier: Bool
    let loadEarlier: () async -> Void
    let jump: (String) -> Void

    @State private var loading = false

    /// The days and topics among the rows, in the conversation's order.
    static func marks(in rows: [ConversationRow]) -> [Mark] {
        rows.compactMap { row in
            switch row.kind {
            case .topic(let topic): Mark(id: row.id, label: topic.label, isTopic: true)
            case .day(let date):
                Mark(id: row.id, label: DayLabel.describe(date, time: false), isTopic: false)
            default: nil
            }
        }
    }

    /// Each day with the topics marked in it, newest day first, its topics in order.
    private var days: [(day: Mark, topics: [Mark])] {
        var days: [(day: Mark, topics: [Mark])] = []
        for mark in marks {
            if mark.isTopic, !days.isEmpty {
                days[days.count - 1].topics.append(mark)
            } else if !mark.isTopic {
                days.append((mark, []))
            }
        }
        return days.reversed()
    }

    var body: some View {
        let days = days
        // The newest place the subject you're reading was marked.
        let lit = marks.last { $0.isTopic && $0.label == current }?.id
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(days, id: \.day.id) { day in
                        VStack(alignment: .leading, spacing: 0) {
                            Button {
                                jump(day.day.id)
                            } label: {
                                Text(day.day.label)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.ariTertiary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Goes to this day")
                            ForEach(Array(day.topics.enumerated()), id: \.element.id) {
                                index, topic in
                                row(
                                    topic, lit: topic.id == lit, last: index == day.topics.count - 1
                                )
                            }
                        }
                    }
                    if days.isEmpty {
                        Text("Topics appear as you talk: Ari marks where the subject changes.")
                            .font(.subheadline)
                            .foregroundStyle(.ariTertiary)
                    }
                    if hasEarlier {
                        Button {
                            loading = true
                            Task {
                                await loadEarlier()
                                loading = false
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text("Earlier days")
                                if loading { ProgressView().controlSize(.small) }
                            }
                            .font(.subheadline)
                            .foregroundStyle(.ariSecondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .overlay(Capsule().strokeBorder(.ariLine))
                        }
                        .buttonStyle(.plain)
                        .disabled(loading)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 4)
                .padding(.bottom, 30)
            }
            .background(.ariBackground)
            .navigationTitle("Topics")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// A topic on its day's rail: the label in Ari's serif, its dot lit if it's where you are.
    private func row(_ topic: Mark, lit: Bool, last: Bool) -> some View {
        Button {
            jump(topic.id)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 0) {
                    Circle()
                        .fill(lit ? Color.ariBone : .ariDusk)
                        .frame(width: 8, height: 8)
                        .padding(.top, 8)
                    if !last {
                        Rectangle().fill(.ariLine).frame(width: 1).frame(maxHeight: .infinity)
                    }
                }
                .frame(width: 8)
                Text(topic.label)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(lit ? Color.ariText : .ariSecondary)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(lit ? .isSelected : [])
    }
}

/// Your message, in a thin outline.
struct YourMessage<Attachments: View, Footer: View>: View {
    let text: String
    let tag: String?
    /// Its photos and files, above the words.
    @ViewBuilder var attachments: Attachments
    /// Below the words: playing back what you said.
    @ViewBuilder var footer: Footer

    /// The tag on screen. "Sending" waits half a second first, so a message that goes at once
    /// doesn't flicker a tag in and out.
    @State private var shown: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            attachments
            // A message may be only photos.
            if !text.isEmpty {
                YourWords(text: text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(
                            .ariLine, lineWidth: 1)
                    )
            }
            footer
            if let shown {
                // Its own line, so it never sits on what comes next.
                Tag(text: shown).padding(.trailing, 6).transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 52)
        .task(id: tag) {
            if tag == "Sending", shown == nil {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
            }
            withAnimation(.easeInOut(duration: 0.3)) { shown = tag }
        }
    }
}

/// Your words in a message. A long one, such as a few minutes spoken, folds after eight lines with
/// a soft fade and Show all, so it doesn't fill the screen; Ari's replies never fold.
private struct YourWords: View {
    let text: String

    static let foldedLines = 8
    /// Shorter than this can't run past eight lines on a phone, so it's never measured.
    static let mightFold = 320

    @State private var unfolded = false
    /// Whether the words run past eight lines, once measured.
    @State private var overflows = false

    var body: some View {
        let folds = text.count >= Self.mightFold
        VStack(alignment: .trailing, spacing: 6) {
            Text(Self.linked(text))
                .foregroundStyle(.ariText)
                .textSelection(.enabled)
                .lineLimit(folds && !unfolded ? Self.foldedLines : nil)
                .frame(maxWidth: folds ? .infinity : nil, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .mask {
                    // The last lines fade out while folded.
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: overflows && !unfolded ? 0.7 : 1),
                            .init(
                                color: .black.opacity(overflows && !unfolded ? 0.1 : 1), location: 1
                            ),
                        ], startPoint: .top, endPoint: .bottom)
                }
                .background(alignment: .topLeading) {
                    if folds && !unfolded && !overflows {
                        // The words in full, unseen, to tell whether eight lines cut them short.
                        Text(text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .hidden()
                            .onGeometryChange(for: CGFloat.self, of: \.size.height) { full in
                                overflows = full > Self.height(ofLines: Self.foldedLines) + 4
                            }
                    }
                }
            if overflows {
                Button {
                    withAnimation(.smooth(duration: 0.35)) { unfolded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(unfolded ? "Show less" : "Show all")
                        Chevron(isOpen: unfolded)
                    }
                    .font(.footnote)
                    .foregroundStyle(.ariSecondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        // As wide as the words need when short, so a short message keeps its snug outline.
        .frame(maxWidth: folds ? .infinity : nil, alignment: .trailing)
    }

    /// How tall `lines` lines of body text are.
    private static func height(ofLines lines: Int) -> CGFloat {
        UIFont.preferredFont(forTextStyle: .body).lineHeight * CGFloat(lines)
    }
}

extension YourWords {
    /// Your words, with any web address in them made a link, as Ari's are.
    static func linked(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard
            let detector = try? NSDataDetector(
                types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return result }
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = match.url, let range = Range(match.range, in: text),
                let start = AttributedString.Index(range.lowerBound, within: result),
                let end = AttributedString.Index(range.upperBound, within: result)
            else { continue }
            result[start..<end].link = url
            result[start..<end].underlineStyle = .single
        }
        return result
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
        let plain = ReplyDocument(markdown: text).plainText
        Group {
            // SwiftUI's text on iPhone can only be copied whole; a text view lets you pick words.
            SelectableText(text: plain)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ariSurface)
    }
}

/// Read-only text you can select any part of, in Ari's serif.
private struct SelectableText: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 22, left: 18, bottom: 22, right: 18)
        view.adjustsFontForContentSizeCategory = true
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let body = UIFont.preferredFont(forTextStyle: .body)
        let serif = body.fontDescriptor.withDesign(.serif).map {
            UIFont(descriptor: $0, size: 0)
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = Rhythm.ariLineSpacing
        paragraph.paragraphSpacing = 10
        view.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: UIFontMetrics(forTextStyle: .body).scaledFont(for: serif ?? body),
                .foregroundColor: UIColor(Color.ariText), .paragraphStyle: paragraph,
            ])
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

/// Ari offers, once, to tell you when it's done: in its own words, at the first turn that takes a
/// while, rather than asking at launch.
struct NotificationOffer: View {
    let answer: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This one may take a minute. Want a nudge when I'm done, even if Ari is closed?")
                .font(.ariBody)
                .foregroundStyle(.ariText)
                .lineSpacing(Rhythm.ariLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button {
                    answer(true)
                } label: {
                    Text("Notify me")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.ariBackground)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ariText, in: Capsule())
                }
                Button {
                    answer(false)
                } label: {
                    Text("Not now")
                        .font(.subheadline)
                        .foregroundStyle(.ariText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .overlay(Capsule().strokeBorder(.ariLine, lineWidth: 1))
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The opening of a reply, on its own card, for the long-press menu's preview.
struct ReplyPreview: View {
    let text: String

    var body: some View {
        let opening = text.count > 700 ? String(text.prefix(700)) + "…" : text
        ReplyView(document: ReplyDocument(markdown: opening), position: .infinity)
            .padding(18)
            .frame(width: 340, alignment: .leading)
            .background(.ariBackground)
    }
}

/// What needs you before Ari can carry on, in place of the composer.
struct ProblemNotice: View {
    let problem: Session.Problem
    let connectAgain: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            switch problem {
            case .tokenRejected(let error):
                Text(error?.message ?? "Your server no longer accepts this token.")
                    .foregroundStyle(.ariSecondary)
                Button("Connect again", action: connectAgain)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.ariText)
            case .protocolMismatch(let mismatch):
                Text(
                    mismatch.update == .ari
                        ? "Your server now speaks a newer protocol. Update Ari."
                        : "Your server speaks an older protocol. Update Ito on your server."
                )
                .foregroundStyle(.ariSecondary)
            }
        }
        .font(.subheadline)
        .multilineTextAlignment(.center)
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
}
