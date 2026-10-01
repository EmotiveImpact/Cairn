import Foundation

/// A suggestion is an observation to inspect, never permission to remove data.
/// Only the known, user-selected roots can produce one. Comparison itself
/// rejects incomplete readings, scope changes and replacement volumes.
struct GrowthSuggestion: Identifiable {
    let change: LocationChange
    var id: String { change.id }
}

enum GrowthSuggestions {
    static let selectableIDs = ["xcode-build", "npm-cache", "chrome-cache", "safari-cache", "downloads"]
    static let defaultIDs = ["xcode-build", "npm-cache", "chrome-cache", "safari-cache"]

    static func evaluate(_ changes: [LocationChange], selectedIDs: [String], minimumBytes: Int64,
                         now: Date = Date()) -> [GrowthSuggestion] {
        let selected = Set(selectedIDs).intersection(selectableIDs)
        guard minimumBytes > 0, !selected.isEmpty else { return [] }
        return changes.filter { change in
            selected.contains(change.id) && change.delta >= minimumBytes &&
            change.after.ended <= now && now.timeIntervalSince(change.after.ended) <= 7 * 86_400
        }.sorted { $0.delta > $1.delta }.prefix(3).map { GrowthSuggestion(change: $0) }
    }
}
