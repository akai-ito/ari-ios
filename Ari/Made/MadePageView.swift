import AriKit
import SwiftUI

// A page Kumo made: a card in the chat that opens it, the page itself, and the Made shelf. Pages
// are living (Kumo keeps them current and says what changed), interactive (sections fold, things
// tick off, places have Directions) and shareable, as text.

/// A page Kumo made, in the chat: its cover, what it is, how big, when it was made or last changed,
/// and Open. It lives in its thread and on the Made shelf.
struct MadeCardView: View {
    let card: ReplyShape.MadeCard

    @Environment(MadePages.self) private var made: MadePages?
    @State private var opens = false

    var body: some View {
        Group {
            if let page = made?[card.made] {
                Button {
                    opens = true
                } label: {
                    MadeCardFace(page: page)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the page")
            } else if made?.forgotten.contains(card.made) == true {
                Label("This page was forgotten.", systemImage: "doc")
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
            } else {
                ShapePlaceholder()
                    .task(id: card.made) { _ = try? await made?.detail(card.made) }
            }
        }
        .fullScreenCover(isPresented: $opens) {
            MadePageView(id: card.made)
        }
    }
}

/// The card's face, as in the chat and on the Made shelf.
struct MadeCardFace: View {
    let page: Made
    var showsOpen = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MadeCover(page: page, longest: 900)
                .frame(height: 132)
                .clipped()
                .overlay(alignment: .topLeading) {
                    Label("Page", systemImage: "doc.richtext")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.ariText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ariBackground.opacity(0.75), in: Capsule())
                        .padding(10)
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(page.title)
                    .font(.ariHeading)
                    .foregroundStyle(.ariText)
                    .multilineTextAlignment(.leading)
                if !page.summary.isEmpty {
                    Text(page.summary)
                        .font(.subheadline)
                        .foregroundStyle(.ariSecondary)
                }
                HStack {
                    Text("\(MadeLook.when(page)) · on your Made shelf")
                        .font(.caption)
                        .foregroundStyle(.ariTertiary)
                    Spacer(minLength: 8)
                    if showsOpen {
                        HStack(spacing: 4) {
                            Text("Open")
                            Image(systemName: "chevron.right").font(.caption.weight(.bold))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.ariBackground)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.ariText, in: Capsule())
                    }
                }
                .padding(.top, 8)
            }
            .padding(14)
        }
        .background(.ariSurface, in: .rect(cornerRadius: 20, style: .continuous))
        .clipShape(.rect(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.ariLine.opacity(0.7), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

/// A page's cover: its picture, or Kumo's dots when it has none.
private struct MadeCover: View {
    let page: Made
    let longest: Int

    var body: some View {
        if let cover = page.cover {
            FoundPhoto(photo: cover, longest: longest, creditOnTap: false)
        } else {
            ZStack {
                Rectangle().fill(.ariSurface)
                DotGlyph(symbol: "doc.richtext", side: 64)
            }
        }
    }
}

enum MadeLook {
    /// "Made just now", or "Updated 2 hours ago" once Kumo has changed it.
    static func when(_ page: Made) -> String {
        let ago = page.changedAt.date.formatted(.relative(presentation: .named))
        return page.version > 1 ? "Updated \(ago)" : "Made \(ago)"
    }

    /// "Saturday", for the day a page is for.
    static func day(_ forDay: String) -> String? {
        guard let date = try? Date.ISO8601FormatStyle().year().month().day().parse(forDay) else {
            return nil
        }
        return date.formatted(.dateTime.weekday(.wide))
    }
}

/// A page Kumo made, opened: its cover, where it came from, how far along your ticks are, what Kumo
/// last changed, its words, then its sections, folding, with things to tick.
struct MadePageView: View {
    let id: MadeID

    @Environment(MadePages.self) private var made: MadePages?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openInChat) private var openInChat
    @Environment(\.openThread) private var openThread
    @State private var open: Set<String>?
    /// The name of the thread it was made in, once the server has said.
    @State private var threadName: String?
    @State private var problem: String?
    /// Scrolled past the cover: a strip behind the buttons keeps the words from the clock.
    @State private var isPastCover = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.ariBackground.ignoresSafeArea()
            if let detail = made?.details[id] {
                page(detail)
            } else if let problem {
                Text(problem)
                    .foregroundStyle(.ariSecondary)
                    .padding(40)
                    .frame(maxHeight: .infinity)
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }
            if isPastCover {
                LinearGradient(
                    colors: [.ariBackground, .ariBackground.opacity(0)], startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 110)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
            buttons
        }
        .animation(.easeOut(duration: 0.2), value: isPastCover)
        .task(id: id) {
            guard let made else {
                problem = "Connect to your server to open this page."
                return
            }
            do throws(RequestError) {
                _ = try await made.detail(id)
            } catch {
                if made.details[id] == nil {
                    problem = "Couldn't open this page: \(error.plainWords)"
                }
            }
        }
    }

    /// Round glass buttons over the cover, tinted dark so they show over a bright photo: close,
    /// and share the page as text.
    private var buttons: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                glyph("chevron.down")
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(.black.opacity(0.3)).interactive(), in: Circle())
            .accessibilityLabel("Close")
            Spacer()
            if let detail = made?.details[id] {
                ShareLink(item: MadeReading.shareText(detail), subject: Text(detail.made.title)) {
                    glyph("square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(.black.opacity(0.3)).interactive(), in: Circle())
                .accessibilityLabel("Share")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func glyph(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.ariText)
            .frame(width: 40, height: 40)
            .contentShape(Circle())
    }

    private func page(_ detail: MadeDetail) -> some View {
        let content = detail.content
        let opened = open ?? MadeReading.openAtFirst(content)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MadeCover(page: detail.made, longest: 1600)
                    .frame(height: detail.made.cover == nil ? 120 : 250)
                    .clipped()
                    .overlay(alignment: .bottom) {
                        LinearGradient(
                            colors: [.clear, .ariBackground], startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: 70)
                    }
                VStack(alignment: .leading, spacing: 18) {
                    heading(detail)
                    if let change = MadeReading.latestChange(detail) {
                        LivingNote(change: change)
                    }
                    if let intro = content.intro {
                        ReplyView(document: ReplyDocument(markdown: intro), position: .infinity)
                    }
                    sections(detail, opened: opened)
                    footer(detail.made)
                }
                .padding(.horizontal, 20)
                .padding(.top, 2)
                .padding(.bottom, 40)
                .frame(maxWidth: Rhythm.column, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .onScrollGeometryChange(for: Bool.self) {
            $0.contentOffset.y > 160
        } action: { _, past in
            isPastCover = past
        }
        #if DEBUG
            .defaultScrollAnchor(DebugScript.opensMadeAtEnd ? .bottom : .top)
        #endif
    }

    private func heading(_ detail: MadeDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            backLink(detail.made)
            Text(detail.made.title)
                .font(.ariTitle)
                .foregroundStyle(.ariText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let progress = MadeReading.progress(detail.content, state: detail.state),
                let line = MadeReading.progressLine(detail.content, state: detail.state)
            {
                HStack(spacing: 10) {
                    TickDots(total: progress.of, lit: progress.done)
                    Text(line).font(.footnote).foregroundStyle(.ariSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Back to where it was made: "From your thread · V&A guide", which opens the thread, or
    /// "From your chat", at the message Kumo was answering.
    @ViewBuilder
    private func backLink(_ page: Made) -> some View {
        if let thread = page.thread, let openThread {
            Button {
                dismiss()
                openThread(thread)
            } label: {
                backLabel(
                    ["From your thread", threadName].compactMap(\.self).joined(separator: " · "))
            }
            .buttonStyle(.plain)
            .task(id: thread) { threadName = await made?.threadName(thread) }
        } else if page.thread == nil, let openInChat {
            Button {
                dismiss()
                openInChat(page.position)
            } label: {
                backLabel("From your chat")
            }
            .buttonStyle(.plain)
        }
    }

    private func backLabel(_ text: String) -> some View {
        Label(text, systemImage: "arrow.turn.up.left")
            .font(.footnote)
            .foregroundStyle(.ariTertiary)
            .lineLimit(1)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private func sections(_ detail: MadeDetail, opened: Set<String>) -> some View {
        let numbers = Self.numbers(detail.content)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(detail.content.sections) { section in
                if section.numbered {
                    MadeSectionView(
                        section: section, number: numbers[section.id] ?? 1, detail: detail,
                        isOpen: opened.contains(section.id),
                        toggle: {
                            withAnimation(.smooth(duration: 0.3)) {
                                var next = opened
                                if next.contains(section.id) {
                                    next.remove(section.id)
                                } else {
                                    next.insert(section.id)
                                }
                                open = next
                            }
                        },
                        tick: tick)
                } else {
                    MadeAside(section: section, detail: detail, tick: tick)
                        .padding(.top, 8)
                }
            }
        }
    }

    private func footer(_ page: Made) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let day = page.forDay.flatMap(MadeLook.day).map { " for \($0)" } ?? ""
            Text("Made by \(LeadName.current)\(day) · on your Made shelf")
                .font(.footnote)
                .foregroundStyle(.ariTertiary)
            Text(
                "\(LeadName.current) keeps this page current. To change it, just say so in the chat."
            )
            .font(.caption)
            .foregroundStyle(.ariTertiary)
        }
        .padding(.top, 6)
    }

    private func tick(_ item: MadeItem, _ done: Bool) {
        Task { _ = await made?.tick(id, item: item.id, done: done) }
    }

    /// Each numbered section's number, counting only numbered ones.
    static func numbers(_ content: MadeContent) -> [String: Int] {
        var numbers: [String: Int] = [:]
        for section in content.sections where section.numbered {
            numbers[section.id] = numbers.count + 1
        }
        return numbers
    }
}

/// What Kumo changed and when: the page is alive.
private struct LivingNote: View {
    let change: MadeChange

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(Color.ariBone).frame(width: 7, height: 7).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text("Updated \(change.at.date.formatted(.relative(presentation: .named)))")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.ariBone)
                Text(change.note)
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(.ariSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ariSurface.opacity(0.6), in: .rect(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A dot for each thing to tick, lit as you tick them.
private struct TickDots: View {
    let total: Int
    let lit: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<min(total, 20), id: \.self) { index in
                Circle()
                    .fill(index < lit ? Color.ariBone : .ariLine)
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }
}

/// One numbered part of a page, such as a room: its number, name and line, with how many you've
/// ticked, and, open, its picture, words and things to tick.
private struct MadeSectionView: View {
    let section: MadeSection
    let number: Int
    let detail: MadeDetail
    let isOpen: Bool
    let toggle: () -> Void
    let tick: (MadeItem, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle().fill(Color.ariLine).frame(height: 1)
            Button(action: toggle) {
                HStack(alignment: .top, spacing: 12) {
                    Text("\(number)")
                        .font(.system(.subheadline, design: .serif).weight(.semibold))
                        .foregroundStyle(.ariBone)
                        .frame(width: 26, height: 26)
                        .overlay(Circle().strokeBorder(Color.ariBone.opacity(0.6), lineWidth: 1))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(section.title)
                                .font(.ariHeading)
                                .foregroundStyle(.ariText)
                                .multilineTextAlignment(.leading)
                            if let badge = section.badge { Badge(text: badge) }
                        }
                        if let line = line {
                            Text(line).font(.footnote).foregroundStyle(.ariTertiary)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.ariTertiary)
                        .rotationEffect(isOpen ? .zero : .degrees(-90))
                        .padding(.top, 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isOpen ? "Open" : "Folded")
            .accessibilityHint(isOpen ? "Folds it" : "Opens it")
            if isOpen {
                SectionBody(section: section, detail: detail, tick: tick)
                    .padding(.leading, 38)
                    .padding(.bottom, 6)
                    .transition(.opacity)
            }
        }
        .padding(.bottom, 12)
    }

    /// "Room 46a–b · 25 min · 2 of 3 spotted".
    private var line: String? {
        let progress = MadeReading.progress(of: section, in: detail.content, state: detail.state)
            .map { "\($0.done) of \($0.of) \((detail.content.check ?? "done").lowercased())" }
        let parts = [section.detail, progress].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// An unnumbered part of a page: a small heading over what it holds, always open.
private struct MadeAside: View {
    let section: MadeSection
    let detail: MadeDetail
    let tick: (MadeItem, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.1)
                .foregroundStyle(.ariTertiary)
                .accessibilityAddTraits(.isHeader)
            SectionBody(section: section, detail: detail, tick: tick)
        }
    }
}

/// What a section holds: its picture, its words with any blocks, and its items.
private struct SectionBody: View {
    let section: MadeSection
    let detail: MadeDetail
    let tick: (MadeItem, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let image = section.image {
                FoundPhoto(photo: image, longest: 1200)
                    .frame(height: 150)
                    .clipShape(.rect(cornerRadius: 16, style: .continuous))
            }
            if let text = section.text {
                ReplyView(document: ReplyDocument(markdown: text), position: .infinity)
            }
            ForEach(section.items) { item in
                ItemRow(
                    item: item, check: detail.content.check, ticked: detail.state.ticks[item.id],
                    tick: tick)
            }
        }
    }
}

/// A thing on a page. With a check word it ticks off: "Spotted it?", then "Spotted at 14:32".
private struct ItemRow: View {
    let item: MadeItem
    let check: String?
    let ticked: Timestamp?
    let tick: (MadeItem, Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let check {
                Button {
                    tick(item, ticked == nil)
                } label: {
                    ZStack {
                        if ticked != nil {
                            Circle().fill(Color.ariBone)
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(.ariBackground)
                        } else {
                            Circle().strokeBorder(Color.ariSecondary, lineWidth: 1.5)
                        }
                    }
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ticked == nil ? "\(check) it?" : "\(check), take it back")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ticked == nil ? Color.ariText : .ariSecondary)
                if let detail = item.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(ticked == nil ? Color.ariSecondary : .ariTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let check {
                    if let ticked {
                        Text("\(check) at \(ticked.date.formatted(.dateTime.hour().minute()))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.ariBone.opacity(0.8))
                    } else {
                        Button {
                            tick(item, true)
                        } label: {
                            Text("\(check) it?")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.ariText)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .overlay(Capsule().strokeBorder(Color.ariLine, lineWidth: 1))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
            }
            Spacer(minLength: 0)
            if let image = item.image {
                FoundPhoto(photo: image, longest: 200)
                    .frame(width: 54, height: 54)
                    .clipShape(.rect(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

/// A word or two Kumo wants seen, such as "Back in", in bone.
private struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.ariBackground)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.ariBone, in: Capsule())
            .fixedSize()
    }
}

// MARK: - The Made shelf

/// The Made shelf, as a navigation value.
struct MadeShelfRoute: Hashable {}

/// The Made shelf's tile in the Library, beside memory's shelves.
struct MadeShelfTile: View {
    let count: Int

    var body: some View {
        NavigationLink(value: MadeShelfRoute()) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    DotGlyph(symbol: "doc.richtext.fill")
                    Spacer(minLength: 4)
                    Text("\(count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.ariTertiary)
                }
                Text("Made")
                    .font(.headline)
                    .foregroundStyle(.ariText)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ariSurface, in: .rect(cornerRadius: 16, style: .continuous))
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Made, \(count) \(count == 1 ? "thing" : "things")")
    }
}

/// Everything Kumo made for you, by when it was made: its pages, and the files it showed you for
/// review, such as a CV. A page opens as it does from the chat, with its way back to where it was
/// made; a document opens in the viewer.
struct MadeShelfView: View {
    @Environment(MadePages.self) private var made: MadePages?
    @State private var opened: MadeID?
    @State private var document: ShownFile?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(
                    "Guides, comparisons, plans and documents \(LeadName.current) made for you. Each opens where it was made."
                )
                .font(.footnote)
                .foregroundStyle(.ariTertiary)
                .padding(.bottom, 22)
                if let made, made.shelfCount > 0 {
                    ForEach(MadeReading.shelf(pages: made.all, documents: made.documents)) {
                        group in
                        Text(group.title)
                            .font(.ariHeading)
                            .foregroundStyle(.ariText)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.bottom, 10)
                        VStack(spacing: 0) {
                            ForEach(group.items) { item in
                                if item.id != group.items.first?.id {
                                    Hairline().padding(.leading, 86)
                                }
                                row(item)
                            }
                        }
                        .background(.ariSurface, in: .rect(cornerRadius: 20, style: .continuous))
                        .padding(.bottom, 26)
                    }
                } else if case .failed(let error) = made?.load {
                    Text("Couldn't reach your server: \(error.plainWords)")
                        .foregroundStyle(.ariSecondary)
                } else {
                    Text(
                        "Nothing yet. When \(LeadName.current) makes you a page, such as a guide for a visit, it's kept here."
                    )
                    .font(.ariBody)
                    .foregroundStyle(.ariTertiary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: Rhythm.column, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(.ariBackground)
        .navigationTitle("Made")
        .navigationBarTitleDisplayMode(.inline)
        .task { await made?.refresh() }
        .refreshable { await made?.refresh() }
        .fullScreenCover(item: $opened) { MadePageView(id: $0) }
        .sheet(item: $document) { file in
            DocumentViewer(file: file, version: file.latest)
                .presentationDetents([.large])
                .preferredColorScheme(.dark)
                .tint(.ariText)
        }
    }

    private func row(_ item: MadeReading.ShelfItem) -> some View {
        Button {
            switch item {
            case .page(let page): opened = page.id
            case .document(let file): document = file
            }
        } label: {
            switch item {
            case .page(let page): MadeShelfRow(page: page)
            case .document(let file): DocumentShelfRow(file: file)
            }
        }
        .buttonStyle(.plain)
    }
}

/// A page on the shelf: its cover, its title, what's in it and when it was made, and Kumo's latest
/// change.
private struct MadeShelfRow: View {
    let page: Made

    var body: some View {
        ShelfRowFrame {
            MadeCover(page: page, longest: 240)
        } words: {
            Text(page.title)
                .font(.ariName)
                .foregroundStyle(.ariText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(
                [page.summary, MadeReading.shelfDay(page.madeAt.date)].filter { !$0.isEmpty }
                    .joined(separator: " · ")
            )
            .font(.caption)
            .foregroundStyle(.ariSecondary)
            .lineLimit(1)
            if page.version > 1 {
                HStack(spacing: 6) {
                    Circle().fill(Color.ariBone).frame(width: 5, height: 5)
                    Text(
                        "Updated \(page.changedAt.date.formatted(.relative(presentation: .named)))")
                }
                .font(.caption)
                .foregroundStyle(.ariBone)
            }
        }
    }
}

/// A file Kumo showed you, on the shelf: its first page, its name, and which version.
private struct DocumentShelfRow: View {
    let file: ShownFile

    @Environment(\.filesActions) private var actions
    @State private var loaded: Loaded?

    var body: some View {
        let latest = file.version(file.latest)
        ShelfRowFrame {
            if let thumbnail = loaded?.thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                ZStack {
                    Rectangle().fill(Color.ariField)
                    Image(systemName: "doc.text").foregroundStyle(.ariTertiary)
                }
            }
        } words: {
            Text(((latest?.attachment.name ?? file.name) as NSString).deletingPathExtension)
                .font(.ariName)
                .foregroundStyle(.ariText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(details)
                .font(.caption)
                .foregroundStyle(.ariSecondary)
                .lineLimit(1)
        }
        .task(id: latest?.attachment.id) {
            guard let latest, let session = actions.session,
                let bytes = await session.bytes(of: latest.attachment.id)
            else { return }
            loaded = await Loaded.read(bytes, mediaType: latest.attachment.mediaType)
        }
    }

    /// "Document · version 2 · 2 pages".
    private var details: String {
        var parts = ["Document"]
        if file.versions.count > 1 { parts.append("version \(file.latest)") }
        if let pages = loaded?.pages { parts.append(pages == 1 ? "1 page" : "\(pages) pages") }
        return parts.joined(separator: " · ")
    }
}

/// A shelf row's shape: a small picture, the words beside it, and a chevron.
private struct ShelfRowFrame<Picture: View, Words: View>: View {
    @ViewBuilder let picture: () -> Picture
    @ViewBuilder let words: () -> Words

    var body: some View {
        HStack(spacing: 16) {
            picture()
                .frame(width: 54, height: 66)
                .clipShape(.rect(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.ariLine.opacity(0.7), lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) { words() }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.ariTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
