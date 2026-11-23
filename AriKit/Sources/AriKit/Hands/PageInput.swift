import CoreGraphics
import Foundation

// Your hand on the streamed page: where a touch on the picture lands on the page, what a finger's
// movement means (a tap, a scroll, or a held drag), what the phone's typing sends, and which
// keyboard a field wants.

/// How the page's picture sits on screen: the viewport drawn across `width` points, edge to edge,
/// and shifted up by `shift` points while the keyboard needs the room. Touches map by the
/// viewport's size, never by the picture's pixels.
public struct PageGeometry: Sendable, Equatable {
    /// The viewport, in CSS pixels.
    public var page: CGSize
    /// How wide the picture is drawn, in points.
    public var width: Double
    /// How far the picture is shifted up, in points.
    public var shift: Double

    public init(page: CGSize, width: Double, shift: Double = 0) {
        self.page = page
        self.width = width
        self.shift = shift
    }

    /// Points on screen for each CSS pixel.
    public var scale: Double { page.width > 0 ? width / page.width : 1 }

    /// How tall the picture is drawn.
    public var height: Double { page.height * scale }

    /// The page's CSS point under a point on the picture's frame, kept inside the viewport.
    public func page(at point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(0, point.x / scale), page.width),
            y: min(max(0, (point.y + shift) / scale), page.height))
    }

    /// Where a rectangle on the page sits on screen.
    public func screen(_ rect: PageRect) -> CGRect {
        CGRect(
            x: rect.x * scale, y: rect.y * scale - shift, width: rect.width * scale,
            height: rect.height * scale)
    }

    /// How far to shift the picture up so a field whose middle is at `y` (on the unshifted
    /// picture) sits in the room above the keyboard, `room` points tall, as Safari scrolls a field
    /// into view. No shift when it's already in view; never past the picture's end.
    public static func shift(toShow y: Double, room: Double, height: Double) -> Double {
        let margin = 72.0
        guard room > 0, y > room - margin else { return 0 }
        return min(max(0, y - room / 2), max(0, height - room))
    }
}

/// What a finger on the picture means, turned into what the stream carries: a quick touch is a
/// tap; a moving one scrolls, with a fling carrying on after it lifts; one held still first, then
/// moved, drags as a finger does (a slider, a map); held and lifted, it's a long press.
public struct TouchMapper: Sendable {
    /// How far a finger moves before it's no longer a tap, in points.
    public static let slop = 8.0
    /// How long a finger rests before it presses and holds, in seconds.
    public static let hold = 0.45

    public var geometry: PageGeometry
    /// The scroll still to carry on with after a finger lifted mid-movement.
    public private(set) var fling: Fling?

    private var state = State.idle

    private enum State: Sendable {
        case idle
        case pending(start: CGPoint, at: TimeInterval)
        case scrolling(last: CGPoint, at: TimeInterval, velocity: CGVector)
        case dragging(last: CGPoint)
    }

    public init(geometry: PageGeometry) { self.geometry = geometry }

    /// Whether a finger is on the page.
    public var isTouching: Bool {
        if case .idle = state { false } else { true }
    }

    public mutating func began(_ point: CGPoint, at time: TimeInterval) -> [BrowserInput] {
        fling = nil
        state = .pending(start: point, at: time)
        return []
    }

    /// Called while the finger rests, such as by a timer: once it has rested long enough, it presses
    /// and holds.
    public mutating func rested(at time: TimeInterval) -> [BrowserInput] {
        guard case .pending(let start, let began) = state, time - began >= Self.hold else {
            return []
        }
        state = .dragging(last: start)
        return [touch(.start, start)]
    }

    public mutating func moved(_ point: CGPoint, at time: TimeInterval) -> [BrowserInput] {
        switch state {
        case .idle:
            return []
        case .pending(let start, let began):
            guard hypot(point.x - start.x, point.y - start.y) > Self.slop else { return [] }
            if time - began >= Self.hold {
                state = .dragging(last: point)
                return [touch(.start, start), touch(.move, point)]
            }
            state = .scrolling(last: point, at: time, velocity: .zero)
            return [scroll(at: start, from: start, to: point)]
        case .scrolling(let last, let at, let velocity):
            let elapsed = max(time - at, 1.0 / 240)
            let instant = CGVector(
                dx: (point.x - last.x) / elapsed, dy: (point.y - last.y) / elapsed)
            let smoothed = CGVector(
                dx: 0.7 * instant.dx + 0.3 * velocity.dx, dy: 0.7 * instant.dy + 0.3 * velocity.dy)
            state = .scrolling(last: point, at: time, velocity: smoothed)
            return [scroll(at: point, from: last, to: point)]
        case .dragging:
            state = .dragging(last: point)
            return [touch(.move, point)]
        }
    }

    public mutating func ended(_ point: CGPoint, at time: TimeInterval) -> [BrowserInput] {
        defer { state = .idle }
        switch state {
        case .idle:
            return []
        case .pending(let start, let began):
            guard time - began < Self.hold else {
                return [touch(.start, start), touch(.end, start)]
            }
            let spot = geometry.page(at: start)
            return [.tap(x: spot.x, y: spot.y)]
        case .scrolling(let last, let at, let velocity):
            var inputs: [BrowserInput] = []
            if point != last { inputs.append(scroll(at: point, from: last, to: point)) }
            // A finger that stopped before lifting doesn't fling.
            if time - at < 0.08 {
                let scale = geometry.scale
                let spot = geometry.page(at: point)
                let fling = Fling(
                    at: spot, velocity: CGVector(dx: -velocity.dx / scale, dy: -velocity.dy / scale)
                )
                self.fling = fling.isMoving ? fling : nil
            }
            return inputs
        case .dragging:
            return [touch(.end, point)]
        }
    }

    public mutating func cancelled() -> [BrowserInput] {
        defer { state = .idle }
        if case .dragging(let last) = state { return [touch(.cancel, last)] }
        return []
    }

    /// The next stretch of a fling, `elapsed` seconds on; `nil` once it has come to rest.
    public mutating func flung(_ elapsed: TimeInterval) -> BrowserInput? {
        guard var fling else { return nil }
        let input = fling.step(elapsed)
        self.fling = fling.isMoving ? fling : nil
        return input
    }

    private func touch(_ phase: BrowserInput.TouchPhase, _ point: CGPoint) -> BrowserInput {
        let spot = geometry.page(at: point)
        return .touch(phase, x: spot.x, y: spot.y)
    }

    /// A finger moving from `from` to `to` scrolls the page the other way: up the screen is down
    /// the page.
    private func scroll(at point: CGPoint, from: CGPoint, to: CGPoint) -> BrowserInput {
        let spot = geometry.page(at: point)
        let scale = geometry.scale
        return .scroll(
            x: spot.x, y: spot.y, dx: -(to.x - from.x) / scale, dy: -(to.y - from.y) / scale)
    }
}

/// A scroll carrying on after the finger lifted, slowing as a scroll view's does.
public struct Fling: Sendable, Equatable {
    /// Where on the page, in CSS pixels.
    public var at: CGPoint
    /// CSS pixels a second, in the page's scroll direction.
    public var velocity: CGVector

    /// Below this, in CSS pixels a second, it has come to rest.
    static let rest = 30.0

    public var isMoving: Bool { hypot(velocity.dx, velocity.dy) >= Self.rest }

    /// Scrolls on for `elapsed` seconds, slowing as it goes.
    public mutating func step(_ elapsed: TimeInterval) -> BrowserInput {
        let input = BrowserInput.scroll(
            x: at.x, y: at.y, dx: velocity.dx * elapsed, dy: velocity.dy * elapsed)
        let decay = pow(0.998, elapsed * 1000)
        velocity = CGVector(dx: velocity.dx * decay, dy: velocity.dy * decay)
        return input
    }
}

/// The native field laid over the page's field, and what each change to it sends. An empty field
/// is filled whole on every change, so iOS's own filling of a password or a code lands exactly. One
/// that already held text when it took the focus keeps it: typing adds where the page's caret is,
/// and deleting past what you typed deletes on the page, until a password or a code filled in at
/// once replaces it all.
public struct FieldMirror: Sendable, Equatable {
    /// What the native field holds.
    public private(set) var text = ""
    /// Whether the page's field held text this one doesn't show.
    public private(set) var keepsPageText: Bool

    public init(field: FocusedField) {
        keepsPageText = field.length > 0
    }

    /// The native field changed to `new`: typed, deleted, pasted or filled in by iOS.
    public mutating func change(to new: String, pasted: Bool = false) -> [BrowserInput] {
        defer { text = new }
        guard new != text else { return [] }
        guard keepsPageText else { return [.fill(new)] }
        if text.isEmpty, !pasted, new.count > 1 {
            // Filled in at once, as iOS fills a password: it replaces what was there.
            keepsPageText = false
            return [.fill(new)]
        }
        return TypedEdit.inputs(from: text, to: new)
    }

    /// Delete with the native field empty: on the page, it deletes what was there before.
    public mutating func deleteWhenEmpty() -> [BrowserInput] {
        keepsPageText && text.isEmpty ? [.key(.backspace)] : []
    }
}

/// What the phone's typing sends. The native field mirrors what you've typed into the page's field
/// since it took the focus, with the caret at its end; each change becomes the keys that make the
/// same change on the page: back over what follows, delete what went, type what came, and forward
/// again.
public enum TypedEdit {
    public static func inputs(from old: String, to new: String) -> [BrowserInput] {
        guard old != new else { return [] }
        let before = Array(old)
        let after = Array(new)
        var prefix = 0
        while prefix < before.count, prefix < after.count, before[prefix] == after[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < before.count - prefix, suffix < after.count - prefix,
            before[before.count - 1 - suffix] == after[after.count - 1 - suffix]
        {
            suffix += 1
        }
        let removed = before.count - prefix - suffix
        let inserted = String(after[prefix..<(after.count - suffix)])
        var inputs = [BrowserInput](repeating: .key(.arrowLeft), count: suffix)
        inputs += [BrowserInput](repeating: .key(.backspace), count: removed)
        if !inserted.isEmpty { inputs.append(.text(inserted)) }
        inputs += [BrowserInput](repeating: .key(.arrowRight), count: suffix)
        return inputs
    }
}

/// The keyboard a page's field wants, so iOS offers what fits: Passwords for a login, the code
/// from Messages for a one-time code, the @ key for an email.
public struct KeyboardSpec: Sendable, Equatable {
    public var content: Content
    public var keys: Keys
    /// Typed as dots.
    public var isSecure: Bool
    public var corrects: Bool
    public var capitalises: Bool
    public var returnKey: ReturnKey

    /// What iOS should offer to fill it with.
    public enum Content: Sendable, Equatable {
        case username, password, oneTimeCode, emailAddress, telephoneNumber, url, none
    }

    public enum Keys: Sendable, Equatable {
        case standard, email, numberPad, phonePad, url, webSearch
    }

    public enum ReturnKey: Sendable, Equatable {
        case go, next, search, done
    }

    /// The keyboard for `field`, knowing what Kumo asked your hand for: in a login, an email or
    /// plain field is the username, so iOS offers your saved passwords.
    public init(field: FocusedField, need: BrowserNeedKind?) {
        let label = field.label.lowercased()
        let login = need?.shown == .login
        let looksLikeCode = ["code", "verification", "one-time", "otp", "passcode"].contains {
            label.contains($0)
        }
        let looksLikeUser = ["user", "email", "e-mail", "login", "sign in", "account"].contains {
            label.contains($0)
        }
        isSecure = false
        corrects = false
        capitalises = false
        returnKey = .go
        switch field.kind.shown {
        case .password:
            content = .password
            keys = .standard
            isSecure = true
        case .code:
            content = .oneTimeCode
            keys = .numberPad
            returnKey = .done
        case .email:
            content = login ? .username : .emailAddress
            keys = .email
        case .tel:
            content = looksLikeCode || need?.shown == .code ? .oneTimeCode : .telephoneNumber
            keys = .phonePad
            returnKey = .done
        case .url:
            content = .url
            keys = .url
        case .search:
            content = .none
            keys = .webSearch
            returnKey = .search
            corrects = true
        case .number:
            content = looksLikeCode || need?.shown == .code ? .oneTimeCode : .none
            keys = .numberPad
            returnKey = .done
        default:
            if looksLikeCode || (need?.shown == .code && !looksLikeUser) {
                content = .oneTimeCode
                keys = .numberPad
                returnKey = .done
            } else if login || looksLikeUser {
                content = .username
                keys = label.contains("mail") ? .email : .standard
            } else {
                content = .none
                keys = .standard
                corrects = true
                capitalises = true
            }
        }
    }
}
