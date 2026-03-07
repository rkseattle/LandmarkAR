import SwiftUI

// MARK: - ErrorLogView (LAR-16)
// Secondary settings screen that shows all logged errors with timestamps.

struct ErrorLogView: View {
    @ObservedObject var logger: ErrorLogger
    @Environment(\.localeBundle) private var bundle

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        List {
            if logger.entries.isEmpty {
                Text("errorLog.noErrors", bundle: bundle)
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
        .navigationTitle(Text("errorLog.title", bundle: bundle))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !logger.entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        logger.clear()
                    } label: {
                        Text("errorLog.clear", bundle: bundle)
                    }
                }
            }
        }
    }
}
