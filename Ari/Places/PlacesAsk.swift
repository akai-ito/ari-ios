import AriKit
import SwiftUI

/// The honest ask for places, before iOS asks anything: what Kumo would keep, where it lives, when
/// it goes to the model and what it costs. iOS asks twice, While Using first and then Always, and
/// Precise has to stay on; with less, places stay off rather than drawing a trail full of gaps.
struct PlacesAsk: View {
    let places: PlacesCollector
    /// Not now, or done: the ask closes.
    let close: () -> Void

    @State private var step: Step = .why

    enum Step {
        case why
        case always
    }

    var body: some View {
        Group {
            switch step {
            case .why: why
            case .always: PlacesAlwaysStep(places: places, close: close)
            }
        }
        .background(Color.ariBackground)
        .animation(.easeInOut(duration: 0.25), value: step)
        // While Using given: on to step two. Already Always and Precise: nothing more to ask.
        .onChange(of: places.access, initial: true) { _, access in
            switch access {
            case .allowed(always: false, _) where step == .why: step = .always
            case .allowed(always: true, precise: true): close()
            default: break
            }
        }
    }

    private var why: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                KumoFace(mood: .bright, size: 96, still: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Where your days go").font(.ariTitle).foregroundStyle(.ariText)
                    Text(
                        "If I can see where you go, I can keep your places, draw your trail, and notice when a week drifts off its rhythm."
                    )
                    .font(.ariBody).foregroundStyle(.ariSecondary).lineSpacing(3)
                }
                VStack(alignment: .leading, spacing: 18) {
                    HonestRow(
                        symbol: "mappin.and.ellipse", title: "What I'd keep",
                        text:
                            "Where you stop and for how long. The way between, only while you're moving."
                    )
                    HonestRow(
                        symbol: "externaldrive.fill", title: "Where it lives",
                        text:
                            "On your box: not with Apple, not with anyone else. Delete a day, a stretch, or all of it."
                    )
                    HonestRow(
                        symbol: "sparkle", title: "When I think about it",
                        text:
                            "When I look at a day or a place, what I read goes to the model, like anything you tell me."
                    )
                    HonestRow(
                        symbol: "battery.75percent", title: "What it costs",
                        text:
                            "About 1–2% of battery a day; a few % more on days you move a lot. Under 20% or in Low Power, I keep only the stops."
                    )
                }
                if places.access == .refused {
                    Text(
                        "Location is off for Ito in iOS Settings. Turn it on there, then come back."
                    )
                    .font(.footnote).foregroundStyle(.ariSecondary)
                } else {
                    Text(
                        "iOS asks twice: While Using first, then Always. Keep Precise Location on."
                    )
                    .font(.footnote).foregroundStyle(.ariTertiary)
                }
                VStack(spacing: 12) {
                    Button(action: allow) {
                        Text(places.access == .refused ? "Open iOS Settings" : "Allow location")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.ariBackground)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Color.ariBone, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Button("Not now", action: close)
                        .font(.body).foregroundStyle(.ariSecondary)
                        .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }

    private func allow() {
        switch places.access {
        case .notAsked: places.askWhileUsing()
        case .refused: PlacesAsk.openSettings()
        case .allowed: step = .always
        }
    }

    static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

/// Step two: from While Using to Always, with Precise on. Kumo explains iOS's prompt before it
/// shows and points at the right button; the prompt itself follows a moment later.
struct PlacesAlwaysStep: View {
    let places: PlacesCollector
    let close: () -> Void

    /// iOS's prompt has been and gone, or can't come again: what's left is iOS Settings.
    @State private var answered = false

    private var precise: Bool {
        if case .allowed(_, let precise) = places.access { return precise }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                KumoFace(mood: .calm, size: 64, still: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("One more: Always").font(.ariHeading).foregroundStyle(.ariText)
                    Text("Step 2 of 2").font(.caption).foregroundStyle(.ariTertiary)
                }
            }
            .padding(.top, 30)
            Text(
                answered
                    ? "iOS kept While Using. For your trail I need Always, so I can keep the stops when Ito's closed. In iOS Settings, choose Always under Location."
                    : "iOS gave me While Using. For your trail I need Always, so I can keep the stops when Ito's closed. iOS will offer it next; pick the second button."
            )
            .font(.ariBody).foregroundStyle(.ariSecondary).lineSpacing(3)
            if !answered { prompt }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Precise Location").font(.body).foregroundStyle(.ariText)
                    Text("Without it, places blur to a few hundred metres.").font(.caption)
                        .foregroundStyle(.ariTertiary)
                }
                Spacer()
                // Only iOS Settings can change it: the switch shows it and takes you there.
                Toggle(
                    "Precise Location",
                    isOn: Binding(get: { precise }, set: { _ in PlacesAsk.openSettings() })
                )
                .labelsHidden().tint(.green)
            }
            .padding(14)
            .background(
                Color.ariSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "pause.circle").foregroundStyle(.ariTertiary)
                Text(
                    "With only While Using, places stay off rather than drawing a trail full of gaps. Turn them on any time in Settings."
                )
                .font(.footnote).foregroundStyle(.ariTertiary)
            }
            Spacer()
            if answered {
                VStack(spacing: 12) {
                    Button(action: PlacesAsk.openSettings) {
                        Text("Open iOS Settings")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.ariBackground)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Color.ariBone, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Button("Not now", action: close)
                        .font(.body).foregroundStyle(.ariSecondary)
                        .frame(minHeight: 44)
                }
                .padding(.bottom, 24)
            }
        }
        .padding(.horizontal, 24)
        .task {
            guard !places.askedAlways else {
                answered = true
                return
            }
            // A moment to read what's coming before iOS covers it.
            try? await Task.sleep(for: .seconds(2))
            places.askAlways()
        }
        // Back from iOS's prompt with While Using still: say what's left.
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
        ) { _ in
            if places.askedAlways { answered = true }
        }
    }

    /// iOS's prompt, drawn: so you know it's coming and which button keeps your trail.
    private var prompt: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Allow “Ito” to also use your location even when you are not using the app?")
                    .font(.headline).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Ito keeps your places and trail on your own server.")
                    .font(.footnote).multilineTextAlignment(.center)
                    .foregroundStyle(.ariSecondary)
            }
            .foregroundStyle(.ariText)
            .padding(18)
            Rectangle().fill(Color.ariLine).frame(height: 0.5)
            Text("Keep Only While Using")
                .font(.body).foregroundStyle(.ariSecondary)
                .frame(maxWidth: .infinity, minHeight: 46)
            Rectangle().fill(Color.ariLine).frame(height: 0.5)
            Text("Change to Always Allow")
                .font(.body.weight(.semibold)).foregroundStyle(.ariText)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Color.ariBone.opacity(0.1))
                .overlay {
                    RoundedRectangle(cornerRadius: 10).stroke(Color.ariBone, lineWidth: 1.5)
                        .padding(3)
                }
        }
        .background(Color.ariField, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("iOS will ask next. Choose Change to Always Allow.")
    }
}

/// One line of the honest ask: a dotted symbol, what it's about, and the plain answer.
struct HonestRow: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            DotGlyph(symbol: symbol, side: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.ariText)
                Text(text).font(.subheadline).foregroundStyle(.ariSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
