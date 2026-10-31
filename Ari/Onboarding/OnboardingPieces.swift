import AriKit
import SwiftUI

extension Font {
    /// Kumo's words as a step's heading: New York, larger, unhurried.
    static let onboardingHeading = Font.system(.title2, design: .serif)
    /// Kumo saying hello.
    static let onboardingGreeting = Font.system(.largeTitle, design: .serif)
}

/// A step's page: its content scrolling, at a comfortable width, and its buttons resting at the
/// bottom. Centred, the content sits in the middle of the screen while it fits.
struct OnboardingPage<Content: View, Footer: View>: View {
    var centred = false
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    @State private var visibleHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: 560, alignment: centred ? .center : .leading)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, minHeight: centred ? visibleHeight : nil)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.containerSize.height - geometry.contentInsets.top
                - geometry.contentInsets.bottom
        } action: { _, height in
            visibleHeight = max(0, height)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 6) { footer }
                .frame(maxWidth: 560)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity)
                .background(alignment: .top) {
                    // Content fades out under the buttons rather than meeting an edge.
                    LinearGradient(
                        colors: [Color.ariBackground.opacity(0), .ariBackground],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 24)
                    .offset(y: -24)
                    .allowsHitTesting(false)
                }
                .background(.ariBackground)
        }
    }
}

extension OnboardingPage where Footer == EmptyView {
    init(centred: Bool = false, @ViewBuilder content: () -> Content) {
        self.init(centred: centred, content: content, footer: { EmptyView() })
    }
}

/// A step's top: the character, Kumo's line in its own hand, and a quiet caption under it.
struct OnboardingHeader: View {
    let poses: PoseHistory
    let title: String
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PresenceView(history: poses, size: 40)
                .padding(.leading, 2)
                .padding(.vertical, 8)
            Text(title)
                .font(.onboardingHeading)
                .foregroundStyle(.ariText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let caption {
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.ariSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The step's way on: filled, the one thing to do next. While its answer is on the way it holds its
/// place with a small spinner.
struct OnboardingButton: View {
    let title: String
    var busy = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, busy: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.busy = busy
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.ariBackground)
                .opacity(busy ? 0 : 1)
                .overlay {
                    if busy { ProgressView().tint(.ariBackground) }
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(.ariText, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled || busy ? 1 : 0.4)
        .accessibilityValue(busy ? "Working" : "")
    }
}

/// The other way on, such as Skip for now or Not now: quiet, and never the one that stands out.
struct OnboardingQuietButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.ariSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Kumo reading, in one quiet line: a small bone dot breathing beside the count, and a hairline that
/// fills under it where there's room for one. No spinner.
struct OnboardingReadingLine: View {
    let text: String
    var spoken: String?
    /// How much is read, for the hairline; `nil` for none.
    var fraction: Double?
    /// Still reading: the dot breathes.
    var active = true
    var alignment = HorizontalAlignment.leading

    init(
        text: String, spoken: String? = nil, fraction: Double? = nil, active: Bool = true,
        alignment: HorizontalAlignment = .leading
    ) {
        self.text = text
        self.spoken = spoken
        self.fraction = fraction
        self.active = active
        self.alignment = alignment
    }

    init(progress: OnboardingProgress, bar: Bool = false, alignment: HorizontalAlignment = .leading)
    {
        self.init(
            text: progress.words, spoken: progress.spoken,
            fraction: bar && progress.total > 0 ? progress.fraction : nil,
            active: !progress.isDone, alignment: alignment)
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 10) {
            HStack(spacing: 8) {
                OnboardingBreathingDot(active: active)
                Text(text)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.ariSecondary)
                    .contentTransition(.numericText())
            }
            if let fraction {
                Capsule()
                    .fill(Color.ariLine)
                    .frame(height: 2)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(Color.ariBone)
                                .frame(width: proxy.size.width * fraction)
                        }
                    }
                    .frame(maxWidth: 220)
                    .animation(.smooth(duration: 0.6), value: fraction)
            }
        }
        .animation(.smooth(duration: 0.4), value: text)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken ?? text)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// A small bone dot that breathes while something carries on; still under Reduce Motion or once
/// it's done.
struct OnboardingBreathingDot: View {
    var active = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if active && !reduceMotion {
            dot.phaseAnimator([0.35, 1.0]) { content, level in
                content.opacity(level)
            } animation: { _ in
                .easeInOut(duration: 1.3)
            }
        } else {
            dot.opacity(active ? 1 : 0.6)
        }
    }

    private var dot: some View {
        Circle().fill(Color.ariBone).frame(width: 6, height: 6)
    }
}

extension View {
    /// Arrives softly once `shown`: rising a little into place. Under Reduce Motion it's simply
    /// there.
    func onboardingArrival(_ shown: Bool) -> some View {
        modifier(OnboardingArrival(shown: shown))
    }
}

private struct OnboardingArrival: ViewModifier {
    let shown: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
    }
}
