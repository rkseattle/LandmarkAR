import SwiftUI
import CoreLocation

// MARK: - ContentView
// The root view of the app. Manages all state and orchestrates:
// - Location permissions
// - Fetching landmarks from Wikipedia
// - Passing data to the AR view
// - Showing the detail sheet when a label is tapped

struct ContentView: View {

    @StateObject private var locationManager = LocationManager()
    @StateObject private var settings = AppSettings()

    @State private var landmarks: [Landmark] = []
    @State private var selectedLandmark: Landmark?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastFetchLocation: CLLocation?
    @State private var showSettings = false

    private let wikipediaService = WikipediaService()
    private let osmService = OpenStreetMapService()
    private let npsService = NPSService()
    private let refetchDistanceThreshold: CLLocationDistance = 200

    // Landmarks filtered by the user's category settings (LAR-5)
    private var filteredLandmarks: [Landmark] {
        landmarks.filter { landmark in
            switch landmark.category {
            case .historical: return settings.showHistorical
            case .natural:    return settings.showNatural
            case .cultural:   return settings.showCultural
            case .other:      return settings.showOther
            }
        }
    }

    var body: some View {
        ZStack {
            // MARK: Permission Not Granted
            if locationManager.authorizationStatus == .denied ||
               locationManager.authorizationStatus == .restricted {
                PermissionDeniedView()

            // MARK: Waiting for first location fix
            } else if locationManager.userLocation == nil {
                WaitingForLocationView()

            // MARK: AR is ready — show the camera + labels
            } else {
                ARLandmarkView(
                    landmarks: filteredLandmarks,
                    userLocation: locationManager.userLocation,
                    heading: locationManager.heading,
                    selectedLandmark: $selectedLandmark
                )
                .ignoresSafeArea()

                overlayUI
            }
        }
        .onAppear {
            locationManager.start()
        }
        .onChange(of: locationManager.userLocation) { _, newLocation in
            guard let newLocation = newLocation else { return }
            fetchLandmarksIfNeeded(at: newLocation)
        }
        // Re-fetch when key settings change (LAR-3, LAR-4, LAR-11, LAR-12)
        .onChange(of: settings.isWikipediaEnabled) { _, _ in
            guard let location = locationManager.userLocation else { return }
            Task { await fetchLandmarks(at: location) }
        }
        .onChange(of: settings.isOpenStreetMapEnabled) { _, _ in
            guard let location = locationManager.userLocation else { return }
            Task { await fetchLandmarks(at: location) }
        }
        .onChange(of: settings.isNPSEnabled) { _, _ in
            guard let location = locationManager.userLocation else { return }
            Task { await fetchLandmarks(at: location) }
        }
        .onChange(of: settings.npsApiKey) { _, _ in
            guard let location = locationManager.userLocation else { return }
            Task { await fetchLandmarks(at: location) }
        }
        .onChange(of: settings.maxDistanceKm) { _, _ in
            guard let location = locationManager.userLocation else { return }
            lastFetchLocation = nil  // force a re-fetch at new radius
            Task { await fetchLandmarks(at: location) }
        }
        .sheet(item: $selectedLandmark) { landmark in
            LandmarkDetailSheet(landmark: landmark)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings)
        }
    }

    // MARK: - Overlay UI

    private var overlayUI: some View {
        VStack {
            // Top bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LandmarkAR")
                        .font(.headline)
                        .foregroundColor(.white)
                    if !filteredLandmarks.isEmpty {
                        Text("\(filteredLandmarks.count) landmarks nearby")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                Spacer()

                // Settings button (LAR-2)
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.white)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }

                // Refresh button
                Button {
                    if let location = locationManager.userLocation {
                        Task { await fetchLandmarks(at: location) }
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.white)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.5), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            Spacer()

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                    Text("Finding landmarks…")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .padding(.bottom, 20)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.red.opacity(0.7))
                    .cornerRadius(8)
                    .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Landmark Fetching

    private func fetchLandmarksIfNeeded(at location: CLLocation) {
        if let last = lastFetchLocation,
           location.distance(from: last) < refetchDistanceThreshold {
            return
        }
        Task { await fetchLandmarks(at: location) }
    }

    @MainActor
    private func fetchLandmarks(at location: CLLocation) async {
        isLoading = true
        errorMessage = nil
        lastFetchLocation = location

        do {
            // Fetch from all enabled data sources in parallel (LAR-11, LAR-12).
            // Wikipedia and NPS can throw; OSM is non-throwing and returns [] on failure.
            async let wikipediaResults = wikipediaService.fetchNearbyLandmarks(near: location, settings: settings)
            async let osmResults = osmService.fetchNearbyLandmarks(near: location, settings: settings)
            async let npsResults = npsService.fetchNearbyLandmarks(near: location, settings: settings)

            let fromOSM = await osmResults
            let (fromWikipedia, fromNPS) = try await (wikipediaResults, npsResults)

            // Merge and deduplicate by title (case-insensitive), preferring Wikipedia entries
            var seen = Set<String>()
            var merged: [Landmark] = []
            for landmark in (fromWikipedia + fromOSM + fromNPS) {
                let key = landmark.title.lowercased()
                if seen.insert(key).inserted {
                    merged.append(landmark)
                }
            }
            landmarks = merged.sorted { $0.distance < $1.distance }
        } catch {
            errorMessage = "Couldn't load landmarks: \(error.localizedDescription)"
        }

        isLoading = false
    }
}

// MARK: - Permission Denied View

struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "location.slash.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            Text("Location Access Required")
                .font(.title2).bold()
            Text("LandmarkAR needs your location to find nearby landmarks and show them in augmented reality.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Waiting for Location View

struct WaitingForLocationView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Acquiring GPS signal…")
                .font(.headline)
            Text("Please stand outside with a clear view of the sky for best results.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
        }
        .padding()
    }
}
