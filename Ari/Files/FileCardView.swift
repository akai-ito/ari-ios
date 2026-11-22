import AriKit
import PDFKit
import QuickLook
import SwiftUI

/// A file Kumo made, at one version: its first page, its name, the version and how many pages. A
/// version that's been replaced shows as a quiet row. Tapping opens the viewer. Feedback on it is
/// about this version, and happens by talking in the thread.
struct FileCardView: View {
    let card: ReplyShape.FileCard

    @Environment(\.filesActions) private var actions
    @State private var file: ShownFile?
    @State private var gone = false
    @State private var document: Loaded?
    @State private var opens = false

    var body: some View {
        Group {
            if gone {
                Label("This file was deleted from your server.", systemImage: "doc")
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
            } else if let file, card.version < file.latest {
                Button {
                    opens = true
                } label: {
                    older(file)
                }.buttonStyle(.plain)
            } else {
                Button {
                    opens = true
                } label: {
                    latest
                }.buttonStyle(.plain)
            }
        }
        .task(id: card.file) { await load() }
        .sheet(isPresented: $opens) {
            if let file {
                DocumentViewer(file: file, version: card.version)
                    .presentationDetents([.large])
                    .preferredColorScheme(.dark)
                    .tint(.ariText)
            }
        }
        .accessibilityHint("Opens it")
    }

    private var version: ShownFile.Version? { file?.version(card.version) }

    private var latest: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumbnail = document?.thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 200, height: 283, alignment: .top)
                            .clipShape(.rect(cornerRadius: 3))
                    } else {
                        RoundedRectangle(cornerRadius: 3).fill(Color.ariLine.opacity(0.4))
                            .frame(width: 200, height: 283)
                    }
                }
                .frame(height: 168, alignment: .top)
                .clipped()
                .padding(.top, 16)
                .frame(maxWidth: .infinity)
                .background(Color.ariField)
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [.clear, Color.ariField], startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 36)
                }
                Text("v\(card.version)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.ariBackground)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.ariBone))
                    .padding(10)
            }
            HStack(spacing: 10) {
                Image(systemName: "doc.text").foregroundStyle(.ariSecondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(version?.attachment.name ?? file?.name ?? "A file")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.ariText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.ariTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
        }
        .frame(width: 260)
        .background(Color.ariSurface)
        .clipShape(.rect(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(
                Color.ariLine.opacity(0.7), lineWidth: 1))
    }

    private func older(_ file: ShownFile) -> some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail = document?.thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 3).fill(Color.ariLine.opacity(0.4))
                }
            }
            .frame(width: 30, height: 42)
            .clipShape(.rect(cornerRadius: 3))
            .opacity(0.7)
            VStack(alignment: .leading, spacing: 1) {
                Text(version?.attachment.name ?? file.name)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.ariSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(details + " · replaced")
                    .font(.caption)
                    .foregroundStyle(.ariTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 250)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(
                .ariLine, lineWidth: 1))
    }

    /// "Version 2 · 2 pages · PDF".
    private var details: String {
        var parts = ["Version \(card.version)"]
        if let pages = document?.pages { parts.append(pages == 1 ? "1 page" : "\(pages) pages") }
        if let version { parts.append(Self.kind(of: version.attachment)) }
        return parts.joined(separator: " · ")
    }

    static func kind(of attachment: Attachment) -> String {
        let ext = (attachment.name as NSString).pathExtension.uppercased()
        if attachment.mediaType == "application/pdf" { return "PDF" }
        return ext.isEmpty ? UploadLimits.sizeWords(attachment.size) : ext
    }

    private func load() async {
        guard let session = actions.session else { return }
        do {
            let shown = try await session.shownFile(card.file, refresh: file == nil)
            file = shown
            guard let version = shown.version(card.version) else { return }
            if let bytes = await session.bytes(of: version.attachment.id) {
                document = await Loaded.read(bytes, mediaType: version.attachment.mediaType)
            }
        } catch {
            if error.status == 404 { gone = true }
        }
    }
}

/// A file's bytes, read once: its pages and first page's picture, when it's a PDF.
nonisolated struct Loaded: @unchecked Sendable {
    let pdf: PDFDocument?
    let pages: Int?
    let thumbnail: UIImage?

    @concurrent static func read(_ bytes: Data, mediaType: String) async -> Loaded {
        guard mediaType == "application/pdf", let pdf = PDFDocument(data: bytes) else {
            return Loaded(pdf: nil, pages: nil, thumbnail: nil)
        }
        let thumbnail = pdf.page(at: 0)?.thumbnail(
            of: CGSize(width: 400, height: 566), for: .mediaBox)
        return Loaded(pdf: pdf, pages: pdf.pageCount, thumbnail: thumbnail)
    }
}

/// The file open over its thread: its pages to scroll and pinch, which version, share, and Use in
/// draft, which asks Kumo to attach exactly this version to the draft it's for. Kumo never sends.
struct DocumentViewer: View {
    let file: ShownFile
    @State var version: Int

    @Environment(\.filesActions) private var actions
    @Environment(\.dismiss) private var dismiss
    @State private var document: Loaded?
    @State private var page = 1
    @State private var shared: URL?
    @State private var looking: URL?

    init(file: ShownFile, version: Int) {
        self.file = file
        _version = State(initialValue: version)
    }

    private var current: ShownFile.Version? { file.version(version) }

    var body: some View {
        NavigationStack {
            pages
                .background(Color(red: 0.09, green: 0.1, blue: 0.115))
                .overlay(alignment: .top) {
                    if let count = document?.pages, count > 1 {
                        Text("Page \(page) of \(count)")
                            .font(.caption.weight(.medium).monospacedDigit())
                            .foregroundStyle(.ariSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .glassEffect(.regular, in: Capsule())
                            .padding(.top, 8)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { useInDraft }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done", systemImage: "xmark") { dismiss() }
                    }
                    ToolbarItem(placement: .principal) { title }
                    ToolbarItem(placement: .primaryAction) {
                        if let shared {
                            ShareLink(item: shared) { Image(systemName: "square.and.arrow.up") }
                                .accessibilityLabel("Share")
                        }
                    }
                }
        }
        .task(id: version) { await load() }
        .quickLookPreview($looking)
    }

    private var title: some View {
        Menu {
            Picker("Version", selection: $version) {
                ForEach(file.versions.reversed(), id: \.version) { each in
                    Text(
                        each.note.map { "Version \(each.version): \($0)" }
                            ?? "Version \(each.version)"
                    )
                    .tag(each.version)
                }
            }
        } label: {
            VStack(spacing: 2) {
                Text(((current?.attachment.name ?? file.name) as NSString).deletingPathExtension)
                    .font(.ariName)
                    .foregroundStyle(.ariText)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text("Version \(version) of \(file.latest)")
                    if file.versions.count > 1 {
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                }
                .font(.caption)
                .foregroundStyle(.ariSecondary)
            }
        }
        .disabled(file.versions.count < 2)
    }

    @ViewBuilder
    private var pages: some View {
        if let pdf = document?.pdf {
            PDFPages(document: pdf, page: $page)
        } else if document != nil, let current {
            VStack(spacing: 14) {
                Image(systemName: "doc").font(.largeTitle).foregroundStyle(.ariSecondary)
                Text(current.attachment.name).font(.subheadline).foregroundStyle(.ariText)
                SmallPill(title: "Preview", acts: true) { looking = shared }
                    .disabled(shared == nil)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView().tint(.ariSecondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var useInDraft: some View {
        VStack(spacing: 8) {
            Button {
                send()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "envelope")
                    Text("Use in draft")
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(.ariBackground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(Color.ariText))
            }
            .buttonStyle(.plain)
            .disabled(actions.session == nil || current == nil)
            Text(
                "Attaches version \(version) to the draft \(LeadName.current)'s writing with it. "
                    + "To change it, tell \(LeadName.current) in the thread."
            )
            .font(.caption)
            .foregroundStyle(.ariTertiary)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(Color.ariBackground)
    }

    /// Asks Kumo to attach exactly this version: your message says it, with the version in a block.
    private func send() {
        guard let current else { return }
        actions.send(
            .attach(YourTap.Attach(file: file.id, version: version)),
            saying: "Use version \(version) of \(current.attachment.name) in the draft")
        dismiss()
    }

    private func load() async {
        guard let current, let session = actions.session,
            let bytes = await session.bytes(of: current.attachment.id)
        else { return }
        document = await Loaded.read(bytes, mediaType: current.attachment.mediaType)
        page = 1
        // A copy under its own name, to share or preview.
        let folder = URL.temporaryDirectory.appending(path: "Shown/\(current.attachment.id)")
        let url = folder.appending(
            path: current.attachment.name.replacingOccurrences(of: "/", with: "-"))
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if (try? bytes.write(to: url, options: .atomic)) != nil { shared = url }
    }
}

/// A PDF's pages, one under another, to scroll and pinch, saying which page is on screen.
private struct PDFPages: UIViewRepresentable {
    let document: PDFDocument
    @Binding var page: Int

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.autoScales = true
        view.pageShadowsEnabled = true
        view.backgroundColor = UIColor(red: 0.09, green: 0.1, blue: 0.115, alpha: 1)
        view.document = document
        context.coordinator.watch(view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document {
            view.document = document
            view.autoScales = true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(page: $page) }

    final class Coordinator {
        let page: Binding<Int>
        // Only set once, on the main actor, and read as the coordinator goes.
        nonisolated(unsafe) private var observer: (any NSObjectProtocol)?

        init(page: Binding<Int>) { self.page = page }

        func watch(_ view: PDFView) {
            observer = NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged, object: view, queue: .main
            ) { [weak self, weak view] _ in
                MainActor.assumeIsolated {
                    guard let view, let current = view.currentPage,
                        let index = view.document?.index(for: current)
                    else { return }
                    self?.page.wrappedValue = index + 1
                }
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
