import SwiftUI

@main
struct SendMoiApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .task {
                    await model.startup()
                }
        }
        #if os(macOS)
        .defaultSize(width: 1040, height: 640)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
        #endif
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await model.retryNow()
                }
            }
        }
    }
}
