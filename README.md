# <img src="https://raw.githubusercontent.com/akai-ito/.github/main/profile/mark.svg" width="34" alt=""> Ari

**The iPhone app for Ito: one continuous conversation with your agent, live.**

[![CI](https://github.com/akai-ito/ari-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/akai-ito/ari-ios/actions/workflows/ci.yml)

> [!NOTE]
> Ari can't reach a server yet. What's here is its foundation: Ito's client protocol in Swift, and the
> store that turns the server's events into the conversation, tested against every golden transcript.
> The connect screen and the conversation itself come next. The
> [map](https://github.com/akai-ito/.github/blob/main/map.md) has the design.

## What it will be

- Native SwiftUI for iOS 26, dark-first, with the agent's living presence as its one signature
  element.
- A thin client: it renders what your Ito server says, so the conversation is the same wherever
  you pick it up.

## What's here

| Path | What it is |
| --- | --- |
| [Ari](Ari) | The app, for iPhone and Mac from one SwiftUI target; for now, a placeholder screen |
| [AriKit](AriKit) | Everything but the screens: the protocol's models and the conversation store |
| [protocol](protocol) | ito-core's client API, copied at the commit in [protocol.pin](protocol.pin) |
| [project.yml](project.yml) | The Xcode project, which XcodeGen generates |

- **Tolerant decoding.** Every event decodes envelope first, so a newer server can't break Ari. An
  event type it doesn't know is skipped while its id still moves the cursor, fields it doesn't know
  are ignored, and values it doesn't know fall back as the protocol says.
- **One store, fed by the server.** `Conversation` is built from the server's events, applied in
  order, and its answers to what Ari asks. Ari changes it ahead of the server only for what you
  do (your message the moment you send it, Stop's freeze, and Try again), and the server then
  confirms each.

## Building Ari

You need Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```sh
xcodegen generate   # writes Ari.xcodeproj; run it again whenever project.yml changes
open Ari.xcodeproj
```

Ari runs in the Simulator and on your Mac as it is. To run it on your iPhone, copy
`Config/Local.xcconfig.example` to `Config/Local.xcconfig`, which git ignores, and set your Apple
team there. If you sign with your own team, choose your own bundle identifier there too.

## Tests

```sh
swift test --package-path AriKit
```

Most tests play ito-core's [golden transcripts](protocol/transcripts), one per scenario. Each
event, send, Stop, Try again and answer in a transcript goes to the store. The store must end where
the scenario says, with no message shown twice, no text revised, no status outliving its turn and
no words appearing after a tap on Stop. Other tests check that every event and answer decodes,
that what Ari doesn't know is tolerated, and that the models know every event type, required field
and value in the pinned spec.

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
