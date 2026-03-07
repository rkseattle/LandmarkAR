import CoreLocation
import MapKit
import XCTest
@testable import LandmarkAR

// MARK: - MapsDirectionsTests (LAR-37)
// Verifies that a Landmark's coordinate maps correctly to an MKPlacemark,
// which is the input to the "Get Directions" / openInMaps call.

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
        let landmark = makeLandmark(lat: -33.8688, lon: 151.2093, title: "Sydney Opera House")
        let placemark = MKPlacemark(coordinate: landmark.coordinate)

        XCTAssertEqual(placemark.coordinate.latitude,  -33.8688, accuracy: 0.00001)
        XCTAssertEqual(placemark.coordinate.longitude, 151.2093, accuracy: 0.00001)
    }
}
