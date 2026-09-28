import Foundation

/// A file or folder Sweeply found and could move to the Trash.
struct FoundItem: Identifiable, Hashable, Sendable {
    let url: URL
    /// Space it takes on disk, in bytes.
    let size: Int64

    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

struct CategoryResult: Sendable {
    /// Largest first.
    var items: [FoundItem] = []
    /// Cache folders left alone because their app is running.
    var skippedRunning: [String] = []

    var total: Int64 { items.reduce(0) { $0 + $1.size } }
}

/// Finds junk and measures it. Read-only: nothing here deletes or moves anything.
enum Scanner {
    static func scan(_ category: CleanCategory, home: URL, runningApps: Set<String>) -> CategoryResult {
        var result = CategoryResult()
        for url in category.candidates(home: home) {
            if case .appCaches = category.source, belongsToRunningApp(url.lastPathComponent, runningApps) {
                result.skippedRunning.append(url.lastPathComponent)
                continue
            }
            let size = allocatedSize(of: url)
            if size > 0 {
                result.items.append(FoundItem(url: url, size: size))
            }
        }
        result.items.sort { $0.size > $1.size }
        return result
    }

    /// Cache folders are usually named after the app's bundle identifier,
    /// sometimes with a suffix (com.example.App.helper).
    static func belongsToRunningApp(_ folderName: String, _ runningApps: Set<String>) -> Bool {
        runningApps.contains { folderName == $0 || folderName.hasPrefix($0 + ".") }
    }

    /// Space on disk, not the logical file size. Symbolic links are not followed.
    /// Files shared through hard links or APFS clones are counted in full, so this
    /// can overstate what cleaning frees up.
    static func allocatedSize(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        func size(_ values: URLResourceValues) -> Int64 {
            Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }

        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        guard values.isDirectory == true, values.isSymbolicLink != true else { return size(values) }

        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true })
        while let file = enumerator?.nextObject() as? URL {
            guard let values = try? file.resourceValues(forKeys: keys), values.isDirectory != true else { continue }
            total += size(values)
        }
        return total
    }
}
