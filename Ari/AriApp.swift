import AriKit
import SwiftUI

@main
struct AriApp: App {
    #if os(iOS)
        @UIApplicationDelegateAdaptor private var delegate: AppDelegate
        private var model: AppModel { delegate.model }
    #else
        @State private var model = AppModel()
    #endif
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
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
            .onOpenURL { model.open($0) }
            #if DEBUG
                .task { if let url = DebugScript.openURL { model.open(url) } }
            #endif
            .preferredColorScheme(.dark)
            .tint(.ariText)
            .onChange(of: scenePhase, initial: true) { _, phase in
                // On screen, the stream is live; off screen it closes, while a waiting message
                // or a Stop still goes.
                if phase == .active {
                    model.session?.start()
                    model.collectShares()
                    model.refreshServer()
                } else {
                    model.session?.pause()
                }
            }
        }
    }
}
