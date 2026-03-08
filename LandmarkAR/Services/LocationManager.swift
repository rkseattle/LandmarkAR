import CoreLocation
import Combine
import Foundation

// MARK: - LocationManager
// Handles GPS location + compass heading updates from the device.
// Uses the "ObservableObject" pattern so SwiftUI views update automatically.

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    // Published properties: any SwiftUI view that reads these will re-render when they change
    @Published var userLocation: CLLocation?
    @Published var heading: CLHeading?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var errorMessage: String?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // Request the best accuracy available — important for AR positioning
        // Only publish a new location after moving at least 10 m; prevents
        // hammering fetchLandmarksIfNeeded on every millimetre of GPS drift.
        manager.distanceFilter = 10
    }

    // Call this to start everything (called from the main view on appear)
    func start() {
        manager.requestWhenInUseAuthorization()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways {
            // Start both GPS and compass once we have permission.
            // Heading filter of 5° prevents excessive redraws from tiny compass jitter.
            manager.headingFilter = 5
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Take the most recent location
        userLocation = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = "Location error: \(error.localizedDescription)"
    }
}
