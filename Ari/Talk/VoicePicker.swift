import AVFoundation
import AriKit
import SwiftUI
import os

/// Choosing Ari's voice: the server's voices, American and British, each heard as you tap it.
/// The choice is for the whole server, so every device hears the same Ari.
struct VoicePickerView: View {
    let voices: Voices

    @State private var player: AVAudioPlayer?
    /// The voice whose preview is on its way.
    @State private var previewing: String?
    @State private var problem: String?
    private static let line = "Hi, I'm Ari. This is how I sound."
    private static let log = Logger(subsystem: "io.github.akai-ito.ari", category: "talk")

    var body: some View {
        Form {
            if !voices.canTalk {
                Section {
                } footer: {
                    Text(voices.reason ?? "Ari's voice isn't ready on your server yet.")
                }
            }
            ForEach([VoiceAccent.american, .british], id: \.self) { accent in
                let matching = voices.list?.voices.filter { $0.accent == accent } ?? []
                if !matching.isEmpty {
                    Section {
                        ForEach(matching) { voice in row(voice) }
                    } header: {
                        Text(accent == .british ? "British" : "American")
                    } footer: {
                        if accent == .american, let problem { Text(problem) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(.ariBackground)
        .navigationTitle("Ari's voice")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if voices.list == nil { ProgressView() }
        }
        .task { await voices.refresh() }
    }

    private func row(_ voice: VoiceOption) -> some View {
        Button {
            choose(voice)
        } label: {
            HStack {
                Text(voice.name).foregroundStyle(.ariText)
                Spacer()
                if previewing == voice.id || voices.choosing == voice.id {
                    ProgressView()
                } else if voices.list?.chosen == voice.id {
                    Image(systemName: "checkmark").foregroundStyle(.ariText)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.ariSurface)
    }

    /// Chooses the voice for the whole server, and plays how it sounds.
    private func choose(_ voice: VoiceOption) {
        problem = nil
        player?.stop()
        Task {
            do {
                try await voices.choose(voice.id)
            } catch {
                problem = "Ari couldn't choose that voice."
                return
            }
            guard voices.canTalk else { return }
            previewing = voice.id
            defer { if previewing == voice.id { previewing = nil } }
            do {
                let wav = try await voices.preview(Self.line, voice: voice.id)
                let player = try AVAudioPlayer(data: wav)
                // Out of the speaker as media, unless a call has the audio.
                if !CallEngine.isOn {
                    let session = AVAudioSession.sharedInstance()
                    try? session.setCategory(.playback)
                    try? session.setActive(true)
                }
                guard previewing == voice.id else { return }
                player.play()
                self.player = player
            } catch {
                Self.log.error(
                    "Preview \(voice.id, privacy: .public) failed: \(error, privacy: .public)")
                problem = "Ari couldn't play that voice."
            }
        }
    }
}
