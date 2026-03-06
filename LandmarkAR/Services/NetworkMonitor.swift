import Network
import Foundation

// MARK: - NetworkMonitor (LAR-28)
// Observes the active network path and publishes whether the device is on Wi-Fi.

class NetworkMonitor: ObservableObject {
    @Published private(set) var isOnWifi: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.landmarkar.NetworkMonitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOnWifi = path.usesInterfaceType(.wifi)
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
