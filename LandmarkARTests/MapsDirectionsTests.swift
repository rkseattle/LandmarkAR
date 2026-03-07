import CoreLocation
import MapKit
import XCTest
@testable import LandmarkAR

// MARK: - MapsDirectionsTests (LAR-37)

final class MapsDirectionsTests: XCTestCase {

    private func makeLandmark(lat: Double, lon: Double, title: String = "Test") -> Landmark {
        Landmark(
            id: "1",
            title: title,
            summary: "",
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            wikipediaURL: nil,
            category: .other,
            distance: 100,
            bearing: 0
        )
    }

    // MARK: - MKPlacemark / MKMapItem construction

    func testPlacemarkCoordinateMatchesLandmark() {
        let landmark = makeLandmark(lat: 37.7749, lon: -122.4194)
        let placemark = MKPlacemark(coordinate: landmark.coordinate)

        XCTAssertEqual(placemark.coordinate.latitude,  landmark.coordinate.latitude,  accuracy: 0.00001)
        XCTAssertEqual(placemark.coordinate.longitude, landmark.coordinate.longitude, accuracy: 0.00001)
    }

    func testMapItemNameMatchesLandmarkTitle() {
        let landmark = makeLandmark(lat: 48.8584, lon: 2.2945, title: "Eiffel Tower")
        let placemark = MKPlacemark(coordinate: landmark.coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = landmark.title

        XCTAssertEqual(mapItem.name, "Eiffel Tower")
    }

    func testPlacemarkPreservesNegativeCoordinates() {
        let landmark = makeLandmark(lat: -33.8688, lon: 151.2093)
        let placemark = MKPlacemark(coordinate: landmark.coordinate)

        XCTAssertEqual(placemark.coordinate.latitude,  -33.8688, accuracy: 0.00001)
        XCTAssertEqual(placemark.coordinate.longitude, 151.2093, accuracy: 0.00001)
    }

    // MARK: - MapApp enum

    func testMapAppDisplayNames() {
        XCTAssertEqual(MapApp.appleMaps.displayName,  "Apple Maps")
        XCTAssertEqual(MapApp.googleMaps.displayName, "Google Maps")
        XCTAssertEqual(MapApp.waze.displayName,       "Waze")
    }

    func testAppleMapsHasNoUrlScheme() {
        XCTAssertNil(MapApp.appleMaps.urlScheme,
                     "Apple Maps requires no canOpenURL check — it is always available")
    }

    func testThirdPartyAppsHaveUrlSchemes() {
        XCTAssertEqual(MapApp.googleMaps.urlScheme, "comgooglemaps")
        XCTAssertEqual(MapApp.waze.urlScheme,       "waze")
    }

    func testAllCasesCount() {
        XCTAssertEqual(MapApp.allCases.count, 3)
    }

    func testAppleMapsIsFirstInAllCases() {
        XCTAssertEqual(MapApp.allCases.first, .appleMaps,
                       "Apple Maps should always be listed first")
    }

    // MARK: - URL scheme format

    func testGoogleMapsDirectionsUrl() {
        let lat = 51.5074, lon = -0.1278
        let url = URL(string: "comgooglemaps://?daddr=\(lat),\(lon)&directionsmode=driving")
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.scheme, "comgooglemaps")
    }

    func testWazeDirectionsUrl() {
        let lat = 51.5074, lon = -0.1278
        let url = URL(string: "waze://?ll=\(lat),\(lon)&navigate=yes")
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.scheme, "waze")
    }
}
