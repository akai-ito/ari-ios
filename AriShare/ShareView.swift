import AriKit
import SwiftUI

/// The share sheet in Ari's look: what you're sharing, a note, and Send.
struct ShareView: View {
    @Bindable var model: ShareModel
    @FocusState private var writing: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if !model.attachments.isEmpty {
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
                    prompt: Text("Add a note for Ari").foregroundStyle(.ariTertiary),
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
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.ariBackground)
            .animation(.easeInOut(duration: 0.25), value: model.state)
            .navigationTitle("Share with Ari")
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

    private var statusLine: String? {
        guard model.isConnected else {
            return "Open Ari and connect it to your server first."
        }
        switch model.state {
        case .reading: return nil
        case .ready: return nil
        case .sending: return "Sending…"
        case .sent: return "Sent to Ari."
        case .waiting: return "Ari will send this the next time it opens."
        case .problem(let words): return words
        }
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
