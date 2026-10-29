import AriKit
import SwiftUI

/// The pages on one shelf: who and what Ari touched lately, then everyone, A to Z. The Journal is
/// its days by month instead, or a calendar.
struct ShelfView: View {
    let memory: Memory?
    let shelf: String

    @State private var pages: [PageSummary]?
    @State private var problem: String?
    @State private var showsCalendar = false

    var body: some View {
        Group {
            if let problem {
                Form {
                    Text(problem).foregroundStyle(.ariSecondary)
                        .listRowBackground(Color.ariSurface)
                }
            } else if let pages {
                if shelf == "journal" {
                    if showsCalendar {
                        JournalCalendar(months: ShelfReading.months(pages))
                    } else {
                        JournalList(months: ShelfReading.months(pages))
                    }
                } else {
                    ShelfList(pages: pages)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(.ariBackground)
        .navigationTitle(LibraryHome.title(ofShelf: shelf))
        .toolbar {
            if shelf == "journal" {
                ToolbarItem(placement: .primaryAction) {
                    Button(
                        showsCalendar ? "List" : "Calendar",
                        systemImage: showsCalendar ? "list.bullet" : "calendar"
                    ) {
                        withAnimation(.smooth(duration: 0.25)) { showsCalendar.toggle() }
                    }
                }
            }
        }
        // Again once there's a server to ask, when the shelf opened first.
        .task(id: memory != nil) {
            #if DEBUG
                showsCalendar = DebugScript.showsCalendar
            #endif
            guard let memory else { return }
            do throws(RequestError) {
                pages = try await memory.pages(on: shelf)
            } catch {
                problem = "Couldn't load this shelf: \(error.plainWords)"
            }
        }
    }
}

/// Lately, while Ari has touched a few pages since they arrived, then everyone.
private struct ShelfList: View {
    let pages: [PageSummary]

    var body: some View {
        let lately = ShelfReading.lately(pages)
        Form {
            if lately.isEmpty {
                rows(ShelfReading.everyone(pages))
            } else {
                Section {
                    rows(lately)
                } header: {
                    heading("Lately")
                }
                Section {
                    rows(ShelfReading.everyone(pages))
                } header: {
                    heading("Everyone")
                }
            }
        }
    }

    private func rows(_ pages: [PageSummary]) -> some View {
        ForEach(pages) { page in
            NavigationLink(value: page.address) {
                Text(page.title).foregroundStyle(.ariText)
            }
        }
        .listRowBackground(Color.ariSurface)
    }
}

/// The journal's days, by month: the weekday and the day, with the headline Ari wrote for it.
private struct JournalList: View {
    let months: [ShelfReading.Month]

    var body: some View {
        Form {
            ForEach(months) { month in
                Section {
                    ForEach(month.days, id: \.page.address) { day in
                        NavigationLink(value: day.page.address) { row(day, in: month) }
                    }
                    .listRowBackground(Color.ariSurface)
                } header: {
                    heading(Journal.title(of: month))
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ day: ShelfReading.Day, in month: ShelfReading.Month) -> some View {
        let date = Journal.date(month, day.day)
        if let gist = day.page.gist {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(date.formatted(Date.FormatStyle(timeZone: .gmt).weekday(.abbreviated).day()))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.ariTertiary)
                    .frame(width: 58, alignment: .leading)
                Text(gist).foregroundStyle(.ariText)
            }
        } else {
            Text(date.formatted(Date.FormatStyle(timeZone: .gmt).weekday(.wide).day()))
                .foregroundStyle(.ariText)
        }
    }
}

/// The journal as month grids, read newest first, like the list: each month turned end to end, its
/// last day at the top left and the 1st at the bottom right, so scrolling down goes steadily back
/// in time. Each day with an entry is marked, and opens it.
private struct JournalCalendar: View {
    let months: [ShelfReading.Month]

    /// Sunday to Monday, since the weeks run backwards.
    private static let weekdays = ["S", "S", "F", "T", "W", "T", "M"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(months) { month in
                    VStack(alignment: .leading, spacing: 10) {
                        heading(Journal.title(of: month))
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(Self.weekdays.indices, id: \.self) { index in
                                Text(Self.weekdays[index])
                                    .font(.caption2)
                                    .foregroundStyle(.ariTertiary)
                            }
                            ForEach(Journal.cells(month).indices, id: \.self) { index in
                                if let number = Journal.cells(month)[index] {
                                    cell(number, in: month)
                                } else {
                                    Color.clear.frame(height: 40)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: Rhythm.column, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func cell(_ number: Int, in month: ShelfReading.Month) -> some View {
        if let day = month.days.first(where: { $0.day == number }) {
            NavigationLink(value: day.page.address) {
                VStack(spacing: 3) {
                    Text("\(number)").font(.callout.monospacedDigit()).foregroundStyle(.ariText)
                    Circle().fill(.ariText).frame(width: 5, height: 5)
                }
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(.ariSurface, in: .rect(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(day.page.title)
        } else {
            Text("\(number)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.ariTertiary)
                .frame(maxWidth: .infinity, minHeight: 40)
        }
    }
}

/// Dates for the journal's days, in the Gregorian calendar with weeks starting on Monday.
private enum Journal {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = .gmt
        return calendar
    }()

    static func date(_ month: ShelfReading.Month, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: month.year, month: month.month, day: day)) ?? .now
    }

    static func title(of month: ShelfReading.Month) -> String {
        date(month, 1).formatted(Date.FormatStyle(timeZone: .gmt).month(.wide).year())
    }

    static func length(of month: ShelfReading.Month) -> Int {
        calendar.range(of: .day, in: .month, for: date(month, 1))?.count ?? 30
    }

    /// Empty cells before the 1st, so it falls under its weekday.
    static func leadingBlanks(_ month: ShelfReading.Month) -> Int {
        let weekday = calendar.component(.weekday, from: date(month, 1))
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    /// The month's grid, turned end to end: its days from the last to the 1st, each still under
    /// its weekday, with `nil` for the empty cells.
    static func cells(_ month: ShelfReading.Month) -> [Int?] {
        let lead = leadingBlanks(month)
        let days = length(of: month)
        let trail = (7 - (lead + days) % 7) % 7
        let grid =
            [Int?](repeating: nil, count: lead) + (1...days).map(Optional.some)
            + [Int?](repeating: nil, count: trail)
        return grid.reversed()
    }
}

private func heading(_ text: String) -> some View {
    Text(text)
        .font(.ariHeading)
        .foregroundStyle(.ariText)
        .textCase(nil)
}
