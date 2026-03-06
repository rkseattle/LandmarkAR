import Foundation

// MARK: - AppSettings
// Persists user preferences via UserDefaults.
// Shared across the app via @StateObject / @EnvironmentObject.

class AppSettings: ObservableObject {

    // MARK: - Data Sources (LAR-3, LAR-11, LAR-12)
    @Published var isWikipediaEnabled: Bool {
        didSet { UserDefaults.standard.set(isWikipediaEnabled, forKey: Keys.isWikipediaEnabled) }
    }
    @Published var isOpenStreetMapEnabled: Bool {
        didSet { UserDefaults.standard.set(isOpenStreetMapEnabled, forKey: Keys.isOpenStreetMapEnabled) }
    }
    @Published var isNPSEnabled: Bool {
        didSet { UserDefaults.standard.set(isNPSEnabled, forKey: Keys.isNPSEnabled) }
    }
    @Published var npsApiKey: String {
        didSet { UserDefaults.standard.set(npsApiKey, forKey: Keys.npsApiKey) }
    }

    // MARK: - Distance Filter (LAR-4, LAR-13)
    // Each category has its own distance slider indexed into distanceSteps.
    // The overall maxDistanceKm is the max of all four, used as the API fetch radius.

    /// Discrete km values available on each category distance slider.
    static let distanceSteps: [Double] = [0.1, 0.5, 1, 5, 10, 25, 100]

    /// Maps a slider index (0...6) to a km value.
    static func km(forIndex index: Double) -> Double {
        let i = max(0, min(Int(index.rounded()), distanceSteps.count - 1))
        return distanceSteps[i]
    }

    /// Formatted display string for a slider index.
    static func distanceLabel(forIndex index: Double) -> String {
        let km = Self.km(forIndex: index)
        return km < 1 ? "\(km) km" : "\(Int(km)) km"
    }

    @Published var maxDistanceIndexHistorical: Double {
        didSet { UserDefaults.standard.set(maxDistanceIndexHistorical, forKey: Keys.maxDistanceIndexHistorical) }
    }
    @Published var maxDistanceIndexNatural: Double {
        didSet { UserDefaults.standard.set(maxDistanceIndexNatural, forKey: Keys.maxDistanceIndexNatural) }
    }
    @Published var maxDistanceIndexCultural: Double {
        didSet { UserDefaults.standard.set(maxDistanceIndexCultural, forKey: Keys.maxDistanceIndexCultural) }
    }
    @Published var maxDistanceIndexOther: Double {
        didSet { UserDefaults.standard.set(maxDistanceIndexOther, forKey: Keys.maxDistanceIndexOther) }
    }

    var maxDistanceKmHistorical: Double { AppSettings.km(forIndex: maxDistanceIndexHistorical) }
    var maxDistanceKmNatural:    Double { AppSettings.km(forIndex: maxDistanceIndexNatural) }
    var maxDistanceKmCultural:   Double { AppSettings.km(forIndex: maxDistanceIndexCultural) }
    var maxDistanceKmOther:      Double { AppSettings.km(forIndex: maxDistanceIndexOther) }

    /// Overall fetch radius — the maximum distance among enabled categories only (LAR-24).
    var maxDistanceKm: Double {
        var distances: [Double] = []
        if showHistorical { distances.append(maxDistanceKmHistorical) }
        if showNatural    { distances.append(maxDistanceKmNatural) }
        if showCultural   { distances.append(maxDistanceKmCultural) }
        if showOther      { distances.append(maxDistanceKmOther) }
        return distances.max() ?? 0
    }

    // MARK: - Display Limit (LAR-23)
    /// Maximum number of landmarks shown at once. Options: 5, 10, 25.
    @Published var maxLandmarkCount: Int {
        didSet { UserDefaults.standard.set(maxLandmarkCount, forKey: Keys.maxLandmarkCount) }
    }

    // MARK: - Category Filters (LAR-5)
    @Published var showHistorical: Bool {
        didSet { UserDefaults.standard.set(showHistorical, forKey: Keys.showHistorical) }
    }
    @Published var showNatural: Bool {
        didSet { UserDefaults.standard.set(showNatural, forKey: Keys.showNatural) }
    }
    @Published var showCultural: Bool {
        didSet { UserDefaults.standard.set(showCultural, forKey: Keys.showCultural) }
    }
    @Published var showOther: Bool {
        didSet { UserDefaults.standard.set(showOther, forKey: Keys.showOther) }
    }

    // MARK: - Real-time Updates (LAR-25)
    /// When enabled, landmarks refresh every 30 s or after moving 50 m (instead of 200 m).
    @Published var isRealtimeUpdatesEnabled: Bool {
        didSet { UserDefaults.standard.set(isRealtimeUpdatesEnabled, forKey: Keys.isRealtimeUpdatesEnabled) }
    }

    // MARK: - Init

    init() {
        let ud = UserDefaults.standard
        isWikipediaEnabled        = ud.object(forKey: Keys.isWikipediaEnabled)        as? Bool ?? true
        isOpenStreetMapEnabled    = ud.object(forKey: Keys.isOpenStreetMapEnabled)    as? Bool ?? true
        isNPSEnabled              = ud.object(forKey: Keys.isNPSEnabled)              as? Bool ?? false
        npsApiKey                 = ud.string(forKey: Keys.npsApiKey) ?? "H7f7Y1eEtjYH7it8HOI2YOp6aBicGNA5FWeyDhPN"
        isRealtimeUpdatesEnabled  = ud.object(forKey: Keys.isRealtimeUpdatesEnabled)  as? Bool ?? false
        // Default index 4 = 10 km (matches old default)
        maxDistanceIndexHistorical = ud.object(forKey: Keys.maxDistanceIndexHistorical) as? Double ?? 4
        maxDistanceIndexNatural    = ud.object(forKey: Keys.maxDistanceIndexNatural)    as? Double ?? 4
        maxDistanceIndexCultural   = ud.object(forKey: Keys.maxDistanceIndexCultural)   as? Double ?? 4
        maxDistanceIndexOther      = ud.object(forKey: Keys.maxDistanceIndexOther)      as? Double ?? 4
        maxLandmarkCount       = ud.object(forKey: Keys.maxLandmarkCount)       as? Int    ?? 10
        showHistorical         = ud.object(forKey: Keys.showHistorical)         as? Bool ?? true
        showNatural            = ud.object(forKey: Keys.showNatural)            as? Bool ?? true
        showCultural           = ud.object(forKey: Keys.showCultural)           as? Bool ?? true
        showOther              = ud.object(forKey: Keys.showOther)              as? Bool ?? true
    }

    // MARK: - Private

    private enum Keys {
        static let isWikipediaEnabled          = "isWikipediaEnabled"
        static let isOpenStreetMapEnabled      = "isOpenStreetMapEnabled"
        static let isNPSEnabled                = "isNPSEnabled"
        static let npsApiKey                   = "npsApiKey"
        static let isRealtimeUpdatesEnabled    = "isRealtimeUpdatesEnabled"
        static let maxDistanceIndexHistorical  = "maxDistanceIndexHistorical"
        static let maxDistanceIndexNatural     = "maxDistanceIndexNatural"
        static let maxDistanceIndexCultural    = "maxDistanceIndexCultural"
        static let maxDistanceIndexOther       = "maxDistanceIndexOther"
        static let maxLandmarkCount            = "maxLandmarkCount"
        static let showHistorical              = "showHistorical"
        static let showNatural                 = "showNatural"
        static let showCultural                = "showCultural"
        static let showOther                   = "showOther"
    }
}
