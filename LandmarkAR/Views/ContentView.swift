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
    @State private var displayedLandmarks: [Landmark] = []
    @State private var selectedLandmark: Landmark?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var errorDismissTask: Task<Void, Never>?
    @State private var activeFetchTask: Task<Void, Never>?
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

    // Recomputes displayedLandmarks from the current landmarks array and filter settings.
    // Called explicitly after each fetch and when filter-only settings change, rather than
    // running as a computed property on every SwiftUI render pass (LAR-5, LAR-13, LAR-23).
    private func updateDisplayedLandmarks() {
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
        displayedLandmarks = applyCountLimit(to: filtered)
    }

    // Cancels any in-flight fetch before starting a new one, preventing stale results
    // from an earlier request from overwriting fresher data if tasks complete out of order.
    private func scheduleFetch(at location: CLLocation) {
        activeFetchTask?.cancel()
        activeFetchTask = Task { await fetchLandmarks(at: location) }
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
                    landmarks: displayedLandmarks,
                    userLocation: locationManager.userLocation,
                    heading: locationManager.heading,
                    labelDisplaySize: settings.labelDisplaySize,
                    selectedLandmark: $selectedLandmark
                )
                .ignoresSafeArea()

                overlayUI
            }
        }
        .onAppear { locationManager.start() }
        .modifier(LocationAndSettingsObserver(
            locationManager: locationManager,
            settings: settings,
            networkMonitor: networkMonitor,
            fetchLandmarksIfNeeded: fetchLandmarksIfNeeded,
            scheduleFetch: scheduleFetch,
            updateDisplayedLandmarks: updateDisplayedLandmarks,
            handleRealtimeModeChange: handleRealtimeModeChange,
            setLastFetchLocation: { lastFetchLocation = $0 }
        ))
        .sheet(item: $selectedLandmark) { landmark in
            LandmarkDetailSheet(landmark: landmark)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings, errorLogger: errorLogger)
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
                        scheduleFetch(at: location)
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
        scheduleFetch(at: location)
    }

    private func handleRealtimeModeChange() {
        if isRealtimeActive {
            guard let location = locationManager.userLocation else { return }
            scheduleFetch(at: location)
            startRealtimeTimer()
        } else {
            stopRealtimeTimer()
        }
    }

    private func startRealtimeTimer() {
        realtimeTimer?.invalidate()
        realtimeTimer = Timer.scheduledTimer(withTimeInterval: realtimeInterval, repeats: true) { _ in
            // Skip the tick if the previous fetch is still in flight to avoid queuing
            // concurrent requests that could overwrite each other's results.
            guard let location = locationManager.userLocation, !isLoading else { return }
            scheduleFetch(at: location)
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

        // LAR-26: Check circuit-breaker availability for each source up front, then
        // launch both network fetches concurrently so neither waits on the other.

        let wikiAvailable = settings.isWikipediaEnabled &&
                            circuitBreaker.isAvailable(DataSourceCircuitBreaker.wikipedia)
        let osmAvailable  = settings.isOpenStreetMapEnabled &&
                            circuitBreaker.isAvailable(DataSourceCircuitBreaker.openStreetMap)

        if settings.isWikipediaEnabled && !wikiAvailable {
            let mins = circuitBreaker.cooldownMinutesRemaining(DataSourceCircuitBreaker.wikipedia) ?? 0
            showError("Wikipedia skipped — too many errors. Retrying in \(mins) min.")
        }
        if settings.isOpenStreetMapEnabled && !osmAvailable {
            let mins = circuitBreaker.cooldownMinutesRemaining(DataSourceCircuitBreaker.openStreetMap) ?? 0
            showError("OpenStreetMap skipped — too many errors. Retrying in \(mins) min.")
        }

        // Start both fetches at the same time. Their network I/O runs concurrently;
        // we collect results below without either blocking the other.
        let wikiTask = Task { () throws -> [Landmark] in
            guard wikiAvailable else { return [] }
            return try await wikipediaService.fetchNearbyLandmarks(near: location, settings: settings)
        }
        let osmTask = Task { () throws -> [Landmark] in
            guard osmAvailable else { return [] }
            return try await osmService.fetchNearbyLandmarks(near: location, settings: settings)
        }

        var fromWikipedia: [Landmark] = []
        do {
            fromWikipedia = try await wikiTask.value
            if wikiAvailable { circuitBreaker.recordSuccess(DataSourceCircuitBreaker.wikipedia) }
        } catch {
            if wikiAvailable {
                circuitBreaker.recordFailure(DataSourceCircuitBreaker.wikipedia)
                let suffix = circuitBreaker.cooldownMinutesRemaining(DataSourceCircuitBreaker.wikipedia)
                    .map { " (paused \($0) min)" } ?? ""
                showError("Wikipedia unavailable\(suffix): \(error.localizedDescription)")
            }
        }

        var fromOSM: [Landmark] = []
        do {
            fromOSM = try await osmTask.value
            if osmAvailable { circuitBreaker.recordSuccess(DataSourceCircuitBreaker.openStreetMap) }
        } catch {
            if osmAvailable {
                circuitBreaker.recordFailure(DataSourceCircuitBreaker.openStreetMap)
                let suffix = circuitBreaker.cooldownMinutesRemaining(DataSourceCircuitBreaker.openStreetMap)
                    .map { " (paused \($0) min)" } ?? ""
                showError("OpenStreetMap unavailable\(suffix): \(error.localizedDescription)")
            }
        }

        // If this fetch was superseded by a newer one, discard results without updating UI.
        guard !Task.isCancelled else { isLoading = false; return }

        // NPS (LAR-17: disabled — service code kept for future re-enablement)
        let fromNPS: [Landmark] = []

        // Merge and deduplicate by title OR geographic proximity (LAR-21).
        // Prefer Wikipedia → OSM → NPS (iteration order already encodes priority).
        // Uses a grid-cell Set for O(1) proximity lookup instead of O(n²) linear scan.
        let gridDegrees = deduplicationProximityMeters / 111_000.0
        var seenTitles   = Set<String>()
        var occupiedCells = Set<String>()
        var merged: [Landmark] = []

        for landmark in (fromWikipedia + fromOSM + fromNPS) {
            let titleKey = landmark.title.lowercased()
            guard seenTitles.insert(titleKey).inserted else { continue }

            let latCell = Int((landmark.coordinate.latitude  / gridDegrees).rounded())
            let lonCell = Int((landmark.coordinate.longitude / gridDegrees).rounded())

            var nearExisting = false
            outerLoop: for dLat in -1...1 {
                for dLon in -1...1 {
                    if occupiedCells.contains("\(latCell + dLat)_\(lonCell + dLon)") {
                        nearExisting = true
                        break outerLoop
                    }
                }
            }
            guard !nearExisting else { continue }

            merged.append(landmark)
            occupiedCells.insert("\(latCell)_\(lonCell)")
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
        updateDisplayedLandmarks()
        isLoading = false
    }
}

// MARK: - Settings / Location Observer
// Extracted from ContentView.body to avoid Swift type-checker timeouts on long
// modifier chains. Each group of onChange calls is a separate body expression.

private struct LocationAndSettingsObserver: ViewModifier {
    let locationManager: LocationManager
    let settings: AppSettings
    let networkMonitor: NetworkMonitor
    let fetchLandmarksIfNeeded: (CLLocation) -> Void
    let scheduleFetch: (CLLocation) -> Void
    let updateDisplayedLandmarks: () -> Void
    let handleRealtimeModeChange: () -> Void
    let setLastFetchLocation: (CLLocation?) -> Void

    func body(content: Content) -> some View {
        content
            // Location
            .onChange(of: locationManager.userLocation) { _, newLocation in
                guard let newLocation else { return }
                fetchLandmarksIfNeeded(newLocation)
            }
            // Re-fetch when key settings change (LAR-3, LAR-4, LAR-11, LAR-12, LAR-39)
            .onChange(of: settings.isIconicLandmarksOnly) { _, _ in
                guard let location = locationManager.userLocation else { return }
                setLastFetchLocation(nil)
                scheduleFetch(location)
            }
            .onChange(of: settings.isWikipediaEnabled) { _, _ in
                guard let location = locationManager.userLocation else { return }
                scheduleFetch(location)
            }
            .onChange(of: settings.isOpenStreetMapEnabled) { _, _ in
                guard let location = locationManager.userLocation else { return }
                scheduleFetch(location)
            }
            // LAR-35: Re-fetch when the language changes
            .onChange(of: settings.appLanguage) { _, _ in
                guard let location = locationManager.userLocation else { return }
                setLastFetchLocation(nil)
                scheduleFetch(location)
            }
            .modifier(DistanceAndFilterObserver(
                locationManager: locationManager,
                settings: settings,
                networkMonitor: networkMonitor,
                scheduleFetch: scheduleFetch,
                updateDisplayedLandmarks: updateDisplayedLandmarks,
                handleRealtimeModeChange: handleRealtimeModeChange,
                setLastFetchLocation: setLastFetchLocation
            ))
    }
}

private struct DistanceAndFilterObserver: ViewModifier {
    let locationManager: LocationManager
    let settings: AppSettings
    let networkMonitor: NetworkMonitor
    let scheduleFetch: (CLLocation) -> Void
    let updateDisplayedLandmarks: () -> Void
    let handleRealtimeModeChange: () -> Void
    let setLastFetchLocation: (CLLocation?) -> Void

    func body(content: Content) -> some View {
        content
            // LAR-13: Re-fetch when any per-category distance changes
            .onChange(of: settings.maxDistanceIndexHistorical) { _, _ in
                guard let location = locationManager.userLocation else { return }
                setLastFetchLocation(nil)
                scheduleFetch(location)
            }
            .onChange(of: settings.maxDistanceIndexNatural) { _, _ in
                guard let location = locationManager.userLocation else { return }
                setLastFetchLocation(nil)
                scheduleFetch(location)
            }
            .onChange(of: settings.maxDistanceIndexCultural) { _, _ in
                guard let location = locationManager.userLocation else { return }
                setLastFetchLocation(nil)
                scheduleFetch(location)
            }
            .onChange(of: settings.maxDistanceIndexOther) { _, _ in
                guard let location = locationManager.userLocation else { return }
                setLastFetchLocation(nil)
                scheduleFetch(location)
            }
            // Filter-only: re-filter without a network round-trip
            .onChange(of: settings.showHistorical)   { _, _ in updateDisplayedLandmarks() }
            .onChange(of: settings.showNatural)      { _, _ in updateDisplayedLandmarks() }
            .onChange(of: settings.showCultural)     { _, _ in updateDisplayedLandmarks() }
            .onChange(of: settings.showOther)        { _, _ in updateDisplayedLandmarks() }
            .onChange(of: settings.maxLandmarkCount) { _, _ in updateDisplayedLandmarks() }
            // LAR-25/LAR-28: real-time timer
            .onChange(of: settings.realtimeUpdateMode) { _, _ in handleRealtimeModeChange() }
            .onChange(of: networkMonitor.isOnWifi)     { _, _ in handleRealtimeModeChange() }
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
