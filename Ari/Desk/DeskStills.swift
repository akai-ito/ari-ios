#if DEBUG
    import AriKit
    import Foundation

    /// The Desk without a server, for checking it against its stills: `ARI_STILL` names a moment of
    /// a made-up Tuesday (Northwind's final at 14:00, a run with Leo, dinner at Kiln), and an
    /// in-process server answers the Desk, the dream, Understanding you, Kumo's work and its plans
    /// from samples. Set `ARI_CLOCK` to the same moment's time. Everyone and everything in it is
    /// made up.
    ///
    /// - `morning` (07:40): last night's dream is new, so the moon; two things wait.
    /// - `afternoon` (16:30): seen, so the sun; nothing waits.
    /// - `evening` (21:30): the low amber sun; one thing waits.
    /// - `asleep` (03:50): Kumo asleep before the dream.
    /// - `dreaming` (04:06): Kumo dreams; its record comes 40 seconds later.
    /// - `dreamt` (04:31): the dream just done, the moon arrived, Kumo still asleep.
    /// - `asked` (14:22): a dream you asked for at 14:20.
    enum DeskStills {
        static let scene = ProcessInfo.processInfo.environment["ARI_STILL"]
        static let address = try! ServerAddress("https://stills.example")
        static let token = Token("ito_stills_not_a_real_token_000000000000000000000")
        static let server: StillServer? = scene.map(StillServer.init(scene:))
    }

    /// Answers the Desk's requests from samples, and keeps one event stream open.
    final class StillServer: Transport, @unchecked Sendable {
        let scene: String
        private let lock = NSLock()
        private var seen = false
        private var dreaming: Bool
        private var stream: AsyncThrowingStream<Data, any Error>.Continuation?
        private var answered: Set<String> = []

        init(scene: String) {
            self.scene = scene
            dreaming = scene == "dreaming"
            seen = ["afternoon", "evening", "asleep", "asked"].contains(scene)
        }

        func send(_ request: HTTPRequest, to base: URL) async throws -> HTTPResponse {
            let path = request.path.split(separator: "?").first.map(String.init) ?? request.path
            switch (request.method, path) {
            case (.get, "/v0/dream"): return json(dreamState)
            case (.post, "/v0/dream"):
                lock.withLock { dreaming = true }
                finishDreaming(after: 30)
                return json(dreamState, status: 202)
            case (.get, "/v0/understanding"): return json(understanding)
            case (.get, "/v0/work"): return json(work)
            case (.get, "/v0/done"):
                return json(
                    #"{"entries":[\#(dreamEntries.joined(separator: ","))],"has_more":false}"#)
            case (.get, "/v0/wakeups"):
                return json(#"{"wake_ups":[\#(plans.joined(separator: ","))]}"#)
            case (.get, "/v0/desk"): return json(desk)
            case (.get, "/v0/threads"): return json(threads)
            case (.get, "/v0/voices"):
                return json(
                    #"{"voices":[{"id":"af_heart","name":"Heart","accent":"american"}],"chosen":"af_heart","state":"ready","voiceprint":"learned"}"#
                )
            default: break
            }
            if request.method == .post, path.hasPrefix("/v0/dreams/") {
                lock.withLock { seen = true }
                return json(#"{"dream":\#(dream)}"#)
            }
            if request.method == .post, path.hasPrefix("/v0/understanding/questions/") {
                let id = String(path.split(separator: "/")[3])
                let notNow = path.hasSuffix("/not-now")
                if !notNow { lock.withLock { _ = answered.insert(id) } }
                let state = notNow ? #""open","later_at":"\#(at(9))""# : #""answered""#
                return json(
                    #"{"question":{"id":"\#(id)","track":"mornings","state":\#(state),"understood":"","missing":"","why":"","options":[],"asked_at":"\#(at(9, day: -3))","changed_at":"\#(at(9))"}}"#
                )
            }
            if request.method == .post, path.hasPrefix("/v0/done/") {
                let id = path.split(separator: "/")[2]
                return json(
                    #"{"entry":{"id":"\#(id)","at":"\#(at(7, 15))","text":"Undone","undo":false,"quiet":false}}"#
                )
            }
            return HTTPResponse(
                status: 404, headers: ["Content-Type": "application/json"],
                body: Data(#"{"error":{"code":"not_found","message":"Not in the stills."}}"#.utf8))
        }

        func open(_ request: HTTPRequest, to base: URL) async throws -> HTTPStream {
            let body = AsyncThrowingStream<Data, any Error> { continuation in
                lock.withLock { stream = continuation }
                continuation.yield(Data("id: e_1\nevent: snapshot\ndata: \(snapshot)\n\n".utf8))
                let task = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(15))
                        continuation.yield(Data(": ping\n\n".utf8))
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
            if scene == "dreaming" { finishDreaming(after: 40) }
            return HTTPStream(
                status: 200, headers: ["Content-Type": "text/event-stream"], body: body)
        }

        private func finishDreaming(after seconds: Int) {
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                lock.withLock { dreaming = false }
                let event =
                    #"{"id":"e_2","type":"dream.finished","at":"\#(at(4, 31))","dream":\#(dream)}"#
                let continuation = lock.withLock { stream }
                continuation?.yield(Data("id: e_2\nevent: dream.finished\ndata: \(event)\n\n".utf8))
            }
        }

        private func json(_ text: String, status: Int = 200) -> HTTPResponse {
            HTTPResponse(
                status: status, headers: ["Content-Type": "application/json"], body: Data(text.utf8)
            )
        }

        // MARK: Time

        /// Today at a time, on the Desk's clock, as the server writes it.
        private func at(_ hour: Int, _ minute: Int = 0, day: Int = 0) -> String {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: DeskClock.now())
            let date =
                calendar.date(
                    bySettingHour: hour, minute: minute, second: 0,
                    of: calendar.date(byAdding: .day, value: day, to: today) ?? today) ?? today
            return Timestamp(date).rawValue
        }

        private func day(_ offset: Int) -> String {
            let date =
                Calendar.current.date(byAdding: .day, value: offset, to: DeskClock.now()) ?? .now
            let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
            return String(
                format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        }

        /// Today's day of the week, as the protocol names it.
        private var today: String {
            let index = (Calendar.current.component(.weekday, from: DeskClock.now()) + 5) % 7
            return Weekday.known[index].rawValue
        }

        // MARK: The Desk

        private var snapshot: String {
            #"{"id":"e_1","type":"snapshot","at":"\#(at(7))","reason":"no_cursor","messages":[],"has_more":false,"steps":[],"asks":[],"calls":[],"threads":[],"turn":null,"next":[],"desk":\#(desk)}"#
        }

        private var line: (String, String) {
            switch scene {
            case "afternoon", "asked":
                ("That's the hard one done, and done well. The rest of today is yours.", "proud")
            case "evening": ("“Rest is not idleness.”", "cosy")
            case "asleep": ("Goodnight. I'll dream over today at four.", "drowsy")
            case "dreaming", "dreamt": ("All sorted. It'll keep till morning.", "drowsy")
            default: ("Morning. Northwind at 2, and I tidied up overnight.", "bright")
            }
        }

        private var waiting: [String] {
            let draft =
                #"{"id":"k_sam","at":"\#(at(7, 2))","kind":"question","title":"Reply to Sam at Halcyon","options":[{"label":"Send it","acts":true},{"label":"Not yet"}],"allows_text":true,"question":{"text":"Sam asked whether Thursday at 11 still works. Shall I say yes?"}}"#
            let mira =
                #"{"id":"k_mira","at":"\#(at(7, 10))","kind":"question","title":"Mira's birthday dinner","options":[{"label":"Book it","acts":true},{"label":"Not now"}],"allows_text":true,"question":{"text":"Kiln has a table for four on the 11th at 19:30. Book it?"}}"#
            switch scene {
            case "morning": return [draft, mira]
            case "evening": return [mira]
            default: return []
            }
        }

        private var desk: String {
            let (text, mood) = line
            return
                #"{"line":{"text":"\#(text)","mood":"\#(mood)","at":"\#(at(7, 30))"},"plans":[\#(plans.joined(separator: ","))],"coming_up":[\#(comingUp.joined(separator: ","))],"waiting":[\#(waiting.joined(separator: ","))],"handled":3}"#
        }

        private var comingUp: [String] {
            let home =
                #""calendar":{"name":"Home","kumo":false},"status":"confirmed","all_day":false"#
            let morningRun = scene == "asleep" || scene == "dreaming" ? (8, 15) : (7, 30)
            return [
                #"{"id":"run","uid":"run@stills","title":"Run with Leo","start":"\#(at(morningRun.0, morningRun.1))","end":"\#(at(morningRun.0 + 1, morningRun.1))",\#(home)}"#,
                #"{"id":"northwind","uid":"nw@stills","title":"Northwind final","start":"\#(at(14))","end":"\#(at(15))",\#(home)}"#,
                #"{"id":"evening-run","uid":"run2@stills","title":"Run with Leo","start":"\#(at(17, 30))","end":"\#(at(18, 15))",\#(home)}"#,
                #"{"id":"kiln","uid":"kiln@stills","title":"Dinner at Kiln","start":"\#(at(19, 30))","end":"\#(at(21))","location":"Kiln",\#(home)}"#,
                #"{"id":"mira","uid":"mira@stills","title":"Coffee with Mira","start":"\#(at(10, day: 1))","end":"\#(at(11, day: 1))",\#(home)}"#,
            ]
        }

        private var plans: [String] {
            func plan(
                _ id: String, _ title: String, _ when: String, what: String, why: String,
                repeats: String? = nil
            ) -> String {
                let repeating = repeats.map { #","repeat":\#($0)"# } ?? ""
                return
                    #"{"id":"\#(id)","at":"\#(when)","title":"\#(title)","what":"\#(what)","why":"\#(why)","by":"kumo","source":{"kind":"chat","title":""},"set_at":"\#(at(4, 12))"\#(repeating)}"#
            }
            let tomorrow = Weekday.known[
                ((Weekday.known.firstIndex(of: Weekday(rawValue: today)) ?? 0) + 1) % 7]
            var all: [String] = []
            if ["morning", "dreamt", "asleep", "dreaming"].contains(scene) {
                all.append(
                    plan(
                        "halcyon", "Prep for Halcyon, half an hour", at(11),
                        what: "Put Sam at Halcyon's notes in front of you and block half an hour.",
                        why: "Sam's call is at 11:30 and his notes came in late yesterday."))
                all.append(
                    plan(
                        "calm", "A calm five minutes before Northwind", at(13, 30),
                        what: "Message you to step away from the screen for five minutes.",
                        why: "You said finals go better when you arrive calm."))
            }
            all.append(
                plan(
                    "ask", "Ask how Northwind went", at(18, 45),
                    what: "Ask how the final went, and note what to follow up.",
                    why: "It ends at 15:00, and you like to talk it through while it's fresh."))
            if scene != "morning" {
                all.append(
                    plan(
                        "bed", "Nudge you toward bed", at(21, 30),
                        what: "Remind you to wind down, unless you're already off your phone.",
                        why: "Three late nights in a row.",
                        repeats: #"{"days":["mon","tue","wed","thu","fri"],"time":"21:30"}"#))
            }
            all.append(
                plan(
                    "aligner", "Aligner change", at(23, 45),
                    what:
                        "Message you at 23:45 with the next tray's number, and tick it off on your Health page when you say done.",
                    why:
                        "You're on tray 9 of 12. Quillfield Dental said to switch weekly, late, so each one settles overnight.",
                    repeats: #"{"days":["\#(today)"],"time":"23:45"}"#))
            all.append(
                plan(
                    "basil", "Water the basil", at(9, day: 1),
                    what: "Remind you to water the basil on the windowsill.",
                    why: "It wilts if it goes more than three days.",
                    repeats: #"{"days":["\#(tomorrow.rawValue)"],"time":"09:00"}"#))
            all.append(
                plan(
                    "sam", "See if Sam at Halcyon replied", at(10, day: 1),
                    what: "Look for Sam's reply and tell you if there isn't one.",
                    why: "You asked him for the panel's names on Monday."))
            all.append(
                plan(
                    "gift", "Order Mira's birthday gift", at(12, day: 2),
                    what: "Show you the gift idea again and order it if you say so.",
                    why: "Her birthday is a week on Friday, and delivery takes four days."))
            all.append(
                plan(
                    "week", "Look back on the week with you", at(18, day: 3),
                    what: "Ask how the week went, and what to carry into next.",
                    why: "You asked for a short look back each Friday.",
                    repeats: #"{"days":["fri"],"time":"18:00"}"#))
            return all
        }

        // MARK: The dream

        private var dream: String {
            if scene == "asked" {
                return
                    #"{"id":"z_asked","day":"\#(day(0))","trigger":"manual","started_at":"\#(at(14, 20))","ended_at":"\#(at(14, 21))","headline":"An afternoon tidy","lines":[{"group":"planned","text":"A quiet half hour after Northwind, at 15:15","done":"d_quiet","undo":true},{"group":"tidied","text":"This morning's notes, into today's journal","page":"memory:journal/\#(day(0))","done":"d_notes","undo":true},{"group":"noticed","text":"You've not eaten since breakfast"}],"seen_at":"\#(at(14, 22))"}"#
            }
            let seenAt = lock.withLock { seen } ? #","seen_at":"\#(at(7, 41))""# : ""
            let lines = [
                #"{"group":"planned","text":"Your run moves to 07:30, before the rain","event":"run","done":"d_run","undo":true}"#,
                #"{"group":"planned","text":"Half an hour for Halcyon prep at 11:00","wake_up":"halcyon","done":"d_halcyon","undo":true}"#,
                #"{"group":"planned","text":"Dropped Friday's boiler reminder; it's fixed","done":"d_boiler","undo":true}"#,
                #"{"group":"tidied","text":"Leo's two pages are one now","page":"memory:people/leo","done":"d_leo","undo":true}"#,
                #"{"group":"tidied","text":"Twelve Northwind notes, folded into its page","page":"memory:work/northwind","done":"d_northwind","undo":true}"#,
                #"{"group":"tidied","text":"Monday's journal, written","page":"memory:journal/\#(day(-1))","done":"d_journal","undo":true}"#,
                #"{"group":"noticed","text":"Three late nights in a row"}"#,
                #"{"group":"noticed","text":"Mira's birthday is a week on Friday"}"#,
                #"{"group":"saved","text":"Sam at Halcyon's notes, ready for 11:00"}"#,
                #"{"group":"saved","text":"A gift idea for Mira, from the shop she loved"}"#,
            ]
            return
                #"{"id":"z_night","day":"\#(day(-1))","trigger":"scheduled","started_at":"\#(at(4))","ended_at":"\#(at(4, 31))","headline":"Monday, tidied; Tuesday before the rain","lines":[\#(lines.joined(separator: ","))]\#(seenAt)}"#
        }

        private var dreamEntries: [String] {
            [
                #"{"id":"d_run","at":"\#(at(4, 12))","text":"Your run moves to 07:30, before the rain","reason":"Rain from 08:00, and Northwind at 2 leaves no room later. Leo's free at 07:30 too.","undo":true,"quiet":false,"dream":"z_night"}"#,
                #"{"id":"d_halcyon","at":"\#(at(4, 14))","text":"Half an hour for Halcyon prep at 11:00","reason":"Sam's call is at 11:30, and his notes came in late yesterday.","undo":true,"quiet":false,"dream":"z_night"}"#,
                #"{"id":"d_leo","at":"\#(at(4, 20))","text":"Leo's two pages are one now","reason":"Both were about the same Leo: your running partner.","undo":true,"quiet":false,"dream":"z_night"}"#,
            ]
        }

        private var dreamState: String {
            let state = lock.withLock { (dreaming, seen) }
            let latest: String =
                switch scene {
                case "asleep": #""latest":\#(yesterdaysDream)"#
                case "dreaming": state.0 ? #""latest":\#(yesterdaysDream)"# : #""latest":\#(dream)"#
                default: #""latest":\#(dream)"#
                }
            let under = state.0 ? #","dreaming":{"since":"\#(at(4))","trigger":"scheduled"}"# : ""
            return #"{"time":"04:00","next_at":"\#(at(4, day: 1))"\#(under),\#(latest)}"#
        }

        private var yesterdaysDream: String {
            #"{"id":"z_before","day":"\#(day(-2))","trigger":"scheduled","started_at":"\#(at(4, day: -1))","ended_at":"\#(at(4, 25, day: -1))","lines":[{"group":"tidied","text":"Sunday's journal, written"}],"seen_at":"\#(at(8, day: -1))"}"#
        }

        // MARK: Work, threads and Understanding you

        private var tracks: String {
            func track(_ id: String, _ name: String, _ stage: String) -> String {
                #"{"id":"\#(id)","name":"\#(name)","stage":"\#(stage)","since":"\#(at(9, day: -20))","confirmed":4,"corrected":1,"evidence":[]}"#
            }
            return [
                track("mornings", "Your mornings", "trusted"),
                track("writing", "How you write", "spot_checks"),
                track("people", "Who matters", "spot_checks"),
                track("tired", "What wears you out", "learning"),
                track("money", "Money and bookings", "learning"),
            ].joined(separator: ",")
        }

        private var work: String {
            let handled = [
                #"{"id":"d_told","at":"\#(at(7, 2))","text":"Told Leo the run's at 07:30","reason":"The run moved before the rain, and Leo asked to hear by seven.","undo":false,"quiet":false}"#,
                #"{"id":"d_news","at":"\#(at(7, 15))","text":"Cleared 14 newsletters","reason":"You said newsletters can wait unless they're from somewhere you book.","undo":true,"quiet":false,"mail":{"message_id":"news-1@stills","from":"Several","subject":"Newsletters"}}"#,
                #"{"id":"d_kiln","at":"\#(at(7, 31))","text":"Confirmed Kiln for 19:30","reason":"Kiln asked you to confirm by 08:00.","undo":true,"quiet":false}"#,
            ]
            return
                #"{"day":"\#(day(0))","handled":[\#(handled.joined(separator: ","))],"cleared":[],"tracks":[\#(tracks)]}"#
        }

        private var threads: String {
            func thread(_ id: String, _ title: String, _ hour: Int) -> String {
                #"{"id":"\#(id)","title":"\#(title)","by":"you","state":"resting","started_at":"\#(at(hour, day: -1))","position":\#(hour),"replies":3,"last_at":"\#(at(hour, 30, day: -1))"}"#
            }
            let list = [
                thread("h_nw", "Northwind prep", 9), thread("h_shoes", "Shoes", 12),
                thread("h_mira", "Mira's birthday", 15), thread("h_leo", "The run with Leo", 18),
                thread("h_rain", "Rain on Tuesday", 20),
            ]
            return #"{"open":[],"threads":[\#(list.joined(separator: ","))],"has_more":false}"#
        }

        private var understanding: String {
            func question(
                _ id: String, _ understood: String, _ missing: String, _ why: String,
                _ options: [String], state: String = "open", extra: String = ""
            ) -> String {
                let list = options.map { "\"\($0)\"" }.joined(separator: ",")
                return
                    #"{"id":"\#(id)","track":"mornings","state":"\#(state)","understood":"\#(understood)","missing":"\#(missing)","why":"\#(why)","options":[\#(list)],"asked_at":"\#(at(9, day: -3))","changed_at":"\#(at(9, day: -1))"\#(extra)}"#
            }
            let open = [
                question(
                    "q_mornings",
                    "You keep mornings clear before 10. You've moved three calls out of them this month, and you sounded better on the days you did.",
                    "Is that every day, or only on office days?",
                    "I could place calls for you without checking each time, and keep the rest of your mornings yours.",
                    ["Every day", "Office days only", "Mondays to Thursdays", "It depends"]),
                question(
                    "q_calls", "Late calls leave you flat the next day.",
                    "Is it the hour, or who the call's with?",
                    "So I know what to keep off your evenings.",
                    ["The hour", "Who it's with", "Both"]),
                question(
                    "q_mira", "You like hearing about Mira's plans early.",
                    "How early is early: a week, or a month?",
                    "So her birthday never sneaks up on you.", ["A week", "Two weeks", "A month"]),
            ].filter { item in
                let id = item.split(separator: "\"")[3]
                return lock.withLock { !answered.contains(String(id)) }
            }
            let settled = (1...4).map { i in
                question(
                    "q_settled_\(i)", "You run long on Saturdays.",
                    "Do you want the long run planned, or left to you?",
                    "So I plan the rest of Saturday around it.", [], state: "settled",
                    extra: #","note":"You said in the chat you'd rather plan it yourself.""#)
            }
            return
                #"{"tracks":[\#(tracks)],"questions":[\#(open.joined(separator: ","))],"recent":[\#(settled.joined(separator: ","))]}"#
        }
    }
#endif
