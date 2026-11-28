import AVFoundation
import AriKit
import SwiftUI

/// What tapping Kumo opens: Getting to know you, the areas Kumo is learning as nine-dot bars, and
/// Understanding you, the few things it would still like you to explain, quietly. No counts that
/// nag, nothing overdue: at most three open questions, the ones you set aside last, and what was
/// settled lately behind a link.
struct KnowYouPage: View {
    let session: Session
    let mood: FaceMood
    #if DEBUG
        /// Opens the first question at once, for a still.
        var opensQuestion = false
    #endif

    @Environment(UnderstandingYou.self) private var understanding: UnderstandingYou?
    @State private var work: KumoWork?
    @State private var asking: Question?
    @State private var path: [Route] = []

    enum Route: Hashable {
        case track(TrackID)
        case settled
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    header
                    OfflineLine()
                    if !tracks.isEmpty {
                        VStack(spacing: 14) {
                            ForEach(tracks) { track in
                                NavigationLink(value: Route.track(track.id)) {
                                    TrackRow(track: track)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else if work == nil, understanding?.current == nil {
                        ProgressView().tint(.ariSecondary).frame(maxWidth: .infinity)
                    } else {
                        Text(
                            "I'm only starting to learn how you like things done. It'll show here."
                        )
                        .font(.footnote)
                        .foregroundStyle(.ariTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    // A server without Understanding you shows none of it.
                    if let understanding, understanding.current != nil { questions(understanding) }
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 40)
                .frame(maxWidth: Rhythm.column, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(.ariBackground)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .track(let id):
                    if let track = tracks.first(where: { $0.id == id }) { TrackView(track: track) }
                case .settled:
                    SettledQuestions(questions: understanding?.settled ?? [])
                }
            }
        }
        .sheet(item: $asking) { question in
            QuestionSheet(question: question)
                .presentationDetents([.fraction(0.82), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ariBackground)
                .environment(understanding)
        }
        .task { await understanding?.refresh() }
        .task { work = try? await session.work() }
        #if DEBUG
            .task {
                try? await Task.sleep(for: .milliseconds(900))
                if opensQuestion { asking = understanding?.shown().first }
            }
        #endif
    }

    /// The tracks, from Understanding you, or from today's work on a server without it.
    private var tracks: [Track] {
        if let tracks = understanding?.current?.tracks, !tracks.isEmpty { return tracks }
        return work?.tracks ?? []
    }

    private var header: some View {
        HStack(spacing: 6) {
            KumoFace(mood: mood, size: 50).frame(width: 60)
            Text("Getting to know you")
                .font(.ariHeading)
                .foregroundStyle(.ariText)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func questions(_ understanding: UnderstandingYou) -> some View {
        let shown = understanding.shown()
        let settled = understanding.settled
        return VStack(alignment: .leading, spacing: 14) {
            DeskSectionLabel("Understanding you")
            if shown.isEmpty {
                Text("Nothing I'd ask right now.")
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
            }
            ForEach(shown) { question in
                OpenQuestionCard(question: question) { asking = question }
            }
            if !settled.isEmpty {
                Button {
                    path.append(.settled)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark").font(.caption2.weight(.bold))
                        Text("Settled lately: \(settled.count)")
                        Image(systemName: "chevron.right").imageScale(.small)
                    }
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            if !shown.isEmpty {
                Text("No rush on any of these. I'll sometimes ask in passing, one at a time.")
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
            }
        }
    }
}

/// One open question, quietly: what Kumo knows, small; the piece it's missing, in serif; and why it
/// would help. No badge, no date, nothing overdue.
struct OpenQuestionCard: View {
    let question: Question
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(question.understood)
                        .font(.footnote)
                        .foregroundStyle(.ariTertiary)
                        .lineLimit(2)
                    Text(question.missing)
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(.ariText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(question.why)
                        .font(.footnote)
                        .foregroundStyle(.ariSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let unheard = question.unheard {
                        Text(unheard).font(.footnote).foregroundStyle(.ariTertiary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.ariTertiary)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(
                    Color.ariBone.opacity(0.06))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Answer it, or leave it for now")
    }
}

/// Answering a question: what Kumo understands, the missing piece, large, and why it would help;
/// quick taps (one or several), your own words or your voice, and the gentle ways out: Not now,
/// None fit, Not sure.
struct QuestionSheet: View {
    let question: Question

    @Environment(UnderstandingYou.self) private var understanding: UnderstandingYou?
    @Environment(Voices.self) private var voices: Voices?
    @Environment(\.dismiss) private var dismiss
    @State private var picked: [String] = []
    @State private var words = ""
    @State private var sending = DeskSending()
    @State private var recorder = AnswerRecorder()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                part("What I understand") {
                    Text(question.understood)
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(.ariSecondary)
                        .lineSpacing(3)
                }
                part("The missing piece") {
                    Text(question.missing)
                        .font(.system(.title2, design: .serif))
                        .foregroundStyle(.ariText)
                }
                part("Why it'd help") {
                    Text(question.why)
                        .font(.subheadline)
                        .foregroundStyle(.ariSecondary)
                }
                if !question.options.isEmpty { options }
                field
                if let problem = sending.problem ?? recorder.problem {
                    DeskProblemLine(text: problem)
                }
                ways
            }
            .padding(.horizontal, 22)
            .padding(.top, 30)
            .padding(.bottom, 30)
            .frame(maxWidth: Rhythm.column, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(.ariBackground)
        .onDisappear { recorder.cancel() }
    }

    private func part(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DeskSectionLabel(label)
            content().fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Kumo's honest possibilities: tap one or several.
    private var options: some View {
        WrappingStack(spacing: 8) {
            ForEach(question.options, id: \.self) { option in
                let on = picked.contains(option)
                Button {
                    if on { picked.removeAll { $0 == option } } else { picked.append(option) }
                } label: {
                    Text(option)
                        .font(.subheadline)
                        .foregroundStyle(on ? Color.ariBackground : .ariText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background {
                            if on {
                                Capsule().fill(Color.ariText)
                            } else {
                                Capsule().strokeBorder(Color.ariLine, lineWidth: 1)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(sending.isSending)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private var typed: String? {
        let trimmed = InlineField.trimmed(words)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Your own words, or your voice where the server can hear it; Send once there's an answer.
    private var field: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if recorder.isRecording {
                HStack(spacing: 10) {
                    Circle().fill(Color.ariBone).frame(width: 8, height: 8)
                    Text("Listening… tap to send")
                        .font(.subheadline)
                        .foregroundStyle(.ariSecondary)
                    Spacer(minLength: 0)
                    Button("Cancel") { recorder.cancel() }
                        .font(.footnote)
                        .foregroundStyle(.ariTertiary)
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(
                        .ariLine, lineWidth: 1))
            } else {
                TextField("Or write it", text: $words, axis: .vertical)
                    .font(.subheadline)
                    .foregroundStyle(.ariText)
                    .lineLimit(1...5)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(.ariLine, lineWidth: 1))
            }
            if !picked.isEmpty || typed != nil {
                DeskPill(title: "Send", acts: true, busy: sending.key == "answer") {
                    reply(QuestionReply(picked: picked, text: typed), key: "answer")
                }
                .disabled(sending.isSending)
                .waitsForConnection()
            } else if voices?.canTalk == true {
                // The server hears a spoken answer on its own voice: only while that's running.
                Button {
                    Task { await voice() }
                } label: {
                    Image(systemName: recorder.isRecording ? "arrow.up" : "waveform")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.ariText)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: Circle())
                        .overlay {
                            if sending.key == "voice" { ProgressView().controlSize(.small) }
                        }
                }
                .buttonStyle(.plain)
                .disabled(sending.isSending)
                .waitsForConnection()
                .accessibilityLabel(recorder.isRecording ? "Send your answer" : "Answer aloud")
            }
        }
    }

    /// Not now leaves it open; None fit and Not sure close it, with your words if you wrote any.
    private var ways: some View {
        HStack(spacing: 22) {
            Button("Not now") {
                Task {
                    let done = await sending.send("later", failure: "Couldn't set it aside") {
                        _ = try await understanding?.notNow(question.id)
                    }
                    if done { dismiss() }
                }
            }
            Button("None fit") { reply(QuestionReply(text: typed, noneFit: true), key: "none") }
            Button("Not sure") { reply(QuestionReply(text: typed, notSure: true), key: "unsure") }
        }
        .font(.subheadline)
        .foregroundStyle(.ariSecondary)
        .buttonStyle(.plain)
        .disabled(sending.isSending || recorder.isRecording)
        .waitsForConnection()
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func reply(_ reply: QuestionReply, key: String) {
        Task {
            let done = await sending.send(key, failure: "Couldn't send your answer") {
                _ = try await understanding?.answer(question.id, reply)
            }
            if done { dismiss() }
        }
    }

    /// Starts listening, or stops and sends what you said.
    private func voice() async {
        guard recorder.isRecording else {
            await recorder.start()
            return
        }
        guard let bytes = recorder.finish() else { return }
        let done = await sending.send("voice", failure: "Couldn't send your answer") {
            _ = try await understanding?.answer(question.id, recording: bytes)
        }
        if done { dismiss() }
    }
}

/// Records a spoken answer as AAC in an M4A file, which the server hears on its own voice.
@Observable
final class AnswerRecorder {
    private(set) var isRecording = false
    private(set) var problem: String?
    @ObservationIgnored private var recorder: AVAudioRecorder?

    private var file: URL {
        FileManager.default.temporaryDirectory.appending(path: "answer.m4a")
    }

    func start() async {
        problem = nil
        guard await AVAudioApplication.requestRecordPermission() else {
            problem = "Ito can't hear you: allow the microphone in Settings, or write it instead."
            return
        }
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .spokenAudio)
            try audio.setActive(true)
            let recorder = try AVAudioRecorder(
                url: file,
                settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 22_050,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
                ])
            guard recorder.record(forDuration: 120) else {
                problem = "Couldn't start listening. Write it instead."
                return
            }
            self.recorder = recorder
            isRecording = true
        } catch {
            problem = "Couldn't start listening. Write it instead."
        }
    }

    /// Stops and hands back what was said, or `nil` if there's nothing.
    func finish() -> Data? {
        recorder?.stop()
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard let bytes = try? Data(contentsOf: file), bytes.count > 1_000 else {
            problem = "That was too short to hear. Try again, or write it."
            return nil
        }
        try? FileManager.default.removeItem(at: file)
        return bytes
    }

    func cancel() {
        recorder?.stop()
        recorder?.deleteRecording()
        recorder = nil
        if isRecording {
            try? AVAudioSession.sharedInstance().setActive(
                false, options: .notifyOthersOnDeactivation)
        }
        isRecording = false
    }
}

/// What was answered or settled lately, newest first: the question, and what Kumo took from it or
/// where it learned the answer.
struct SettledQuestions: View {
    let questions: [Question]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(questions) { question in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(question.missing)
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(.ariText)
                            .fixedSize(horizontal: false, vertical: true)
                        if let line = Self.line(question) {
                            Text(line)
                                .font(.footnote)
                                .foregroundStyle(.ariSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(question.changedAt.date.formatted(DeskTime.weekdayDayMonth))
                            .font(.caption)
                            .foregroundStyle(.ariTertiary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 40)
            .frame(maxWidth: Rhythm.column, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(.ariBackground)
        .navigationTitle("Settled lately")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    /// What Kumo took from your answer, where it learned it, or what you said.
    static func line(_ question: Question) -> String? {
        if let filed = question.filed { return filed }
        if let note = question.note { return note }
        guard let answer = question.answer else { return nil }
        var parts = answer.picked
        if let text = answer.text { parts.append("“\(text)”") }
        if answer.noneFit { parts.append("None fit") }
        if answer.notSure { parts.append("Not sure") }
        return parts.isEmpty
            ? (answer.audio == nil ? nil : "You answered aloud.") : parts.joined(separator: ", ")
    }
}
