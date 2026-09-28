import AppKit
import ServiceManagement
import SwiftUI

@main
struct SweeplyApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @AppStorage(AppSettings.backgroundModeKey) private var backgroundMode = false
    private let models = AppModels.shared
    /// --snapshot, --report and --disk-health runs mustn't create a menu bar item: it would
    /// write its state back into the user's real preferences.
    private let commandLineRun = ["--snapshot", "--report", "--disk-health"].contains { CommandLine.arguments.contains($0) }

    var body: some Scene {
        Window("Sweeply", id: "main") {
            ContentView(model: models.scan, system: models.system, disk: models.disk, devices: models.devices,
                        brightness: models.brightness)
                .environment(\.locale, language.locale)
                .frame(minWidth: 680, minHeight: 540)
                .onAppear { DockIcon.windowOpened() }
                .onDisappear { DockIcon.windowClosed() }
        }
        .defaultSize(width: 780, height: 680)

        Settings {
            SettingsView()
                .environment(\.locale, language.locale)
        }

        // Only while "Run in the background with a menu bar icon" is on.
        MenuBarExtra(isInserted: commandLineRun ? .constant(false) : $backgroundMode) {
            MenuBarPanel(system: models.system, disk: models.disk, brightness: models.brightness)
                .environment(\.locale, language.locale)
        } label: {
            MenuBarLabel(model: models.menuBar)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Sweeply.app/Contents/MacOS/Sweeply --disk-health: print what Disk Health reads, for bug reports.
        // Reads twice through the same path as the tab, like opening it and pressing Refresh.
        if CommandLine.arguments.contains("--disk-health") {
            MainActor.assumeIsolated {
                let model = DiskHealthModel()
                for attempt in 1...2 {
                    model.refresh()
                    if case let .loaded(health) = model.state {
                        print("Read \(attempt): \(health)")
                    } else {
                        print("Read \(attempt): Disk health unavailable")
                    }
                }
            }
            exit(0)
        }
        // Sweeply.app/Contents/MacOS/Sweeply --report: every reading, twice, for bug reports.
        // Contains no serial numbers or other identifiers.
        if CommandLine.arguments.contains("--report") {
            MainActor.assumeIsolated {
                for attempt in 1...2 {
                    let machine = SystemStats.machine()
                    let memory = SystemStats.memory()
                    let storage = SystemStats.storage()
                    let sensors = Sensors.read()
                    let devices = PeripheralScanner.scan()
                    let disk = DiskHealth.readBuiltInDisk()
                    print("""
                    Read \(attempt)
                      Machine: \(machine.chip), \(machine.performanceCores)P + \(machine.efficiencyCores)E cores
                      Memory: used \(memory.map { String($0.used) } ?? "?") of \(memory.map { String($0.total) } ?? "?") bytes, pressure \(memory.map { "\($0.pressure)" } ?? "?")
                      Storage: \(storage.map { "\($0.available) of \($0.total) bytes free" } ?? "?")
                      Sensors: CPU hottest \(sensors.cpuHottest.map { String(format: "%.1f", $0) } ?? "–"), average \(sensors.cpuAverage.map { String(format: "%.1f", $0) } ?? "–"), SSD \(sensors.ssd.map { String(format: "%.1f", $0) } ?? "–"), fans \(sensors.fans.map { $0.map { String(Int($0.rpm)) }.joined(separator: "/") } ?? "unavailable")
                      Devices: \(devices.displays.count) displays, \(devices.drives.count) external drives, \(devices.usb.count) USB, \(devices.thunderbolt.count) Thunderbolt
                      Disk health: \(disk.map { "\(Int($0.bytesWritten / 1e9)) GB written, \($0.percentageUsed)% used" } ?? "unavailable")
                      Login item: \(LoginItem.state) (system status \(SMAppService.mainApp.status.rawValue)), background mode \(AppSettings.backgroundMode ? "on" : "off")
                    """)
                }
            }
            exit(0)
        }
        // Sweeply.app/Contents/MacOS/Sweeply --snapshot <folder>
        if let flag = CommandLine.arguments.firstIndex(of: "--snapshot") {
            let folder = CommandLine.arguments.dropFirst(flag + 1).first ?? "."
            MainActor.assumeIsolated { Snapshots.render(to: URL(fileURLWithPath: folder)) }
            exit(0)
        }
        MainActor.assumeIsolated {
            // Hourly writes-per-day recording and the menu bar number run for the app's
            // lifetime, window or not.
            AppModels.shared.disk.startRecording()
            AppModels.shared.menuBar.start()
        }
        if LoginItem.launchedAtLogin && AppSettings.backgroundMode {
            // Opened at login: stay quietly in the menu bar.
            DispatchQueue.main.async {
                NSApp.windows.filter(\.canBecomeMain).forEach { $0.close() }
                NSApp.setActivationPolicy(.accessory)
            }
        } else {
            // Behave like a normal windowed app when started with `swift run`, too.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// In background mode, closing the window keeps Sweeply in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !AppSettings.backgroundMode
    }

    /// Opening Sweeply again (Launchpad, Finder) while it runs in the background shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { true }
}
