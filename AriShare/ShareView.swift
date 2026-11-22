import AriKit
import SwiftUI

/// The share sheet in Ari's look: what you're sharing, a note, and Send.
struct ShareView: View {
    @Bindable var model: ShareModel
    @FocusState private var writing: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if let recording = model.recording {
                    RecordingItem(name: recording.name, detail: recording.detail)
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
                ForEach(model.words, id: \.self) { words in
                    Text(words)
                        .font(.subheadline)
                        .foregroundStyle(.ariSecondary)
                        .lineLimit(4)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ariSurface, in: .rect(cornerRadius: 14, style: .continuous))
                }
                TextField(
                    "", text: $model.note,
                    prompt: Text("Add a note for \(LeadName.current)").foregroundStyle(
                        .ariTertiary),
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
                }
                if model.recording != nil, model.state == .ready {
                    whatHappens
                }
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.ariBackground)
            .animation(.easeInOut(duration: 0.25), value: model.state)
            .navigationTitle("Share with \(LeadName.current)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
        .preferredColorScheme(.dark)
        .tint(.ariText)
        .onAppear { writing = true }
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
        case .reading: return nil
        case .ready: return nil
        case .sending: return "Sending…"
        case .sent:
            return model.big == nil
                ? "Sent to \(LeadName.current)."
                : "Uploading in the background. \(LeadName.current) answers once it's heard it."
        case .waiting: return "Ito will send this the next time it opens."
        case .problem(let words): return words
        }
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
