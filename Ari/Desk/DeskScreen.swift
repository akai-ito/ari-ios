import AriKit
import SwiftUI

/// Where Ito opens: Kumo, big, a sixth of the way down, on its cushion; its line under it, in its
/// mood; the day's light behind; and today as a thread at the foot. Three cues live in the scene:
/// - the bubble, "2 for you", only while something waits on you, which opens just that list and is
///   the only thing Kumo glances at;
/// - over Kumo's shoulder, the moon from the night's dream until you've seen it, then the sun by
///   day, low and amber in the evening, and nothing from midnight until the dream; either opens one
///   page, last night above today's plans and what's done;
/// - Kumo itself, which opens Getting to know you.
/// At night Kumo sleeps; while it dreams, its thoughts drift up and form words, and a tap watches
/// the dream as a weave. The thread opens your day.
struct DeskScreen: View {
    let session: Session
    let model: AppModel

    @Environment(Dreams.self) private var dreams: Dreams?
    @State private var opened: Opened?
    /// What's wrong on the server, opened from "Something's wrong ›" to see how to fix it.
    @State private var showsProblems = false
    @State private var watching = false
    /// The words that drift up while Kumo dreams: the day's subjects.
    @State private var dreamWords: [String] = []

    enum Opened: Identifiable, Equatable {
        case needsYou
        case sky(Sky)
        case knowYou
        case day

        var id: String {
            switch self {
            case .needsYou: "needs"
            case .sky: "sky"
            case .knowYou: "know"
            case .day: "day"
            }
        }
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = DeskClock.now(context.date)
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    Spacer().frame(height: geometry.size.height / 6)
                    kumo(now: now, width: geometry.size.width, top: geometry.size.height / 6)
                    words(asleep: DreamReading.asleep(now: now, state: dreams?.state))
                        .padding(.top, 34)
                    Spacer(minLength: 16)
                    thread(now: now).padding(.bottom, 30)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 28)
            .animation(
                .smooth(duration: 0.8), value: DreamReading.sky(now: now, state: dreams?.state))
        }
        .background { DayLight().ignoresSafeArea() }
        .overlay(alignment: .top) {
            topLine
                .padding(.top, 10)
                .padding(.horizontal, 24)
                .transition(.opacity)
        }
        .sheet(item: $opened) { opened in
            sheet(opened)
        }
        .sheet(isPresented: $showsProblems) { ProblemsSheet(problems: session.problems) }
        .fullScreenCover(isPresented: $watching) {
            WeaveScreen(session: session).environment(dreams)
        }
        // Once the server has nothing wrong, there's nothing left to fix.
        .onChange(of: session.problems.isEmpty) { _, fixed in
            if fixed { showsProblems = false }
        }
        .task(id: isDreaming) {
            guard isDreaming else { return }
            let day = WeaveSource.day(of: nil, now: DeskClock.now())
            let material = await WeaveSource.material(for: day, session: session)
            let words = DreamReading.words(from: material.threads)
            dreamWords = words.isEmpty ? [WeaveSource.weekday(day)] : words
        }
        .animation(.smooth(duration: 0.5), value: session.desk?.line)
        .animation(.smooth(duration: 0.35), value: session.problems)
        .animation(.smooth(duration: 0.35), value: waiting)
        .animation(.smooth(duration: 0.6), value: isDreaming)
        #if DEBUG
            .task {
                try? await Task.sleep(for: .seconds(1))
                switch DebugScript.desk {
                case "needs", "upto": opened = .needsYou
                case "sky", "line", "done", "today", "plans", "plan", "wrong", "lower":
                    opened = .sky(DreamReading.sky(now: DeskClock.now(), state: dreams?.state))
                case "know", "tracks", "question": opened = .knowYou
                case "day": opened = .day
                case "problems": showsProblems = true
                case "weave": watching = true
                default: break
                }
            }
        #endif
    }

    private var mood: FaceMood { FaceMood(session.desk?.line?.mood) }

    private var waiting: Int { session.desk?.waiting.count ?? 0 }

    private var isDreaming: Bool { dreams?.dreaming != nil }

    /// The top of the scene: the weather, or the offer to show it. The offline marker ("Offline ·
    /// updated 14:02") takes this same slot when the Desk is read from the cache.
    @ViewBuilder
    private var topLine: some View {
        if let ambient = session.desk?.ambient {
            AmbientLine(ambient: ambient)
        } else if offersWeather {
            WeatherOffer(allow: model.whereabouts.ask, decline: model.declineWeather)
        }
    }

    /// Where the weather would sit, the first time it could: once the Desk is up, until you've
    /// answered, and never again after you closed it.
    private var offersWeather: Bool {
        session.desk != nil && model.whereabouts.permission == .notAsked && !model.declinedWeather
    }

    // MARK: Kumo and its cues

    /// Kumo, which opens Getting to know you (or, while it dreams, the dream); beside it the bubble
    /// when something waits; over its shoulder the moon or the sun.
    private func kumo(now: Date, width: CGFloat, top: CGFloat) -> some View {
        let asleep = DreamReading.asleep(now: now, state: dreams?.state)
        let sky = DreamReading.sky(now: now, state: dreams?.state)
        return Button {
            if isDreaming { watching = true } else { opened = .knowYou }
        } label: {
            Group {
                if asleep {
                    // Its z's until the dream; after it, the moon says it's done.
                    SleepingKumo(size: 150, dreaming: isDreaming, zs: sky == .none)
                } else {
                    KumoFace(
                        mood: mood, size: 150,
                        glance: waiting > 0 ? CGPoint(x: 3.6, y: 0.2) : nil)
                }
            }
            .transition(.opacity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDreaming ? "\(LeadName.current), dreaming" : "Getting to know you")
        .accessibilityValue(
            asleep ? "\(LeadName.current) is asleep" : "\(LeadName.current) looks \(mood.spoken)"
        )
        .accessibilityHint(isDreaming ? "Watch the dream" : "")
        .overlay(alignment: .bottom) {
            if isDreaming {
                // Thoughts drift up off Kumo into the space above it, and form words there: from
                // the top of the Desk down to Kumo's foot, the full width of the screen.
                let height = top + 150 * 0.92
                let head = height - 150 * 0.92 / 2 - 58
                DreamDrift(
                    words: dreamWords,
                    kumoTop: CGPoint(x: (width + 56) / 2, y: head),
                    wordCentre: CGPoint(x: (width + 56) / 2, y: max(44, head - 72)),
                    fontSize: 64
                )
                .frame(width: width + 56, height: height)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            if waiting > 0 {
                Button {
                    opened = .needsYou
                } label: {
                    Text("\(waiting) for you")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.ariBone)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.ariBone.opacity(0.17)))
                        .overlay(
                            Capsule().strokeBorder(Color.ariBone.opacity(0.45), lineWidth: 0.7))
                }
                .buttonStyle(.plain)
                .fixedSize()
                // Level with Kumo's eyes, clear of what floats above it, such as its z's.
                .offset(x: 98, y: 30)
                .accessibilityLabel(
                    waiting == 1 ? "1 thing needs you" : "\(waiting) things need you"
                )
                .transition(.opacity)
            }
        }
        .overlay(alignment: .topLeading) {
            if sky != .none {
                Button {
                    opened = .sky(sky)
                } label: {
                    SkyGlyph(sky: sky, side: 62)
                        .padding(8)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .id(sky)
                // Over Kumo's left shoulder, clear of its twinkle and z's on the right.
                .offset(x: -80, y: -46)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
                .accessibilityLabel(sky.spoken)
                .accessibilityHint(
                    sky == .moon
                        ? "What \(LeadName.current) did overnight" : "Today's plans and what's done"
                )
            }
        }
    }

    /// Kumo's line, in its own hand, and under it, only while something on the server needs you,
    /// "Something's wrong ›". While Kumo dreams, it says so, with a way to watch.
    private func words(asleep: Bool) -> some View {
        VStack(spacing: 14) {
            if isDreaming {
                VStack(spacing: 10) {
                    Text("Sorting through yesterday.")
                        .font(.system(.title2, design: .serif).italic())
                        .foregroundStyle(.ariSecondary)
                        .multilineTextAlignment(.center)
                    Button("Dreaming · tap to watch") { watching = true }
                        .font(.footnote)
                        .foregroundStyle(.ariTertiary)
                        .buttonStyle(.plain)
                }
                .transition(.opacity)
            } else if let line = session.desk?.line {
                Text(line.text)
                    .font(
                        Self.isQuote(line.text)
                            ? .system(.title2, design: .serif).italic()
                            : .system(.title2, design: .serif)
                    )
                    .foregroundStyle(asleep ? Color.ariSecondary : .ariText)
                    .lineSpacing(5)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(line.at)
                    .transition(.opacity)
            }
            if !session.problems.isEmpty {
                Button {
                    showsProblems = true
                } label: {
                    Text(
                        "\(ProblemLook.line(session.problems)) \(Text("›").foregroundStyle(.ariTertiary))"
                    )
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.ariBone)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows what's wrong, and how to fix it")
                .transition(.opacity)
            }
        }
        .frame(maxWidth: 320)
    }

    /// Kumo's line as a quote, such as “Rest is not idleness.”, sets in italics.
    static func isQuote(_ text: String) -> Bool {
        let quotes: Set<Character> = ["“", "\""]
        return text.first.map(quotes.contains) == true
    }

    /// Today as a thread, which opens your day.
    private func thread(now: Date) -> some View {
        let today = DayReading.group(on: now, desk: session.desk, now: now)
        let next = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        let tomorrow = DayReading.group(on: next, desk: session.desk, now: now)
        return Button {
            opened = .day
        } label: {
            DayThread(
                events: DayReading.knots(today), tomorrow: DayReading.knots(tomorrow).first,
                now: now
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows your day")
    }

    // MARK: What it opens

    @ViewBuilder
    private func sheet(_ opened: Opened) -> some View {
        Group {
            switch opened {
            case .needsYou:
                NeedsYouSheet(session: session, mood: mood)
            case .sky(let sky):
                #if DEBUG
                    SkyPage(session: session, sky: sky, opensAtFirst: DebugScript.desk)
                #else
                    SkyPage(session: session, sky: sky)
                #endif
            case .knowYou:
                #if DEBUG
                    KnowYouPage(
                        session: session, mood: mood,
                        opensQuestion: DebugScript.desk == "question")
                #else
                    KnowYouPage(session: session, mood: mood)
                #endif
            case .day:
                day
            }
        }
        // What waits on you is a short list: half the screen, unless it's long.
        .presentationDetents(opened == .needsYou ? [.medium, .large] : [.large])
        .presentationDragIndicator(.visible)
        .environment(dreams)
    }

    private var day: some View {
        #if DEBUG
            DayView(
                session: session,
                shownGuess: DebugScript.guess.flatMap {
                    ["open": DayView.GuessShown.open, "correct": .correct][$0]
                })
        #else
            DayView(session: session)
        #endif
    }
}
