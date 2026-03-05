import CoreLocation
import Foundation

// MARK: - LandmarkCategory (LAR-5)
// Keyword-based classification used for the category filter in Settings.

enum LandmarkCategory: String {
    case historical, natural, cultural, other

    static func classify(title: String, summary: String) -> LandmarkCategory {
        let text = (title + " " + summary).lowercased()

        let historicalKeywords = ["museum", "historic", "monument", "memorial", "war", "battle",
                                  "fort", "castle", "ruin", "colonial", "ancient", "heritage",
                                  "cemetery", "landmark", "church", "cathedral", "temple",
                                  "mosque", "synagogue", "basilica", "shrine", "chapel",
                                  "mission", "palace", "mansion", "historic district"]
        let naturalKeywords    = ["park", "mountain", "lake", "river", "forest", "canyon",
                                  "waterfall", "nature", "wildlife", "reserve", "beach",
                                  "glacier", "valley", "volcano", "creek", "bay", "island",
                                  "peak", "hill", "ridge", "trail", "wilderness", "garden",
                                  "botanical", "preserve"]
        let culturalKeywords   = ["art", "theater", "theatre", "gallery", "library", "university",
                                  "college", "stadium", "arena", "market", "bridge", "plaza",
                                  "center", "centre", "district", "neighborhood", "street",
                                  "avenue", "hall", "opera", "concert", "sculpture"]

        if historicalKeywords.contains(where: { text.contains($0) }) { return .historical }
        if naturalKeywords.contains(where:    { text.contains($0) }) { return .natural }
        if culturalKeywords.contains(where:   { text.contains($0) }) { return .cultural }
        return .other
    }
}

// MARK: - Landmark Model
// Represents a single point of interest (natural landmark, historic site, etc.)

struct Landmark: Identifiable {
    let id: String           // Unique Wikipedia page ID
    let title: String        // Display name
    let summary: String      // Short description from Wikipedia
    let coordinate: CLLocationCoordinate2D  // Lat/long of the landmark
    let wikipediaURL: URL?   // Link to full Wikipedia article
    let category: LandmarkCategory  // Used for category filtering (LAR-5)

    // Calculated at runtime — filled in after we know the user's location
    var distance: CLLocationDistance = 0   // Meters from user
    var bearing: Double = 0                // Degrees (0=North, 90=East, etc.)
}

// MARK: - Wikipedia API Response Models
// These structs map directly to the JSON returned by the Wikipedia GeoSearch API

struct WikipediaGeoSearchResponse: Codable {
    let query: WikipediaQuery
}

struct WikipediaQuery: Codable {
    let geosearch: [WikipediaGeoResult]
}

struct WikipediaGeoResult: Codable {
    let pageid: Int
    let title: String
    let lat: Double
    let lon: Double
    let dist: Double    // Distance in meters (provided by Wikipedia)
}

// MARK: - Wikipedia Summary Response
// Used when we fetch a short description for each landmark

struct WikipediaSummaryResponse: Codable {
    let extract: String?  // Plain-text summary; absent on error/missing pages
    let content_urls: WikipediaContentURLs?
}

struct WikipediaContentURLs: Codable {
    let desktop: WikipediaDesktopURL?
}

struct WikipediaDesktopURL: Codable {
    let page: String?
}
