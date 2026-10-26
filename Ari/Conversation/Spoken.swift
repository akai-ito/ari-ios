import AVFoundation
import AriKit
import SwiftUI

/// Where a call started in the conversation: "Call · 24 min", or "On a call" while it's on. Its
/// menu deletes the call's recordings; the words stay.
struct CallBlock: View {
    let call: Call
    /// Opens the call screen, when the call is this phone's and still on.
    var returnToCall: (() -> Void)?
    let deleteAudio: () -> Void

    @State private var confirmsDelete = false

    var body: some View {
        Menu {
            if let returnToCall {
                Button("Return to the call", systemImage: "phone", action: returnToCall)
            }
            if !call.isOn, !call.audioDeleted {
                Button("Delete recordings", systemImage: "trash", role: .destructive) {
                    confirmsDelete = true
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: call.isOn ? "phone.fill" : "phone")
                    .font(.system(size: 11))
                Text(Self.describe(call))
            }
            .font(.caption)
            .foregroundStyle(call.isOn ? .ariSecondary : .ariTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(Capsule().strokeBorder(.ariLine, lineWidth: 1))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .confirmationDialog(
            "Delete this call's recordings?", isPresented: $confirmsDelete, titleVisibility: .visible
        ) {
            Button("Delete recordings", role: .destructive, action: deleteAudio)
        } message: {
            Text("What you said stays in the conversation as words.")
        }
    }

    static func describe(_ call: Call) -> String {
        guard !call.isOn else { return "On a call" }
        let minutes = max(1, Int(((Double(call.durationMs ?? 0) / 60_000)).rounded()))
        let length = minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
        return "Call · \(length)" + (call.audioDeleted ? " · recordings deleted" : "")
    }
}

/// Under a message you spoke: play it back, and what the phone corrected, each one undoable.
struct SpokenFooter: View {
    let spoken: Spoken
    let text: String
    let bytes: (AttachmentID) async -> Data?
    let fixWord: () -> Void

    @State private var replay = AudioReplay()

    var body: some View {
        HStack(spacing: 10) {
            if let audio = spoken.audio {
                Button {
                    Task { await replay.toggle(audio.id, bytes: bytes) }
                } label: {
                    Image(systemName: replay.playing == audio.id ? "stop.fill" : "speaker.wave.2")
                        .font(.system(size: 12))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(replay.playing == audio.id ? "Stop" : "Hear yourself")
            }
            Menu {
                ForEach(Array((spoken.corrections ?? []).enumerated()), id: \.offset) { _, correction in
                    let meant = Self.meant(correction, in: text)
                    Section("Heard “\(correction.heard)” as \(meant)") {
                        Button("Don't correct this again", systemImage: "arrow.uturn.backward") {
                            Refusals.add(.init(heard: correction.heard, meant: meant))
                        }
                    }
                }
                Button("Fix a word…", systemImage: "character.cursor.ibeam", action: fixWord)
            } label: {
                Image(systemName: "waveform")
                    .font(.system(size: 12))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("Spoken")
        }
        .foregroundStyle(.ariTertiary)
        .padding(.trailing, 4)
    }

    /// The words a correction put in the text.
    static func meant(_ correction: Correction, in text: String) -> String {
        let utf16 = text.utf16
        guard correction.offset + correction.length <= utf16.count else { return "" }
        let start = utf16.index(utf16.startIndex, offsetBy: correction.offset)
        let end = utf16.index(start, offsetBy: correction.length)
        return String(text[start..<end])
    }

    /// Your words with the corrected ones underlined, dotted.
    static func marked(_ text: AttributedString, _ corrections: [Correction], in plain: String)
        -> AttributedString
    {
        var text = text
        for correction in corrections {
            let meant = meant(correction, in: plain)
            guard !meant.isEmpty, let range = text.range(of: meant) else { continue }
            text[range].underlineStyle = Text.LineStyle(pattern: .dot, color: nil)
        }
        return text
    }
}

/// Plays a recording back, fetched once.
@Observable
final class AudioReplay: NSObject, AVAudioPlayerDelegate {
    private(set) var playing: AttachmentID?
    @ObservationIgnored private var player: AVAudioPlayer?

    func toggle(_ id: AttachmentID, bytes: (AttachmentID) async -> Data?) async {
        if playing == id {
            stop()
            return
        }
        guard let data = await bytes(id), let player = try? AVAudioPlayer(data: data) else { return }
        #if os(iOS)
            // A call keeps its own audio session; otherwise play as media.
            if AVAudioSession.sharedInstance().category != .playAndRecord {
                try? AVAudioSession.sharedInstance().setCategory(.playback)
                try? AVAudioSession.sharedInstance().setActive(true)
            }
        #endif
        player.delegate = self
        player.play()
        self.player = player
        playing = id
    }

    func stop() {
        player?.stop()
        player = nil
        playing = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}

/// Teaching Ari a word it misheard: what the recogniser wrote, and what you meant. Next time the
/// phone corrects it, and the recogniser leans towards what you meant.
struct FixWordSheet: View {
    let text: String
    let teach: (String, String) async -> Bool

    @State private var heard = ""
    @State private var meant = ""
    @State private var saving = false
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(text).foregroundStyle(.ariSecondary)
                }
                Section {
                    TextField("Ari heard", text: $heard)
                    TextField("You meant", text: $meant)
                } footer: {
                    Text(
                        failed
                            ? "Ari couldn't reach your server. Try again in a moment."
                            : "Such as “Bara” for Bora. Ari keeps it with the person or place it names."
                    )
                }
            }
            .navigationTitle("Fix a word")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Teach") {
                        saving = true
                        Task {
                            let taught = await teach(
                                heard.trimmingCharacters(in: .whitespaces),
                                meant.trimmingCharacters(in: .whitespaces))
                            saving = false
                            if taught { dismiss() } else { failed = true }
                        }
                    }
                    .disabled(
                        saving || heard.trimmingCharacters(in: .whitespaces).isEmpty
                            || meant.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// Corrections you undid, kept on this device so they aren't made again.
enum Refusals {
    private static let key = "talk.refused"

    static func load() -> Set<Corrector.Refusal> {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode(Set<Corrector.Refusal>.self, from: data)) ?? []
    }

    static func add(_ refusal: Corrector.Refusal) {
        var refused = load()
        refused.insert(refusal)
        UserDefaults.standard.set(try? JSONEncoder().encode(refused), forKey: key)
    }
}
