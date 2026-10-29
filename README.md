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

- **Tolerant decoding.** Every event decodes envelope first, so a newer server can't break Ari. An
  event type it doesn't know is skipped while its id still moves the cursor, fields it doesn't know
  are ignored, and values it doesn't know fall back as the protocol says.
- **One store, fed by the server.** `Conversation` is built from the server's events, applied in
  order, and its answers to what Ari asks. Ari changes it ahead of the server only for what you
  do (your message the moment you send it, Stop's freeze, and Try again), and the server then
  confirms each.
- **A first connection that names the problem.** `Connector` checks the address (HTTPS, or plain
  HTTP to this device only), that an Ito server answers, that it speaks Ari's protocol (and if not,
  which side to update), and then the token. Or it pairs: the short code `ito pair` shows, scanned
  from its QR code, opened from the Camera as an `ito://pair` link, or typed, becomes a token of
  this device's own. The token lives in the Keychain, on this device only, and never prints in
  full: anything that logs it shows its last four characters.
- **A session that stays live.** `Session` keeps the conversation current from the event stream:
  it resumes from the last event it applied, reconnects with backoff, the moment the network
  returns, and treats 45 seconds without even a ping as a lost connection.
- **Photos and files.** An attachment starts uploading the moment you pick it, under an id Ari
  makes, so a retry never makes a second copy, and it's saved beside the outbox until the server
  has it. Photos go as JPEG, about 2048 pixels on the long edge, without their location. A message
  waits for its attachments, and `AttachmentCache` keeps their bytes, so each is fetched at most
  once.
- **Share to Ari.** From any app's share sheet, photos, files, links and text go to Ari with a
  note. The extension sends them at once when it can, reaching the server with the address and
  token Ari keeps in its app group; otherwise they wait there, and Ari sends them when it opens.
- **Reading at a person's pace.** `Reveal` shows a reply at a steady reading pace, catching up
  when the screen falls more than a couple of seconds behind the server. `ReplyDocument` reads its
  Markdown with Apple's [swift-markdown](https://github.com/swiftlang/swift-markdown) and keeps
  where each run of text sits in the source, so text never reflows as it arrives, no `**` ever
  flashes, and Stop can say exactly how much was on screen.
- **Ari's trail.** Between your message and Ari's answer, what it did along the way: each step on
  a rail of the character's own dots, in plain words that change tense as it finishes, with Ari's
  short notes where it wrote them. `Timeline` merges messages and steps by position, groups
  similar steps ("Read 3 files"), and folds each run once the turn is over; tap a step to open
  its specifics (the command and its output, the pages, the files, the plan) in place.
- **Asks that wait for you.** When Ari needs something (which one you meant, your go-ahead, a
  code), it asks on the trail and waits: options to tap, room to type, and Stop to let it go. Any
  message you send answers it, and a secret answer stays out of your history.
- **Three places, and Settings.** Chat, Goals and Library, as the design map plans them, in the
  iOS 26 tab bar; Goals and Library say plainly what they'll hold. Settings
  open from the corner: the server (with "Connect to another server…"), notifications, and the
  app icon, Rest or Peeking.
- **The look.** A cool slate dark with soft white text and no accent colour. Ari writes in New
  York, Apple's serif; you write in SF Pro, in a thin outline. Ari's presence is a small pebble of
  bone-coloured dots with two eyes that follow what it's doing: up while thinking, aside while
  searching, along the lines while writing, dimmed when the connection drops, and fading to a quiet
  stone at rest. Colours live in the asset catalogue, ready for a light mode.
- **Never lose a message.** Each message is saved on the device before it's sent, then sent one at
  a time, in order, with the same id until the server has it, even across a restart. Stop has its
  own lane, never behind a send or a reconnect, and Try again is safe to repeat.

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
opens a tab, `ARI_SHELF` opens a shelf in the Library (`ARI_CALENDAR` shows the Journal's calendar),
`ARI_SETTINGS` opens Settings and `ARI_OPEN_URL` opens a link such as `ito://pair?…`, which is handy
from `xcrun simctl launch` (prefix each with `SIMCTL_CHILD_`). A message with *busy* in it
makes the demo engine walk a whole trail of steps; *long*, *fail* and *silent* try Stop, a failure
and a timeout.

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
  It must end where the scenario says, with no message shown twice, no text revised, no status
  outliving its turn and no words appearing after a tap on Stop.
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
answering an ask, a secret answer, links, the trail, the long-press menu, Settings, and the
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
- **Keep secrets out of anything saved.** The draft is saved as you type; a secret answer has its
  own field that never is.

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
