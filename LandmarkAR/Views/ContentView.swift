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
    @StateObject private var errorLogger = ErrorLogger()
    @StateObject private var circuitBreaker = DataSourceCircuitBreaker()
    @StateObject private var networkMonitor = NetworkMonitor()

    @State private var landmarks: [Landmark] = []
    @State private var selectedLandmark: Landmark?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var errorDismissTask: Task<Void, Never>?
    @State private var lastFetchLocation: CLLocation?
    @State private var lastFetchTime: Date?
    @State private var realtimeTimer: Timer?
    @State private var showSettings = false

    private let wikipediaService = WikipediaService()
    private let osmService = OpenStreetMapService()
    private let npsService = NPSService()
    private let elevationService = ElevationService()
    private let normalDistanceThreshold: CLLocationDistance = 200
    private let realtimeDistanceThreshold: CLLocationDistance = 50
    private let realtimeInterval: TimeInterval = 30
    private let deduplicationProximityMeters: CLLocationDistance = 75

    // LAR-28: Real-time is active when mode is "always", or "wifiOnly" while on Wi-Fi.
    private var isRealtimeActive: Bool {
        switch settings.realtimeUpdateMode {
        case .off:      return false
        case .always:   return true
        case .wifiOnly: return networkMonitor.isOnWifi
        }
    }

    private var refetchDistanceThreshold: CLLocationDistance {
        isRealtimeActive ? realtimeDistanceThreshold : normalDistanceThreshold
    }

    // Landmarks filtered by category toggles, per-category distance, and display limit (LAR-5, LAR-13, LAR-23)
    private var filteredLandmarks: [Landmark] {
        let filtered = landmarks.filter { landmark in
            switch landmark.category {
            case .historical:
                return settings.showHistorical && landmark.distance <= settings.maxDistanceKmHistorical * 1000
            case .natural:
                return settings.showNatural && landmark.distance <= settings.maxDistanceKmNatural * 1000
            case .cultural:
                return settings.showCultural && landmark.distance <= settings.maxDistanceKmCultural * 1000
            case .other:
                return settings.showOther && landmark.distance <= settings.maxDistanceKmOther * 1000
            }
        }
        return applyCountLimit(to: filtered)
    }

    // LAR-23: Return at most maxLandmarkCount, always including the closest and farthest.
    private func applyCountLimit(to sorted: [Landmark]) -> [Landmark] {
        let limit = settings.maxLandmarkCount
        guard sorted.count > limit else { return sorted }
        guard limit >= 2 else { return Array(sorted.prefix(limit)) }

        var selected = [sorted.first!, sorted.last!]
        let pool = Array(sorted.dropFirst().dropLast())
        let needed = limit - 2
        guard !pool.isEmpty, needed > 0 else {
            return selected.sorted { $0.distance < $1.distance }
        }

        let step = Double(pool.count) / Double(needed)
        for i in 0..<needed {
            let idx = min(Int((Double(i) * step + step / 2).rounded()), pool.count - 1)
            selected.append(pool[idx])
        }
        return selected.sorted { $0.distance < $1.distance }
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
                    labelDisplaySize: settings.labelDisplaySize,
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
        // LAR-13: Re-fetch when any per-category distance changes (may expand the radius)
        .onChange(of: settings.maxDistanceIndexHistorical) { _, _ in
            guard let location = locationManager.userLocation else { return }
            lastFetchLocation = nil
            Task { await fetchLandmarks(at: location) }
        }
        .onChange(of: settings.maxDistanceIndexNatural) { _, _ in
            guard let location = locationManager.userLocation else { return }
            lastFetchLocation = nil
            Task { await fetchLandmarks(at: location) }
        }
        .onChange(of: settings.maxDistanceIndexCultural) { _, _ in
            guard let location = locationManager.userLocation else { return }
            lastFetchLocation = nil
            Task { await fetchLandmarks(at: location) }
        }
        .onChange(of: settings.maxDistanceIndexOther) { _, _ in
            guard let location = locationManager.userLocation else { return }
            lastFetchLocation = nil
            Task { await fetchLandmarks(at: location) }
        }
        // LAR-25/LAR-28: Start/stop real-time timer when mode or Wi-Fi connectivity changes
        .onChange(of: settings.realtimeUpdateMode) { _, _ in handleRealtimeModeChange() }
        .onChange(of: networkMonitor.isOnWifi) { _, _ in handleRealtimeModeChange() }
        .sheet(item: $selectedLandmark) { landmark in
            LandmarkDetailSheet(landmark: landmark)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings, errorLogger: errorLogger)
        }
        // LAR-35: Re-fetch when the language changes (Wikipedia subdomain switches)
        .onChange(of: settings.appLanguage) { _, _ in
            guard let location = locationManager.userLocation else { return }
            lastFetchLocation = nil
            Task { await fetchLandmarks(at: location) }
        }
        // LAR-35: Inject the language-specific bundle into the environment for all child views
        .environment(\.localeBundle, settings.localizedBundle)
    }

    // MARK: - Overlay UI

    private var overlayUI: some View {
        VStack {
            // Top bar (LAR-31)
            HStack {
                // Refresh button — upper left
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

                Spacer()

                // Settings button — upper right (LAR-2)
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
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
                    Text("content.findingLandmarks", bundle: settings.localizedBundle)
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
                    .onTapGesture { dismissError() }
            }
        }
    }

    // MARK: - Error Bubble (LAR-16)

    private func showError(_ message: String) {
        errorLogger.log(message)
        errorMessage = message
        errorDismissTask?.cancel()
        errorDismissTask = Task {
            try? await Task.sleep(for: .seconds(20))
            if !Task.isCancelled {
                errorMessage = nil
            }
        }
    }

    private func dismissError() {
        errorDismissTask?.cancel()
        errorMessage = nil
    }

    // MARK: - Landmark Fetching

    private func fetchLandmarksIfNeeded(at location: CLLocation) {
        if let last = lastFetchLocation,
           location.distance(from: last) < refetchDistanceThreshold {
            // In real-time mode also apply a time gate so we don't spam on slow movement
            if isRealtimeActive,
               let lastTime = lastFetchTime,
               Date().timeIntervalSince(lastTime) < realtimeInterval {
                return
            } else if !isRealtimeActive {
                return
            }
        }
        Task { await fetchLandmarks(at: location) }
    }

    private func handleRealtimeModeChange() {
        if isRealtimeActive {
            guard let location = locationManager.userLocation else { return }
            Task { await fetchLandmarks(at: location) }
            startRealtimeTimer()
        } else {
            stopRealtimeTimer()
        }
    }

    private func startRealtimeTimer() {
        realtimeTimer?.invalidate()
        realtimeTimer = Timer.scheduledTimer(withTimeInterval: realtimeInterval, repeats: true) { _ in
            guard let location = locationManager.userLocation else { return }
            Task { await fetchLandmarks(at: location) }
        }
    }

    private func stopRealtimeTimer() {
        realtimeTimer?.invalidate()
        realtimeTimer = nil
    }

    @MainActor
    private func fetchLandmarks(at location: CLLocation) async {
        isLoading = true
        errorMessage = nil
        lastFetchLocation = location
        lastFetchTime = Date()

        // LAR-26: Fetch each source individually so we can record per-source
        // successes/failures and skip sources that are in circuit-breaker cooldown.

        // Wikipedia
        var fromWikipedia: [Landmark] = []
        if settings.isWikipediaEnabled {
            let src = DataSourceCircuitBreaker.wikipedia
            if circuitBreaker.isAvailable(src) {
                do {
                    fromWikipedia = try await wikipediaService.fetchNearbyLandmarks(near: location, settings: settings)
                    circuitBreaker.recordSuccess(src)
                } catch {
                    circuitBreaker.recordFailure(src)
                    let suffix = circuitBreaker.cooldownMinutesRemaining(src).map { " (paused \($0) min)" } ?? ""
                    showError("Wikipedia unavailable\(suffix): \(error.localizedDescription)")
                }
            } else {
                let mins = circuitBreaker.cooldownMinutesRemaining(src) ?? 0
                showError("Wikipedia skipped — too many errors. Retrying in \(mins) min.")
            }
        }

        // OpenStreetMap (non-throwing; returns [] on failure)
        var fromOSM: [Landmark] = []
        if settings.isOpenStreetMapEnabled {
            let src = DataSourceCircuitBreaker.openStreetMap
            if circuitBreaker.isAvailable(src) {
                let result = await osmService.fetchNearbyLandmarks(near: location, settings: settings)
                if result.isEmpty && settings.isOpenStreetMapEnabled {
                    // Treat an empty result as a soft failure only when we expected data
                    // (OSM returns [] both when disabled and on network error; we can't distinguish easily,
                    // so we only record success here — circuit breaker stays neutral on empty results)
                }
                fromOSM = result
                circuitBreaker.recordSuccess(src)
            } else {
                let mins = circuitBreaker.cooldownMinutesRemaining(src) ?? 0
                showError("OpenStreetMap skipped — too many errors. Retrying in \(mins) min.")
            }
        }

        // NPS (LAR-17: disabled — service code kept for future re-enablement)
        var fromNPS: [Landmark] = []
        if false {
            let src = DataSourceCircuitBreaker.nps
            if circuitBreaker.isAvailable(src) {
                do {
                    fromNPS = try await npsService.fetchNearbyLandmarks(near: location, settings: settings)
                    circuitBreaker.recordSuccess(src)
                } catch {
                    circuitBreaker.recordFailure(src)
                    let suffix = circuitBreaker.cooldownMinutesRemaining(src).map { " (paused \($0) min)" } ?? ""
                    showError("NPS unavailable\(suffix): \(error.localizedDescription)")
                }
            } else {
                let mins = circuitBreaker.cooldownMinutesRemaining(src) ?? 0
                showError("NPS skipped — too many errors. Retrying in \(mins) min.")
            }
        }

        // Merge and deduplicate by title OR geographic proximity (LAR-21).
        // Prefer Wikipedia → OSM → NPS (iteration order already encodes priority).
        var seenTitles = Set<String>()
        var acceptedLocations: [CLLocation] = []
        var merged: [Landmark] = []
        for landmark in (fromWikipedia + fromOSM + fromNPS) {
            let titleKey = landmark.title.lowercased()
            guard seenTitles.insert(titleKey).inserted else { continue }

            let landmarkLoc = CLLocation(latitude: landmark.coordinate.latitude,
                                         longitude: landmark.coordinate.longitude)
            let isDuplicate = acceptedLocations.contains {
                $0.distance(from: landmarkLoc) < deduplicationProximityMeters
            }
            guard !isDuplicate else { continue }

            merged.append(landmark)
            acceptedLocations.append(landmarkLoc)
        }
        var sorted = merged.sorted { $0.distance < $1.distance }

        // Fetch elevations for landmarks that don't already have one (LAR-15)
        let elevations = await elevationService.fetchElevations(for: sorted)
        if !elevations.isEmpty {
            sorted = sorted.map { landmark in
                guard let alt = elevations[landmark.id] else { return landmark }
                var updated = landmark
                updated.altitude = alt
                return updated
            }
        }

        landmarks = sorted
        isLoading = false
    }
}

// MARK: - Permission Denied View

struct PermissionDeniedView: View {
    @Environment(\.localeBundle) private var bundle

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "location.slash.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            Text("content.permission.title", bundle: bundle)
                .font(.title2).bold()
            Text("content.permission.message", bundle: bundle)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("content.permission.openSettings", bundle: bundle)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Waiting for Location View

struct WaitingForLocationView: View {
    @Environment(\.localeBundle) private var bundle

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("content.gps.acquiring", bundle: bundle)
                .font(.headline)
            Text("content.gps.hint", bundle: bundle)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
        }
        .padding()
    }
}
