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
            } catch {
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
