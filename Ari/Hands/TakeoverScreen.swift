import AriKit
import SwiftUI

/// You hold the page Kumo was on: the site full-bleed at its real phone size (taps go to the page,
/// the iOS keyboard types into it), a slim header in Kumo's words saying what it needs and where
/// you are, and Hand back to Kumo at the bottom, riding above the keyboard. Nothing of remote
/// desktop: no frame, no zoom, no cursor.
struct TakeoverScreen: View {
    let hands: Hands
    let session: Session?

    @Environment(\.keyboardShown) private var keyboard

    var body: some View {
        let takeover = hands.takeover
        VStack(spacing: 0) {
            TakeoverHeader(
                title: Self.title(takeover?.need), site: site,
                secure: url?.hasPrefix("https") ?? true,
                slow: hands.stream?.isDegraded ?? false,
                reconnecting: hands.stream?.isReconnecting ?? false,
                stop: stop, reload: { hands.send(.navigate(.reload)) }, leave: hands.leave)
            ZStack {
                if let stream = hands.stream {
                    PageSurface(
                        stream: stream, need: takeover?.need?.kind,
                        live: takeover?.acceptsInput ?? false, keyboard: keyboard,
                        send: hands.send)
                }
                TakeoverCover(
                    takeover: takeover, picture: hands.stream?.picture != nil,
                    ended: hands.stream?.endReason,
                    retry: { Task { await hands.takeOver() } }, close: hands.close)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HandBackBar(
                problem: takeover?.problem,
                busy: takeover?.phase == .handingBack,
                enabled: takeover?.phase == .holding
            ) {
                Task { await hands.handBack() }
            }
        }
        .background(Color.ariBackground)
        .onAppear { hands.watch() }
        .onDisappear { hands.unwatch() }
    }

    private var url: String? { hands.stream?.view?.url ?? hands.browser.url }

    /// The site's address, as the header shows it: "railway-tickets.co.uk".
    private var site: String {
        if let url, let host = URL(string: url)?.host() {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        return hands.browser.host ?? hands.browser.site ?? ""
    }

    /// What Kumo needs, in its words; a plain line for each kind when it gave none.
    static func title(_ need: Browser.Need?) -> String {
        if let why = need?.why, !why.isEmpty { return why }
        return switch need?.kind.shown {
        case .login: "Log in, then hand back"
        case .code: "Put the code in, then hand back"
        case .captcha: "Get past the check, then hand back"
        case .payment: "Check the order and press Pay yourself"
        default: "You have the page"
        }
    }

    /// Stop the task: nothing more of it is done, and the page stays as it is. The task's trail
    /// says you stopped it; Kumo isn't woken to carry on.
    private func stop() {
        Task { await hands.stopTask() }
    }
}

/// The takeover's header: Kumo, waiting on you; what it needs, in its serif; the site's address
/// (or, only when the stream struggles, that it's slow); and a menu.
struct TakeoverHeader: View {
    let title: String
    let site: String
    var secure = true
    var slow = false
    /// The picture isn't live: the connection dropped, or the page couldn't be shown.
    var reconnecting = false
    let stop: () -> Void
    let reload: () -> Void
    let leave: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            PresenceView(history: PoseHistory(.asking), size: 24)
                .padding(.leading, 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.ariName)
                    .foregroundStyle(.ariText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Group {
                    if reconnecting {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Reconnecting…")
                        }
                        .foregroundStyle(.ariBone)
                    } else if slow {
                        HStack(spacing: 5) {
                            Image(systemName: "wifi.exclamationmark")
                            Text("Slow connection · taps may lag")
                        }
                        .foregroundStyle(.ariBone)
                    } else {
                        HStack(spacing: 4) {
                            if secure {
                                Image(systemName: "lock.fill").font(.caption2)
                                    .accessibilityLabel("Secure")
                            }
                            Text(site)
                        }
                        .foregroundStyle(.ariTertiary)
                    }
                }
                .font(.caption)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            Menu {
                Button("Leave it with me for now", systemImage: "hand.raised", action: leave)
                Button("Reload the page", systemImage: "arrow.clockwise", action: reload)
                Button(
                    "Stop the task", systemImage: "stop.circle", role: .destructive, action: stop)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.ariText)
                    .frame(width: 36, height: 36)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background(Color.ariBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.ariLine).frame(height: 1)
        }
    }
}

/// The bar under the page: one wide Hand back to Kumo. Above the keyboard, it slims down.
struct HandBackBar: View {
    var problem: String?
    var busy = false
    var enabled = true
    let handBack: () -> Void

    @Environment(\.keyboardShown) private var keyboard

    var body: some View {
        VStack(spacing: 6) {
            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.ariSecondary)
                    .padding(.top, 8)
            }
            Button(action: handBack) {
                Text("Hand back to \(LeadName.current)")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.ariBackground)
                    .opacity(busy ? 0 : 1)
                    .overlay {
                        if busy { ProgressView().tint(.ariBackground) }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: keyboard ? 42 : 50)
                    .background(Color.ariText, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!enabled || busy)
            .opacity(enabled || busy ? 1 : 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.top, keyboard ? 7 : 10)
        .padding(.bottom, keyboard ? 7 : 4)
        .background(Color.ariBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.ariLine).frame(height: 1)
        }
    }
}

/// Over the page while it isn't yours yet, or no longer is: taking it (Kumo finishes its step
/// first), the server refusing, the page gone back, or the browser stopped.
private struct TakeoverCover: View {
    let takeover: Takeover?
    let picture: Bool
    let ended: String?
    let retry: () -> Void
    let close: () -> Void

    var body: some View {
        if let message {
            VStack(spacing: 14) {
                Text(message)
                    .font(.ariBody)
                    .foregroundStyle(.ariText)
                    .multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    if canRetry { DeskPill(title: "Try again", acts: true, action: retry) }
                    DeskPill(title: "Close", action: close)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.ariBackground.opacity(0.92))
        } else if takeover?.phase == .taking || !picture {
            VStack(spacing: 10) {
                ProgressView().tint(.ariSecondary)
                Text(
                    takeover?.phase == .taking
                        ? "\(LeadName.current) is finishing its step…" : "Loading the page…"
                )
                .font(.footnote)
                .foregroundStyle(.ariSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.ariBackground.opacity(picture ? 0.6 : 1))
            .allowsHitTesting(false)
        }
    }

    private var message: String? {
        if let ended { return ended }
        switch takeover?.phase {
        case .failed(let why), .lost(let why): return why
        default: return nil
        }
    }

    private var canRetry: Bool {
        if ended != nil { return false }
        if case .failed = takeover?.phase { return true }
        return false
    }
}

extension EnvironmentValues {
    /// Whether the keyboard is up, for the takeover's bar to slim down.
    @Entry var keyboardShown = false
}
