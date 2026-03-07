import SwiftUI

// MARK: - SplashScreenView (LAR-31)
// Shown on launch for 4 seconds. Uses a full-screen background image and
// displays the app name, tagline, and studio credit.

struct SplashScreenView: View {
    // LAR-35: The splash appears before ContentView, so read the saved language
    // directly rather than depending on the environment.
    private var localizedBundle: Bundle {
        let code = UserDefaults.standard.string(forKey: "appLanguage")
                   ?? AppLanguage.systemDefault().rawValue
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }

    var body: some View {
        ZStack {
            // Background image
            Image("SplashBackground")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            // Darkening overlay for legibility
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Text("LandmarkAR")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundColor(.white)

                Text("splash.tagline", bundle: localizedBundle)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.top, 12)

                Spacer()

                Text("splash.credit", bundle: localizedBundle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.65))
                    .padding(.bottom, 48)
            }
            .padding(.horizontal, 32)
        }
    }
}
