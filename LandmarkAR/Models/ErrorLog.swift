import Foundation

// MARK: - ErrorLogEntry

struct ErrorLogEntry: Identifiable, Codable {
    let id: UUID
    let date: Date
    let message: String

    init(message: String) {
        self.id = UUID()
        self.date = Date()
        self.message = message
    }
}

// MARK: - ErrorLogger (LAR-16, LAR-32)
// Collects timestamped error messages and makes them available
// for display in the Error Log screen in Settings.
// Entries are persisted across app sessions via UserDefaults (LAR-32).

class ErrorLogger: ObservableObject {
    @Published private(set) var entries: [ErrorLogEntry] = []

    private static let storageKey = "errorLogEntries"
    private static let maxEntries = 200

    init() {
        load()
    }

    func log(_ message: String) {
        entries.append(ErrorLogEntry(message: message))
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    // MARK: - Private

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([ErrorLogEntry].self, from: data)
        else { return }
        entries = decoded
    }
}
