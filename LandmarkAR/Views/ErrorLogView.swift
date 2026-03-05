import SwiftUI

// MARK: - ErrorLogView (LAR-16)
// Secondary settings screen that shows all logged errors with timestamps.

struct ErrorLogView: View {
    @ObservedObject var logger: ErrorLogger

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        List {
            if logger.entries.isEmpty {
                Text("No errors logged.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(logger.entries.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Self.dateFormatter.string(from: entry.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(entry.message)
                            .font(.body)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Error Log")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !logger.entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear", role: .destructive) {
                        logger.clear()
                    }
                }
            }
        }
    }
}
