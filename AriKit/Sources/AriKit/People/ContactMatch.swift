import Foundation

/// Finds the phone's contact for a person the box knows, once, by phone numbers, email addresses
/// and name. The box's card ids (CardDAV) aren't the phone's, so the app matches and remembers the
/// pairing. A number or an address is sure; a name alone counts only when exactly one contact has
/// it. Two contacts equally sure is no match: better to ask than to open the wrong card.
public enum ContactMatch {
    /// What's known about someone, from the box or from a phone contact.
    public struct Facts: Sendable, Equatable, Identifiable {
        public var id: String
        /// Every name to try: the full name, and a nickname.
        public var names: [String]
        public var phones: [String]
        public var emails: [String]

        public init(id: String, names: [String], phones: [String] = [], emails: [String] = []) {
            self.id = id
            self.names = names
            self.phones = phones
            self.emails = emails
        }
    }

    /// The contact among `candidates` that is `person`, or `nil` when none is, or two could be.
    public static func best(for person: Facts, among candidates: [Facts]) -> String? {
        let phones = Set(person.phones.compactMap(phoneKey))
        let emails = Set(person.emails.map(emailKey).filter { !$0.isEmpty })
        let names = Set(person.names.map(nameKey).filter { !$0.isEmpty })
        let scored = candidates.map { candidate in
            let sure =
                Set(candidate.phones.compactMap(phoneKey)).intersection(phones).count
                + Set(candidate.emails.map(emailKey)).intersection(emails).count
            let named = !Set(candidate.names.map(nameKey)).isDisjoint(with: names)
            return (id: candidate.id, sure: sure, named: named)
        }
        let surest = scored.map(\.sure).max() ?? 0
        if surest > 0 {
            let top = scored.filter { $0.sure == surest }
            if top.count == 1 { return top[0].id }
            let named = top.filter(\.named)
            return named.count == 1 ? named[0].id : nil
        }
        let named = scored.filter(\.named)
        return named.count == 1 ? named[0].id : nil
    }

    /// A number's last nine digits, so `+44 7700 900142` and `07700 900142` agree; too short to
    /// tell apart, `nil`.
    static func phoneKey(_ phone: String) -> String? {
        let digits = phone.filter(\.isASCIIDigit)
        guard digits.count >= 7 else { return nil }
        return String(digits.suffix(9))
    }

    static func emailKey(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// A name without case, accents or extra spaces.
    static func nameKey(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool { isASCII && isNumber }
}

/// The one-tap ways to reach someone, as the links iOS opens: Phone, Messages, FaceTime, Mail and
/// Maps' directions.
public enum ReachLinks {
    /// One of the row of actions on a person's page.
    public enum Action: String, Sendable, CaseIterable {
        case call, message, faceTime, email, directions

        public var title: String {
            switch self {
            case .call: "Call"
            case .message: "Message"
            case .faceTime: "FaceTime"
            case .email: "Email"
            case .directions: "Directions"
            }
        }

        public var symbol: String {
            switch self {
            case .call: "phone.fill"
            case .message: "message.fill"
            case .faceTime: "video.fill"
            case .email: "envelope.fill"
            case .directions: "arrow.triangle.turn.up.right.diamond.fill"
            }
        }
    }

    /// The row for someone, in its fixed order, each with its link or `nil` when there's nothing to
    /// reach them by (drawn dimmed, never hidden, so the row doesn't shift). The first number goes
    /// to Phone, Messages and FaceTime; Messages and FaceTime fall back to the first address.
    public static func actions(phones: [String], emails: [String], address: String?)
        -> [(action: Action, url: URL?)]
    {
        let phone = phones.first
        let email = emails.first
        return [
            (.call, phone.flatMap(call)),
            (.message, (phone ?? email).flatMap(message)),
            (.faceTime, (phone ?? email).flatMap(faceTime)),
            (.email, email.flatMap(self.email)),
            (.directions, address.flatMap { directions(to: $0) }),
        ]
    }

    public static func call(_ phone: String) -> URL? {
        dialable(phone).flatMap { URL(string: "tel:\($0)") }
    }

    /// Messages, to a number or an email address.
    public static func message(_ handle: String) -> URL? {
        handle.contains("@")
            ? URL(string: "sms:\(handle.trimmingCharacters(in: .whitespaces))")
            : dialable(handle).flatMap { URL(string: "sms:\($0)") }
    }

    /// FaceTime, to a number or an email address.
    public static func faceTime(_ handle: String) -> URL? {
        handle.contains("@")
            ? URL(string: "facetime:\(handle.trimmingCharacters(in: .whitespaces))")
            : dialable(handle).flatMap { URL(string: "facetime:\($0)") }
    }

    public static func email(_ address: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("@") else { return nil }
        return URL(string: "mailto:\(trimmed)")
    }

    /// Directions in Maps to an address, from where you are.
    public static func directions(to address: String) -> URL? {
        var components = URLComponents(string: "maps://")
        components?.queryItems = [URLQueryItem(name: "daddr", value: address)]
        return components?.url
    }

    /// Directions in Maps to a place on the map.
    public static func directions(latitude: Double, longitude: Double) -> URL? {
        URL(string: "maps://?daddr=\(latitude),\(longitude)")
    }

    /// A number as a link takes it: digits, and a leading `+`.
    static func dialable(_ phone: String) -> String? {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.filter(\.isASCIIDigit)
        guard !digits.isEmpty else { return nil }
        return (trimmed.hasPrefix("+") ? "+" : "") + digits
    }
}
