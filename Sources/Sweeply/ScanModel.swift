import AppKit
import Observation

/// Scan state for the window: what was found per category and what the user selected.
@MainActor @Observable
final class ScanModel {
    private(set) var results: [String: CategoryResult] = [:]
    private(set) var scanning: Set<String> = []
    var selected: Set<String> = Set(CleanCategory.all.filter(\.selectedByDefault).map(\.id))

    init(results: [String: CategoryResult] = [:]) {
        self.results = results
    }

    var hasStarted: Bool { !results.isEmpty || !scanning.isEmpty }
    var isScanning: Bool { !scanning.isEmpty }
    var foundBytes: Int64 { results.values.reduce(0) { $0 + $1.total } }
    var selectedBytes: Int64 { selected.compactMap { results[$0]?.total }.reduce(0, +) }

    /// Scans every category in parallel; each row fills in as its category finishes.
    func scan(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        runningApps: Set<String> = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    ) {
        guard !isScanning else { return }
        results = [:]
        scanning = Set(CleanCategory.all.map(\.id))
        for category in CleanCategory.all {
            Task {
                let result = await Task.detached(priority: .userInitiated) {
                    Scanner.scan(category, home: home, runningApps: runningApps)
                }.value
                results[category.id] = result
                scanning.remove(category.id)
            }
        }
    }

    func isSelected(_ id: String) -> Bool { selected.contains(id) }

    func setSelected(_ id: String, _ on: Bool) {
        if on { selected.insert(id) } else { selected.remove(id) }
    }
}
