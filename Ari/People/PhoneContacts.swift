import AriKit
import Contacts
import ContactsUI
import SwiftUI

/// A person's card in the phone's own Contacts, for "Contact card" on their page. The box links
/// people to iCloud cards over CardDAV, whose ids aren't the phone's, so the first time a card is
/// opened the phone matches it by phone numbers, email addresses and name (see ``ContactMatch``)
/// and remembers the pairing. Contacts permission is asked then, not before.
@MainActor
final class PhoneContacts {
    static let shared = PhoneContacts()

    /// Why no card opened, in plain words.
    enum Problem: Error, Equatable {
        case refused
        case notFound
        /// Two contacts could be them: better to say so than to open the wrong one.
        case unsure
    }

    private let store = CNContactStore()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The phone's contact for `person`, asking for Contacts the first time.
    func contact(for person: ContactMatch.Facts) async -> Result<CNContact, Problem> {
        guard await allowed() else { return .failure(.refused) }
        let keys = Self.keys
        if let id = paired[person.id],
            let contact = try? store.unifiedContact(withIdentifier: id, keysToFetch: keys)
        {
            return .success(contact)
        }
        let candidates = Self.candidates(for: person, keys: keys, from: store)
        let facts = candidates.map(Self.facts)
        guard let id = ContactMatch.best(for: person, among: facts),
            let contact = candidates.first(where: { $0.identifier == id })
        else { return .failure(candidates.isEmpty ? .notFound : .unsure) }
        paired[person.id] = id
        return .success(contact)
    }

    /// Asks for Contacts once; limited access counts, for the contacts you shared.
    private func allowed() async -> Bool {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited: return true
        case .notDetermined: return (try? await store.requestAccess(for: .contacts)) ?? false
        default: return false
        }
    }

    /// The box's person ids, paired with the phone's contact ids.
    private var paired: [String: String] {
        get { defaults.dictionary(forKey: "contactPairs") as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: "contactPairs") }
    }

    private static var keys: [any CNKeyDescriptor] {
        [
            CNContactViewController.descriptorForRequiredKeys(),
            CNContactGivenNameKey as any CNKeyDescriptor,
            CNContactFamilyNameKey as any CNKeyDescriptor,
            CNContactNicknameKey as any CNKeyDescriptor,
            CNContactPhoneNumbersKey as any CNKeyDescriptor,
            CNContactEmailAddressesKey as any CNKeyDescriptor,
        ]
    }

    /// Contacts that share a number, an address or a name with them: indexed lookups, quick
    /// enough to make here.
    private static func candidates(
        for person: ContactMatch.Facts, keys: [any CNKeyDescriptor], from store: CNContactStore
    ) -> [CNContact] {
        var predicates: [NSPredicate] = []
        predicates += person.phones.map {
            CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: $0))
        }
        predicates += person.emails.map { CNContact.predicateForContacts(matchingEmailAddress: $0) }
        predicates += person.names.map { CNContact.predicateForContacts(matchingName: $0) }
        var found: [String: CNContact] = [:]
        for predicate in predicates {
            let contacts =
                (try? store.unifiedContacts(matching: predicate, keysToFetch: keys)) ?? []
            for contact in contacts { found[contact.identifier] = contact }
        }
        return Array(found.values)
    }

    private static func facts(_ contact: CNContact) -> ContactMatch.Facts {
        let full = [contact.givenName, contact.familyName].filter { !$0.isEmpty }
            .joined(separator: " ")
        return ContactMatch.Facts(
            id: contact.identifier,
            names: [full, contact.nickname].filter { !$0.isEmpty },
            phones: contact.phoneNumbers.map(\.value.stringValue),
            emails: contact.emailAddresses.map { $0.value as String })
    }
}

extension View {
    /// "Contact card": opens the phone's card for `person` in a sheet, Apple's own view, asking for
    /// Contacts the first time. Set `person` to open it; it goes back to `nil` when closed.
    func contactCard(for person: Binding<ContactMatch.Facts?>) -> some View {
        sheet(item: person) { facts in
            ContactCardSheet(person: facts)
        }
    }
}

/// The sheet behind "Contact card": finding the card, then Apple's `CNContactViewController`, or
/// a plain line on why there's none.
struct ContactCardSheet: View {
    let person: ContactMatch.Facts

    @Environment(\.dismiss) private var dismiss
    @State private var found: Result<CNContact, PhoneContacts.Problem>?

    var body: some View {
        Group {
            switch found {
            case .success(let contact):
                ContactCardView(contact: contact) { dismiss() }
                    .ignoresSafeArea()
            case .failure(let problem):
                missing(problem)
            case nil:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.ariBackground)
        .task { found = await PhoneContacts.shared.contact(for: person) }
    }

    private func missing(_ problem: PhoneContacts.Problem) -> some View {
        VStack(spacing: 16) {
            Text(Self.words(problem, name: person.names.first ?? "them"))
                .font(.ariBody).foregroundStyle(.ariSecondary)
                .multilineTextAlignment(.center)
            if problem == .refused {
                Button("Open iOS Settings", action: PlacesAsk.openSettings)
                    .buttonStyle(.borderedProminent).tint(.ariBone).foregroundStyle(.ariBackground)
            }
            Button("Close") { dismiss() }.foregroundStyle(.ariSecondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents([.medium])
    }

    static func words(_ problem: PhoneContacts.Problem, name: String) -> String {
        switch problem {
        case .refused:
            "Ito can't see your contacts. Allow Contacts for Ito in iOS Settings to open \(name)'s card here."
        case .notFound:
            "There's no card for \(name) in this phone's contacts."
        case .unsure:
            "More than one of your contacts could be \(name), so Ito won't guess."
        }
    }
}

/// Apple's contact card, in its own navigation bar with Done.
struct ContactCardView: UIViewControllerRepresentable {
    let contact: CNContact
    let done: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let card = CNContactViewController(for: contact)
        card.allowsEditing = true
        card.allowsActions = true
        card.navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .done, primaryAction: UIAction { _ in context.coordinator.done() })
        return UINavigationController(rootViewController: card)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {
        context.coordinator.done = done
    }

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator {
        var done: () -> Void
        init(done: @escaping () -> Void) { self.done = done }
    }
}
