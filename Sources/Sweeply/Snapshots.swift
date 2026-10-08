import AppKit
import SwiftUI

/// Renders the main window in every language to PNG files, to check layouts
/// without clicking through the app, and for README screenshots:
///
///     build.noindex/Sweeply.app/Contents/MacOS/Sweeply --snapshot <folder>
///
/// Uses made-up scan results; nothing on this Mac is scanned.
@MainActor
enum Snapshots {
    static let size = NSSize(width: 780, height: 680)

    static func render(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        renderMenuBarIcon(to: folder)
        for language in AppLanguage.allCases where language != .system {
            let pages: [(String, ScanModel, ContentView.Tab)] = [
                ("main", .sample, .clean), ("cleaned", .sampleAfterCleanup, .clean), ("system", .sample, .system),
                ("disk", .sample, .disk), ("devices", .sample, .devices), ("items", .sample, .clean),
                ("disk-full", .sample, .disk),
            ]
            for (name, model, tab) in pages {
            // The expanded list and the whole Disk Health tab are long; render them tall enough.
            let height: CGFloat = name == "items" ? 2600 : name == "disk-full" ? 1240 : size.height
            for dark in [false, true] {
                let view = ContentView(
                    model: model, system: .sample, disk: DiskHealthModel(state: .loaded(.sample), history: .sample, space: .sample, live: false),
                    devices: PeripheralsModel(peripherals: .sample, live: false), brightness: .sample, volume: .sample, tab: tab)
                    .environment(\.expandAllItems, name == "items")
                    .environment(\.locale, language.locale)
                    .frame(width: size.width, height: height)
                    // A borderless off-screen window doesn't paint its background.
                    .background(Color(nsColor: .windowBackgroundColor))
                let file = "\(name)-\(language.rawValue)-\(dark ? "dark" : "light").png"
                if let png = draw(view, dark: dark, height: height) {
                    try? png.write(to: folder.appending(path: file))
                }
            }
            }

            // Settings and the menu bar panel, sized to fit. The settings shown come from the
            // argument domain: in memory for this run only, so real preferences aren't touched.
            var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            arguments[AppSettings.backgroundModeKey] = true
            arguments[AppSettings.menuBarShowsKey] = MenuBarShows.temperature.rawValue
            UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
            for dark in [false, true] {
                let suffix = "\(language.rawValue)-\(dark ? "dark" : "light").png"
                let settings = SettingsView()
                    .environment(\.locale, language.locale)
                    .background(Color(nsColor: .windowBackgroundColor))
                if let png = draw(settings, dark: dark, height: nil) {
                    try? png.write(to: folder.appending(path: "settings-" + suffix))
                }
                let panel = MenuBarPanel(
                    system: .sample, disk: DiskHealthModel(state: .loaded(.sample), history: .sample, space: .sample, live: false),
                    brightness: .sample, volume: .sample)
                    .environment(\.locale, language.locale)
                    .background(Color(nsColor: .windowBackgroundColor))
                if let png = draw(panel, dark: dark, height: nil) {
                    try? png.write(to: folder.appending(path: "menubar-" + suffix))
                }
            }
        }
    }

    /// Draws the view in an off-screen window, so AppKit-backed controls
    /// (buttons, menus, scroll views) render too. Needs no screen-recording permission.
    /// The menu bar icon, enlarged, on light and dark bars (for checking the drawing).
    static func renderMenuBarIcon(to folder: URL) {
        let icon = HStack(spacing: 24) {
            ForEach([false, true], id: \.self) { dark in
                Image(nsImage: MenuBarIcon.image)
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: 72, height: 72)
                    .foregroundStyle(dark ? .white : .black)
                    .padding(12)
                    .background(dark ? Color.black : Color(white: 0.92))
            }
        }
        if let png = draw(icon, dark: false, height: nil) {
            try? png.write(to: folder.appending(path: "menubar-icon.png"))
        }
    }

    /// With `height` nil, the view is drawn at its natural size.
    private static func draw(_ view: some View, dark: Bool, height: CGFloat?) -> Data? {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: height.map { NSSize(width: size.width, height: $0) } ?? hosting.fittingSize)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        // Let SwiftUI finish a layout pass before drawing.
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
    }
}

extension BrightnessModel {
    /// Made-up display brightness for screenshots (id 1 matches Peripherals.sample's display).
    static var sample: BrightnessModel {
        BrightnessModel(displays: [Display(id: 1, name: "External Display", value: 0.72, supported: true, volume: 0.31)], live: false)
    }
}

extension VolumeModel {
    /// A made-up sound output for screenshots.
    static var sample: VolumeModel {
        VolumeModel(output: Output(name: "Speakers", volume: 0.45, muted: false, canSetVolume: true, canMute: true), live: false)
    }
}

extension DiskWriteHistory {
    /// Made-up month of writes for screenshots.
    static var sample: DiskWriteHistory {
        var history = DiskWriteHistory()
        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-29 * 86_400 + 12 * 3600)
        var total = 10_000_000_000_000.0
        for day in 0..<30 {
            history.record(total, at: start.addingTimeInterval(Double(day) * 86_400))
            total += (18 + Double((day * 37) % 29)) * 1_000_000_000
        }
        return history
    }
}

extension Peripherals {
    /// Made-up devices for screenshots.
    static let sample = Peripherals(
        displays: [Display(id: 1, name: "External Display", pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60, isBuiltIn: false)],
        drives: [
            Drive(path: "/Volumes/Backup", name: "Backup", capacity: 2_000_000_000_000, available: 1_240_000_000_000,
                  format: "APFS", connection: .usb),
            Drive(path: "/Volumes/Photos", name: "Photos", capacity: 1_000_000_000_000, available: 310_000_000_000,
                  format: "APFS", connection: .thunderbolt),
        ],
        usb: [
            USBDevice(id: 1, name: "Wireless Receiver", vendor: "Example", speed: 1),
            USBDevice(id: 2, name: "Portable SSD", vendor: "Example", speed: 4),
        ],
        thunderbolt: [ThunderboltDevice(id: 3, name: "Thunderbolt Dock", vendor: "Example")])
}

extension SystemModel {
    /// Made-up readings for screenshots (no real machine's details).
    static var sample: SystemModel {
        let model = SystemModel(machine: SystemStats.Machine(
            chip: "Apple M-series", performanceCores: 8, efficiencyCores: 4, logicalCores: 12,
            bootDate: Date().addingTimeInterval(-(5 * 86400 + 3 * 3600))), live: false)
        let gib: UInt64 = 1 << 30
        model.showForSnapshot(
            coreUsage: [0.12, 0.18, 0.09, 0.22, 0.64, 0.41, 0.35, 0.92, 0.28, 0.15, 0.51, 0.33],
            memory: SystemStats.Memory(
                total: 32 * gib, app: 11 * gib, wired: 3 * gib, compressed: 2 * gib,
                cachedFiles: 9 * gib, swapUsed: 0, pressure: .normal),
            storage: SystemStats.Storage(total: 494_000_000_000, available: 191_000_000_000),
            sensors: SensorReadings(
                cpuHottest: 48.5, cpuAverage: 44.2, ssd: 35,
                fans: [SensorReadings.Fan(rpm: 1350, minimum: 1000, maximum: 3500)]))
        return model
    }
}

extension DiskHealth {
    /// Made-up readings for screenshots.
    static let sample = DiskHealth(
        model: "APPLE SSD", capacity: 512_000_000_000, bytesWritten: 10_960_000_000_000, bytesRead: 25_150_000_000_000,
        percentageUsed: 2, availableSpare: 100, spareThreshold: 99, temperature: 32, powerOnHours: 3510,
        powerCycles: 254, unsafeShutdowns: 18, mediaErrors: 0, criticalWarning: 0)
}

extension ScanModel {
    /// Made-up results right after a cleanup, with one item that couldn't move.
    static var sampleAfterCleanup: ScanModel {
        let model = sample
        let summary = CleanupSummary(
            moved: [
                FoundItem(url: URL(fileURLWithPath: "/Users/you/Library/Logs/old"), size: 8_860_000_000),
                FoundItem(url: URL(fileURLWithPath: "/Library/LaunchDaemons/com.example.remote.service.plist"), size: 4_096,
                          leftover: Leftover(kind: .backgroundService, identifier: "com.example.remote.service", appName: "Example Remote", needsPassword: true)),
            ],
            notMoved: [FoundItem(url: URL(fileURLWithPath: "/Users/you/Library/Caches/com.example.locked"), size: 1)])
        model.showCleanupForSnapshot(summary)
        return model
    }

    /// Made-up results for screenshots.
    static var sample: ScanModel {
        let gb: Int64 = 1_000_000_000
        let mb: Int64 = 1_000_000
        func found(_ folder: String, _ items: [(String, Int64)]) -> CategoryResult {
            CategoryResult(items: items.map { FoundItem(url: URL(fileURLWithPath: "/Users/you/\(folder)/\($0.0)"), size: $0.1) })
        }
        var appCaches = found("Library/Caches", [
            ("com.example.editor", 1_400 * mb), ("com.example.music", 820 * mb), ("com.example.chat", 360 * mb),
        ])
        appCaches.skippedRunning = ["com.example.browser"]
        return ScanModel(results: [
            "xcode.derivedData": found("Library/Developer/Xcode/DerivedData", [("MyApp-abcdefgh", 3 * gb), ("Demo-ijklmnop", 1_200 * mb)]),
            "xcode.caches": found("Library/Caches/com.apple.dt.Xcode", [("DocumentationCache", 420 * mb)]),
            "xcode.deviceSupport": found("Library/Developer/Xcode/iOS DeviceSupport", [("iPhone15,2 17.5 (21F79)", 4 * gb), ("iPhone15,2 18.0 (22A3354)", 3 * gb)]),
            "xcode.archives": found("Library/Developer/Xcode/Archives", [("2026-05-01", 225 * mb)]),
            "simulator.caches": CategoryResult(),
            "gradle": found(".gradle/caches", [("modules-2", 900 * mb), ("transforms-4", 300 * mb)]),
            "homebrew": found("Library/Caches/Homebrew", [("downloads", 190 * mb)]),
            "packageCaches": found("Library/Caches", [("pip", 180 * mb), ("CocoaPods", 64 * mb)]),
            "app.caches": appCaches,
            "app.logs": found("Library/Logs", [("DiagnosticReports", 30 * mb)]),
            "xcode.simulators": CategoryResult(items: [
                FoundItem(url: URL(fileURLWithPath: "/Users/you/Library/Developer/CoreSimulator/Devices/A"), size: 4_600 * mb, label: "iPhone 17 Pro · iOS 26.2"),
                FoundItem(url: URL(fileURLWithPath: "/Users/you/Library/Developer/CoreSimulator/Devices/B"), size: 13 * mb, label: "iPad mini · iOS 16.1"),
            ], skippedRunning: ["iPhone 16e · iOS 26.4"]),
            "downloads.installers": CategoryResult(items: [
                FoundItem(url: URL(fileURLWithPath: "/Users/you/Downloads/SomeApp-2.1.dmg"), size: 310 * mb, date: Date().addingTimeInterval(-40 * 86_400)),
                FoundItem(url: URL(fileURLWithPath: "/Users/you/Downloads/Driver.pkg"), size: 45 * mb, date: Date().addingTimeInterval(-3 * 86_400)),
            ]),
            "leftovers": sampleLeftovers,
        ], excludedItems: Set(sampleLeftovers.items.filter { $0.leftover?.kind == .audioDriver }.map(\.id)))
    }

    /// Made-up apps: a remote desktop tool's service that macOS keeps restarting, a VPN's
    /// login item, a sync app's own login item and the remote tool's audio driver.
    static var sampleLeftovers: CategoryResult {
        CategoryResult(items: [
            FoundItem(url: URL(fileURLWithPath: "/Library/LaunchDaemons/com.example.remote.service.plist"), size: 4_096,
                      leftover: Leftover(kind: .backgroundService, identifier: "com.example.remote.service", appName: "Example Remote",
                                         missingProgram: "/Applications/Example Remote.app/Contents/MacOS/service", runs: 86_412, needsPassword: true)),
            FoundItem(url: URL(fileURLWithPath: "/Library/LaunchAgents/com.example.vpn.agent.plist"), size: 4_096,
                      leftover: Leftover(kind: .loginItemForAllUsers, identifier: "com.example.vpn.agent", appName: "Old VPN",
                                         missingProgram: "/Applications/Old VPN.app/Contents/MacOS/agent", runs: 1, needsPassword: true)),
            FoundItem(url: URL(fileURLWithPath: "/Users/you/Library/LaunchAgents/com.example.photosync.plist"), size: 4_096,
                      leftover: Leftover(kind: .loginItem, identifier: "com.example.photosync", appName: "Photo Sync",
                                         missingProgram: "/Applications/Photo Sync.app/Contents/MacOS/Photo Sync", needsPassword: false)),
            FoundItem(url: URL(fileURLWithPath: "/Library/Audio/Plug-Ins/HAL/ExampleRemoteSound.driver"), size: 1_200_000, label: "ExampleRemoteSound",
                      leftover: Leftover(kind: .audioDriver, identifier: "com.example.ExampleRemoteSound", appName: "Example Remote", needsPassword: true)),
        ])
    }
}

extension DiskSpaceHistory {
    /// Made-up month on a 1 TB disk: slowly filling up, with one cleanup along the way.
    static var sample: DiskSpaceHistory {
        var history = DiskSpaceHistory()
        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-29 * 86_400 + 20 * 3600)
        var used: Int64 = 236_000_000_000
        for day in 0..<30 {
            used += Int64(900_000_000 + ((day * 37) % 11 - 5) * 200_000_000)
            if day == 19 { used -= 12_000_000_000 }
            history.record(used: used, total: 1_000_000_000_000, at: start.addingTimeInterval(Double(day) * 86_400))
        }
        return history
    }
}
