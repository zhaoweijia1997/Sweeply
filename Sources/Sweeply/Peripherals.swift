import AppKit
import DiskArbitration
import IOKit

/// Connected displays, drives and devices. Names, sizes and speeds only: no serial numbers,
/// and nothing on an external drive is ever read.
struct Peripherals: Equatable, Sendable {
    struct Display: Identifiable, Equatable, Sendable {
        let id: UInt32
        let name: String
        let pixelWidth: Int
        let pixelHeight: Int
        let refreshRate: Int
        let isBuiltIn: Bool
    }

    struct Drive: Identifiable, Equatable, Sendable {
        enum Connection: Equatable, Sendable {
            case usb, thunderbolt, diskImage, other(String)
        }

        var id: String { path }
        let path: String
        let name: String
        let capacity: Int64
        let available: Int64
        let format: String
        let connection: Connection
    }

    struct USBDevice: Identifiable, Equatable, Sendable {
        let id: UInt64
        let name: String
        let vendor: String?
        /// IOKit "Device Speed": 0 low, 1 full, 2 high, 3 super, 4 super+, 5 super+ 2x2.
        let speed: Int?

        var speedText: String? {
            switch speed {
            case 0: "USB 1.1 · 1.5 Mb/s"
            case 1: "USB 1.1 · 12 Mb/s"
            case 2: "USB 2.0 · 480 Mb/s"
            case 3: "USB 3 · 5 Gb/s"
            case 4: "USB 3 · 10 Gb/s"
            case 5: "USB 3 · 20 Gb/s"
            default: nil
            }
        }
    }

    struct ThunderboltDevice: Identifiable, Equatable, Sendable {
        let id: UInt64
        let name: String
        let vendor: String?
    }

    var displays: [Display] = []
    var drives: [Drive] = []
    var usb: [USBDevice] = []
    var thunderbolt: [ThunderboltDevice] = []
}

enum PeripheralScanner {
    @MainActor
    static func scan() -> Peripherals {
        Peripherals(displays: displays(), drives: externalDrives(), usb: usbDevices(), thunderbolt: thunderboltDevices())
    }

    @MainActor
    static func displays() -> [Peripherals.Display] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = number.uint32Value
            let mode = CGDisplayCopyDisplayMode(id)
            return Peripherals.Display(
                id: id,
                name: screen.localizedName,
                pixelWidth: mode?.pixelWidth ?? Int(screen.frame.width * screen.backingScaleFactor),
                pixelHeight: mode?.pixelHeight ?? Int(screen.frame.height * screen.backingScaleFactor),
                refreshRate: screen.maximumFramesPerSecond,
                isBuiltIn: CGDisplayIsBuiltin(id) != 0)
        }
    }

    /// Mounted volumes that aren't on the internal disk. Only the volume's own metadata
    /// (name, capacity, format, bus) is read.
    static func externalDrives() -> [Peripherals.Drive] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeIsInternalKey, .volumeIsLocalKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey, .volumeLocalizedFormatDescriptionKey,
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]),
              let session = DASessionCreate(kCFAllocatorDefault) else { return [] }
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsLocal == true, values.volumeIsInternal != true else { return nil }
            return Peripherals.Drive(
                path: url.path,
                name: values.volumeName ?? url.lastPathComponent,
                capacity: Int64(values.volumeTotalCapacity ?? 0),
                available: Int64(values.volumeAvailableCapacity ?? 0),
                format: values.volumeLocalizedFormatDescription ?? "",
                connection: connection(of: url, session: session))
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func connection(of volume: URL, session: DASession) -> Peripherals.Drive.Connection {
        guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, volume as CFURL),
              let description = DADiskCopyDescription(disk) as? [CFString: Any] else { return .other("") }
        let model = description[kDADiskDescriptionDeviceModelKey] as? String
        let bus = description[kDADiskDescriptionDeviceProtocolKey] as? String ?? ""
        if model?.trimmingCharacters(in: .whitespaces) == "Disk Image" || bus == "Virtual Interface" { return .diskImage }
        switch bus {
        case "USB": return .usb
        case "Thunderbolt": return .thunderbolt
        default: return .other(bus)
        }
    }

    /// USB devices, without hubs (they're plumbing, not something you plugged in to use).
    static func usbDevices() -> [Peripherals.USBDevice] {
        registryEntries(matching: "IOUSBHostDevice") { id, service in
            guard property(service, "bDeviceClass") as? Int != 9 else { return nil }
            return Peripherals.USBDevice(
                id: id,
                name: property(service, "USB Product Name") as? String ?? "USB",
                vendor: property(service, "USB Vendor Name") as? String,
                speed: property(service, "Device Speed") as? Int)
        }
    }

    /// Thunderbolt / USB4 devices plugged in. The Mac's own controllers sit at depth 0.
    static func thunderboltDevices() -> [Peripherals.ThunderboltDevice] {
        registryEntries(matching: "IOThunderboltSwitch") { id, service in
            guard let depth = property(service, "Depth") as? Int, depth > 0 else { return nil }
            return Peripherals.ThunderboltDevice(
                id: id,
                name: property(service, "Device Model Name") as? String ?? "Thunderbolt",
                vendor: property(service, "Device Vendor Name") as? String)
        }
    }

    /// Calls `read` for each matching registry entry while it's still retained.
    private static func registryEntries<T>(matching className: String, _ read: (UInt64, io_service_t) -> T?) -> [T] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var results: [T] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            var id: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &id)
            if let value = read(id, service) { results.append(value) }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return results
    }

    private static func property(_ service: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}

/// Refreshes the Devices tab every three seconds while it's on screen.
@MainActor @Observable
final class PeripheralsModel {
    private(set) var peripherals: Peripherals?
    private var timer: Timer?
    private let live: Bool

    init(peripherals: Peripherals? = nil, live: Bool = true) {
        self.peripherals = peripherals
        self.live = live
    }

    func start() {
        guard live, timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let latest = PeripheralScanner.scan()
        if latest != peripherals { peripherals = latest }
    }
}
