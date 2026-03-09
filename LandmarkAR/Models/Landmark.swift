import CoreLocation
import Foundation

// MARK: - LandmarkCategory (LAR-5)
// Keyword-based classification used for the category filter in Settings.

enum LandmarkCategory: String {
    case historical, natural, cultural, other

    // LAR-14: Icon matching the category toggles shown in Settings
    var systemImageName: String {
        switch self {
        case .historical: return "building.columns.fill"
        case .natural:    return "mountain.2.fill"
        case .cultural:   return "theatermasks.fill"
        case .other:      return "mappin.circle.fill"
        }
    }

    static func classify(title: String, summary: String) -> LandmarkCategory {
        let text  = (title + " " + summary).lowercased()
        // Split into individual words so single-word keywords match whole words only,
        // preventing substrings like "ridge" (natural) from firing on "bridge" (cultural).
        // Multi-word keywords (e.g. "historic district") still use plain text.contains().
        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
                        .filter { !$0.isEmpty }

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

        // A keyword matches if any word in the text starts with it (handles plurals/suffixes)
        // or, for multi-word keywords, if the full phrase appears anywhere in the text.
        func matches(_ keywords: [String]) -> Bool {
            keywords.contains(where: { kw in
                kw.contains(" ") ? text.contains(kw)
                                 : words.contains(where: { $0.hasPrefix(kw) })
            })
        }

        if matches(historicalKeywords) { return .historical }
        if matches(naturalKeywords)    { return .natural }
        if matches(culturalKeywords)   { return .cultural }
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
    var altitude: Double? = nil            // Meters above sea level; nil if unknown (LAR-15)

    // LAR-39: Significance scoring from Wikipedia pageviews + article length.
    // nil pageviews = API call failed (landmark is kept, scored on article length only).
    var significanceScore: Double = 0
    var pageviews: Int? = nil
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

// MARK: - Wikipedia Pageviews Response (LAR-39)
// Maps the Wikimedia pageviews REST API response for monthly article view counts.

struct WikipediaPageviewsResponse: Codable {
    let items: [WikipediaPageviewItem]
}

struct WikipediaPageviewItem: Codable {
    let views: Int
}
