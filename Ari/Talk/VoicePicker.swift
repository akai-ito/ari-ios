#if os(iOS)
    import AVFoundation
    import SwiftUI

    /// Choosing Ari's voice on a call from the voices on this iPhone, best first, each heard as
    /// you tap it. The natural ones are a free download in iOS's own Settings; Siri's voices are
    /// only for Apple's apps.
    struct VoicePickerView: View {
        @AppStorage(Voice.chosenKey) private var chosen = ""
        @State private var voices: [AVSpeechSynthesisVoice] = []
        @State private var synthesizer = AVSpeechSynthesizer()

        var body: some View {
            Form {
                Section {
                    row(title: "Best on this iPhone", detail: Voice.best()?.name, id: "")
                }
                ForEach(Self.qualities, id: \.title) { quality in
                    let matching = voices.filter { $0.quality == quality.value }
                    if !matching.isEmpty {
                        Section(quality.title) {
                            ForEach(matching, id: \.identifier) { voice in
                                row(
                                    title: voice.name, detail: Self.region(voice),
                                    id: voice.identifier)
                            }
                        }
                    }
                }
                Section {
                } footer: {
                    Text(
                        "More natural voices download free in Settings › Accessibility › Spoken Content › Voices › English: look for Premium or Enhanced. Siri's own voices are only for Apple's apps."
                    )
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(.ariBackground)
            .navigationTitle("Ari's voice")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { voices = Voice.installed() }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)
            ) { _ in voices = Voice.installed() }
        }

        private func row(title: String, detail: String?, id: String) -> some View {
            Button {
                chosen = id
                preview(id)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).foregroundStyle(.ariText)
                        if let detail {
                            Text(detail).font(.footnote).foregroundStyle(.ariTertiary)
                        }
                    }
                    Spacer()
                    if chosen == id {
                        Image(systemName: "checkmark").foregroundStyle(.ariText)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.ariSurface)
        }

        /// A line in the voice, as Ari might say it on a walk.
        private func preview(_ id: String) {
            synthesizer.stopSpeaking(at: .immediate)
            let utterance = AVSpeechUtterance(
                string: "Hi, it's Ari. I've put the details in the chat.")
            utterance.voice = id.isEmpty ? Voice.best() : AVSpeechSynthesisVoice(identifier: id)
            synthesizer.speak(utterance)
        }

        private static let qualities: [(title: String, value: AVSpeechSynthesisVoiceQuality)] = [
            ("Premium", .premium), ("Enhanced", .enhanced), ("Standard", .default),
        ]

        private static func region(_ voice: AVSpeechSynthesisVoice) -> String {
            Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language
        }
    }
#endif
