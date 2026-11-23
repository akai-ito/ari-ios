import AriKit
import Clocks
import CoreGraphics
import Foundation
import Synchronization
import Testing

/// Kumo's hands: the live line where a task lives, a takeover from asking for the page to handing
/// it back, and what your hand on the streamed page sends.
@MainActor
@Suite("Kumo's hands")
struct HandsTests {
    private static let tablewise = Browser(
        state: .browsing, line: "On Tablewise: choosing Sat 19:30 · step 6", thread: "h_table",
        site: "Tablewise", url: "https://www.tablewise.example/kiln/times",
        doing: "choosing Sat 19:30",
        step: 6)

    private static let login = Browser.Need(kind: .login, why: "Log in, then hand back")

    // MARK: - The live line

    @Test("the line says where Kumo is, what it's doing and the step, in the trail and in main")
    func liveLine() throws {
        let line = try #require(LiveLine(Self.tablewise))
        #expect(line.kind == .browsing)
        #expect(line.text == "On Tablewise · choosing Sat 19:30 · step 6")
        #expect(line.detail == "On Tablewise · step 6")
        #expect(line.hint == "Tap to watch")
        #expect(line.showsPicture)

        // Back after you had the page.
        var later = Self.tablewise
        later.doing = "filling in the checkout"
        later.step = 7
        let back = try #require(LiveLine(later, resumed: true))
        #expect(back.text == "Back on it · filling in the checkout · step 7")
        #expect(back.detail == "Back on it · step 7")

        // Without the parts, the server's own line.
        let bare = Browser(state: .browsing, line: "Looking at the menu")
        #expect(LiveLine(bare)?.text == "Looking at the menu")
    }

    @Test("waiting on you, yours and waiting for a tap each say so; idle has no line")
    func otherLines() throws {
        let needs = Browser(
            state: .needsYou, line: "Needs your hand on Railway", thread: "h_rail", site: "Railway",
            need: Self.login)
        #expect(LiveLine(needs)?.kind == .needsYou)
        #expect(LiveLine(needs)?.text == "Needs your hand on Railway")
        #expect(LiveLine(needs)?.hint == "Tap to take over")
        let yours = Browser(state: .yours, site: "Railway")
        #expect(LiveLine(yours)?.text == "You have the page on Railway")
        #expect(LiveLine(yours)?.hint == "Tap to go back to it")
        let waiting = Browser(state: .waiting, site: "Tablewise", card: "k_1")
        #expect(LiveLine(waiting)?.text == "Waiting for your OK on Tablewise")
        #expect(LiveLine(waiting)?.showsPicture == false)
        #expect(LiveLine(.idle) == nil)
        // A state Ari doesn't know is idle.
        #expect(LiveLine(Browser(state: BrowserState(rawValue: "dreaming"))) == nil)
    }

    @Test("the line shows only where its task lives")
    func linePlace() {
        let hands = Hands(backend: FakeHands())
        hands.follow(Self.tablewise)
        #expect(hands.line(in: "h_table")?.detail == "On Tablewise · step 6")
        #expect(hands.line(in: nil) == nil)
        #expect(hands.line(in: "h_other") == nil)
        hands.follow(.idle)
        #expect(hands.line(in: "h_table") == nil)
    }

    // MARK: - Taking over

    @Test("a takeover holds the page once the server says it's yours, and only then takes input")
    func takeoverMachine() {
        var takeover = Takeover(need: Self.login, thread: "h_rail")
        #expect(takeover.phase == .taking && !takeover.acceptsInput)
        takeover.took(Browser(state: .yours, need: Self.login))
        #expect(takeover.phase == .holding && takeover.acceptsInput)

        // Hand back: in flight, then done.
        let handing = takeover.handBack()
        #expect(handing)
        #expect(!takeover.acceptsInput)
        let again = takeover.handBack()
        #expect(!again, "only once")
        takeover.handedBack()
        #expect(takeover.phase == .handedBack && takeover.isOver)

        // Asked again later.
        let retaking = takeover.retake()
        #expect(retaking)
        takeover.took(Browser(state: .browsing))
        #expect(takeover.phase == .failed("Kumo still has the page. Try again in a moment."))
    }

    @Test("the page going back by itself ends the takeover; a failed hand back keeps it yours")
    func leaseRunsOut() {
        var takeover = Takeover()
        takeover.observed(Browser(state: .yours))
        #expect(takeover.phase == .holding)
        takeover.observed(Browser(state: .browsing))
        #expect(takeover.phase == .lost("The page went back to Kumo."))

        var ended = Takeover()
        ended.took(Browser(state: .yours))
        ended.observed(.idle)
        #expect(ended.phase == .lost("The task is over."))

        var stuck = Takeover()
        stuck.took(Browser(state: .yours))
        _ = stuck.handBack()
        stuck.couldNotHandBack("No connection to your server.")
        #expect(stuck.phase == .holding && stuck.problem == "No connection to your server.")
        // While handing back, the stream saying browsing isn't the page lost.
        _ = stuck.handBack()
        stuck.observed(Browser(state: .browsing))
        #expect(stuck.phase == .handingBack)
    }

    @Test("take over, type, hand back: the trail keeps the hand-off and the line is back on it")
    func takeOverAndHandBack() async throws {
        let backend = FakeHands()
        let socket = FakeSocket()
        socket.script([.awaitSent(1)])
        let hands = Hands(
            backend: backend, now: { Date(timeIntervalSince1970: 1_000) },
            makeStream: { _ in BrowserStream(connect: { socket }) })
        let needs = Browser(
            state: .needsYou, line: "Needs your hand on Railway", thread: "h_rail", site: "Railway",
            need: Self.login)
        hands.follow(needs)
        hands.watch()
        // Connected before anything goes up: what's sent while it's down is dropped.
        try await Task.sleep(for: .milliseconds(20))

        // Before the page is yours, nothing goes up.
        hands.send(.tap(x: 1, y: 1))
        backend.answer = Browser(state: .yours, thread: "h_rail", site: "Railway", need: Self.login)
        await hands.takeOver()
        #expect(hands.showsTakeover)
        #expect(hands.takeover?.phase == .holding)
        #expect(hands.takeover?.need == Self.login)
        hands.send(.text("divy@home.example"))
        try await Task.sleep(for: .milliseconds(60))
        #expect(socket.sent == [.text(BrowserInput.text("divy@home.example").json)])

        // Leave it with me: the screen goes, the page stays yours.
        hands.leave()
        #expect(!hands.showsTakeover && hands.takeover?.phase == .holding)
        await hands.takeOver()
        #expect(hands.showsTakeover && backend.takes == 2, "coming back moves the lease on")

        backend.answer = Browser(
            state: .browsing, thread: "h_rail", site: "Railway", doing: "filling in the checkout",
            step: 7)
        await hands.handBack()
        #expect(!hands.showsTakeover && hands.takeover == nil)
        #expect(backend.handBacks == 1)
        let handoff = try #require(hands.handoffs(in: "h_rail").first)
        #expect(handoff.asked == "Needed you to log in")
        #expect(handoff.answered == "You logged in and handed back")
        #expect(handoff.at == Date(timeIntervalSince1970: 1_000))
        #expect(hands.line(in: "h_rail")?.text == "Back on it · filling in the checkout · step 7")
        hands.unwatch()
    }

    @Test("a page that went back by itself says so on the trail")
    func wentBackByItself() throws {
        let hands = Hands(backend: FakeHands())
        hands.follow(Browser(state: .yours, thread: "h_rail", need: Self.login))
        hands.follow(Browser(state: .browsing, thread: "h_rail", site: "Railway", step: 8))
        let handoff = try #require(hands.handoffs(in: "h_rail").first)
        #expect(!handoff.handedBack)
        #expect(handoff.answered == "The page went back to Kumo")
        #expect(hands.resumed)
        hands.follow(.idle)
        #expect(!hands.resumed)
    }

    @Test("a takeover the server refuses says why, and can be asked for again")
    func refusedTakeover() async {
        let backend = FakeHands()
        backend.failure = .refused(status: 503, error: nil, retryAfter: nil)
        let hands = Hands(backend: backend)
        await hands.takeOver()
        #expect(hands.takeover?.phase == .failed("Kumo's browser isn't on."))
        backend.failure = nil
        backend.answer = Browser(state: .yours)
        await hands.takeOver()
        #expect(hands.takeover?.phase == .holding)
    }

    // MARK: - Your hand on the page

    @Test("a touch maps by the viewport's size, with the picture's shift")
    func geometry() {
        let geometry = PageGeometry(page: CGSize(width: 390, height: 844), width: 390 * 1.25)
        #expect(geometry.scale == 1.25)
        #expect(geometry.page(at: CGPoint(x: 125, y: 250)) == CGPoint(x: 100, y: 200))
        // Never outside the viewport.
        #expect(geometry.page(at: CGPoint(x: -5, y: 5_000)) == CGPoint(x: 0, y: 844))
        let shifted = PageGeometry(page: CGSize(width: 390, height: 844), width: 390, shift: 100)
        #expect(shifted.page(at: CGPoint(x: 10, y: 10)) == CGPoint(x: 10, y: 110))
        #expect(
            shifted.screen(PageRect(x: 10, y: 300, width: 100, height: 40))
                == CGRect(x: 10, y: 200, width: 100, height: 40))
        // A field low on the page moves up into the room above the keyboard; one in view stays.
        #expect(PageGeometry.shift(toShow: 500, room: 400, height: 844) == 300)
        #expect(PageGeometry.shift(toShow: 200, room: 400, height: 844) == 0)
        #expect(PageGeometry.shift(toShow: 840, room: 400, height: 844) == 444)
    }

    @Test("a quick touch is a tap; a moving one scrolls the other way, in CSS pixels")
    func tapAndScroll() {
        var mapper = TouchMapper(
            geometry: PageGeometry(page: CGSize(width: 400, height: 800), width: 200))
        _ = mapper.began(CGPoint(x: 50, y: 100), at: 0)
        let slight = mapper.moved(CGPoint(x: 53, y: 102), at: 0.05)
        #expect(slight.isEmpty, "inside the slop")
        let tap = mapper.ended(CGPoint(x: 53, y: 102), at: 0.1)
        #expect(tap == [.tap(x: 100, y: 200)])

        _ = mapper.began(CGPoint(x: 50, y: 300), at: 1)
        // Up the screen by 20 points is down the page by 40 CSS pixels.
        let scrolled = mapper.moved(CGPoint(x: 50, y: 280), at: 1.02)
        #expect(
            scrolled
                == [.scroll(x: 100, y: 600, dx: 0, dy: 40)])
        let further = mapper.moved(CGPoint(x: 50, y: 270), at: 1.04)
        #expect(
            further
                == [.scroll(x: 100, y: 540, dx: 0, dy: 20)])
        let lifted = mapper.ended(CGPoint(x: 50, y: 270), at: 1.05)
        #expect(lifted.isEmpty)
        // Lifted mid-movement: it flings on, slowing, until it rests.
        var steps = 0
        var travelled = 0.0
        while let step = mapper.flung(1.0 / 60) {
            if case .scroll(_, _, _, let dy) = step { travelled += dy }
            steps += 1
            if steps > 600 { break }
        }
        #expect(steps > 5 && steps < 600)
        #expect(travelled > 0, "on down the page")
        #expect(mapper.fling == nil)
    }

    @Test("held still, then moved, it drags as a finger; held and lifted, a long press")
    func holdAndDrag() {
        var mapper = TouchMapper(
            geometry: PageGeometry(page: CGSize(width: 400, height: 800), width: 400))
        _ = mapper.began(CGPoint(x: 10, y: 10), at: 0)
        let resting = mapper.rested(at: 0.2)
        #expect(resting.isEmpty)
        let held = mapper.rested(at: 0.5)
        #expect(held == [.touch(.start, x: 10, y: 10)])
        let dragged = mapper.moved(CGPoint(x: 60, y: 10), at: 0.6)
        #expect(dragged == [.touch(.move, x: 60, y: 10)])
        let dropped = mapper.ended(CGPoint(x: 80, y: 10), at: 0.7)
        #expect(dropped == [.touch(.end, x: 80, y: 10)])

        _ = mapper.began(CGPoint(x: 30, y: 30), at: 1)
        let pressed = mapper.ended(CGPoint(x: 30, y: 30), at: 1.6)
        #expect(
            pressed
                == [.touch(.start, x: 30, y: 30), .touch(.end, x: 30, y: 30)])

        _ = mapper.began(CGPoint(x: 30, y: 30), at: 2)
        _ = mapper.rested(at: 2.5)
        let cancelled = mapper.cancelled()
        #expect(cancelled == [.touch(.cancel, x: 30, y: 30)])
    }

    @Test("typing, deleting, pasting and fixing a letter mid-word each send what the page needs")
    func typing() {
        #expect(TypedEdit.inputs(from: "", to: "d") == [.text("d")])
        #expect(TypedEdit.inputs(from: "div", to: "divy@home.example") == [.text("y@home.example")])
        #expect(TypedEdit.inputs(from: "divy", to: "di") == [.key(.backspace), .key(.backspace)])
        // A whole field replaced, as autofill does.
        #expect(
            TypedEdit.inputs(from: "dvy", to: "sam")
                == [.key(.backspace), .key(.backspace), .key(.backspace), .text("sam")])
        // A letter fixed mid-word: back over the end, fix it, forward again.
        #expect(
            TypedEdit.inputs(from: "hullo", to: "hello")
                == [
                    .key(.arrowLeft), .key(.arrowLeft), .key(.arrowLeft), .key(.backspace),
                    .text("e"), .key(.arrowRight), .key(.arrowRight), .key(.arrowRight),
                ])
        #expect(TypedEdit.inputs(from: "same", to: "same").isEmpty)
    }

    @Test("an empty field is filled whole; one that held text keeps it until iOS fills it in")
    func mirror() {
        var empty = FieldMirror(field: FocusedField(kind: .email, length: 0))
        let typed = empty.change(to: "d")
        #expect(typed == [.fill("d")])
        let filled = empty.change(to: "divy@home.example")
        #expect(filled == [.fill("divy@home.example")])
        let cleared = empty.change(to: "")
        #expect(cleared == [.fill("")])
        let nothing = empty.deleteWhenEmpty()
        #expect(nothing.isEmpty)

        var held = FieldMirror(field: FocusedField(kind: .text, length: 5))
        let added = held.change(to: "s")
        #expect(added == [.text("s")])
        let back = held.change(to: "")
        #expect(back == [.key(.backspace)])
        let pastBack = held.deleteWhenEmpty()
        #expect(pastBack == [.key(.backspace)])
        let pasted = held.change(to: "Window seat", pasted: true)
        #expect(pasted == [.text("Window seat")])

        var password = FieldMirror(field: FocusedField(kind: .password, length: 8))
        let autofilled = password.change(to: "correct-horse")
        #expect(autofilled == [.fill("correct-horse")])
        #expect(!password.keepsPageText)
    }

    @Test("each field gets the keyboard and the autofill it wants")
    func keyboards() {
        func spec(_ kind: FieldKind, _ label: String = "", need: BrowserNeedKind? = nil)
            -> KeyboardSpec
        {
            KeyboardSpec(field: FocusedField(kind: kind, label: label), need: need)
        }
        let password = spec(.password, "Password", need: .login)
        #expect(password.content == .password && password.isSecure)
        #expect(spec(.code).content == .oneTimeCode && spec(.code).keys == .numberPad)
        #expect(spec(.email, "Email address", need: .login).content == .username)
        #expect(spec(.email, "Email address").content == .emailAddress)
        #expect(spec(.email).keys == .email)
        #expect(spec(.text, "Username", need: .login).content == .username)
        #expect(spec(.text, "Verification code").content == .oneTimeCode)
        #expect(spec(.text, "", need: .code).content == .oneTimeCode)
        #expect(spec(.number, "Enter the 6-digit code").content == .oneTimeCode)
        #expect(spec(.tel, "Mobile").content == .telephoneNumber)
        #expect(spec(.url).content == .url)
        #expect(spec(.search).returnKey == .search)
        let plain = spec(.text, "Special requests")
        #expect(plain.content == .none && plain.corrects)
        // A kind Ari doesn't know types as text.
        #expect(spec(FieldKind(rawValue: "colour"), "Notes") == plain)
    }

    // MARK: - The stream

    @Test("the stream's frames read as the contract writes them")
    func frames() {
        func event(_ json: String) -> BrowserStreamEvent {
            BrowserStreamEvent(json: Data(json.utf8))
        }
        #expect(
            event(
                #"{"type":"view","url":"https://railway.example/login","width":390,"height":844,"tab":1,"tabs":2}"#
            )
                == .view(
                    PageView(url: "https://railway.example/login", width: 390, height: 844, tabs: 2)
                ))
        #expect(
            event(
                #"{"type":"focus","field":{"kind":"password","label":"Password","box":{"x":16,"y":302,"width":358,"height":48},"length":0}}"#
            )
                == .focus(
                    FocusedField(
                        kind: .password, label: "Password",
                        box: PageRect(x: 16, y: 302, width: 358, height: 48), length: 0)))
        #expect(event(#"{"type":"focus"}"#) == .focus(nil))
        #expect(
            event(#"{"type":"refused","message":"Take over first."}"#)
                == .refused("Take over first."))
        #expect(event(#"{"type":"ended","reason":"Switched off."}"#) == .ended("Switched off."))
        #expect(
            event(
                #"{"type":"state","browser":{"state":"yours","lease":{"until":"2026-11-23T17:31:00.000Z"}}}"#
            )
                == .state(
                    Browser(
                        state: .yours,
                        lease: Browser.Lease(until: Timestamp("2026-11-23T17:31:00.000Z")!))))
        #expect(event(#"{"type":"cursor","x":1}"#) == .unknown)
        #expect(event("not json") == .unknown)
    }

    @Test("what you do goes up as the contract writes it")
    func inputs() throws {
        func object(_ input: BrowserInput) throws -> JSONValue { try JSONValue(data: input.json) }
        #expect(
            try object(.tap(x: 100.04, y: 200))
                == JSONValue(json: #"{"type":"tap","x":100,"y":200}"#))
        #expect(
            try object(.touch(.move, x: 10, y: -3))
                == JSONValue(json: #"{"type":"touch","phase":"move","x":10,"y":0}"#))
        #expect(
            try object(.scroll(x: 1, y: 2, dx: 0, dy: -40.25))
                == JSONValue(json: #"{"type":"scroll","x":1,"y":2,"dx":0,"dy":-40.3}"#))
        #expect(try object(.text("hi")) == JSONValue(json: #"{"type":"text","text":"hi"}"#))
        #expect(try object(.fill("")) == JSONValue(json: #"{"type":"fill","text":""}"#))
        #expect(try object(.key(.enter)) == JSONValue(json: #"{"type":"key","key":"Enter"}"#))
        #expect(
            try object(.navigate(.reload))
                == JSONValue(json: #"{"type":"navigate","action":"reload"}"#))
        #expect(
            try object(.navigate(.url("https://railway.example")))
                == JSONValue(json: #"{"type":"navigate","url":"https://railway.example"}"#))
    }

    @Test(
        "the live view keeps the latest picture, forgets the focus on another page, and reconnects")
    func stream() async throws {
        let first = FakeSocket()
        first.script([
            .message(
                .text(
                    Data(
                        #"{"type":"view","url":"https://a.example/","width":390,"height":844,"tab":1,"tabs":1}"#
                            .utf8))),
            .message(.binary(Data([1]))),
            .message(
                .text(
                    Data(
                        #"{"type":"focus","field":{"kind":"email","label":"Email","box":{"x":16,"y":200,"width":358,"height":48},"length":4}}"#
                            .utf8))),
            .closed(1006),
        ])
        let second = FakeSocket()
        second.script([
            .message(.binary(Data([2]))),
            .message(
                .text(
                    Data(
                        #"{"type":"view","url":"https://a.example/next","width":390,"height":844,"tab":1,"tabs":1}"#
                            .utf8))),
            .message(.text(Data(#"{"type":"ended","reason":"Switched off."}"#.utf8))),
        ])
        let sockets = Mutex([first, second])
        let stream = BrowserStream(
            connect: { sockets.withLock { $0.removeFirst() } }, clock: ImmediateClock())
        var focused: [FocusedField?] = []
        stream.listen { event in
            if case .focus(let field) = event { focused.append(field) }
        }
        stream.start()
        for _ in 0..<200 where stream.endReason == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(stream.endReason == "Switched off.")
        #expect(stream.picture == Data([2]) && stream.pictures == 2)
        #expect(stream.view?.url == "https://a.example/next")
        #expect(
            focused == [
                FocusedField(
                    kind: .email, label: "Email",
                    box: PageRect(x: 16, y: 200, width: 358, height: 48), length: 4)
            ])
        #expect(stream.focus == nil, "another page: the field is gone")
    }

    @Test("a stream the server refuses says why")
    func refusedStream() async throws {
        let socket = FakeSocket()
        socket.script([.refused(503)])
        let stream = BrowserStream(connect: { socket })
        stream.start()
        for _ in 0..<100 where stream.endReason == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(stream.endReason == "Kumo's browser isn't on, on your server.")
    }

    // MARK: - Notifications

    @Test("a takeover notification names what Kumo needs, and where")
    func notification() throws {
        let json =
            #"{"kind":"takeover","text":"Your 08:00 on Friday is in the basket.","thread":"h_rail","thread_title":"Edinburgh tickets","takeover":{"need":"login","site":"Railway"}}"#
        let notification = try JSONDecoder().decode(PushNotification.self, from: Data(json.utf8))
        #expect(notification.kind == .takeover)
        #expect(notification.thread == "h_rail" && notification.threadTitle == "Edinburgh tickets")
        let takeover = try #require(notification.takeover)
        #expect(takeover.title == "Kumo needs you to log into Railway")
        #expect(
            PushNotification.Takeover(need: .payment, site: "Railway").title
                == "Kumo needs you to press Pay on Railway")
        #expect(PushNotification.Takeover(need: .code).title == "Kumo needs a code from you")
        #expect(
            PushNotification.Takeover(need: BrowserNeedKind(rawValue: "selfie")).title
                == "Kumo needs your hand")
    }
}

/// The server's side of Kumo's hands, answering as told.
final class FakeHands: HandsBackend, @unchecked Sendable {
    var answer = Browser(state: .yours)
    var failure: RequestError?
    private(set) var takes = 0
    private(set) var handBacks = 0

    func takeOver() async throws(RequestError) -> Browser {
        takes += 1
        if let failure { throw failure }
        return answer
    }

    func handBack() async throws(RequestError) -> Browser {
        handBacks += 1
        if let failure { throw failure }
        return answer
    }

    func openStream() -> any WebSocketChannel {
        let socket = FakeSocket()
        socket.script([.awaitSent(10_000)])
        return socket
    }
}
