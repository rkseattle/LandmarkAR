import Foundation

// MARK: - LabelDisplaySize (LAR-29)

enum LabelDisplaySize: String, CaseIterable {
    case small  = "small"
    case medium = "medium"
    case large  = "large"
}

// MARK: - RealtimeUpdateMode (LAR-28)

enum RealtimeUpdateMode: String, CaseIterable {
    case off      = "off"
    case wifiOnly = "wifiOnly"
    case always   = "always"
}

// MARK: - AppSettings
// Persists user preferences via UserDefaults.
// Shared across the app via @StateObject / @EnvironmentObject.

class AppSettings: ObservableObject {

    // MARK: - Data Sources (LAR-3, LAR-11, LAR-12)
    @Published var isWikipediaEnabled: Bool {
        didSet { deferredWrite(key: Keys.isWikipediaEnabled, value: isWikipediaEnabled) }
    }
    @Published var isOpenStreetMapEnabled: Bool {
        didSet { deferredWrite(key: Keys.isOpenStreetMapEnabled, value: isOpenStreetMapEnabled) }
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
        didSet { deferredWrite(key: Keys.maxDistanceIndexHistorical, value: maxDistanceIndexHistorical) }
    }
    @Published var maxDistanceIndexNatural: Double {
        didSet { deferredWrite(key: Keys.maxDistanceIndexNatural, value: maxDistanceIndexNatural) }
    }
    @Published var maxDistanceIndexCultural: Double {
        didSet { deferredWrite(key: Keys.maxDistanceIndexCultural, value: maxDistanceIndexCultural) }
    }
    @Published var maxDistanceIndexOther: Double {
        didSet { deferredWrite(key: Keys.maxDistanceIndexOther, value: maxDistanceIndexOther) }
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
        didSet { deferredWrite(key: Keys.maxLandmarkCount, value: maxLandmarkCount) }
    }

    // MARK: - Category Filters (LAR-5)
    @Published var showHistorical: Bool {
        didSet { deferredWrite(key: Keys.showHistorical, value: showHistorical) }
    }
    @Published var showNatural: Bool {
        didSet { deferredWrite(key: Keys.showNatural, value: showNatural) }
    }
    @Published var showCultural: Bool {
        didSet { deferredWrite(key: Keys.showCultural, value: showCultural) }
    }
    @Published var showOther: Bool {
        didSet { deferredWrite(key: Keys.showOther, value: showOther) }
    }

    // MARK: - Label Display Size (LAR-29)
    @Published var labelDisplaySize: LabelDisplaySize {
        didSet { deferredWrite(key: Keys.labelDisplaySize, value: labelDisplaySize.rawValue) }
    }

    // MARK: - Language (LAR-35)
    // Stored as the BCP 47 locale code. Defaults to the device system language if supported,
    // otherwise falls back to English.
    @Published var appLanguage: AppLanguage {
        didSet { deferredWrite(key: Keys.appLanguage, value: appLanguage.rawValue) }
    }

    /// The Bundle for the current language's .lproj directory.
    /// Views pass this to Text(_, bundle:) so language changes take effect immediately.
    var localizedBundle: Bundle {
        guard let path = Bundle.main.path(forResource: appLanguage.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }

    // MARK: - Real-time Updates (LAR-25, LAR-28)
    /// Controls automatic landmark refresh: off, wi-fi only, or always.
    @Published var realtimeUpdateMode: RealtimeUpdateMode {
        didSet { deferredWrite(key: Keys.realtimeUpdateMode, value: realtimeUpdateMode.rawValue) }
    }

    // MARK: - Deferred Persistence

    // Debounces UserDefaults writes so rapid slider drags don't cause dozens of
    // synchronous disk writes on the main thread. Each key gets its own pending
    // work item so independent settings don't cancel each other's saves.
    private var pendingWrites: [String: DispatchWorkItem] = [:]

    private func deferredWrite(key: String, value: Any) {
        pendingWrites[key]?.cancel()
        let item = DispatchWorkItem { UserDefaults.standard.set(value, forKey: key) }
        pendingWrites[key] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    // MARK: - Init

    init() {
        let ud = UserDefaults.standard
        isWikipediaEnabled     = ud.object(forKey: Keys.isWikipediaEnabled)     as? Bool ?? true
        isOpenStreetMapEnabled = ud.object(forKey: Keys.isOpenStreetMapEnabled) as? Bool ?? true
        let savedMode = ud.string(forKey: Keys.realtimeUpdateMode).flatMap(RealtimeUpdateMode.init(rawValue:))
        realtimeUpdateMode = savedMode ?? .off
        let savedSize = ud.string(forKey: Keys.labelDisplaySize).flatMap(LabelDisplaySize.init(rawValue:))
        labelDisplaySize = savedSize ?? .medium
        let savedLang = ud.string(forKey: Keys.appLanguage).flatMap(AppLanguage.init(rawValue:))
        appLanguage = savedLang ?? AppLanguage.systemDefault()
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
        static let realtimeUpdateMode          = "realtimeUpdateMode"
        static let labelDisplaySize            = "labelDisplaySize"
        static let maxDistanceIndexHistorical  = "maxDistanceIndexHistorical"
        static let maxDistanceIndexNatural     = "maxDistanceIndexNatural"
        static let maxDistanceIndexCultural    = "maxDistanceIndexCultural"
        static let maxDistanceIndexOther       = "maxDistanceIndexOther"
        static let maxLandmarkCount            = "maxLandmarkCount"
        static let showHistorical              = "showHistorical"
        static let showNatural                 = "showNatural"
        static let showCultural                = "showCultural"
        static let showOther                   = "showOther"
        static let appLanguage                 = "appLanguage"
    }
}
