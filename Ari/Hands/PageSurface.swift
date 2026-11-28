import AriKit
import SwiftUI
import UIKit

/// The streamed page in a takeover, edge to edge, at the size of the room it has here: it tells the
/// server that room, and how much of it the keyboard covers, and the page's viewport follows, so
/// nothing sits under the bar or the keyboard. Your taps and scrolls go to the page, and when a
/// field on it takes the focus, a real text field lies over it, invisible, so the iOS keyboard types
/// into the page with Passwords, codes from Messages and paste. On a payment, the site's own button
/// has a ring around it; while the picture isn't live, it dims.
struct PageSurface: UIViewRepresentable {
    let stream: BrowserStream
    /// What Kumo asked your hand for: in a login, the email field is the username.
    let need: BrowserNeedKind?
    /// Whether what you do reaches the page.
    let live: Bool
    /// Whether the keyboard is up.
    var keyboard = false
    let send: (BrowserInput) -> Void

    func makeUIView(context: Context) -> PageSurfaceView {
        PageSurfaceView()
    }

    func updateUIView(_ view: PageSurfaceView, context: Context) {
        view.send = send
        view.need = need
        view.live = live
        view.keyboardUp = keyboard
        view.show(
            picture: stream.picture, count: stream.pictures,
            page: stream.view.map { CGSize(width: $0.width, height: $0.height) })
        view.focus(live ? stream.focus : nil)
        view.ring(live ? stream.mark : nil)
        view.dims(stream.isReconnecting)
    }
}

final class PageSurfaceView: UIView, UITextFieldDelegate {
    var send: (BrowserInput) -> Void = { _ in }
    var need: BrowserNeedKind?
    var live = false {
        didSet {
            guard live != oldValue else { return }
            // Holding the page again: the server hears the room afresh.
            reported = nil
            reportRoom()
        }
    }
    var keyboardUp = false {
        didSet { if keyboardUp != oldValue { reportRoom() } }
    }

    private let picture = UIImageView()
    private let field = PageTextField()
    private var shown = -1
    private var page = CGSize(width: 390, height: 844)
    private var mapper = TouchMapper(geometry: PageGeometry(page: .zero, width: 0))
    private var tracked: UITouch?
    private var rest: Timer?
    private var fling: CADisplayLink?
    private var focusedField: FocusedField?
    private var mirror: FieldMirror?
    private var pasting = false
    private let markRing = UIView()
    private var shownMark: PageMark?
    /// The room's height while the keyboard is down, and the room last told to the server.
    private var fullHeight: CGFloat = 0
    private var reported: Room?

    private struct Room: Equatable {
        let width: Double
        let height: Double
        let keyboard: Double
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        backgroundColor = .white
        isMultipleTouchEnabled = false
        picture.contentMode = .scaleToFill
        picture.isUserInteractionEnabled = false
        addSubview(picture)
        // Invisible: the page draws its own text and caret in the stream.
        field.textColor = .clear
        field.tintColor = .clear
        field.backgroundColor = .clear
        field.borderStyle = .none
        field.delegate = self
        field.isHidden = true
        field.addTarget(self, action: #selector(changed), for: .editingChanged)
        field.deletedWhenEmpty = { [weak self] in
            guard let self, var mirror = self.mirror else { return }
            mirror.deleteWhenEmpty().forEach(self.send)
            self.mirror = mirror
        }
        field.willPaste = { [weak self] in self?.pasting = true }
        markRing.isUserInteractionEnabled = false
        markRing.isHidden = true
        markRing.layer.borderWidth = 2.5
        markRing.layer.cornerRadius = 10
        markRing.layer.borderColor = UIColor(Color.ariBone).cgColor
        addSubview(markRing)
        addSubview(field)
        isAccessibilityElement = true
        accessibilityLabel = "The page Kumo was on"
        accessibilityTraits = .allowsDirectInteraction
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The latest picture of the page, drawn only when it's new.
    func show(picture data: Data?, count: Int, page: CGSize?) {
        if let page, page != self.page {
            self.page = page
            setNeedsLayout()
            // A page at another size than the room told, such as one that opened before the
            // server heard it, gets the room again, once.
            if let reported,
                page != CGSize(width: reported.width, height: reported.height - reported.keyboard)
            {
                self.reported = nil
                reportRoom()
            }
        }
        guard count != shown, let data, let image = UIImage(data: data) else { return }
        shown = count
        picture.image = image
    }

    /// The field with the focus: the native field goes over it with the keyboard it wants, or away.
    func focus(_ next: FocusedField?) {
        guard next != focusedField else { return }
        let before = focusedField
        focusedField = next
        guard let next else {
            mirror = nil
            field.text = ""
            field.isHidden = true
            if field.isFirstResponder { field.resignFirstResponder() }
            return
        }
        // The same field moving as the page scrolls keeps what you typed.
        let same = before.map { $0.kind == next.kind && $0.label == next.label } ?? false
        if !same || mirror == nil {
            mirror = FieldMirror(field: next)
            field.text = ""
            configure(KeyboardSpec(field: next, need: need))
        }
        field.isHidden = false
        setNeedsLayout()
        layoutIfNeeded()
        if !field.isFirstResponder {
            field.becomeFirstResponder()
        } else if !same {
            field.reloadInputViews()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var geometry = PageGeometry(page: page, width: bounds.width)
        // With the keyboard up, the field you're typing in comes into view, as Safari scrolls it.
        if let focusedField {
            let shift = PageGeometry.shift(
                toShow: focusedField.box.midY * geometry.scale, room: bounds.height,
                height: geometry.height)
            geometry.shift = shift
        }
        mapper.geometry = geometry
        picture.frame = CGRect(
            x: 0, y: -geometry.shift, width: bounds.width, height: geometry.height)
        if let focusedField {
            field.frame = geometry.screen(focusedField.box).insetBy(dx: 0, dy: 0)
        }
        if let shownMark {
            markRing.frame = geometry.screen(shownMark.box).insetBy(dx: -5, dy: -5)
        }
        if !keyboardUp, bounds.height > 0 { fullHeight = bounds.height }
        reportRoom()
    }

    /// Tells the server the room the page has here, and how much of it the keyboard covers, when
    /// that changes; it makes the page's viewport the room above the keyboard.
    private func reportRoom() {
        guard live, bounds.width > 0, bounds.height > 0 else { return }
        let full = max(fullHeight, bounds.height)
        let keyboard = keyboardUp ? max(0, full - bounds.height) : 0
        let room = Room(
            width: bounds.width.rounded(), height: full.rounded(), keyboard: keyboard.rounded())
        guard room != reported else { return }
        reported = room
        send(.viewport(width: room.width, height: room.height, keyboard: room.keyboard))
    }

    /// The site's own pay button, ringed, or no ring.
    func ring(_ mark: PageMark?) {
        guard mark != shownMark else { return }
        shownMark = mark
        markRing.isHidden = mark == nil
        markRing.accessibilityLabel = mark.map { "Press \($0.label) yourself" }
        setNeedsLayout()
    }

    /// While the picture isn't live, it dims, so it never passes for the page as it is now.
    func dims(_ reconnecting: Bool) {
        let alpha: CGFloat = reconnecting ? 0.45 : 1
        guard picture.alpha != alpha else { return }
        UIView.animate(withDuration: 0.25) { self.picture.alpha = alpha }
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard live, tracked == nil, let touch = touches.first else { return }
        tracked = touch
        stopFling()
        mapper.began(touch.location(in: self), at: touch.timestamp).forEach(send)
        rest?.invalidate()
        rest = Timer.scheduledTimer(withTimeInterval: TouchMapper.hold + 0.01, repeats: false) {
            [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.mapper.rested(at: CACurrentMediaTime()).forEach(self.send)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let tracked, touches.contains(tracked) else { return }
        let inputs = mapper.moved(tracked.location(in: self), at: tracked.timestamp)
        if !inputs.isEmpty { rest?.invalidate() }
        inputs.forEach(send)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let tracked, touches.contains(tracked) else { return }
        rest?.invalidate()
        mapper.ended(tracked.location(in: self), at: tracked.timestamp).forEach(send)
        self.tracked = nil
        if mapper.fling != nil { startFling() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let tracked, touches.contains(tracked) else { return }
        rest?.invalidate()
        mapper.cancelled().forEach(send)
        self.tracked = nil
    }

    private func startFling() {
        stopFling()
        let link = CADisplayLink(target: self, selector: #selector(flung(_:)))
        link.add(to: .main, forMode: .common)
        fling = link
    }

    private func stopFling() {
        fling?.invalidate()
        fling = nil
    }

    @objc private func flung(_ link: CADisplayLink) {
        guard let input = mapper.flung(link.targetTimestamp - link.timestamp) else {
            return stopFling()
        }
        send(input)
    }

    // MARK: - Typing

    private func configure(_ spec: KeyboardSpec) {
        field.textContentType =
            switch spec.content {
            case .username: .username
            case .password: .password
            case .oneTimeCode: .oneTimeCode
            case .emailAddress: .emailAddress
            case .telephoneNumber: .telephoneNumber
            case .url: .URL
            case .none: nil
            }
        field.keyboardType =
            switch spec.keys {
            case .standard: .default
            case .email: .emailAddress
            case .numberPad: .numberPad
            case .phonePad: .phonePad
            case .url: .URL
            case .webSearch: .webSearch
            }
        field.returnKeyType =
            switch spec.returnKey {
            case .go: .go
            case .next: .next
            case .search: .search
            case .done: .done
            }
        field.isSecureTextEntry = spec.isSecure
        field.autocorrectionType = spec.corrects ? .default : .no
        field.spellCheckingType = spec.corrects ? .default : .no
        field.autocapitalizationType = spec.capitalises ? .sentences : .none
        field.smartQuotesType = .no
        field.smartDashesType = .no
    }

    @objc private func changed() {
        guard var mirror else { return }
        mirror.change(to: field.text ?? "", pasted: pasting).forEach(send)
        self.mirror = mirror
        pasting = false
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        send(.key(.enter))
        return false
    }
}

/// The native field over the page's: it says when you delete with nothing in it, which deletes on
/// the page, and when you paste.
final class PageTextField: UITextField {
    var deletedWhenEmpty: () -> Void = {}
    var willPaste: () -> Void = {}

    override func deleteBackward() {
        if text?.isEmpty ?? true { deletedWhenEmpty() }
        super.deleteBackward()
    }

    override func paste(_ sender: Any?) {
        willPaste()
        super.paste(sender)
    }
}
