import AriKit
import SwiftUI

@main
struct AriApp: App {
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate
    private var model: AppModel { delegate.model }
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                    if DebugScript.showsMoods { KumoMoods() } else { app }
                #else
                    app
                #endif
            }
            .onOpenURL { model.open($0) }
            #if DEBUG
                .task { if let url = DebugScript.openURL { model.open(url) } }
            #endif
            .preferredColorScheme(.dark)
            .tint(.ariText)
            .onChange(of: scenePhase, initial: true) { _, phase in
                // On screen, the stream is live; in the background it closes, while a waiting
                // message or a Stop still goes. Only the background: Control Center, a permission
                // prompt or a call's banner make Ari inactive for a moment, and closing the stream
                // for each made it reconnect.
                switch phase {
                case .active:
                    model.session?.start()
                    model.collectShares()
                    model.refreshServer()
                    model.whereabouts.refresh()
                case .background:
                    // A call carries on in your pocket: Ari's replies still have to arrive.
                    if CallEngine.isOn { break }
                    model.session?.pause()
                default:
                    break
                }
            }
        }

    }

    /// Ito itself: the Desk and its tabs once connected, else connecting.
    @ViewBuilder
    private var app: some View {
        if let session = model.session, model.pairing == nil {
            MainView(session: session, model: model)
        } else {
            // A pairing link opened while connected pairs at once; Not now goes back.
            ConnectView(
                address: model.lastAddress, pairing: model.pairing,
                cancel: model.session == nil ? nil : { model.pairing = nil },
                connected: model.connected
            )
            .id(model.pairing?.code)
        }
    }
}
