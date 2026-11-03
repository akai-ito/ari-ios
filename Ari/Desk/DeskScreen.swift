import AriKit
import SwiftUI

/// Where Ito opens: Kumo, big, a sixth of the way down, on its cushion; its line under it, in its
/// mood; the day's light behind; and today as a thread at the foot. Kumo is the only door: tapping
/// it opens What I'm up to, and when something waits for you a small "2 for you" sits beside it,
/// which Kumo glances at. The thread opens your day. Nothing on it moves Kumo.
struct DeskScreen: View {
    let session: Session

    @State private var showsUpTo = false
    @State private var showsDay = false
    /// What's wrong on the server, opened from "Something's wrong ›" to see how to fix it.
    @State private var showsProblems = false

    var body: some View {
        TimelineView(.everyMinute) { context in
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    Spacer().frame(height: geometry.size.height / 6)
                    kumo
                    words.padding(.top, 34)
                    Spacer(minLength: 16)
                    thread(now: context.date).padding(.bottom, 30)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 28)
        }
        .background { DayLight().ignoresSafeArea() }
        .overlay(alignment: .top) {
            if let ambient = session.desk?.ambient {
                AmbientLine(ambient: ambient)
                    .padding(.top, 10)
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showsUpTo) { upTo }
        .sheet(isPresented: $showsDay) { day }
        .sheet(isPresented: $showsProblems) { ProblemsSheet(problems: session.problems) }
        // Once the server has nothing wrong, there's nothing left to fix.
        .onChange(of: session.problems.isEmpty) { _, fixed in
            if fixed { showsProblems = false }
        }
        .animation(.smooth(duration: 0.5), value: session.desk?.line)
        .animation(.smooth(duration: 0.35), value: session.problems)
        .animation(.smooth(duration: 0.35), value: waiting)
        #if DEBUG
            .task {
                try? await Task.sleep(for: .seconds(1))
                switch DebugScript.desk {
                case "upto", "wrong", "tracks": showsUpTo = true
                case "day": showsDay = true
                case "problems": showsProblems = true
                default: break
                }
            }
        #endif
    }

    private var mood: FaceMood { FaceMood(session.desk?.line?.mood) }

    private var waiting: Int { session.desk?.waiting.count ?? 0 }

    /// Kumo, the only door, and beside it the one cue when something waits for you.
    private var kumo: some View {
        Button {
            showsUpTo = true
        } label: {
            KumoFace(
                mood: mood, size: 150, glance: waiting > 0 ? CGPoint(x: 3.6, y: 0.2) : nil)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("What \(LeadName.current)'s up to")
        .accessibilityValue("\(LeadName.current) looks \(mood.spoken)")
        .overlay(alignment: .topTrailing) {
            if waiting > 0 {
                Button {
                    showsUpTo = true
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
    }

    /// Kumo's line, in its own hand, and under it, only while something on the server needs you,
    /// "Something's wrong ›".
    private var words: some View {
        VStack(spacing: 14) {
            if let line = session.desk?.line {
                Text(line.text)
                    .font(
                        Self.isQuote(line.text)
                            ? .system(.title2, design: .serif).italic()
                            : .system(.title2, design: .serif)
                    )
                    .foregroundStyle(.ariText)
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
                    Text("Something's wrong \(Text("›").foregroundStyle(.ariTertiary))")
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
            showsDay = true
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

    private var upTo: some View {
        #if DEBUG
            WhatImUpTo(
                session: session, mood: mood, asksWrongAtFirst: DebugScript.desk == "wrong",
                opensAtTracks: DebugScript.desk == "tracks"
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #else
            WhatImUpTo(session: session, mood: mood)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        #endif
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
