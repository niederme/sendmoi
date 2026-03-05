import SwiftUI

@main
struct SendMoiApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsSplashOverlay = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(model)

                #if os(iOS)
                if showsSplashOverlay {
                    SplashOverlayView()
                        .transition(.opacity)
                }
                #endif
            }
            .task {
                async let startup: Void = model.startup()

                #if os(iOS)
                try? await Task.sleep(for: .milliseconds(650))
                if !Task.isCancelled {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showsSplashOverlay = false
                    }
                }
                #endif

                _ = await startup
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await model.retryNow()
                }
            }
        }
    }
}

#if os(iOS)
private struct SplashOverlayView: View {
    var body: some View {
        GeometryReader { proxy in
            let splashSize = min(max(proxy.size.width * 0.34, 120), 180)

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.22, green: 0.49, blue: 0.98),
                        Color(red: 0.10, green: 0.34, blue: 0.96),
                        Color(red: 0.69, green: 0.09, blue: 0.99)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(spacing: splashSize * 0.16) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: splashSize, weight: .regular))
                        .rotationEffect(.degrees(18))
                        .foregroundStyle(.white)

                    Text("moi")
                        .font(.system(size: splashSize * 0.56, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .offset(y: -proxy.size.height * 0.03)
            }
            .ignoresSafeArea()
        }
        .accessibilityHidden(true)
    }
}
#endif
