#if DEBUG
    import MapKit
    import SwiftUI

    // MARK: - Naming the places Kumo doesn't know: Kumo on the map

    struct UnknownSpot {
        let place: LifePlace
        let when: String
        let ask: String
        let guesses: [String]
        let index: Int

        static let dalry = UnknownSpot(
            place: LifeData.unknown, when: "Last Tuesday · 19:40 to 21:40 · off Dalry Road",
            ask: "Tuesday, 2 hours here. What was it?",
            guesses: ["Five-a-side", "A class", "Someone's place", "Something else…"], index: 0)
        static let market = UnknownSpot(
            place: LifeData.market, when: "Saturday · 10:50 to 11:30 · off Leith Walk",
            ask: "Saturday, 40 minutes here, around 11. What was it?",
            guesses: ["A market", "Brunch", "A shop", "Something else…"], index: 1)
    }

    struct NamingCard: View {
        let spot: UnknownSpot
        var look: MapLook = .muted
        var lit: String?

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                ZStack(alignment: .topLeading) {
                    LifeMap(
                        scene: MapScene(
                            region: MKCoordinateRegion(
                                center: .init(
                                    latitude: spot.place.lat + 0.0012, longitude: spot.place.lon),
                                span: .init(latitudeDelta: 0.008, longitudeDelta: 0.012)),
                            heat: [HeatPoint(coordinate: spot.place.coordinate, weight: 0.5)],
                            spread: 26, kumo: spot.place.coordinate, kumoSize: 62,
                            kumoMood: .bright),
                        look: look, step: 4.5
                    )
                    .frame(height: 236)
                    SpeechLine(text: spot.ask)
                        .padding(.top, 16)
                        .padding(.horizontal, 16)
                }
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous))
                VStack(alignment: .leading, spacing: 14) {
                    Text(spot.when).font(.caption).foregroundStyle(.ariTertiary)
                    FlowChips(words: spot.guesses, lit: lit)
                    HStack {
                        Text("Not a place").font(.footnote).foregroundStyle(.ariTertiary)
                        Text("·").foregroundStyle(.ariTertiary)
                        Text("Skip").font(.footnote).foregroundStyle(.ariTertiary)
                        Spacer()
                        HStack(spacing: 5) {
                            ForEach(0..<3, id: \.self) { i in
                                Circle()
                                    .fill(i == spot.index ? Color.ariBone : Color.ariLine)
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .background(
                Color.ariSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    /// Kumo's line, in a bone bubble with a tail down toward it.
    struct SpeechLine: View {
        let text: String

        var body: some View {
            Text(text)
                .font(.system(.body, design: .serif).weight(.medium))
                .foregroundStyle(.ariBackground)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Color.ariBone, in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay(alignment: .bottom) {
                    Triangle().fill(Color.ariBone).frame(width: 16, height: 10).offset(y: 9)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
    }

    nonisolated struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            Path { p in
                p.move(to: CGPoint(x: rect.minX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                p.closeSubpath()
            }
        }
    }

    struct FlowChips: View {
        let words: [String]
        var lit: String?

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(words.prefix(2), id: \.self) { Chip(text: $0, lit: $0 == lit) }
                }
                HStack(spacing: 8) {
                    ForEach(words.dropFirst(2), id: \.self) { Chip(text: $0, lit: $0 == lit) }
                }
            }
        }
    }

    /// Getting to know you, with the places Kumo can't name as a deck of cards.
    struct KnowYouPlaces: View {
        var second = false

        var body: some View {
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    Spacer().frame(height: 14)
                    VStack(alignment: .leading, spacing: 20) {
                        Capsule().fill(Color.ariLine).frame(width: 38, height: 5)
                            .frame(maxWidth: .infinity)
                        HStack(spacing: 12) {
                            KumoFace(mood: .bright, size: 40, still: true)
                            Text("Getting to know you").font(.ariHeading).foregroundStyle(.ariText)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            KnowRow(title: "Your mornings", lit: 6)
                            KnowRow(title: "How you write", lit: 5)
                            KnowRow(title: "Your places", lit: 3, new: true)
                        }
                        HStack {
                            SectionHead(text: "Places I can't name yet · \(second ? 2 : 3)")
                            Spacer()
                        }
                        if second {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark").font(.caption.weight(.bold))
                                Text("Dalry on Tuesdays is Omar's five-a-side. I'll remember.")
                                    .font(.system(.footnote, design: .serif))
                            }
                            .foregroundStyle(.ariSecondary)
                        }
                        NamingCard(
                            spot: second ? .market : .dalry, look: second ? .halftone : .muted
                        )
                        // The next card, waiting at the edge: swipe to it.
                        .background(alignment: .trailing) {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.ariSurface.opacity(0.6))
                                .frame(width: 60)
                                .padding(.vertical, 14)
                                .offset(x: 34)
                        }
                        Text(
                            "Swipe for the next one. No rush: I'll ask in passing too, one at a time."
                        )
                        .font(.footnote)
                        .foregroundStyle(.ariTertiary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 34, topTrailingRadius: 34, style: .continuous
                        )
                        .fill(Color.ariBackground)
                    )
                    .ignoresSafeArea(edges: .bottom)
                }
            }
        }
    }

    struct KnowRow: View {
        let title: String
        let lit: Int
        var new = false

        var body: some View {
            HStack {
                Text(title).font(.body).foregroundStyle(.ariText)
                if new {
                    Text("new").font(.caption2.weight(.semibold)).foregroundStyle(.ariBackground)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.ariBone, in: Capsule())
                }
                Spacer()
                HStack(spacing: 3) {
                    ForEach(0..<9, id: \.self) { i in
                        Circle().fill(i < lit ? Color.ariBone : Color.ariLine).frame(
                            width: 5, height: 5
                        )
                        .padding(.leading, i % 3 == 0 && i > 0 ? 4 : 0)
                    }
                }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.ariTertiary)
            }
        }
    }

    // MARK: - First run: asking for Always and Precise, honestly

    struct FirstRunLocation: View {
        var body: some View {
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
                    Text(
                        "iOS asks twice: While Using first, then Always. Keep Precise Location on."
                    )
                    .font(.footnote).foregroundStyle(.ariTertiary)
                    VStack(spacing: 12) {
                        Text("Allow location")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.ariBackground)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Color.ariBone, in: Capsule())
                        Text("Not now").font(.body).foregroundStyle(.ariSecondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(Color.ariBackground)
        }
    }

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
        }
    }

    /// The second ask: from While Using to Always, with Precise on, and what happens without it.
    struct FirstRunAlways: View {
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
                    "iOS gave me While Using. For your trail I need Always, so I can keep the stops when Ito's closed. iOS will offer it next; pick the second button."
                )
                .font(.ariBody).foregroundStyle(.ariSecondary).lineSpacing(3)
                VStack(spacing: 0) {
                    VStack(spacing: 6) {
                        Text(
                            "Allow “Ito” to also use your location even when you are not using the app?"
                        )
                        .font(.headline).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        Text("Ito keeps your places and trail on your own server.")
                            .font(.footnote).multilineTextAlignment(.center).foregroundStyle(
                                .ariSecondary)
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
                .background(
                    Color.ariField, in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
                .padding(.horizontal, 18)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Precise Location").font(.body).foregroundStyle(.ariText)
                        Text("Without it, places blur to a few hundred metres.").font(.caption)
                            .foregroundStyle(.ariTertiary)
                    }
                    Spacer()
                    Toggle("", isOn: .constant(true)).labelsHidden().tint(.green)
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
            }
            .padding(.horizontal, 24)
            .background(Color.ariBackground)
        }
    }
#endif
