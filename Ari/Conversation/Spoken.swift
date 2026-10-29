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
            "Delete this call's recordings?", isPresented: $confirmsDelete,
            titleVisibility: .visible
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

/// Under a message you spoke: play it back, while the recording is kept.
struct SpokenFooter: View {
    let spoken: Spoken
    let bytes: (AttachmentID) async -> Data?

    @State private var replay = AudioReplay()

    var body: some View {
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
            .foregroundStyle(.ariTertiary)
            .padding(.trailing, 4)
            .accessibilityLabel(replay.playing == audio.id ? "Stop" : "Hear yourself")
        }
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
        guard let data = await bytes(id), let player = try? AVAudioPlayer(data: data) else {
            return
        }
        // A call keeps its own audio session; otherwise play as media, out of the speaker.
        if !CallEngine.isOn {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            try? AVAudioSession.sharedInstance().setActive(true)
        }
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
