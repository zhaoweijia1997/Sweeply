import AppKit
import ServiceManagement

/// User settings stored in UserDefaults.
enum AppSettings {
    /// Keep running with a menu bar icon after the window is closed. Off by default.
    static let backgroundModeKey = "backgroundMode"
    static let menuBarShowsKey = "menuBarShows"

    static var backgroundMode: Bool { UserDefaults.standard.bool(forKey: backgroundModeKey) }

    static var menuBarShows: MenuBarShows {
        UserDefaults.standard.string(forKey: menuBarShowsKey).flatMap(MenuBarShows.init) ?? .icon
    }
}

/// What the menu bar icon shows next to the little broom.
enum MenuBarShows: String, CaseIterable, Identifiable {
    case icon, temperature, usage
    var id: Self { self }
}

/// "Open at login". Uses the system's login items first; builds the system won't register
/// (for example ones not signed with a Developer ID) fall back to a per-user launch agent,
/// which the system also lists under System Settings → General → Login Items.
enum LoginItem {
    enum State: Equatable {
        case off, on, needsApproval
    }

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        default: return FileManager.default.fileExists(atPath: agentURL.path) ? .on : .off
        }
    }

    static func set(_ enabled: Bool, agentURL: URL = agentURL, appPath: String = Bundle.main.bundlePath) throws {
        if enabled {
            do {
                try SMAppService.mainApp.register()
                removeAgent(agentURL)
            } catch {
                // Already registered: nothing more to do. A launch agent as well would start
                // a second Sweeply at login.
                if [.enabled, .requiresApproval].contains(SMAppService.mainApp.status) {
                    removeAgent(agentURL)
                    return
                }
                try FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try PropertyListSerialization.data(fromPropertyList: agentPlist(appPath: appPath), format: .xml, options: 0)
                    .write(to: agentURL, options: .atomic)
            }
        } else {
            if [.enabled, .requiresApproval].contains(SMAppService.mainApp.status) {
                try? SMAppService.mainApp.unregister()
            }
            if FileManager.default.fileExists(atPath: agentURL.path) {
                try FileManager.default.removeItem(at: agentURL)
            }
        }
    }

    /// One way of starting at login only: once the system's login item is on, a launch agent
    /// left from an earlier fallback is removed (with both, two copies started at login).
    static func tidyUp() {
        if SMAppService.mainApp.status == .enabled { removeAgent(agentURL) }
    }

    private static func removeAgent(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.removeItem(at: url) }
    }

    static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/LaunchAgents/\(Bundle.main.bundleIdentifier ?? "com.weijiazhao.sweeply").login.plist")
    }

    /// Opens Sweeply in the background (-g) at login, telling it so with --login.
    static func agentPlist(appPath: String) -> [String: Any] {
        [
            "Label": "\(Bundle.main.bundleIdentifier ?? "com.weijiazhao.sweeply").login",
            "ProgramArguments": ["/usr/bin/open", "-g", "-a", appPath, "--args", "--login"],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
        ]
    }

    /// True when Sweeply was started at login rather than opened by the user.
    static var launchedAtLogin: Bool {
        if CommandLine.arguments.contains("--login") { return true }
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}

/// The app's models, shared by the window, the menu bar panel and the app delegate,
/// so recording keeps going with the window closed.
@MainActor
final class AppModels {
    static let shared = AppModels()

    let scan = ScanModel()
    let system = SystemModel()
    let disk = DiskHealthModel()
    let devices = PeripheralsModel()
    let menuBar = MenuBarModel()
    let brightness = BrightnessModel()
    let volume = VolumeModel()
}

/// Shows or hides the Dock icon: in background mode Sweeply lives in the menu bar
/// while its window is closed.
@MainActor
enum DockIcon {
    static func windowOpened() {
        NSApp.setActivationPolicy(.regular)
    }

    static func windowClosed() {
        if AppSettings.backgroundMode { NSApp.setActivationPolicy(.accessory) }
    }
}

/// One Sweeply at a time. macOS starts a login item by its identifier and may pick any copy,
/// a build folder's included, and opening a second copy by hand starts a second process; each
/// would add its own menu bar icon.
enum SingleInstance {
    /// True when this process quits in favor of another copy.
    @MainActor
    static func handOver() -> Bool {
        guard let identifier = Bundle.main.bundleIdentifier else { return false }
        let me = NSRunningApplication.current
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).filter { $0 != me }
        if !others.isEmpty {
            // The installed copy wins over stray ones from elsewhere.
            if isInstalled(Bundle.main.bundleURL), !others.contains(where: { $0.bundleURL.map(isInstalled) ?? false }) {
                others.forEach { $0.terminate() }
                return false
            }
            // Opened by hand: show the window of the one already running.
            if !LoginItem.launchedAtLogin, let other = others.first { reopen(other) }
            quitSoon()
            return true
        }
        // Started at login from a copy outside Applications: start the installed copy instead.
        if LoginItem.launchedAtLogin, !isInstalled(Bundle.main.bundleURL), let installed = installedCopy(identifier) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = ["--login"]
            configuration.activates = false
            // Otherwise Launch Services finds this process (same identifier) and starts nothing.
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: installed, configuration: configuration) { _, _ in quitSoon() }
            return true
        }
        return false
    }

    static func isInstalled(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix("/Applications/") || path.hasPrefix(home + "/Applications/")
    }

    private static func installedCopy(_ identifier: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let name = Bundle.main.bundleURL.lastPathComponent
        return ["/Applications", home + "/Applications"]
            .map { URL(fileURLWithPath: $0).appending(path: name) }
            .first { Bundle(url: $0)?.bundleIdentifier == identifier }
    }

    /// What opening it from the Finder does: Launch Services finds the copy running at that
    /// path and shows its window (a reopen event alone doesn't bring a menu bar app forward).
    private static func reopen(_ app: NSRunningApplication) {
        guard let url = app.bundleURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func quitSoon() {
        DispatchQueue.main.async { exit(0) }
    }
}
