import AriKit
import SwiftUI

/// Opens a thing in motion full screen, growing it from what you tapped: the pinned line, a compact
/// line under a reply, a row of In motion. The screen that presents the thing sets it.
struct MotionOpener: Equatable {
    var namespace: Namespace.ID?
    var open: ((MotionID, _ source: String) -> Void)?

    /// The same opener as long as it presents in the same place. The conversation makes a new one
    /// with every frame of a reply; were each one new, everything reading it would redraw too, and
    /// the pinned line, redrawn under the conversation every frame, kept it from following the reply.
    static func == (a: MotionOpener, b: MotionOpener) -> Bool {
        a.namespace == b.namespace && (a.open == nil) == (b.open == nil)
    }
}

/// A thing to open, and what it grows from.
struct OpenedMotion: Identifiable, Hashable {
    let id: MotionID
    let source: String
}

extension EnvironmentValues {
    @Entry var motionOpener = MotionOpener()
    /// Goes to the message at a position in the chat, as "What changed" links back to it.
    @Entry var openInChat: ((Int) -> Void)?
    /// An attachment's bytes, from the server or the device's cache.
    @Entry var attachmentBytes: ((AttachmentID) async -> Data?)?
}

extension View {
    /// What an opened thing grows from, and shrinks back into.
    @ViewBuilder
    func motionSource(_ id: String, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedTransitionSource(id: id, in: namespace) { source in
                source.background(.ariSurface).clipShape(
                    .rect(cornerRadius: 18, style: .continuous))
            }
        } else {
            self
        }
    }

    /// Presents a thing in motion over the screen, grown from its source on the iPhone.
    func motionCover(_ opened: Binding<OpenedMotion?>, in namespace: Namespace.ID) -> some View {
        fullScreenCover(item: opened) { item in
            MotionView(id: item.id)
                .navigationTransition(.zoom(sourceID: item.source, in: namespace))
        }
    }
}

/// The symbol for a kind of thing: a plane for a trip.
enum MotionSymbol {
    static func name(for kind: MotionKind) -> String {
        switch kind {
        case .trip: "airplane"
        case .training: "figure.run"
        default: "circle.dotted.circle"
        }
    }

    static func name(for mode: TravelMode) -> String {
        switch mode {
        case .walk: "figure.walk"
        case .train: "train.side.front.car"
        case .tram: "tram.fill"
        case .bus: "bus.fill"
        case .metro: "lightrail.fill"
        case .car, .taxi: "car.fill"
        case .bike: "bicycle"
        case .ferry: "ferry.fill"
        case .flight: "airplane"
        default: "arrow.right"
        }
    }
}

/// A thing's symbol, dark on a bone disc.
struct SymbolDisc: View {
    let symbol: String
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.ariBackground)
            .frame(width: size, height: size)
            .background(.ariBone, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Where something stands: to book, picked, booked. Filled once it's settled.
struct StatusChip: View {
    let text: String
    var filled = false

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(filled ? Color.ariBackground : .ariSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(filled ? Color.ariBone : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(filled ? Color.clear : .ariLine))
            .fixedSize()
    }

    /// A booking's chip, or none when it needs none.
    @ViewBuilder
    static func booking(_ booking: Trip.Booking?) -> some View {
        switch booking?.status {
        case .toBook?: StatusChip(text: "To book")
        case .booked?: StatusChip(text: "Booked", filled: true)
        default: EmptyView()
        }
    }

    static func place(_ status: PlaceStatus) -> StatusChip {
        switch status {
        case .picked: StatusChip(text: "Picked", filled: true)
        case .booked: StatusChip(text: "Booked", filled: true)
        default: StatusChip(text: "Shortlisted")
        }
    }
}

/// What a thing's line says. A trip's is drawn from its content and your ticks, so the count moves
/// the moment you tick; until its content is here, and for a kind Ari doesn't know, it's Ari's own
/// summary.
struct MotionLineText {
    /// "Florence", for the pinned line; the thing's title for a kind Ari doesn't know.
    let name: String
    /// "6–9 Nov", or Ari's summary.
    let detail: String
    /// The to-dos left, when there's a list.
    let left: Int?
    /// What's on today, such as "Intervals today".
    let today: String?
    /// How much is done, from 0 to 1.
    let progress: Double?

    init(_ motion: Motion, _ detail: MotionDetail?) {
        let state = detail?.state ?? [:]
        switch detail?.content {
        case .trip(let trip)?:
            let line = TripReading.line(trip, state: state)
            name = line.name
            self.detail = line.when
            left = line.left
            today = nil
            progress = TripReading.progress(trip, state: state)
        case .training(let training)?:
            let line = TrainingReading.line(training, state: state)
            name = line.name
            self.detail = line.when ?? motion.summary
            left = nil
            today = line.today
            progress = TrainingReading.progress(training, state: state)
        default:
            name = motion.title
            self.detail = motion.summary
            left = nil
            today = nil
            progress = nil
        }
    }
}

/// What's left, as a number that rolls when it changes: "3 to do", then "2 to do", then "All done".
struct LeftCount: View {
    let left: Int

    var body: some View {
        Group {
            if left == 0 {
                Text("All done")
            } else {
                HStack(spacing: 0) {
                    Text("\(left)")
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(.ariBone)
                        .contentTransition(.numericText(value: Double(left)))
                    Text(" to do")
                }
                .accessibilityElement(children: .combine)
            }
        }
        .animation(.smooth(duration: 0.5), value: left)
    }
}

/// A photo Ari found, filling its frame. A tap shows its credit, which links to where it came from.
struct FoundPhoto: View {
    let photo: Photo
    /// Pixels on its longer side, for how large it's shown.
    var longest = 720
    var creditOnTap = true
    var creditAlignment = Alignment.bottomLeading
    /// It couldn't be loaded: where a photo can go, the place it held can go too.
    var failed: (() -> Void)?

    @Environment(\.attachmentBytes) private var bytes
    @State private var image: CGImage?
    @State private var didFail = false
    @State private var showsCredit = false

    var body: some View {
        Rectangle()
            .fill(.ariSurface)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else if didFail {
                    // Said quietly, rather than an empty box that looks like it's still coming.
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.ariTertiary.opacity(0.6))
                        .accessibilityLabel("Couldn't load this photo")
                }
            }
            .clipped()
            .overlay(alignment: creditAlignment) {
                if showsCredit {
                    Link(destination: photo.sourceURL) {
                        Label(photo.credit, systemImage: "camera")
                            .font(.caption2)
                            .foregroundStyle(.ariText)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.55), in: Capsule())
                    }
                    .padding(10)
                    .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard creditOnTap else { return }
                withAnimation(.easeOut(duration: 0.2)) { showsCredit.toggle() }
            }
            .task(id: showsCredit) {
                guard showsCredit else { return }
                try? await Task.sleep(for: .seconds(5))
                if !Task.isCancelled {
                    withAnimation(.easeOut(duration: 0.3)) { showsCredit = false }
                }
            }
            .accessibilityElement()
            .accessibilityLabel(photo.alt)
            .accessibilityAddTraits(.isImage)
            .accessibilityHint(creditOnTap ? "Shows who took it" : "")
            .task(id: photo.attachment) {
                guard let bytes else { return }
                let loaded = await Thumbnails.image(for: photo.attachment, longest: longest) {
                    await bytes(photo.attachment)
                }
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.25)) { image = loaded }
                if loaded == nil {
                    didFail = true
                    failed?()
                }
            }
    }
}
