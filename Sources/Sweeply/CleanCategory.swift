import Foundation

/// A kind of junk Sweeply knows how to find.
///
/// `title` and `detail` are English localization keys; translations live in
/// `Resources/Localization/<language>.lproj/Localizable.strings`.
struct CleanCategory: Identifiable, Sendable {
    enum Group: String, CaseIterable, Identifiable, Sendable {
        case developer
        case appData

        var id: Self { self }

        var title: String {
            switch self {
            case .developer: "Developer tools"
            case .appData: "App caches & logs"
            }
        }
    }

    enum Source: Sendable {
        /// Every item inside these folders. Paths are relative to the home folder.
        case contents(of: [String])
        /// Everything in ~/Library/Caches, except folders another category claims
        /// and the system's own caches (com.apple.*).
        case appCaches
    }

    let id: String
    let group: Group
    let title: String
    let detail: String
    let selectedByDefault: Bool
    let source: Source
}

extension CleanCategory {
    static let all: [CleanCategory] = [
        CleanCategory(
            id: "xcode.derivedData", group: .developer,
            title: "Xcode build data",
            detail: "Intermediate files from building projects (DerivedData). Xcode recreates them on the next build.",
            selectedByDefault: true,
            source: .contents(of: ["Library/Developer/Xcode/DerivedData"])),
        CleanCategory(
            id: "xcode.caches", group: .developer,
            title: "Xcode caches",
            detail: "Caches Xcode keeps for documentation, previews and other features. Recreated when needed.",
            selectedByDefault: true,
            source: .contents(of: ["Library/Caches/com.apple.dt.Xcode"])),
        CleanCategory(
            id: "xcode.deviceSupport", group: .developer,
            title: "Device support files",
            detail: "Debug symbols copied from iPhones, Apple Watches and other devices you've connected to Xcode. Copied again the next time you connect that device.",
            selectedByDefault: false,
            source: .contents(of: [
                "Library/Developer/Xcode/iOS DeviceSupport",
                "Library/Developer/Xcode/watchOS DeviceSupport",
                "Library/Developer/Xcode/tvOS DeviceSupport",
                "Library/Developer/Xcode/visionOS DeviceSupport",
            ])),
        CleanCategory(
            id: "xcode.archives", group: .developer,
            title: "Xcode archives",
            detail: "Builds you archived for distribution, including the symbols needed to read their crash reports. Only remove the ones you no longer need.",
            selectedByDefault: false,
            source: .contents(of: ["Library/Developer/Xcode/Archives"])),
        CleanCategory(
            id: "simulator.caches", group: .developer,
            title: "Simulator caches",
            detail: "Caches used by the iOS Simulator. Recreated when needed.",
            selectedByDefault: true,
            source: .contents(of: ["Library/Developer/CoreSimulator/Caches"])),
        CleanCategory(
            id: "gradle", group: .developer,
            title: "Gradle caches",
            detail: "Dependencies and build caches downloaded by Gradle (Android Studio). Downloaded again when needed. Quit Android Studio before cleaning.",
            selectedByDefault: true,
            source: .contents(of: [".gradle/caches"])),
        CleanCategory(
            id: "homebrew", group: .developer,
            title: "Homebrew downloads",
            detail: "Installer files Homebrew downloaded. Your installed packages are not affected.",
            selectedByDefault: true,
            source: .contents(of: ["Library/Caches/Homebrew"])),
        CleanCategory(
            id: "packageCaches", group: .developer,
            title: "Package manager caches",
            detail: "Download caches of pip, npm, Yarn, CocoaPods and Swift Package Manager. Downloaded again when needed.",
            selectedByDefault: true,
            source: .contents(of: [
                "Library/Caches/pip",
                ".npm/_cacache",
                "Library/Caches/Yarn",
                "Library/Caches/CocoaPods",
                "Library/Caches/org.swift.swiftpm",
            ])),
        CleanCategory(
            id: "app.caches", group: .appData,
            title: "App caches",
            detail: "Temporary files apps keep to load faster. Apps recreate them as needed. Caches of apps that are running are skipped.",
            selectedByDefault: true,
            source: .appCaches),
        CleanCategory(
            id: "app.logs", group: .appData,
            title: "Logs",
            detail: "Log files written by apps. Only useful for troubleshooting.",
            selectedByDefault: true,
            source: .contents(of: ["Library/Logs"])),
    ]

    /// Folders inside ~/Library/Caches that a more specific category owns,
    /// so "App caches" doesn't count them twice.
    static let claimedCacheFolders: Set<String> = {
        let prefix = "Library/Caches/"
        var claimed = Set<String>()
        for category in all {
            guard case let .contents(roots) = category.source else { continue }
            for root in roots where root.hasPrefix(prefix) {
                claimed.insert(String(root.dropFirst(prefix.count).split(separator: "/")[0]))
            }
        }
        return claimed
    }()

    /// The top-level files and folders this category would move to the Trash.
    func candidates(home: URL) -> [URL] {
        switch source {
        case let .contents(roots):
            return roots.flatMap { Self.children(of: home.appending(path: $0)) }
        case .appCaches:
            return Self.children(of: home.appending(path: "Library/Caches")).filter {
                let name = $0.lastPathComponent
                return !Self.claimedCacheFolders.contains(name) && !name.hasPrefix("com.apple.")
            }
        }
    }

    private static let ignoredNames: Set<String> = [".DS_Store", ".localized"]

    private static func children(of folder: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return items.filter { !ignoredNames.contains($0.lastPathComponent) }
    }
}
