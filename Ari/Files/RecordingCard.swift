import AriKit
import SwiftUI

/// A recording on your message. While it goes up and the server listens: its name and size, the
/// bar, and the three steps it goes through (Upload, Transcript, Kumo's take). Once transcribed, a
/// compact row that opens the transcript with its player. It says plainly when it failed, with Try
/// again, or when its audio was deleted.
struct RecordingCard: View {
    let attachment: Attachment

    @Environment(\.filesActions) private var actions
    @Environment(BigUploads.self) private var uploads: BigUploads?
    @State private var retrying = false

    var body: some View {
        let recording = actions.session?.recordings[attachment.id]
        let upload = uploads?.uploads[attachment.id]
        Group {
            if let upload, upload.isSending || recording == nil && !upload.isFinished {
                card(step: .upload, upload: upload, recording: nil)
            } else if let recording {
                switch recording.state {
                case .ready: ready(recording)
                case .deleted: deleted
                case .failed: failed(recording)
                default: card(step: .transcript, upload: upload, recording: recording)
                }
            } else {
                // Sent from this phone a moment ago, or from before Ari opened: the server says.
                card(step: .transcript, upload: upload, recording: nil)
            }
        }
        .task(id: attachment.id) {
            if recording == nil, upload?.isSending != true {
                await actions.session?.refreshRecording(attachment.id)
            }
        }
    }

    private var name: String {
        let stem = (attachment.name as NSString).deletingPathExtension
        return stem.isEmpty ? attachment.name : stem
    }

    private enum Step: Int {
        case upload, transcript, take
    }

    // MARK: - On its way

    private func card(step: Step, upload: BigUpload?, recording: Recording?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                DotGlyph(symbol: "waveform", side: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.ariText)
                        .lineLimit(2)
                    Text(sizeLine(upload: upload, recording: recording))
                        .font(.caption)
                        .foregroundStyle(.ariTertiary)
                }
            }
            if case .refused(let error) = upload?.state {
                Text("Your server didn't take it. \(error.message)")
                    .font(.caption)
                    .foregroundStyle(.ariSecondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    bar(progress(step: step, upload: upload, recording: recording))
                    HStack(alignment: .firstTextBaseline) {
                        Text(statusLine(step: step, upload: upload, recording: recording))
                            .foregroundStyle(.ariSecondary)
                            .lineLimit(2)
                        Spacer(minLength: 6)
                        if step == .upload, let upload {
                            ETA(upload: upload, sent: uploads?.sent(upload.id) ?? 0)
                        }
                    }
                    .font(.caption.monospacedDigit())
                }
                HStack(spacing: 6) {
                    stepMark("Upload", step, .upload)
                    dash
                    stepMark("Transcript", step, .transcript)
                    dash
                    stepMark("Kumo's take", step, .take)
                }
                if step == .upload {
                    Text(keepsGoing)
                        .font(.caption2)
                        .foregroundStyle(.ariTertiary)
                }
            }
        }
        .padding(14)
        .frame(width: 270, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(
                .ariLine, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    /// The limit, in the server's own numbers, under a recording going up.
    private var keepsGoing: String {
        let limit = actions.session?.knownUploadLimits?.limits.kind(.audio)?.maxBytes
        return "Keeps going if you leave Ito"
            + (limit.map { " · recordings up to \(UploadLimits.sizeWords($0))" } ?? "")
    }

    private func sizeLine(upload: BigUpload?, recording: Recording?) -> String {
        let seconds = recording?.durationSeconds ?? upload?.durationSeconds
        return
            ([seconds.map(durationWords)].compactMap(\.self)
            + [UploadLimits.sizeWords(upload?.size ?? attachment.size)])
            .joined(separator: " · ")
    }

    private func progress(step: Step, upload: BigUpload?, recording: Recording?) -> Double {
        switch step {
        case .upload:
            guard let upload, upload.size > 0 else { return 0 }
            return Double(uploads?.sent(upload.id) ?? upload.received) / Double(upload.size)
        default:
            return recording?.progress?.fraction ?? 0
        }
    }

    private func statusLine(step: Step, upload: BigUpload?, recording: Recording?) -> String {
        if step == .upload, let upload {
            let sent = uploads?.sent(upload.id) ?? upload.received
            return "Uploading · \(megabytes(sent)) of \(UploadLimits.sizeWords(upload.size))"
        }
        guard let recording else { return "Your server has it" }
        switch recording.state {
        case .transcribing:
            guard let done = recording.progress else { return "Transcribing" }
            if let total = done.totalSeconds, total > 0 {
                return
                    "Transcribing · \(durationWords(done.doneSeconds)) of \(durationWords(total))"
            }
            return "Transcribing · \(durationWords(done.doneSeconds)) heard"
        case .queued:
            return recording.reason.map { "Waiting: \($0)" } ?? "Waiting its turn to be transcribed"
        default:
            return "Your server has it"
        }
    }

    private func megabytes(_ bytes: Int) -> String {
        "\(bytes / (1024 * 1024))"
    }

    private func bar(_ fraction: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.ariLine)
                Capsule().fill(Color.ariBone)
                    .frame(width: geometry.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 3)
        .animation(.easeOut(duration: 0.3), value: fraction)
    }

    private func stepMark(_ title: String, _ now: Step, _ step: Step) -> some View {
        let lit = now == step
        let done = step.rawValue < now.rawValue
        return HStack(spacing: 5) {
            Circle()
                .fill(lit || done ? Color.ariBone : .clear)
                .overlay(
                    Circle().strokeBorder(lit || done ? Color.ariBone : .ariTertiary, lineWidth: 1)
                )
                .frame(width: 6, height: 6)
            Text(title)
                .font(.caption2.weight(lit ? .semibold : .regular))
                .foregroundStyle(lit ? .ariText : done ? .ariSecondary : .ariTertiary)
        }
    }

    private var dash: some View {
        Rectangle().fill(Color.ariLine).frame(width: 10, height: 1)
    }

    // MARK: - Transcribed

    /// The recording, once the server has heard it: play it in its transcript.
    private func ready(_ recording: Recording) -> some View {
        Button {
            actions.openTranscript(attachment.id, nil)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.ariText)
                    .frame(width: 34, height: 34)
                    .overlay(Circle().strokeBorder(.ariLine, lineWidth: 1))
                VStack(alignment: .leading, spacing: 5) {
                    DotWaveform(played: 0, bars: 34, seed: stableSeed(attachment.id.rawValue))
                        .frame(height: 18)
                    Text(
                        [name, recording.durationSeconds.map(RecordingLink.clock)]
                            .compactMap(\.self).joined(separator: " · ")
                    )
                    .font(.caption)
                    .foregroundStyle(.ariTertiary)
                    .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: 250)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(
                    .ariLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name), recording")
        .accessibilityHint("Opens its transcript")
    }

    private func failed(_ recording: Recording) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                DotGlyph(symbol: "waveform", side: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(.ariText)
                    Text("Couldn't be transcribed")
                        .font(.caption)
                        .foregroundStyle(.ariTertiary)
                }
            }
            Text(recording.error?.message ?? "Your server couldn't hear it.")
                .font(.caption)
                .foregroundStyle(.ariSecondary)
            HStack {
                Spacer()
                SmallPill(title: retrying ? "Trying" : "Try again", acts: true) {
                    retrying = true
                    Task {
                        try? await actions.session?.retryRecording(attachment.id)
                        retrying = false
                    }
                }
                .disabled(retrying || actions.session == nil)
            }
        }
        .padding(14)
        .frame(width: 270, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(
                .ariLine, lineWidth: 1))
    }

    private var deleted: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.slash").foregroundStyle(.ariTertiary)
            Text("\(name) · deleted from your server")
                .font(.footnote)
                .foregroundStyle(.ariTertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(
                .ariLine, lineWidth: 1))
    }
}

extension BigUpload {
    var isFinished: Bool {
        if case .finished = state { true } else { false }
    }
}

/// How long the rest of an upload will take, at the speed it's going: "about a minute".
private struct ETA: View {
    let upload: BigUpload
    let sent: Int

    @State private var samples: [(at: Date, sent: Int)] = []

    var body: some View {
        Text(words ?? "")
            .foregroundStyle(.ariTertiary)
            .onChange(of: sent, initial: true) { _, sent in
                samples.append((.now, sent))
                samples.removeAll { Date.now.timeIntervalSince($0.at) > 20 }
            }
    }

    private var words: String? {
        guard let first = samples.first, let last = samples.last, last.at > first.at,
            last.sent > first.sent
        else { return nil }
        let rate = Double(last.sent - first.sent) / last.at.timeIntervalSince(first.at)
        let left = Double(upload.size - last.sent) / rate
        switch left {
        case ..<45: return "a few seconds"
        case ..<90: return "about a minute"
        case ..<3600: return "about \(Int((left / 60).rounded())) minutes"
        default: return "over an hour"
        }
    }
}
