import AriKit
import SwiftUI
import UIKit

/// A thread open over the chat.
struct OpenedThread: Identifiable, Equatable {
    let id: ThreadID
}

/// What a thread is called where it shows: its name, or a plain stand-in until Kumo names it.
extension SideThread {
    var shownTitle: String { title ?? (anchor == nil ? "New thread" : "Reply thread") }
}

/// The corner a thread hangs from: down, then along.
private nonisolated struct Hook: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            let radius = min(rect.width, rect.height) * 0.45
            path.move(to: CGPoint(x: rect.minX + 1, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + 1, y: rect.maxY - radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + 1 + radius, y: rect.maxY),
                control: CGPoint(x: rect.minX + 1, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
    }
}

/// The small dotted ring an open thread carries.
private struct OpenRing: View {
    var body: some View {
        Image(systemName: "circle.dotted")
            .font(.caption.weight(.heavy))
            .foregroundStyle(.ariBone)
            .accessibilityHidden(true)
    }
}

/// A thread in the main chat. At rest, one quiet line, `└ Kiln menu · 6 replies ›`, with a dotted
/// ring while it's open; under the message it hangs from, just `└ 2 replies ›`. With something new
/// from Kumo, it carries a bone dot and the news's first line.
struct ThreadLine: View {
    let thread: SideThread
    /// Whether it sits under the message it hangs from, which names it well enough.
    let isUnderAnchor: Bool
    /// What it says in place of its replies, such as how its recording is getting on.
    var detail: String?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Hook()
                    .stroke(
                        .ariDusk,
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 12, height: 17)
                    .alignmentGuide(.lastTextBaseline) { $0[.bottom] - 4 }
                if let news = thread.news { bumped(news) } else { quiet }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityHint("Opens the thread")
        .accessibilityAddTraits(.isButton)
    }

    private var replies: String {
        detail ?? (thread.replies == 1 ? "1 reply" : "\(thread.replies) replies")
    }

    private var quiet: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if thread.isOpen { OpenRing() }
            if !isUnderAnchor {
                Text(thread.shownTitle).foregroundStyle(
                    thread.isOpen ? Color.ariText : .ariSecondary)
                Text("·").foregroundStyle(.ariTertiary)
            }
            Text(replies).foregroundStyle(isUnderAnchor ? Color.ariSecondary : .ariTertiary)
                .monospacedDigit()
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.ariTertiary)
        }
        .font(.footnote)
        .lineLimit(1)
    }

    private func bumped(_ news: SideThread.News) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if thread.isOpen { OpenRing() }
            Text(thread.shownTitle).fontWeight(.semibold).foregroundStyle(.ariText)
                .layoutPriority(1)
            Circle().fill(.ariBone).frame(width: 6, height: 6)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
            Text(news.text).foregroundStyle(.ariSecondary).lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.ariTertiary)
        }
        .font(.footnote)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ariSurface, in: .rect(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.ariLine.opacity(0.7), lineWidth: 1))
    }

    private var spoken: String {
        let state = thread.isOpen ? "open thread" : "thread, done"
        let news = thread.news.map { ", new: \($0.text)" } ?? ""
        return "\(thread.shownTitle), \(state), \(replies)\(news)"
    }
}

/// In the main chat, a thread you started here that the server hasn't named yet, such as the one a
/// recording starts while it goes up: `└ New thread · Uploading your recording · 42% ›`.
struct StartedThreadLine: View {
    let session: Session
    let thread: ThreadID
    let open: () -> Void
    @Environment(BigUploads.self) private var uploads: BigUploads?

    var body: some View {
        let conversation = session.conversation(in: thread)
        let progress = RecordingProgress(
            in: conversation, uploads: uploads?.uploads ?? [:],
            sent: { uploads?.sent($0.id) ?? $0.received }, recordings: session.recordings)
        ThreadLine(
            thread: SideThread(
                id: thread, by: .you, startedAt: Timestamp(.now), position: 0,
                anchor: session.drafts[thread] ?? nil, replies: conversation.entries.count),
            isUnderAnchor: false, detail: progress?.line, open: open)
    }
}

/// The quiet line at the end of a thread that's done: who marked it, when, and that replying opens it.
struct ThreadDoneLine: View {
    let done: SideThread.Done

    var body: some View {
        let who = done.by == .you ? "You" : LeadName.current
        let time = done.at.date.formatted(date: .omitted, time: .shortened)
        HStack(spacing: 6) {
            Image(systemName: "checkmark").font(.caption2.weight(.heavy))
            Text("\(who) marked this done · \(time) · reply to reopen")
        }
        .font(.caption)
        .foregroundStyle(.ariTertiary)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }
}

/// At the top of a reply thread: the main chat's message it hangs from, quietly.
struct ThreadAnchor: View {
    let entry: Conversation.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.role == .user ? "You said" : "\(LeadName.current) said")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.ariTertiary)
            Text(entry.text.isEmpty ? entry.line : entry.text)
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(.ariSecondary)
                .lineLimit(6)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Rectangle().fill(.ariBone.opacity(0.7)).frame(width: 2)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Above your reply in a thread: a line of the message it answers.
struct QuotedLine: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(.ariBone.opacity(0.7)).frame(width: 2, height: 16)
            Text(text)
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(.ariTertiary)
                .lineLimit(1)
        }
        .padding(.leading, 70)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityLabel("Replying to: \(text)")
    }
}

/// Above the composer while you reply to a message in a thread: what you're answering, to let go.
struct QuoteChip: View {
    let text: String
    var remove: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(.ariBone.opacity(0.7)).frame(width: 2, height: 18)
            Text(text)
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(.ariSecondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let remove {
                Button("Stop replying", systemImage: "xmark", action: remove)
                    .labelStyle(.iconOnly)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.ariTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

/// A thread's header: back to the chat, its name, whether it's open or done, and its menu. While
/// your recording in it goes up and is transcribed, it says how that's getting on instead.
struct ThreadHeader: View {
    let thread: SideThread?
    let session: Session
    let place: ThreadID
    let back: () -> Void
    let markDone: (Bool) -> Void
    let rename: () -> Void
    let move: () -> Void

    var body: some View {
        ZStack {
            HStack {
                Button("Back", systemImage: "chevron.left", action: back)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.ariText)
                    .frame(width: 40, height: 40)
                    .glassEffect(.regular.interactive(), in: Circle())
                Spacer()
                if let thread {
                    Menu {
                        Button(
                            thread.isOpen ? "Mark done" : "Mark open",
                            systemImage: thread.isOpen ? "checkmark.circle" : "circle.dotted"
                        ) { markDone(thread.isOpen) }
                        Button("Rename", systemImage: "pencil", action: rename)
                        Button("Move a message", systemImage: "arrow.turn.up.right", action: move)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.ariText)
                            .frame(width: 40, height: 40)
                            .glassEffect(.regular.interactive(), in: Circle())
                    }
                    .accessibilityLabel("Thread options")
                }
            }
            VStack(spacing: 3) {
                Text(thread?.shownTitle ?? "New thread")
                    .font(.ariName)
                    .foregroundStyle(.ariText)
                    .lineLimit(1)
                ThreadStatusLine(thread: thread, session: session, place: place)
            }
            .padding(.horizontal, 56)
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .background {
            VStack(spacing: 0) {
                Color.ariBackground
                LinearGradient(
                    colors: [.ariBackground, .ariBackground.opacity(0)], startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 28)
            }
            .padding(.bottom, -28)
            .ignoresSafeArea(edges: .top)
        }
    }
}

/// Under a thread's name: how your recording is getting on while it goes up and is transcribed, then
/// whether the thread is open or done, and how many replies it has. Its own view, so an upload's
/// progress redraws only this line.
private struct ThreadStatusLine: View {
    let thread: SideThread?
    let session: Session
    let place: ThreadID
    @Environment(BigUploads.self) private var uploads: BigUploads?

    var body: some View {
        Group {
            if let progress = RecordingProgress(
                in: session.conversation(in: place), uploads: uploads?.uploads ?? [:],
                sent: { uploads?.sent($0.id) ?? $0.received }, recordings: session.recordings)
            {
                Text(progress.line)
                    .monospacedDigit()
                    .lineLimit(1)
                    .contentTransition(.numericText())
            } else if let thread {
                HStack(spacing: 5) {
                    Image(systemName: thread.isOpen ? "circle.dotted" : "checkmark")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(thread.isOpen ? Color.ariBone : .ariTertiary)
                    Text(
                        "\(thread.isOpen ? "Open" : "Done") · \(thread.replies == 1 ? "1 reply" : "\(thread.replies) replies")"
                    )
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(.ariTertiary)
    }
}

/// Moving a message: first which one, from the ⋯ menu, then where to, the main chat or another
/// open thread.
struct MoveSheet: View {
    /// The messages that can move, when it's opened from the menu; empty when one is already chosen.
    let messages: [Conversation.Entry]
    /// The message already chosen, from its own menu.
    let chosen: Conversation.Entry?
    /// Where it can go: the main chat (`nil`), then the open threads, but not where it is.
    let destinations: [SideThread]
    let isInMainChat: Bool
    let move: (Conversation.Entry, ThreadID?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Conversation.Entry?

    var body: some View {
        NavigationStack {
            List {
                if let message = picked ?? chosen {
                    Section {
                        Text(message.line).foregroundStyle(.ariSecondary).lineLimit(2)
                    } header: {
                        Text("Moving")
                    }
                    Section("To") {
                        if !isInMainChat {
                            destination("Main chat", systemImage: "bubble.left") {
                                move(message, nil)
                            }
                        }
                        ForEach(destinations) { thread in
                            destination(thread.shownTitle, systemImage: "circle.dotted") {
                                move(message, thread.id)
                            }
                        }
                    }
                } else {
                    Section("Which message?") {
                        ForEach(messages) { message in
                            Button {
                                picked = message
                            } label: {
                                Text(message.line).foregroundStyle(.ariText).lineLimit(2)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(.ariBackground)
            .navigationTitle("Move a message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func destination(_ title: String, systemImage: String, go: @escaping () -> Void)
        -> some View
    {
        Button {
            go()
            dismiss()
        } label: {
            Label(title, systemImage: systemImage).foregroundStyle(.ariText)
        }
    }
}

/// What replaces Topics: every thread, open ones first, then by day, for finding things again.
/// Each with its result in a line, its picture when it has one and a page mark when Kumo made one.
/// Days with nothing in them don't show.
struct ThreadsSheet: View {
    let session: Session
    let open: (ThreadID) -> Void
    let startThread: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var listed: ThreadList?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    search
                    if let listed {
                        if !listed.open.isEmpty { section("Open", listed.open, isOpen: true) }
                        ForEach(days(listed.threads), id: \.title) { day in
                            section(day.title, day.threads, isOpen: false)
                        }
                        if listed.open.isEmpty, listed.threads.isEmpty {
                            Text(
                                query.isEmpty
                                    ? "Threads appear as you talk: \(LeadName.current) starts one for a new subject, and replying to a message starts one too."
                                    : "No thread holds “\(query)”."
                            )
                            .font(.subheadline)
                            .foregroundStyle(.ariTertiary)
                            .padding(.top, 20)
                        }
                    } else if failed {
                        Text("Couldn't load your threads. Pull down to try again.")
                            .font(.subheadline)
                            .foregroundStyle(.ariTertiary)
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 30)
            }
            .refreshable { await load() }
            .background(.ariBackground)
            .navigationTitle("Threads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("New thread", systemImage: "square.and.pencil", action: startThread)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: query) {
                if !query.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
                guard !Task.isCancelled else { return }
                await load()
            }
        }
    }

    private func load() async {
        do {
            listed = try await session.threads(matching: query)
            failed = false
        } catch {
            failed = listed == nil
        }
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.ariTertiary)
            TextField("A dish, a place, a person", text: $query)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ariSurface, in: Capsule())
    }

    /// Done threads by the day they started, newest first.
    private func days(_ threads: [SideThread]) -> [(title: String, threads: [SideThread])] {
        let calendar = Calendar.current
        var days: [(title: String, threads: [SideThread])] = []
        var current: Date?
        for thread in threads {
            let date = thread.startedAt.date
            if let day = current, calendar.isDate(day, inSameDayAs: date) {
                days[days.count - 1].threads.append(thread)
            } else {
                current = date
                days.append((DayLabel.describe(date, time: false), [thread]))
            }
        }
        return days
    }

    private func section(_ title: String, _ threads: [SideThread], isOpen: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isOpen ? Color.ariBone : .ariTertiary)
                .padding(.bottom, 6)
            ForEach(Array(threads.enumerated()), id: \.element.id) { index, thread in
                if index > 0 {
                    Rectangle().fill(.ariLine.opacity(0.7)).frame(height: 1).padding(.leading, 26)
                }
                Button {
                    open(thread.id)
                } label: {
                    ThreadRow(session: session, thread: thread, isOpenSection: isOpen)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// One thread in Threads by day.
private struct ThreadRow: View {
    let session: Session
    let thread: SideThread
    let isOpenSection: Bool
    @State private var picture: UIImage?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if thread.isOpen { OpenRing() } else { Color.clear }
            }
            .frame(width: 14, height: 14)
            .padding(.top, 4)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(thread.shownTitle)
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(thread.isOpen ? Color.ariText : .ariSecondary)
                    if thread.news != nil {
                        Circle().fill(.ariBone).frame(width: 6, height: 6)
                    }
                    if thread.page == true {
                        Image(systemName: "doc.richtext")
                            .font(.caption)
                            .foregroundStyle(.ariTertiary)
                            .accessibilityLabel("Has a page")
                    }
                }
                if let line = thread.news?.text ?? thread.result {
                    // Two lines at most, never cut mid-word: a cut-off label was a bug in Topics.
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(thread.news == nil ? Color.ariTertiary : .ariText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let picture {
                Image(uiImage: picture)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(.rect(cornerRadius: 9, style: .continuous))
                    .accessibilityHidden(true)
            }
            Text(time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(thread.news == nil ? Color.ariTertiary : .ariBone)
                .frame(width: 44, alignment: .trailing)
                .padding(.top, 3)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .task(id: thread.picture) {
            guard let attachment = thread.picture, let bytes = await session.bytes(of: attachment)
            else { return }
            picture = UIImage(data: bytes)
        }
    }

    /// Open ones by when they last moved, the rest by when they started: a time today, a weekday
    /// this week, or a date.
    private var time: String {
        if thread.news != nil { return "Now" }
        let date = isOpenSection ? thread.lastAt.date : thread.startedAt.date
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if !isOpenSection { return date.formatted(date: .omitted, time: .shortened) }
        if let week = calendar.date(byAdding: .day, value: -6, to: .now), date > week {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
