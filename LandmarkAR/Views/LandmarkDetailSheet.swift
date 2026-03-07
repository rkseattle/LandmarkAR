import MapKit
import SwiftUI
import UIKit

// MARK: - LandmarkDetailSheet
// Shown when the user taps a floating label in AR.
// Displays the Wikipedia summary + a link to the full article.

struct LandmarkDetailSheet: View {
    let landmark: Landmark
    @Environment(\.dismiss) private var dismiss
    @Environment(\.localeBundle) private var bundle

    @State private var showMapPicker = false

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

                    // Get Directions (LAR-37)
                    Button {
                        let apps = availableMapApps
                        if apps.count > 1 {
                            showMapPicker = true
                        } else {
                            open(in: .appleMaps)
                        }
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
                    .confirmationDialog(
                        Text("detail.getDirections", bundle: bundle),
                        isPresented: $showMapPicker,
                        titleVisibility: .visible
                    ) {
                        ForEach(availableMapApps) { app in
                            Button(app.displayName) { open(in: app) }
                        }
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

    // MARK: - Map App Support

    /// The map apps currently installed on this device, in display order.
    /// Apple Maps is always first and always available.
    private var availableMapApps: [MapApp] {
        MapApp.allCases.filter { app in
            guard let scheme = app.urlScheme else { return true } // Apple Maps has no scheme check
            return UIApplication.shared.canOpenURL(URL(string: "\(scheme)://")!)
        }
    }

    private func open(in app: MapApp) {
        let lat = landmark.coordinate.latitude
        let lon = landmark.coordinate.longitude

        switch app {
        case .appleMaps:
            let placemark = MKPlacemark(coordinate: landmark.coordinate)
            let mapItem = MKMapItem(placemark: placemark)
            mapItem.name = landmark.title
            mapItem.openInMaps(launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault
            ])
        case .googleMaps:
            if let url = URL(string: "comgooglemaps://?daddr=\(lat),\(lon)&directionsmode=driving") {
                UIApplication.shared.open(url)
            }
        case .waze:
            if let url = URL(string: "waze://?ll=\(lat),\(lon)&navigate=yes") {
                UIApplication.shared.open(url)
            }
        }
    }

    // MARK: - Formatted Distance

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

// MARK: - MapApp

enum MapApp: CaseIterable, Identifiable {
    case appleMaps
    case googleMaps
    case waze

    var id: Self { self }

    var displayName: String {
        switch self {
        case .appleMaps:  return "Apple Maps"
        case .googleMaps: return "Google Maps"
        case .waze:       return "Waze"
        }
    }

    /// The URL scheme used to check if this app is installed.
    /// nil means the app is always available (Apple Maps).
    var urlScheme: String? {
        switch self {
        case .appleMaps:  return nil
        case .googleMaps: return "comgooglemaps"
        case .waze:       return "waze"
        }
    }
}
