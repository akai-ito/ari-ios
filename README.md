# <img src="https://raw.githubusercontent.com/akai-ito/.github/main/profile/mark.svg" width="34" alt=""> Ari

**The iPhone app for Ito: one continuous conversation with your agent, live.**

[![CI](https://github.com/akai-ito/ari-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/akai-ito/ari-ios/actions/workflows/ci.yml)

> [!NOTE]
> Ari connects to your Ito server and holds the conversation live, in its own look. Still to come:
> opening instantly from the phone's cache, a light mode, and an iPad layout. The
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
- **Ari's trail.** Between your message and Ari's answer, what it did along the way, in plain words
  that change tense as it finishes, with its short notes as quiet grey lines. `Timeline` merges
  messages and steps, groups similar steps, and folds each run once the turn is over; tap a step
  for its specifics.
- **Where you are.** The title under Ari is the topic Ari marked for what's on screen, or its day,
  changing as you scroll; tap it for every topic and day, to jump to. Your long messages fold after
  eight lines.
- **Asks that wait for you.** When Ari needs something (which one you meant, your go-ahead), it
  asks on the trail and waits: options to tap, room to type, and Stop to let it go. Any message you
  send answers it, from a notification too. An approval shows what it would do, and any pictures
  it would make public, such as a report's screenshots.
- **In motion.** What you're actually doing, kept current as you talk: a trip, a training block.
  It's pinned above the composer and opens full screen; In motion is its own tab. A trip has its
  days, a map whose pins show their place, its places by kind (each with a page of its own, where
  you say whether it's an idea, in the plan or not for you), and travel; what Ari changed is behind
  a button at the top.
- **What Ari knows.** The Library shows Ari's memory: In mind, shelves of pages (each with its glyph
  in Ari's dots; people by circle), and the journal, all in the device's search.
- **Talk.** A call with Ari through CallKit: your voice goes to your server, and Ari's comes back
  with captions as each line is heard.
- **Capabilities.** What Ari can reach, switched on in Settings, and connected through the
  provider's own page where it can ("Connect GitHub"), so keys never pass through the phone.
- **Three places, and Settings.** Chat, In motion and Library in the iOS 26 tab bar. Settings opens
  from the corner: the server, notifications, Ari's voice and model, capabilities, and the app icon.
- **The look.** A cool slate dark with soft white text and no accent colour. Ari's answers are in
  New York, Apple's serif, the only serif in the conversation; you write in SF Pro, in a thin
  outline. Ari's presence is a small pebble of bone-coloured dots whose eyes follow what it's
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
opens a tab (`ARI_MOTION` then opens a thing in motion, with `ARI_MOTION_TAB`, `ARI_MOTION_PLACE`,
`ARI_MOTION_PIN` or `ARI_MOTION_CHANGES` going further in), `ARI_SHELF` opens a shelf in the
Library (`ARI_CALENDAR` shows the Journal's calendar), `ARI_SETTINGS` opens Settings and
`ARI_OPEN_URL` opens a link such as `ito://pair?…`, which is handy from `xcrun simctl launch`
(prefix each with `SIMCTL_CHILD_`). A message with *busy* in it
makes the demo engine walk a whole trail of steps; *long*, *fail* and *silent* try Stop, a failure
and a timeout; *trip* and *training* start things in motion, and *booked* changes the trip.

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
