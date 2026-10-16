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
                if let session = model.session {
                    MainView(session: session, model: model)
                } else {
                    ConnectView(address: model.lastAddress, connected: model.connected)
                }
            }
            .preferredColorScheme(.dark)
            .tint(.ariText)
            .onChange(of: scenePhase, initial: true) { _, phase in
                // On screen, the stream is live; off screen it closes, while a waiting message
                // or a Stop still goes.
                if phase == .active {
                    model.session?.start()
                    model.refreshServer()
                } else {
                    model.session?.pause()
                }
            }
        }
    }
}
