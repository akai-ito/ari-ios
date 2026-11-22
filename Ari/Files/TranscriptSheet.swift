import AriKit
import SwiftUI

/// A recording's transcript, open over its thread: play from any line, who spoke and when, the line
/// being said lit, and a misheard name fixed everywhere it was heard. It's what the server heard,
/// not a summary.
struct TranscriptSheet: View {
    let session: Session
    let opening: TranscriptOpening

    @Environment(\.dismiss) private var dismiss
    @State private var transcript: Transcript?
    @State private var problem: String?
    @State private var player = RecordingPlayer()
    @State private var searching = false
    @State private var query = ""
    /// The turn whose words you're fixing.
    @State private var fixing: Int?

    var body: some View {
        NavigationStack {
            content
                .background(Color.ariBackground)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 2) {
                            Text("Transcript").font(.ariName).foregroundStyle(.ariText)
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.ariSecondary)
                                .lineLimit(1)
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done", systemImage: "xmark") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Search", systemImage: "magnifyingglass") {
                            searching.toggle()
                            if !searching { query = "" }
                        }
                    }
                }
        }
        .task { await load() }
        .onDisappear { player.stop() }
    }

    private var recording: Recording? { session.recordings[opening.recording] }

    private var subtitle: String {
        let name = transcript?.name ?? recording?.name ?? "Recording"
        let seconds = transcript?.durationSeconds ?? recording?.durationSeconds
        return ([stem(name)] + [seconds.map(durationWords)].compactMap(\.self))
            .joined(separator: " · ")
    }

    @ViewBuilder
    private var content: some View {
        if let transcript {
            let turns = Turn.of(transcript)
            ScrollViewReader { scroller in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(shown(turns)) { turn in
                            line(turn, in: transcript)
                                .id(turn.id)
                            if fixing == turn.id {
                                FixWords(
                                    turn: turn, transcript: transcript,
                                    cancel: { fixing = nil },
                                    fix: { heard, meant in await fix(heard, meant) })
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .top, spacing: 0) { header }
                .onAppear {
                    guard let at = opening.at else { return }
                    player.seek(to: at)
                    if let turn = Turn.near(at, in: turns) {
                        scroller.scrollTo(turn.id, anchor: .top)
                    }
                }
                .onChange(of: Turn.at(player.time, in: turns)?.id) { _, now in
                    guard player.isPlaying, let now, fixing == nil else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        scroller.scrollTo(now, anchor: .center)
                    }
                }
            }
        } else if let problem {
            Text(problem)
                .font(.subheadline)
                .foregroundStyle(.ariSecondary)
                .multilineTextAlignment(.center)
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView().tint(.ariSecondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The player, and the search field while you search.
    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button(action: player.toggle) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.ariBackground)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.ariText))
                        .opacity(player.state == .ready ? 1 : 0.4)
                }
                .buttonStyle(.plain)
                .disabled(player.state != .ready)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                Group {
                    switch player.state {
                    case .unavailable(let why):
                        Text(why).font(.caption).foregroundStyle(.ariTertiary).lineLimit(2)
                    case .fetching:
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.mini).tint(.ariSecondary)
                            Text("Getting the audio from your server")
                                .font(.caption)
                                .foregroundStyle(.ariTertiary)
                        }
                    case .ready:
                        DotWaveform(played: player.fraction, bars: 46, seed: stableSeed(opening.id))
                            .frame(height: 22)
                            .contentShape(Rectangle())
                            .gesture(
                                SpatialTapGesture().onEnded { tap in
                                    // A tap on the waveform goes there.
                                    let width = max(1, waveformWidth)
                                    player.seek(to: player.duration * tap.location.x / width)
                                }
                            )
                            .onGeometryChange(for: CGFloat.self, of: \.size.width) {
                                waveformWidth = $0
                            }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(RecordingLink.clock(player.time))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.ariSecondary)
            }
            if searching {
                TextField(
                    "", text: $query,
                    prompt: Text("Find in the transcript").foregroundStyle(.ariTertiary)
                )
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.ariField, in: Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.ariBackground)
    }

    @State private var waveformWidth: CGFloat = 1

    private func shown(_ turns: [Turn]) -> [Turn] {
        let words = query.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else { return turns }
        return turns.filter { $0.text.localizedCaseInsensitiveContains(words) }
    }

    private func line(_ turn: Turn, in transcript: Transcript) -> some View {
        // The line at the player's place is lit, playing or paused there.
        let playing =
            (player.isPlaying || player.time > 0) && Turn.at(player.time, in: [turn]) != nil
        let speaker = transcript.speaker(turn.speaker)
        return HStack(alignment: .top, spacing: 12) {
            Rectangle().fill(playing ? Color.ariBone : .clear).frame(width: 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(speaker?.name ?? "")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(speaker?.you == true ? .ariText : .ariSecondary)
                    Spacer()
                    Button(RecordingLink.clock(turn.start)) {
                        player.seek(to: turn.start)
                        if !player.isPlaying, player.state == .ready { player.toggle() }
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(playing ? .ariBone : .ariTertiary)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play from \(RecordingLink.clock(turn.start))")
                }
                Text(turn.text)
                    .font(.body)
                    .foregroundStyle(playing ? .ariText : .ariText.opacity(0.86))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { fixing = fixing == turn.id ? nil : turn.id }
                    .accessibilityHint("Fix a misheard word")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func load() async {
        do {
            transcript = try await session.transcript(of: opening.recording)
        } catch {
            problem =
                error.serverError?.message
                ?? "Couldn't fetch the transcript from your server. Try again in a moment."
            return
        }
        if let opening = opening.at { player.seek(to: opening) }
        guard let transcript else { return }
        let attachment = Attachment(
            id: transcript.attachment, kind: .audio, name: transcript.name,
            mediaType: mediaType(of: transcript.name), size: 0)
        await player.load(attachment, from: session, duration: transcript.durationSeconds)
    }

    private func fix(_ heard: String, _ meant: String) async -> String? {
        do {
            transcript = try await session.correct(opening.recording, heard: heard, meant: meant)
            fixing = nil
            return nil
        } catch {
            return error.serverError?.message
                ?? "Couldn't reach your server. Try again in a moment."
        }
    }

    private func stem(_ name: String) -> String {
        let stem = (name as NSString).deletingPathExtension
        return stem.isEmpty ? name : stem
    }

    /// The media type for playing the recording, from its name, as the transcript doesn't carry it.
    private func mediaType(of name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "mp3": "audio/mpeg"
        case "wav": "audio/wav"
        case "aac": "audio/aac"
        case "caf": "audio/x-caf"
        case "aif", "aiff": "audio/aiff"
        case "flac": "audio/flac"
        case "ogg", "opus": "audio/ogg"
        default: "audio/mp4"
        }
    }
}

/// What one voice said before another spoke: the server's pieces, joined.
struct Turn: Identifiable, Equatable {
    let id: Int
    let speaker: String?
    let start: Double
    let end: Double
    let text: String

    static func of(_ transcript: Transcript) -> [Turn] {
        var turns: [Turn] = []
        for segment in transcript.segments {
            if let last = turns.last, last.speaker == segment.speaker, segment.start - last.end < 4
            {
                turns[turns.count - 1] = Turn(
                    id: last.id, speaker: last.speaker, start: last.start, end: segment.end,
                    text: last.text + " " + segment.text)
            } else {
                turns.append(
                    Turn(
                        id: turns.count, speaker: segment.speaker, start: segment.start,
                        end: segment.end, text: segment.text))
            }
        }
        return turns
    }

    /// The turn being said at `seconds`.
    static func at(_ seconds: Double, in turns: [Turn]) -> Turn? {
        turns.last { $0.start <= seconds + 0.01 && seconds < $0.end + 1 }
    }

    /// The last turn begun by `seconds`, for opening at a moment that falls in a pause.
    static func near(_ seconds: Double, in turns: [Turn]) -> Turn? {
        turns.last { $0.start <= seconds + 0.5 } ?? turns.first
    }
}

/// Fixing a misheard name or word: what it heard, what was said, and how many lines it's in. The
/// server fixes it everywhere it was heard, and keeps what it heard underneath.
private struct FixWords: View {
    let turn: Turn
    let transcript: Transcript
    let cancel: () -> Void
    let fix: (String, String) async -> String?

    @State private var heard = ""
    @State private var meant = ""
    @State private var busy = false
    @State private var problem: String?
    @FocusState private var focus: Field?

    private enum Field { case heard, meant }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TextField("", text: $heard, prompt: Text("Heard").foregroundStyle(.ariTertiary))
                    .foregroundStyle(.ariTertiary)
                    .focused($focus, equals: .heard)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.ariTertiary)
                TextField(
                    "", text: $meant, prompt: Text("Really said").foregroundStyle(.ariTertiary)
                )
                .foregroundStyle(.ariText)
                .focused($focus, equals: .meant)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.ariField, in: .rect(cornerRadius: 8, style: .continuous))
            }
            .font(.subheadline)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            let lines = Self.lines(with: heard, in: transcript)
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.ariBone)
                Text("Everywhere it was heard · \(lines) \(lines == 1 ? "line" : "lines")")
                    .font(.footnote)
                    .foregroundStyle(.ariSecondary)
            }
            .opacity(lines > 0 ? 1 : 0.4)
            HStack {
                Text(problem ?? "Kumo reads the fixed words from now on.")
                    .font(.caption)
                    .foregroundStyle(.ariTertiary)
                Spacer()
                SmallPill(title: "Cancel", action: cancel)
                SmallPill(title: busy ? "Fixing" : "Fix", acts: true) {
                    busy = true
                    Task {
                        problem = await fix(
                            heard.trimmingCharacters(in: .whitespaces),
                            meant.trimmingCharacters(in: .whitespaces))
                        busy = false
                    }
                }
                .disabled(busy || lines == 0 || meant.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .deskCard(padding: 14, cornerRadius: 16)
        .padding(.leading, 14)
        .onAppear {
            heard = Self.guess(in: turn.text)
            meant = heard
            focus = heard.isEmpty ? .heard : .meant
        }
    }

    /// The name it most likely misheard: the longest run of capitalised words past a sentence's
    /// start, as names are what it gets wrong.
    static func guess(in text: String) -> String {
        var best: [Substring] = []
        var run: [Substring] = []
        var sentenceStart = true
        for word in text.split(separator: " ") {
            let bare = word.trimmingCharacters(in: .punctuationCharacters)
            let capital = bare.first?.isUppercase == true && bare != "I"
            if capital && !sentenceStart {
                run.append(Substring(bare))
            } else {
                if run.count > best.count { best = run }
                run = []
            }
            sentenceStart = word.last.map { ".?!".contains($0) } ?? false
            if word.last.map({ ",;:".contains($0) }) == true, run.count > best.count {
                best = run
                run = []
            }
        }
        if run.count > best.count { best = run }
        return best.joined(separator: " ")
    }

    /// How many of the transcript's pieces have the words, whole and in any case.
    static func lines(with words: String, in transcript: Transcript) -> Int {
        let words = words.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else { return 0 }
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: words) + "\\b"
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        else { return 0 }
        return transcript.segments.count { segment in
            expression.firstMatch(
                in: segment.text, range: NSRange(segment.text.startIndex..., in: segment.text))
                != nil
        }
    }
}
