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

    /// A small picture of it, for choosing.
    var preview: ImageResource {
        switch self {
        case .rest: .iconPreviewRest
        case .peeking: .iconPreviewPeeking
        }
    }

    static var current: AppIcon {
        allCases.first { $0.alternateName == UIApplication.shared.alternateIconName } ?? .rest
    }
}

/// The two icons side by side; the chosen one is outlined. iOS confirms a change with its own
/// alert.
struct AppIconChooser: View {
    @State private var selection = AppIcon.current

    var body: some View {
        HStack(spacing: 22) {
            ForEach(AppIcon.allCases) { icon in
                Button {
                    choose(icon)
                } label: {
                    VStack(spacing: 8) {
                        Image(icon.preview)
                            .resizable()
                            .frame(width: 60, height: 60)
                            .clipShape(.rect(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 17, style: .continuous)
                                    .strokeBorder(
                                        selection == icon ? Color.ariText : .clear, lineWidth: 2
                                    )
                                    .padding(-4)
                            }
                        Text(icon.title)
                            .font(.caption)
                            .foregroundStyle(selection == icon ? .ariText : .ariTertiary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == icon ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func choose(_ icon: AppIcon) {
        guard icon != selection else { return }
        selection = icon
        Task { try? await UIApplication.shared.setAlternateIconName(icon.alternateName) }
    }
}
