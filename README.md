# <img src="https://raw.githubusercontent.com/akai-ito/.github/main/profile/mark.svg" width="34" alt=""> Ito for iPhone

**The iPhone app for Ito: a Desk for everything admin, and one continuous conversation with Kumo,
live.** (The repository and its code still say Ari, the app's earlier name.)

[![CI](https://github.com/akai-ito/ari-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/akai-ito/ari-ios/actions/workflows/ci.yml)

> [!NOTE]
> Ito connects to your Ito server and holds the Desk and the conversation live, in its own look.
> Still to come: opening instantly from the phone's cache, a light mode, and an iPad layout. The
> [map](https://github.com/akai-ito/.github/blob/main/map.md) has the design.

## What it will be

- Native SwiftUI for iOS 26, dark-first, with the agent's living presence as its one signature
  element.
- A thin client: it renders what your Ito server says, so the conversation is the same wherever
  you pick it up.

## What's here

| Path | What it is |
| --- | --- |
| [Ari](Ari) | The app, for iPhone, in SwiftUI: the connect screen and the conversation |
| [AriKit](AriKit) | Everything but the screens: the protocol's models, the conversation store, the networking and the reading pace |
| [protocol](protocol) | ito-core's client API, copied at the commit in [protocol.pin](protocol.pin) |
| [project.yml](project.yml) | The Xcode project, which XcodeGen generates |

- **Tolerant decoding.** Every event decodes envelope first, so an event type Ari doesn't know is
  skipped while its id still moves the cursor, fields it doesn't know are ignored, and values it
  doesn't know fall back as the protocol says.
- **One store, fed by the server.** `Conversation` is built from the server's events, applied in
  order, and its answers to what Ari asks. Ari changes it ahead of the server only for what you do
  (your message the moment you send it, Stop, and Try again), and the server then confirms each.
- **A first connection that names the problem.** `Connector` checks the address (HTTPS, or plain
  HTTP to this device only), that an Ito server answers, that it speaks Ari's protocol (and if not,
  which side to update), and then the token. Or it pairs: the short code `ito pair` shows, scanned,
  opened from the Camera as an `ito://pair` link, or typed. The token lives in the Keychain and
  never prints in full.
- **A session that stays live.** `Session` keeps the conversation current from the event stream: it
  resumes from the last event it applied, reconnects with backoff the moment the network returns,
  and treats 45 seconds without even a ping as a lost connection.
- **Never lose a message.** Each message is saved on the device before it's sent, then sent in
  order, with the same id until the server has it, even across a restart. Stop, Try again, calls
  and the rest each go on a lane of their own, never behind a send or a reconnect.
- **Reading at a person's pace.** `Reveal` shows a reply at a steady reading pace, catching up when
  the screen falls behind. `ReplyDocument` reads its Markdown with Apple's
  [swift-markdown](https://github.com/swiftlang/swift-markdown) and keeps where each run sits in the
  source, so text never reflows as it arrives. Stop shows everything Ari wrote at once.
- **Replies shaped by what they are.** Where Markdown can't, Ari writes a block the app draws: a
  place on Apple's map (a still picture in the chat, a live map with Directions when you open it),
  short answers to tap, pictures it found (credited on tap), and a line that opens a thing in
  motion.
- **Kumo's trail.** Between your message and Kumo's answer, what it did along the way, in plain
  words that change tense as it finishes, with its short notes as quiet grey lines. `Timeline`
  merges messages and steps, groups similar steps, and folds each run once the turn is over; tap a
  step for its specifics.
- **Where you are.** The title under Kumo is the topic Kumo marked for what's on screen, or its day,
  changing as you scroll; tap it for every topic and day, to jump to. Your long messages fold after
  eight lines.
- **Asks that wait for you.** When Kumo needs something (which one you meant, your go-ahead), it
  asks on the trail and waits: options to tap, room to type, and Stop to let it go. Any message you
  send answers it, from a notification too. An approval shows what it would do, and any pictures
  it would make public, such as a report's screenshots.
- **The Desk.** Where Ito opens, and where Kumo is. Kumo sits big, a sixth of the way down, on a
  faint cushion of dots, in its mood (bright, proud, focused, cosy, concerned, drowsy, or calm),
  with its line under it in its own serif: something Kumo thought worth saying now, which never
  notifies. Behind it the day's light changes with the hour, and once the box knows roughly where
  you are, the weather and the sunset sit small at the top. Nothing moves Kumo. When something
  needs you, a small "2 for you" sits beside it, and Kumo glances at it.
- **What I'm up to.** Tapping Kumo opens what needs you (drafts to open in Mail, invites, times to
  check against your work calendar, questions, offers), Kumo's plans (each check-in it set, with
  when, why, whether it repeats and who set it; tap one to move or reword it, or cancel it), today's
  Done with Undo and "That was wrong" (a word, a tap on a usual word, or just the tap) and
  everything before, and Getting to know you: the areas Kumo is learning, as dots by stage, each
  opening what it stands on.
- **Your day.** At the Desk's foot, today is a dotted thread: dense where the day has been, your
  events as knots, now ringed, and only the next one named. Tapping it opens the day as a calm list,
  then tomorrow, with Kumo's planned blocks, guesses and check-ins woven in faintly (Only mine hides
  them). A guess takes Right or Not right?, a planned block moves or comes off (Done keeps an undo),
  and a check-in changes or cancels. Your own events open in Apple's event view. While something on
  the server needs you, a quiet "Something's wrong ›" under Kumo's line opens how to fix it;
  Settings lists it first, and both clear on their own once it's fixed.
- **Getting started.** Five calm steps after pairing: meet Kumo, connect mail and calendar, a few
  questions while Kumo reads three months of mail (or "still true?" for what it already knows), a
  short talk about how Kumo should check in, where the first plans it sets show as they come, then
  notifications, then what's in motion. Kumo's questions can offer answers to tap.
  Settings opens it again, with nothing wiped: Kumo reads mail again only for an account you add.
- **In motion.** What you're actually doing, kept current as you talk: a trip, a training block, a
  pursuit such as a job search, an occasion such as a dentist appointment, or a case such as the
  boiler.
  It's pinned above the composer and opens full screen; In motion is its own tab. A trip has its
  days, a map whose pins show their place, its places by kind (each with a page of its own, where
  you say whether it's an idea, in the plan or not for you), and travel; what Ari changed is behind
  a button at the top.
- **What Kumo knows.** You shows Kumo's memory: In mind, shelves of pages (each with its glyph
  in Ari's dots; people by circle), and the journal, all in the device's search. A photo you shared
  stays where Kumo put it in the story; tap it to see it full screen. Settings › Memory
  backs it up to GitHub: approve a code, install Ito Memory on just your private `ito-thread`, and
  your server pushes after each change; it says when that stops, and Disconnect keeps the
  repository.
- **Talk.** A call with Kumo through CallKit: your voice goes to your server, and Kumo's comes back
  with captions as each line is heard.
- **Capabilities.** What Kumo can reach, switched on in Settings, and connected through the
  provider's own page where it can ("Connect GitHub", "Connect Outlook"), or with guided steps where
  it can't (an iCloud or Gmail app password), so keys go to your box and never come back.
- **Four places, and Settings.** Desk, Chat, In motion and You in the iOS 26 tab bar. Settings opens
  from the corner of Chat, In motion and You: the server, Kumo's name, notifications, Kumo's voice
  and model, capabilities, and the app icon. To show Ito to someone, hide the You tab there: no
  search result or step in the chat opens a page while it's hidden, and Face ID or the passcode
  brings it back. Chat, the Desk and notifications still show what they show.
- **Where you are, roughly.** Ito tells your box the phone's time zone each time it opens and
  whenever it changes, so Kumo lives by your clock wherever you are. The first time the Desk could
  show the weather, it offers to, in one line: allow rough location (When In Use, approximate) and
  the phone adds its town, rounded to about 10 km, re-read at most hourly. Refuse it and only the
  time zone goes. Settings › Kumo shows what the box keeps.
- **Messages that reach you.** Every message from Kumo notifies as it's sent, encrypted on the way:
  a reply, a failure, a question, or something Kumo wrote to you on its own. With Ito open it's a
  banner, except while you're reading the chat. Your Focus decides what makes a sound; a message
  that can't wait breaks through it and carries a small "Couldn't wait" mark in the chat.
- **The look.** A cool slate dark with soft white text and no accent colour. Kumo's answers are in
  New York, Apple's serif, the only serif in the conversation; you write in SF Pro, in a thin
  outline. Kumo's presence is a small pebble of bone-coloured dots whose eyes follow what it's
  doing, and look at you when you tap it.

## Building Ari

You need Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```sh
xcodegen generate   # writes Ari.xcodeproj; run it again whenever project.yml changes
open Ari.xcodeproj
```

Ari runs in the Simulator as it is. To try it without an agent, run ito-core's
demo engine on your Mac (`node bin/ito.ts serve --engine demo` in an
[ito-core](https://github.com/akai-ito/ito-core) clone) and connect to `http://127.0.0.1:8787` with
the token it prints. In debug builds, `ARI_SERVER` and `ARI_TOKEN` fill in the connect screen,
`ARI_SAY` sends a message once connected, `ARI_STOP_AFTER` taps Stop that many seconds later,
`ARI_DRAFT` fills in the composer, `ARI_ATTACH` attaches files (paths, separated by commas),
`ARI_OPEN_TRAIL` opens every step on the trail, `ARI_TOPICS` opens the topics sheet, `ARI_PLACE`
opens a tab (`chat`, `motion` or `you`; Ito opens on the Desk; `ARI_MOTION` then opens a thing in
motion, with `ARI_MOTION_TAB`, `ARI_MOTION_PLACE`, `ARI_MOTION_PIN` or `ARI_MOTION_CHANGES` going
further in), `ARI_SHELF` opens a shelf in You (`ARI_CALENDAR` shows the Journal's calendar),
`ARI_ONBOARDING` opens getting started at a step (`knowYou` or `checkIn`) while it's on,
`ARI_DESK` opens part of the Desk (`upto`, `tracks`, `day`, `problems` or `wrong`),
`ARI_SETTINGS` opens Settings and
`ARI_OPEN_URL` opens a link such as `ito://pair?…`, which is handy from `xcrun simctl launch`
(prefix each with `SIMCTL_CHILD_`). A message with *busy* in it
makes the demo engine walk a whole trail of steps; *long*, *fail* and *silent* try Stop, a failure
and a timeout; *trip* and *training* start things in motion, and *booked* changes the trip; *desk*,
*times*, *invite* and *mail* put cards on the Desk, *work* fills Kumo's work, and *plan* lays out a
day of Kumo's plan and guesses (`ARI_GUESS` shows the day's first guess `open`, or with what it
really was, `correct`).

To use your own server from your iPhone, reach it over your tailnet: `tailscale serve --bg 8787` on
the server gives an HTTPS address Ari accepts. To run Ari on your iPhone, copy
`Config/Local.xcconfig.example` to `Config/Local.xcconfig`, which git ignores, and set your Apple
team there. If you sign with your own team, choose your own bundle identifier there too.

## Tests

```sh
swift test --package-path AriKit
```

Most tests play ito-core's [golden transcripts](protocol/transcripts), one per scenario, at two
levels:

- **The store.** Each event, send, Stop, Try again and answer in a transcript goes to the store.
  It must end as the transcript's own messages do, read from its JSON, with no message shown
  twice, no text revised and no status outliving its turn.
- **The client.** The transcript's server sits behind the transport, its network drops and
  restarts happen on cue, and a test clock stands in for time. Ari must make exactly the
  transcript's requests, in order, and end with the store's conversation. More tests cover what the
  transcripts don't: a silent connection, Stop while reconnecting or before the turn is announced,
  Retry-After, a rejected token and a restart with messages waiting.

Other tests check that every event and answer decodes, that what Ari doesn't know is tolerated,
and that the models know every event type, required field and value in the pinned spec.

A few tests run against a real server and are skipped unless you point them at one. In an
[ito-core](https://github.com/akai-ito/ito-core) clone, run `node bin/ito.ts serve --engine demo`,
which answers without an agent and prints a token on its first run; then:

```sh
ITO_SERVER=http://127.0.0.1:8787 ITO_TOKEN=<token> swift test --package-path AriKit
```

With `ITO_PAIRING_CODE` set to a fresh code from `node bin/ito.ts pair`, they pair too.

The app's own interactions have UI tests in [AriUITests](AriUITests): sending, Stop, Try again,
answering an ask, links, the trail, the long-press menu, Settings, and the
conversation's scrolling (margins, following, the keyboard). They drive the app as you would,
against the demo engine, so they're opt in: connect Ari to a demo server in the Simulator once,
then run

```sh
xcodebuild test -project Ari.xcodeproj -scheme AriUITests -destination 'platform=iOS Simulator,name=<simulator>'
```

## Things that bit us

Each cost a round of bugs on a real phone. The code says why where it matters; this is the list to
read before changing these parts.

- **Run `xcodegen generate` after pulling.** `Ari.xcodeproj` isn't in git, and a stale one still
  builds, because the app's sources are a synced folder, but without what `project.yml` added since:
  entitlements, Info.plist keys, extensions. The build now stops when `project.yml` is newer.
- **The Simulator hides two classes of bug.** It doesn't enforce Keychain access groups, so the app
  group's Keychain works there even without the entitlement, and it doesn't run notification
  service extensions for `simctl push`. Check those on a phone.
- **Finish iOS's completion handlers on the main thread.** The async forms of
  `UNUserNotificationCenterDelegate` call them from a background task, and UIKit aborts.
- **Don't let the conversation redraw on every frame or keystroke.** The reading pace moves 30
  times a second: only the message being revealed may redraw (`RevealModel`, `Paced`). The
  composer's text field measures itself with TextKit whenever it redraws, so it lives in its own
  equatable view (`ComposerArea`).
- **Scroll to rows as wide as the screen.** Scrolling to a row lines up its edge with the screen's:
  a row starting at a margin slides everything sideways. And a lazy stack guesses the heights of
  rows it hasn't drawn, which made the conversation jump or scroll into blank space, so it's a
  plain stack of the latest rows.
- **Follow the end on new rows only, without animation.** Following every change in height, with an
  animation, fed itself in a long conversation and froze the screen.
- **Don't hand a closure down the environment from a view that redraws every frame.** Each redraw
  makes a new one, so everything reading it redraws too. The pinned line, redrawn under the
  conversation every frame, kept it from following a reply. Make such a value equatable on what
  matters (`MotionOpener`).

## The protocol

[protocol](protocol) is ito-core's
[protocol directory](https://github.com/akai-ito/ito-core/tree/main/protocol), copied byte for byte
at the commit in [protocol.pin](protocol.pin): the spec, the guarantees and the transcripts, with
the generator and TypeScript types its pages link to. Ari never changes it; the protocol changes in
ito-core first. To move to a newer one:

```sh
.github/scripts/sync-protocol main   # or any commit on ito-core's main branch
```

Then commit `protocol` and `protocol.pin` together. CI fails whenever the copy and the pin disagree.

## Formatting

CI checks the Swift with the swift-format that comes with Xcode, configured in
[.swift-format](.swift-format). To format everything:

```sh
swift format format --in-place --recursive Ari AriKit
```

## Getting Ari

At first you build Ari yourself with Xcode; TestFlight and then the App Store come later.

## Licence

Source-available under your choice of the
[PolyForm Noncommercial](LICENSES/PolyForm-Noncommercial-1.0.0.md) or
[PolyForm Small Business](LICENSES/PolyForm-Small-Business-1.0.0.md) licence; see
[LICENSE.md](LICENSE.md).
