import AriKit
import SwiftUI

/// What the weave is built from: the day's threads and mail, read from the box, and the dream's
/// record once there is one.
@MainActor
enum WeaveSource {
    /// The day a dream looks back on: its own, or for one under way, yesterday before noon.
    static func day(of dream: Dream?, now: Date) -> String {
        if let dream { return dream.day }
        let calendar = Calendar.current
        let date =
            calendar.component(.hour, from: now) < 12
            ? calendar.date(byAdding: .day, value: -1, to: now) ?? now : now
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// "Monday" for `2026-11-30`.
    static func weekday(_ day: String) -> String {
        guard let date = LocalTime(day)?.date else { return "the day" }
        return date.formatted(.dateTime.weekday(.wide))
    }

    /// The day's threads, newest first, and the mail read that day, as far as the box says.
    static func material(for day: String, session: Session) async -> (threads: [String], mail: Int)
    {
        async let list = try? session.threads()
        async let work = try? session.work(day: day)
        let threads = (await list).map { list in
            (list.open + list.threads)
                .filter { thread in
                    let start = LocalTime(day)?.date ?? .distantPast
                    let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
                    return thread.lastAt.date >= start && thread.lastAt.date < end
                }
                .compactMap(\.title)
        }
        var seen = Set<String>()
        let unique = (threads ?? []).filter { seen.insert($0).inserted }
        let mail = (await work).map { work in
            work.cleared.count + work.handled.filter { $0.mail != nil }.count
        }
        return (unique, mail ?? 0)
    }

    static func scene(
        for dream: Dream?, threads: [String], mail: Int, session: Session, now: Date
    ) -> WeaveScene {
        WeaveScene.make(
            day: weekday(day(of: dream, now: now)), threads: threads, mailRead: mail, dream: dream,
            plans: session.desk?.plans ?? [], comingUp: session.desk?.comingUp ?? [])
    }
}

/// The dream, live, full screen: "Tap to watch" on the sleeping Desk opens it. Kumo weaves the day
/// as it dreams: gathering, then tying for as long as it takes, then tomorrow once the record comes.
/// Under Reduce Motion each moment is a still that fades to the next.
struct WeaveScreen: View {
    let session: Session

    @Environment(Dreams.self) private var dreams: Dreams?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var material: (threads: [String], mail: Int) = ([], 0)
    @State private var clock = WeaveClock(mode: .live, started: .now)
    /// Whether the weave has reached tomorrow and holds still.
    @State private var finished = false

    var body: some View {
        ZStack {
            Color.ariBackground.ignoresSafeArea()
            RadialGradient(
                colors: [Color(red: 0.45, green: 0.5, blue: 0.7).opacity(0.12), .clear],
                center: UnitPoint(x: 0.45, y: 0.4), startRadius: 0, endRadius: 420
            )
            .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                header
                if reduceMotion {
                    still
                } else {
                    TimelineView(.animation(minimumInterval: 1 / 30, paused: finished)) {
                        context in
                        moment(at: context.date)
                    }
                }
            }
        }
        .task {
            // Opened just as the dream finished: straight through to its record.
            if record != nil, clock.recorded == nil {
                clock.recordedFrom = 0
                clock.recorded = .now
            }
            material = await WeaveSource.material(
                for: WeaveSource.day(of: record, now: DeskClock.now()), session: session)
        }
        .onChange(of: dreams?.dreaming == nil) { _, done in
            guard done, clock.recorded == nil else { return }
            clock.recordedFrom = clock.progress(at: .now)
            clock.recorded = .now
        }
        // Once it has woven tomorrow, it stops drawing.
        .task(id: clock.recorded) {
            guard let recorded = clock.recorded else { return }
            let left = 6.2 - Date.now.timeIntervalSince(recorded)
            if left > 0 { try? await Task.sleep(for: .seconds(left)) }
            finished = true
        }
        .preferredColorScheme(.dark)
    }

    /// The dream's record, once it has finished.
    private var record: Dream? { dreams?.dreaming == nil ? dreams?.latest : nil }

    private var scene: WeaveScene {
        WeaveSource.scene(
            for: record, threads: material.threads, mail: material.mail, session: session,
            now: DeskClock.now())
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record == nil ? "Dreaming" : "Dreamt")
                    .font(.ariHeading)
                    .foregroundStyle(.ariText)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.ariText)
                    .frame(width: 40, height: 40)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
    }

    /// "04:03 · weaving Monday".
    private var subtitle: String {
        let since = dreams?.dreaming?.since.date ?? record?.startedAt.date ?? .now
        return "\(since.formatted(DeskTime.time)) · weaving \(scene.day)"
    }

    private func moment(at date: Date) -> some View {
        let progress = clock.progress(at: date)
        let time = date.timeIntervalSince(clock.started)
        return content(progress: progress, time: time)
    }

    /// Under Reduce Motion: where the dream is, still; the record's moment once it has come.
    private var still: some View {
        content(progress: record == nil ? 1.9 : 3, time: 0)
            .animation(.easeInOut(duration: 0.8), value: record?.id)
    }

    private func content(progress: Double, time: Double) -> some View {
        let scene = scene
        let caption = WeaveClock.caption(scene, progress: progress, time: time)
        return VStack(spacing: 0) {
            WeaveCanvas(scene: scene, progress: progress, time: time)
                .padding(.top, 40)
                .padding(.bottom, 20)
            Text(caption)
                .font(.system(.title3, design: .serif).italic())
                .foregroundStyle(.ariSecondary)
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 36)
                .frame(height: 96, alignment: .top)
                .id(caption)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.6), value: caption)
                .accessibilityAddTraits(.updatesFrequently)
            WeavePhaseDots(progress: progress)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 26)
        }
    }
}

/// Last night's weave, small at the top of its page: it rests on the finished weave, and a tap
/// replays it in twelve seconds, then rests again. Under Reduce Motion the replay steps through its
/// three moments with a fade.
struct WeaveReplayStrip: View {
    let scene: WeaveScene

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playing: Date?

    static let seconds = 12.0

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let playing {
                    if reduceMotion {
                        TimelineView(.periodic(from: playing, by: Self.seconds / 3)) { context in
                            let step = min(
                                3,
                                1
                                    + Int(
                                        context.date.timeIntervalSince(playing) / (Self.seconds / 3)
                                    ))
                            WeaveCanvas(scene: scene, progress: Double(step), compact: true)
                                .id(step)
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.6), value: step)
                        }
                    } else {
                        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                            let elapsed = context.date.timeIntervalSince(playing)
                            WeaveCanvas(
                                scene: scene, progress: min(3, elapsed / Self.seconds * 3),
                                time: elapsed, compact: true)
                        }
                    }
                } else {
                    WeaveCanvas(scene: scene, progress: 3, compact: true, resting: true)
                }
            }
            .padding(.vertical, 14)
            Button {
                play()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: playing == nil ? "play.fill" : "stop.fill").font(.caption2)
                    Text(playing == nil ? "Replay last night · \(Int(Self.seconds)) s" : "Stop")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.ariText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular.interactive(), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(10)
            .accessibilityLabel(playing == nil ? "Replay last night's dream" : "Stop the replay")
        }
        .frame(height: 200)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.ariText.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.ariLine.opacity(0.7), lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 20, style: .continuous))
        .task(id: playing) {
            guard playing != nil else { return }
            try? await Task.sleep(for: .seconds(Self.seconds + 0.5))
            playing = nil
        }
    }

    private func play() {
        playing = playing == nil ? .now : nil
    }
}
