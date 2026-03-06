import SwiftUI

// MARK: - LandmarkARApp (LAR-31)
// Shows the splash screen for 4 seconds, then fades into ContentView.

@main
struct LandmarkARApp: App {
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            Group {
                if showSplash {
                    SplashScreenView()
                        .transition(.opacity)
                } else {
                    ContentView()
                        .transition(.opacity)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    withAnimation(.easeOut(duration: 0.6)) {
                        showSplash = false
                    }
                }
            }
        }
    }
}
