import AriKit
import SwiftUI

/// What Kumo did in a space, newest first, by day: each action with its time, and Undo where it
/// can be undone. A day's mail read with nothing needed folds into one line, "31 read, nothing
/// needed", that opens to each with Kumo's reason. Tapping any line tells Kumo it got it wrong, and
/// that becomes a preference.
struct DoneView: View {
    /// The entries loaded so far, newest first.
    let entries: [DoneEntry]
    /// Whether there are older ones. With no entries yet, the first page loads through `loadMore`.
    let hasMore: Bool
    let undo: (DoneEntry) async throws -> Void
    /// Tells Kumo it got an entry wrong, in your words.
    let correct: (DoneEntry, String) async throws -> Void
    /// Loads the next, older page.
    let loadMore: () async throws -> Void

    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .footnote) private var timeWidth: CGFloat = 44
    @State private var openDays: Set<Date> = []
    @State private var correcting: DoneEntry?
    @State private var undoing: DoneID?
    @State private var undone: Set<DoneID> = []
    @State private var undoProblem: (id: DoneID, text: String)?
    @State private var loading = false
    @State private var loadProblem: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if entries.isEmpty && !hasMore {
                    Text("Nothing yet. What Kumo does here shows up in Done.")
                        .font(.subheadline)
                        .foregroundStyle(.ariTertiary)
                        .padding(.top, 8)
                }
                ForEach(
                    Array(Self.days(entries, calendar: calendar).enumerated()), id: \.element.day
                ) { index, day in
                    dayView(day).padding(.top, index == 0 ? 0 : 10)
                }
                if hasMore { more }
                Text("Reply to any line to tell Kumo it got it wrong.")
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: Rhythm.column, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(.ariBackground)
        .navigationTitle("Done")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $correcting) { entry in
            CorrectionSheet(entry: entry) { words in try await correct(entry, words) }
        }
    }

    private func dayView(_ day: Day) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            DeskSectionLabel(DayLabel.describe(day.day, calendar: calendar, time: false))
            ForEach(day.actions) { entry in row(entry) }
            if !day.quiet.isEmpty { quiet(day) }
        }
    }

    private func row(_ entry: DoneEntry) -> some View {
        let layout =
            typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button {
                    correcting = entry
                } label: {
                    layout {
                        Text(entry.at.date, format: DeskTime.time)
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.ariTertiary)
                            .frame(minWidth: timeWidth, alignment: .leading)
                        Text(entry.text)
                            .font(.subheadline)
                            .foregroundStyle(.ariText)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Tell Kumo it got this wrong")
                if entry.undo { undoButton(entry) }
            }
            if let undoProblem, undoProblem.id == entry.id {
                DeskProblemLine(text: undoProblem.text)
                    .padding(.leading, typeSize.isAccessibilitySize ? 0 : timeWidth + 12)
            }
        }
    }

    @ViewBuilder
    private func undoButton(_ entry: DoneEntry) -> some View {
        if undone.contains(entry.id) {
            Text("Undone").font(.footnote).foregroundStyle(.ariTertiary)
        } else if undoing == entry.id {
            ProgressView()
                .controlSize(.small)
                .tint(.ariSecondary)
                .accessibilityLabel("Undoing")
        } else {
            Button("Undo") {
                Task { await performUndo(entry) }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.ariBone)
            .buttonStyle(.plain)
            .disabled(undoing != nil)
            .accessibilityLabel("Undo: \(entry.text)")
        }
    }

    private func performUndo(_ entry: DoneEntry) async {
        guard undoing == nil else { return }
        undoing = entry.id
        undoProblem = nil
        defer { undoing = nil }
        do {
            try await undo(entry)
            undone.insert(entry.id)
        } catch is CancellationError {
        } catch {
            undoProblem = (entry.id, "Couldn't undo it: \(DeskSending.words(for: error))")
        }
    }

    /// The day's quiet mail, folded to one line that opens to each with Kumo's reason.
    private func quiet(_ day: Day) -> some View {
        let open = openDays.contains(day.day)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.smooth(duration: 0.3)) {
                    if open { openDays.remove(day.day) } else { openDays.insert(day.day) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("\(day.quiet.count) read, nothing needed")
                        .font(.subheadline)
                        .foregroundStyle(.ariSecondary)
                    Chevron(isOpen: open)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(day.quiet.count) read, nothing needed")
            .accessibilityValue(open ? "Shown" : "Folded")
            .accessibilityHint(open ? "Folds them" : "Shows each, with why")
            if open {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(day.quiet) { entry in
                        Button {
                            correcting = entry
                        } label: {
                            quietLine(entry)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Tell Kumo it got this wrong")
                    }
                }
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.ariLine).frame(width: 1)
                }
                .transition(.opacity)
            }
        }
        .padding(.top, 4)
    }

    private func quietLine(_ entry: DoneEntry) -> some View {
        let text = Text(entry.text).foregroundStyle(.ariSecondary)
        return Group {
            if let reason = entry.reason {
                Text("\(text)\(Text("  ·  \(reason)").foregroundStyle(.ariTertiary))")
            } else {
                text
            }
        }
        .font(.footnote)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The bottom of what's loaded: the next page loads as it comes into view.
    @ViewBuilder
    private var more: some View {
        Group {
            if let loadProblem {
                VStack(alignment: .leading, spacing: 8) {
                    DeskProblemLine(text: loadProblem)
                    DeskPill(title: "Try again", label: "Try loading earlier ones again") {
                        self.loadProblem = nil
                    }
                }
            } else {
                ProgressView()
                    .tint(.ariSecondary)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Loading earlier ones")
                    // Again after each page, in case the bottom is still in view.
                    .task(id: entries.count) { await load() }
            }
        }
        .padding(.top, 10)
    }

    private func load() async {
        guard !loading, loadProblem == nil else { return }
        loading = true
        defer { loading = false }
        do {
            try await loadMore()
        } catch is CancellationError {
        } catch {
            loadProblem = "Couldn't load earlier ones: \(DeskSending.words(for: error))"
        }
    }

    // MARK: Days

    /// One day of Done: what Kumo did, and the mail it read with nothing needed.
    struct Day {
        let day: Date
        let actions: [DoneEntry]
        let quiet: [DoneEntry]
    }

    /// The entries by the day they fall on, newest day first, each keeping the order given.
    static func days(_ entries: [DoneEntry], calendar: Calendar) -> [Day] {
        var order: [Date] = []
        var byDay: [Date: [DoneEntry]] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.at.date)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(entry)
        }
        return order.sorted(by: >).map { day in
            let entries = byDay[day, default: []]
            return Day(
                day: day, actions: entries.filter { !$0.quiet }, quiet: entries.filter(\.quiet))
        }
    }
}

/// Telling Kumo it got one line of Done wrong, in your words. It goes to the space as a message
/// quoting the line, and Kumo keeps it as a preference.
private struct CorrectionSheet: View {
    let entry: DoneEntry
    let send: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var words = ""
    @State private var sending = DeskSending()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Tell Kumo it got this wrong").font(.headline).foregroundStyle(.ariText)
                Spacer(minLength: 8)
                Button("Cancel") { dismiss() }
                    .font(.subheadline)
                    .foregroundStyle(.ariSecondary)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text).font(.subheadline).foregroundStyle(.ariSecondary)
                if let reason = entry.reason {
                    Text(reason).font(.footnote).foregroundStyle(.ariTertiary)
                }
            }
            .padding(.leading, 12)
            .overlay(alignment: .leading) { Rectangle().fill(Color.ariLine).frame(width: 2) }
            .accessibilityElement(children: .combine)
            TextField(
                entry.quiet ? "Such as: this one needed me" : "What should Kumo have done?",
                text: $words, axis: .vertical
            )
            .font(.subheadline)
            .foregroundStyle(.ariText)
            .lineLimit(2...6)
            .focused($focused)
            .padding(12)
            .background(.ariField, in: .rect(cornerRadius: 14, style: .continuous))
            if let problem = sending.problem { DeskProblemLine(text: problem) }
            HStack {
                Spacer()
                DeskPill(
                    title: "Send", acts: true, busy: sending.isSending,
                    label: "Send it to Kumo"
                ) {
                    let text = words.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task {
                        if await sending.send("send", { try await send(text) }) { dismiss() }
                    }
                }
                .disabled(
                    words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || sending.isSending)
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .presentationDetents([.medium, .large])
        .presentationBackground(.ariSurface)
        .onAppear { focused = true }
    }
}

#if DEBUG
    #Preview("Done") {
        @Previewable @State var page = DeskSamples.donePage
        NavigationStack {
            DoneView(
                entries: page.entries, hasMore: page.hasMore,
                undo: { _ in try await Task.sleep(for: .seconds(1)) },
                correct: { _, _ in try await Task.sleep(for: .seconds(1)) },
                loadMore: {
                    try await Task.sleep(for: .seconds(1))
                    page = DonePage(entries: page.entries + DeskSamples.olderDone, hasMore: false)
                })
        }
        .preferredColorScheme(.dark)
    }
#endif
