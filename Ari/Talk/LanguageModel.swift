#if os(iOS)
    import AriKit
    import CryptoKit
    import Foundation
    import Speech

    /// Steers the recogniser towards your names and words: a custom language model built from the
    /// server's vocabulary, on the phone. Building one takes a second or so, so each is kept, named
    /// for the vocabulary it came from, and the last few are reused.
    nonisolated enum LanguageModel {
        /// The model for this vocabulary, built if it isn't kept yet; `nil` if it can't be built.
        @concurrent static func configuration(for vocabulary: Vocabulary, locale: Locale) async
            -> SFSpeechLanguageModel.Configuration?
        {
            guard !vocabulary.terms.isEmpty else { return nil }
            let version = fingerprint(vocabulary, locale: locale)
            let folder = URL.cachesDirectory.appending(path: "Talk/\(version)", directoryHint: .isDirectory)
            let configuration = SFSpeechLanguageModel.Configuration(
                languageModel: folder.appending(path: "model"),
                vocabulary: folder.appending(path: "vocabulary"))
            let built = folder.appending(path: "built")
            if FileManager.default.fileExists(atPath: built.path()) { return configuration }

            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let data = SFCustomLanguageModelData(
                    locale: locale, identifier: "ari.vocabulary", version: version)
                for term in vocabulary.terms {
                    // Every term on its own, more for those used most, and in the phrases it's
                    // really used in.
                    data.insert(
                        phraseCount: SFCustomLanguageModelData.PhraseCount(
                            phrase: term.text, count: 40 + Int(160 * term.weight)))
                    for phrase in term.phrases {
                        data.insert(
                            phraseCount: SFCustomLanguageModelData.PhraseCount(
                                phrase: phrase, count: 8))
                    }
                }
                let names = vocabulary.terms.filter { $0.kind == .person }.map(\.text)
                if !names.isEmpty {
                    SFCustomLanguageModelData.PhraseCountsFromTemplates(classes: ["name": names]) {
                        SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                            "with <name>", count: 20)
                        SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                            "<name> said", count: 20)
                        SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                            "talk to <name>", count: 10)
                    }
                    .insert(data: data)
                }
                let exported = folder.appending(path: "data.bin")
                try await data.export(to: exported)
                try await SFSpeechLanguageModel.prepareCustomLanguageModel(
                    for: exported, configuration: configuration)
                FileManager.default.createFile(atPath: built.path(), contents: Data())
                tidy(keeping: version)
                return configuration
            } catch {
                try? FileManager.default.removeItem(at: folder)
                return nil
            }
        }

        private static func fingerprint(_ vocabulary: Vocabulary, locale: Locale) -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let bytes = (try? encoder.encode(vocabulary)) ?? Data()
            let digest = SHA256.hash(data: bytes + Data(locale.identifier.utf8))
            return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        }

        /// Keeps the newest few models, so a vocabulary that changes daily doesn't fill the phone.
        private static func tidy(keeping current: String) {
            let root = URL.cachesDirectory.appending(path: "Talk", directoryHint: .isDirectory)
            let folders =
                (try? FileManager.default.contentsOfDirectory(
                    at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            let dated = folders.map { folder in
                (folder, (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast)
            }
            for (folder, _) in dated.sorted(by: { $0.1 > $1.1 }).dropFirst(3)
            where folder.lastPathComponent != current {
                try? FileManager.default.removeItem(at: folder)
            }
        }
    }
#endif
