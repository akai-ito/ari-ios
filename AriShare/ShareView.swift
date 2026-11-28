import AriKit
import SwiftUI

/// The share sheet in Ari's look: what you're sharing, your thought, and Send. Once it's gone, the
/// sheet stays a few seconds for Kumo's answer and says which thread it's in.
struct ShareView: View {
    @Bindable var model: ShareModel
    @FocusState private var writing: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let recording = model.recording {
                        RecordingItem(name: recording.name, detail: recording.detail)
                    }
                    if let link = model.link {
                        LinkItem(url: link, title: model.linkTitle, image: model.linkImage)
                    }
                    if !model.attachments.isEmpty, model.recording == nil {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(model.attachments) { attachment in
                                    SharedItem(attachment: attachment)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                    ForEach(model.texts, id: \.self) { words in
                        Text(words)
                            .font(.subheadline)
                            .foregroundStyle(.ariSecondary)
                            .lineLimit(4)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                .ariSurface, in: .rect(cornerRadius: 14, style: .continuous))
                    }
                    if model.isAnswering {
                        sent
                    } else {
                        writingNote
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(.ariBackground)
            .animation(.easeInOut(duration: 0.25), value: model.state)
            .navigationTitle("Share with \(LeadName.current)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .preferredColorScheme(.dark)
        .tint(.ariText)
        .onAppear { writing = true }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if model.isAnswering {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: model.done)
                    .fontWeight(.semibold)
            }
        } else {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: model.cancel)
                    .disabled(model.state == .sending)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Send", action: model.send)
                    .fontWeight(.semibold)
                    .disabled(!model.canSend)
            }
        }
    }

    /// Before Send: your thought, and where Kumo will answer.
    @ViewBuilder
    private var writingNote: some View {
        TextField(
            "", text: $model.note,
            prompt: Text("Add a thought for \(LeadName.current)").foregroundStyle(.ariTertiary),
            axis: .vertical
        )
        .lineLimit(1...5)
        .focused($writing)
        .foregroundStyle(.ariText)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.ariLine, lineWidth: 1))
        if let line = statusLine {
            Text(line)
                .font(.footnote)
                .foregroundStyle(.ariSecondary)
                .transition(.opacity)
        } else if model.recording == nil, model.isConnected {
            Text(
                "\(LeadName.current) answers in a thread about this, or in the one it belongs to."
            )
            .font(.footnote)
            .foregroundStyle(.ariTertiary)
        }
        if model.recording != nil, model.state == .ready {
            whatHappens
        }
    }

    /// After Send: your thought as sent, then Kumo's answer, or where it's coming.
    @ViewBuilder
    private var sent: some View {
        let note = model.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            Text(note)
                .font(.subheadline)
                .foregroundStyle(.ariSecondary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 40)
        }
        switch model.state {
        case .replied(let reply):
            Answer(reply: reply, open: model.openThread)
                .transition(.opacity)
        case .answering(let reply):
            Waiting(
                thread: reply.map { ($0.title, $0.thread) },
                words: reply == nil
                    ? "\(LeadName.current)'s reading it…"
                    : nil)
        case .handedOff(let reply):
            Waiting(
                thread: reply.map { ($0.title, $0.thread) },
                words:
                    "\(LeadName.current)'s still on it. Its answer comes as a notification.",
                isDone: true)
        default:
            EmptyView()
        }
    }

    /// Plainly what happens next, and the limits, before you tap Send.
    private var whatHappens: some View {
        let transcription = model.limits?.transcription
        let limit = model.limits?.limits.kind(.audio)?.maxBytes
        return VStack(alignment: .leading, spacing: 12) {
            next("icloud.and.arrow.up", "Uploads in the background, so you can close this.")
            if let transcription, !transcription.isReady {
                next(
                    "text.badge.xmark",
                    "Your server can't transcribe right now"
                        + (transcription.reason.map { ": \($0)" } ?? "")
                        + ". It waits, and starts when it can.")
            } else {
                next("text.quote", "Your server transcribes it, a few minutes for most.")
            }
            next(
                "bubble.left",
                "\(LeadName.current) listens, then answers with what it heard.")
            if let consent = transcription?.consent {
                Text(consent).font(.caption).foregroundStyle(.ariTertiary)
            }
            Text(
                (limit.map { "Recordings up to \(UploadLimits.sizeWords($0)). " } ?? "")
                    + "Audio and transcript stay on your server; delete them any time."
            )
            .font(.caption)
            .foregroundStyle(.ariTertiary)
        }
    }

    private func next(_ symbol: String, _ words: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(.ariSecondary)
                .frame(width: 18)
            Text(words).font(.footnote).foregroundStyle(.ariSecondary)
        }
    }

    private var statusLine: String? {
        guard model.isConnected else {
            return "Open Ito and connect it to your server first."
        }
        switch model.state {
        case .reading, .ready, .answering, .replied, .handedOff: return nil
        case .sending: return "Sending…"
        case .sent:
            return model.big == nil
                ? "Sent to \(LeadName.current)."
                : "Uploading in the background. \(LeadName.current) answers once it's heard it."
        case .waiting(let words): return words
        case .problem(let words): return words
        }
    }
}

/// Kumo, small, as the app's icon draws it at rest.
private struct KumoMark: View {
    var body: some View {
        Image("IconPreviewRest")
            .resizable()
            .scaledToFill()
            .frame(width: 28, height: 28)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}

/// "Kumo replied in Shoes thread", or in a new thread it hasn't named yet.
private func repliedLine(_ lead: String, verb: String, title: String?) -> Text {
    guard let title else {
        return Text("\(lead) \(verb) in a new thread").foregroundStyle(.ariSecondary)
    }
    return Text(
        "\(Text("\(lead) \(verb) in ").foregroundStyle(.ariSecondary))\(Text(title).fontWeight(.semibold).foregroundStyle(.ariText))\(Text(" thread").foregroundStyle(.ariSecondary))"
    )
}

/// Kumo's answer, while the sheet is still open: which thread, its first words, and the way there.
private struct Answer: View {
    let reply: ShareReply
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                KumoMark()
                repliedLine(LeadName.current, verb: "replied", title: reply.title)
                    .font(.subheadline)
                    .lineLimit(2)
            }
            Text(Self.markdown(reply.text ?? ""))
                .font(.system(.body, design: .serif))
                .foregroundStyle(.ariText)
                .lineSpacing(5)
                .lineLimit(8)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: open) {
                Text("Open the thread")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.ariBackground)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ariText, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ariSurface, in: .rect(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.ariLine, lineWidth: 1)
        )
        .padding(.top, 6)
        .accessibilityElement(children: .contain)
    }

    /// Kumo's words with their emphasis and links, as one paragraph.
    private static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

/// Kumo hasn't answered yet: reading the share, writing in its thread, or, once the sheet stops
/// waiting, answering by notification.
private struct Waiting: View {
    let thread: (title: String?, id: ThreadID)?
    let words: String?
    var isDone = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                KumoMark()
                if let thread {
                    repliedLine(
                        LeadName.current, verb: isDone ? "is answering" : "is writing",
                        title: thread.title
                    )
                    .font(.subheadline)
                    .lineLimit(2)
                } else if let words {
                    Text(words).font(.subheadline).foregroundStyle(.ariSecondary)
                }
                Spacer(minLength: 0)
                if !isDone { ProgressView().controlSize(.small) }
            }
            if thread != nil, let words {
                Text(words).font(.footnote).foregroundStyle(.ariTertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ariSurface, in: .rect(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.ariLine, lineWidth: 1)
        )
        .padding(.top, 6)
    }
}

/// The link you're sharing: the page's picture when the app gave one, its title, and its site.
private struct LinkItem: View {
    let url: URL
    let title: String?
    let image: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "link")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.ariSecondary)
                }
            }
            .frame(width: 52, height: 52)
            .background(.ariField)
            .clipShape(.rect(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title ?? host)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.ariText)
                    .lineLimit(2)
                Text(host).font(.caption).foregroundStyle(.ariTertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.ariLine, lineWidth: 1))
    }

    private var host: String {
        guard let host = url.host() else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// A recording you're sharing: a waveform mark, its name, how long and how big.
private struct RecordingItem: View {
    let name: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.ariBone)
                .frame(width: 40, height: 40)
                .background(Color.ariBone.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text((name as NSString).deletingPathExtension)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.ariText)
                    .lineLimit(2)
                Text(detail).font(.caption).foregroundStyle(.ariTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.ariLine, lineWidth: 1))
    }
}

/// A photo or file you're sharing.
private struct SharedItem: View {
    let attachment: PendingAttachment

    var body: some View {
        if attachment.attachment.kind == .image,
            let image = AttachmentMaker.image(from: attachment.bytes, longest: 240)
        {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
        } else {
            HStack(spacing: 8) {
                Image(systemName: "doc").foregroundStyle(.ariSecondary)
                Text(attachment.name)
                    .font(.footnote)
                    .foregroundStyle(.ariText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 12)
            .frame(height: 72)
            .frame(maxWidth: 180)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.ariLine, lineWidth: 1))
        }
    }
}
