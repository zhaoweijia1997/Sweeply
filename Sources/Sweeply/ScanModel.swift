import AppKit
import Observation

/// Window state: what was found per category, what the user selected, and the last cleanup.
@MainActor @Observable
final class ScanModel {
    enum CheckState {
        case on, off, mixed
    }

    private(set) var results: [String: CategoryResult] = [:]
    private(set) var scanning: Set<String> = []
    private(set) var isCleaning = false
    private(set) var lastCleanup: CleanupSummary?

    /// Selected categories, and items the user unticked inside them.
    private(set) var selected: Set<String> = Set(CleanCategory.all.filter(\.selectedByDefault).map(\.id))
    private(set) var excludedItems: Set<String> = []

    init(results: [String: CategoryResult] = [:], excludedItems: Set<String> = []) {
        self.results = results
        self.excludedItems = excludedItems
    }

    var hasStarted: Bool { !results.isEmpty || !scanning.isEmpty }
    var isScanning: Bool { !scanning.isEmpty }
    var isBusy: Bool { isScanning || isCleaning }
    var foundBytes: Int64 { results.values.reduce(0) { $0 + $1.total } }

    /// What "Move to Trash" would move, in display order.
    var selection: [(category: CleanCategory, item: FoundItem)] {
        CleanCategory.all.flatMap { category in
            itemsToClean(in: category.id).map { (category, $0) }
        }
    }

    var selectedBytes: Int64 { selection.reduce(0) { $0 + $1.item.size } }

    func itemsToClean(in categoryID: String) -> [FoundItem] {
        guard selected.contains(categoryID), let result = results[categoryID] else { return [] }
        return result.items.filter { !excludedItems.contains($0.id) }
    }

    // MARK: Selection

    func state(of categoryID: String) -> CheckState {
        guard let items = results[categoryID]?.items, !items.isEmpty else { return .off }
        let count = itemsToClean(in: categoryID).count
        return count == 0 ? .off : count == items.count ? .on : .mixed
    }

    /// Ticking a category selects all its items again.
    func setSelected(_ categoryID: String, _ on: Bool) {
        if on { selected.insert(categoryID) } else { selected.remove(categoryID) }
        for item in results[categoryID]?.items ?? [] {
            excludedItems.remove(item.id)
        }
    }

    func isIncluded(_ item: FoundItem, in categoryID: String) -> Bool {
        selected.contains(categoryID) && !excludedItems.contains(item.id)
    }

    func setIncluded(_ item: FoundItem, in categoryID: String, _ on: Bool) {
        if on {
            excludedItems.remove(item.id)
            selected.insert(categoryID)
        } else {
            excludedItems.insert(item.id)
        }
    }

    // MARK: Scan

    /// Scans every category in parallel; each row fills in as its category finishes.
    func scan(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        runningApps: Set<String>? = nil,
        leftoverPlaces: LeftoverScanner.Places? = nil
    ) {
        guard !isBusy else { return }
        let runningApps = runningApps ?? Self.runningApps()
        results = [:]
        excludedItems = []
        lastCleanup = nil
        scanning = Set(CleanCategory.all.map(\.id))
        for category in CleanCategory.all {
            Task {
                let result = await Task.detached(priority: .userInitiated) {
                    Scanner.scan(category, home: home, runningApps: runningApps, leftoverPlaces: leftoverPlaces)
                }.value
                // A driver is a guess (same developer as a leftover); the user ticks it if sure.
                excludedItems.formUnion(result.items.filter { $0.leftover?.kind == .audioDriver }.map(\.id))
                results[category.id] = result
                scanning.remove(category.id)
            }
        }
    }

    // MARK: Clean

    /// Moves the selection to the Trash, then drops what moved from the results. Leftovers of
    /// deleted apps are stopped first; those in system folders ask for a password, once.
    func clean(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        runningApps: Set<String>? = nil,
        moveToTrash: @escaping Cleaner.MoveToTrash = Cleaner.systemTrash,
        places: LeftoverScanner.Places? = nil,
        bootout: @escaping LeftoverRemover.Bootout = LeftoverRemover.launchctlBootout,
        runAsAdmin: @escaping LeftoverRemover.RunAsAdmin = LeftoverRemover.administrator
    ) async {
        guard !isBusy, !selection.isEmpty else { return }
        // Checked again now: an app may have started since the scan.
        let runningApps = runningApps ?? Self.runningApps()
        isCleaning = true
        defer { isCleaning = false }

        let selection = self.selection.filter { $0.item.leftover == nil }
        let leftovers = self.selection.map(\.item).filter { $0.leftover != nil }
        var summary = await Task.detached(priority: .userInitiated) {
            Cleaner.clean(selection, home: home, runningApps: runningApps, moveToTrash: moveToTrash)
        }.value
        if !leftovers.isEmpty {
            let removal = LeftoverRemover.remove(
                leftovers, places: places ?? .standard(home: home), bootout: bootout, runAsAdmin: runAsAdmin, moveToTrash: moveToTrash)
            summary.moved += removal.removed
            summary.notMoved += removal.notRemoved
            summary.passwordCancelled = removal.passwordCancelled
        }

        let moved = Set(summary.moved.map(\.id))
        for id in results.keys {
            results[id]?.items.removeAll { moved.contains($0.id) }
        }
        excludedItems.subtract(moved)
        lastCleanup = summary
    }

    /// Only for `--snapshot` renders.
    func showCleanupForSnapshot(_ summary: CleanupSummary) {
        lastCleanup = summary
    }

    static func runningApps() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }
}
