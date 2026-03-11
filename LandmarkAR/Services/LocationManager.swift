import CoreLocation
import Combine
import Foundation
import UIKit

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
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceOrientationDidChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
        applyHeadingOrientation()
    }

    deinit {
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    // MARK: - Heading Orientation

    // Keeps CLLocationManager.headingOrientation in sync with device rotation so the
    // compass reads correctly in both portrait and landscape (CLDeviceOrientation and
    // UIDeviceOrientation share raw values, so the cast is safe).
    @objc private func deviceOrientationDidChange() {
        applyHeadingOrientation()
    }

    private func applyHeadingOrientation() {
        let raw = Int32(UIDevice.current.orientation.rawValue)
        guard let orientation = CLDeviceOrientation(rawValue: raw),
              orientation != .unknown,
              orientation != .faceUp,
              orientation != .faceDown else { return }
        manager.headingOrientation = orientation
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
