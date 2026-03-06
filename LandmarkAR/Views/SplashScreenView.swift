import SwiftUI
import UIKit

// MARK: - SplashScreenView (LAR-31)
// Shown on launch for 4 seconds. Uses the app icon artwork as a full-screen
// background and displays the app name, tagline, and studio credit.

struct SplashScreenView: View {
    var body: some View {
        ZStack {
            // App icon artwork as full-bleed background
            Image(uiImage: UIImage(named: "AppIcon") ?? UIImage())
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

                Text("Discover landmarks around you\nin augmented reality")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.top, 12)

                Spacer()

                Text("by Edward Aspen Studios")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.65))
                    .padding(.bottom, 48)
            }
            .padding(.horizontal, 32)
        }
    }
}
