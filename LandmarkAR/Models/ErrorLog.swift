import Foundation

// MARK: - ErrorLogEntry

struct ErrorLogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let message: String
}

// MARK: - ErrorLogger (LAR-16)
// Collects timestamped error messages and makes them available
// for display in the Error Log screen in Settings.

class ErrorLogger: ObservableObject {
    @Published private(set) var entries: [ErrorLogEntry] = []

    func log(_ message: String) {
        entries.append(ErrorLogEntry(date: Date(), message: message))
    }

    func clear() {
        entries.removeAll()
    }
}
