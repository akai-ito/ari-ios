import AriKit
import EventKit
import EventKitUI
import SwiftUI

/// An event from Coming up, opened in Apple's own event view: details, the map, editing. The box
/// owns the calendar; the phone finds the same event by its iCal UID, since iCloud syncs it here.
struct CalendarEventView: View {
    let item: CalendarItem

    @State private var event: EKEvent?
    @State private var looked = false
    @Environment(\.dismiss) private var dismiss

    private static let store = EKEventStore()

    var body: some View {
        Group {
            if let event {
                EventViewController(event: event, store: Self.store) { dismiss() }
                    .ignoresSafeArea()
            } else if looked {
                details
            } else {
                ProgressView().tint(.ariSecondary)
            }
        }
        .task { await find() }
    }

    /// When the phone can't see it (calendar access refused, or iCloud hasn't synced it yet): what
    /// the box knows, plainly.
    private var details: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("When", value: Self.when(item))
                    if let location = item.location { LabeledContent("Where", value: location) }
                    LabeledContent("Calendar", value: item.calendar.name)
                } footer: {
                    Text("Allow calendar access in Settings to open it in Calendar.")
                }
                .listRowBackground(Color.ariSurface)
            }
            .scrollContentBackground(.hidden)
            .background(.ariBackground)
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func find() async {
        defer { looked = true }
        guard (try? await Self.store.requestFullAccessToEvents()) == true else { return }
        let matches = Self.store.calendarItems(withExternalIdentifier: item.uid)
            .compactMap { $0 as? EKEvent }
        event = matches.min { distance($0) < distance($1) }
    }

    /// A repeating event shares one UID: the occurrence nearest the box's start time.
    private func distance(_ event: EKEvent) -> TimeInterval {
        abs(event.startDate.timeIntervalSince(item.start.date))
    }

    private static func when(_ item: CalendarItem) -> String {
        if item.allDay {
            return item.start.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
        let start = item.start.date.formatted(.dateTime.weekday(.abbreviated).day().hour().minute())
        let end = item.end.date.formatted(.dateTime.hour().minute())
        return "\(start)–\(end)"
    }
}

private struct EventViewController: UIViewControllerRepresentable {
    let event: EKEvent
    let store: EKEventStore
    let done: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = EKEventViewController()
        controller.event = event
        controller.allowsEditing = true
        controller.delegate = context.coordinator
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, EKEventViewDelegate {
        let done: () -> Void
        init(done: @escaping () -> Void) { self.done = done }

        func eventViewController(
            _ controller: EKEventViewController, didCompleteWith action: EKEventViewAction
        ) {
            done()
        }
    }
}
