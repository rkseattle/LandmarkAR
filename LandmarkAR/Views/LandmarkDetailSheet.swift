import MapKit
import SwiftUI

// MARK: - LandmarkDetailSheet
// Shown when the user taps a floating label in AR.
// Displays the Wikipedia summary + a link to the full article.

struct LandmarkDetailSheet: View {
    let landmark: Landmark
    @Environment(\.dismiss) private var dismiss
    @Environment(\.localeBundle) private var bundle

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // Distance badge
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(.blue)
                        Text(formattedDistance)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    Divider()

                    // Wikipedia summary text
                    Text(landmark.summary)
                        .font(.body)
                        .lineSpacing(4)

                    Divider()

                    // Get Directions in Maps (LAR-37)
                    Button {
                        openInMaps()
                    } label: {
                        HStack {
                            Image(systemName: "map.fill")
                            Text("detail.getDirections", bundle: bundle)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.subheadline)
                        .foregroundColor(.green)
                        .padding()
                        .background(Color.green.opacity(0.08))
                        .cornerRadius(10)
                    }

                    // Link to full Wikipedia article
                    if let url = landmark.wikipediaURL {
                        Link(destination: url) {
                            HStack {
                                Image(systemName: "globe")
                                Text("detail.readOnWikipedia", bundle: bundle)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }
                            .font(.subheadline)
                            .foregroundColor(.blue)
                            .padding()
                            .background(Color.blue.opacity(0.08))
                            .cornerRadius(10)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(landmark.title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Text("detail.done", bundle: bundle)
                    }
                }
            }
        }
    }

    // LAR-37: Open Apple Maps with turn-by-turn directions from current location.
    private func openInMaps() {
        let placemark = MKPlacemark(coordinate: landmark.coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = landmark.title
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault
        ])
    }

    private var formattedDistance: String {
        let meters = landmark.distance
        if meters < 1000 {
            let fmt = bundle.localizedString(forKey: "detail.metersAway", value: "%d meters away", table: nil)
            return String(format: fmt, Int(meters))
        } else {
            let fmt = bundle.localizedString(forKey: "detail.kmAway", value: "%.1f km away", table: nil)
            return String(format: fmt, meters / 1000)
        }
    }
}
