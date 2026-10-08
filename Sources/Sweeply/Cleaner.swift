import Foundation

struct CleanupSummary: Sendable {
    var moved: [FoundItem] = []
    /// Items that were left in place: they failed a safety check or couldn't be moved.
    var notMoved: [FoundItem] = []
    /// The password prompt for leftovers in system folders was cancelled.
    var passwordCancelled = false

    var movedBytes: Int64 { moved.reduce(0) { $0 + $1.size } }
}

/// Moves items to the Trash, never deletes them. Each item is checked again right
/// before it moves, in case something changed since the scan.
enum Cleaner {
    /// Moves one item to the Trash. Tests pass a stand-in so they never touch the real Trash.
    typealias MoveToTrash = @Sendable (URL) throws -> Void

    static let systemTrash: MoveToTrash = { url in
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    static func clean(
        _ selection: [(category: CleanCategory, item: FoundItem)],
        home: URL,
        runningApps: Set<String>,
        moveToTrash: MoveToTrash = systemTrash
    ) -> CleanupSummary {
        var summary = CleanupSummary()
        for (category, item) in selection {
            guard isSafeToMove(item.url, in: category, home: home, runningApps: runningApps) else {
                summary.notMoved.append(item)
                continue
            }
            do {
                try moveToTrash(item.url)
                summary.moved.append(item)
            } catch {
                summary.notMoved.append(item)
            }
        }
        return summary
    }

    /// An item may move only if it is still something this category would find:
    /// directly inside one of the category's folders, on the same disk as the home
    /// folder (never an external drive), and — for app caches — not the system's own
    /// cache or one of a running app.
    static func isSafeToMove(_ url: URL, in category: CleanCategory, home: URL, runningApps: Set<String>) -> Bool {
        let item = url.standardizedFileURL
        let name = item.lastPathComponent
        let parent = item.deletingLastPathComponent().resolvingSymlinksInPath().path

        let allowedFolders: [String]
        switch category.source {
        case let .contents(roots):
            allowedFolders = roots.map { home.appending(path: $0).resolvingSymlinksInPath().path }
        case .appCaches:
            guard !CleanCategory.claimedCacheFolders.contains(name),
                  !name.hasPrefix("com.apple."),
                  !Scanner.belongsToRunningApp(name, runningApps) else { return false }
            allowedFolders = [home.appending(path: "Library/Caches").resolvingSymlinksInPath().path]
        case .simulatorDevices:
            // Only a device folder (never device_set.plist), and never one that's running now.
            guard SimulatorDevice.isDeviceFolder(item), !SimulatorDevice.isRunning(item) else { return false }
            allowedFolders = [home.appending(path: CleanCategory.simulatorDevicesFolder).resolvingSymlinksInPath().path]
        case let .installers(folder, extensions):
            guard extensions.contains(item.pathExtension.lowercased()) else { return false }
            allowedFolders = [home.appending(path: folder).resolvingSymlinksInPath().path]
        case .leftovers:
            // LeftoverRemover checks and removes these.
            return false
        }
        guard allowedFolders.contains(parent) else { return false }

        // Still there (without following a symbolic link), and on the home folder's disk.
        guard (try? item.resourceValues(forKeys: [.isSymbolicLinkKey])) != nil,
              let itemVolume = volume(of: item.deletingLastPathComponent()),
              let homeVolume = volume(of: home),
              itemVolume.isEqual(homeVolume) else { return false }
        return true
    }

    private static func volume(of url: URL) -> NSObject? {
        (try? url.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject
    }
}
