import AppKit
import SwiftUI

@main
struct SweeplyApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @State private var model = ScanModel()
    @State private var system = SystemModel()
    @State private var disk = DiskHealthModel()
    @State private var devices = PeripheralsModel()

    var body: some Scene {
        Window("Sweeply", id: "main") {
            ContentView(model: model, system: system, disk: disk, devices: devices)
                .environment(\.locale, language.locale)
                .task {
                    // Rendering snapshots must not record this Mac's real disk writes.
                    if !AppDelegate.isRenderingSnapshots { disk.startRecording() }
                }
                .frame(minWidth: 680, minHeight: 540)
        }
        .defaultSize(width: 780, height: 680)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let isRenderingSnapshots = CommandLine.arguments.contains("--snapshot")

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
        // Behave like a normal windowed app when started with `swift run`, too.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
