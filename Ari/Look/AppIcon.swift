#if os(iOS)
    import SwiftUI
    import UIKit

    /// Ari's two icons, both Ari at rest: the dusky pebble with its eyes faded, and Peeking, low in
    /// the frame and looking up at you.
    enum AppIcon: String, CaseIterable, Identifiable {
        case rest
        case peeking

        var id: Self { self }

        var title: String {
            switch self {
            case .rest: "Rest"
            case .peeking: "Peeking"
            }
        }

        /// The icon set's name for `setAlternateIconName`; `nil` is the main icon.
        var alternateName: String? {
            switch self {
            case .rest: nil
            case .peeking: "AppIconPeeking"
            }
        }

        static var current: AppIcon {
            allCases.first { $0.alternateName == UIApplication.shared.alternateIconName } ?? .rest
        }
    }

    /// The icon choice, as a menu section. iOS confirms a change with its own alert.
    struct AppIconPicker: View {
        @State private var selection = AppIcon.current

        var body: some View {
            Picker("App icon", selection: $selection) {
                ForEach(AppIcon.allCases) { icon in
                    Text(icon.title).tag(icon)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selection) { _, icon in
                guard icon != AppIcon.current else { return }
                Task { try? await UIApplication.shared.setAlternateIconName(icon.alternateName) }
            }
        }
    }
#endif
