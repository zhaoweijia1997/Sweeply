import Foundation
import IOKit

/// Health of the Mac's built-in SSD, from the drive's own NVMe SMART log.
/// Read-only; external drives are never read.
struct DiskHealth: Equatable, Sendable {
    enum Verdict {
        case good, attention, replace
    }

    var model: String
    var capacity: Int64?
    var bytesWritten: Double
    var bytesRead: Double
    /// The drive's own wear estimate. Can go past 100.
    var percentageUsed: Int
    var availableSpare: Int
    var spareThreshold: Int
    var temperature: Int?
    var powerOnHours: Double
    var powerCycles: Double
    var unsafeShutdowns: Double
    var mediaErrors: Double
    var criticalWarning: UInt8

    var fullDiskWrites: Double? {
        guard let capacity, capacity > 0 else { return nil }
        return bytesWritten / Double(capacity)
    }

    var verdict: Verdict {
        if criticalWarning != 0 || availableSpare < spareThreshold || percentageUsed >= 100 { return .replace }
        if mediaErrors > 0 || percentageUsed >= 80 { return .attention }
        return .good
    }
}

extension DiskHealth {
    /// Parses the 512-byte NVMe SMART / Health Information log page (NVMe spec, log page 02h).
    init?(smartLog log: [UInt8], model: String, capacity: Int64?) {
        guard log.count >= 192 else { return nil }
        func u128(_ offset: Int) -> Double {
            (0..<16).reversed().reduce(0.0) { $0 * 256 + Double(log[offset + $1]) }
        }
        // "Data units" are thousands of 512-byte blocks.
        let dataUnit = 512_000.0
        let kelvin = Int(UInt16(log[1]) | UInt16(log[2]) << 8)

        self.init(
            model: model,
            capacity: capacity,
            bytesWritten: u128(48) * dataUnit,
            bytesRead: u128(32) * dataUnit,
            percentageUsed: Int(log[5]),
            availableSpare: Int(log[3]),
            spareThreshold: Int(log[4]),
            temperature: kelvin > 0 ? kelvin - 273 : nil,
            powerOnHours: u128(128),
            powerCycles: u128(112),
            unsafeShutdowns: u128(144),
            mediaErrors: u128(160),
            criticalWarning: log[0])
    }

    /// Reads the built-in NVMe SSD. Returns nil when there is none that reports SMART data
    /// (for example older Macs with a SATA SSD).
    static func readBuiltInDisk() -> DiskHealth? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IONVMeBlockStorageDevice"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            let location = (property(service, "Protocol Characteristics") as? [String: Any])?["Physical Interconnect Location"] as? String
            guard location == "Internal", property(service, "NVMe SMART Capable") as? Bool == true,
                  let log = readSMARTLog(service) else { continue }
            let model = (property(service, "Device Characteristics") as? [String: Any])?["Product Name"] as? String
            let capacity = (IORegistryEntrySearchCFProperty(
                service, kIOServicePlane, "Size" as CFString, kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateRecursively)) as? NSNumber)?.int64Value
            return DiskHealth(smartLog: log, model: model ?? "SSD", capacity: capacity)
        }
        return nil
    }

    private static func property(_ service: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    // Apple's NVMe SMART user-client plug-in. Not in the public SDK headers; these
    // UUIDs and the interface layout are the ones smartmontools uses on macOS.
    private static let smartUserClientType = CFUUIDGetConstantUUIDWithBytes(
        nil, 0xAA, 0x0F, 0xA6, 0xF9, 0xC2, 0xD6, 0x45, 0x7F, 0xB1, 0x0B, 0x59, 0xA1, 0x32, 0x53, 0x29, 0x2F)!
    private static let smartInterface = CFUUIDGetConstantUUIDWithBytes(
        nil, 0xCC, 0xD1, 0xDB, 0x19, 0xFD, 0x9A, 0x4D, 0xAF, 0xBF, 0x95, 0x12, 0x45, 0x4B, 0x23, 0x0A, 0xB6)!
    /// kIOCFPlugInInterfaceID, a macro Swift doesn't import.
    private static let cfPlugInInterface = CFUUIDGetConstantUUIDWithBytes(
        nil, 0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4, 0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F)!

    private static func readSMARTLog(_ service: io_service_t) -> [UInt8]? {
        var plugin: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0
        guard IOCreatePlugInInterfaceForService(service, smartUserClientType, cfPlugInInterface, &plugin, &score) == KERN_SUCCESS,
              let plugin, let pluginInterface = plugin.pointee else { return nil }
        defer { _ = pluginInterface.pointee.Release(plugin) }

        var interface: LPVOID?
        guard pluginInterface.pointee.QueryInterface(plugin, CFUUIDGetUUIDBytes(smartInterface), &interface) == S_OK,
              let interface else { return nil }

        // IONVMeSMARTInterface: IUnknown (4 pointers), UInt16 version, UInt16 revision,
        // then function pointers starting with SMARTReadData.
        typealias Release = @convention(c) (UnsafeMutableRawPointer?) -> UInt32
        typealias SMARTReadData = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> IOReturn
        let vtable = interface.assumingMemoryBound(to: UnsafeMutableRawPointer.self).pointee
        let release = unsafeBitCast(vtable.load(fromByteOffset: 3 * MemoryLayout<UnsafeRawPointer>.size, as: UnsafeRawPointer.self), to: Release.self)
        let readData = unsafeBitCast(vtable.load(fromByteOffset: 5 * MemoryLayout<UnsafeRawPointer>.size, as: UnsafeRawPointer.self), to: SMARTReadData.self)
        defer { _ = release(interface) }

        var log = [UInt8](repeating: 0, count: 512)
        let result = log.withUnsafeMutableBytes { readData(interface, $0.baseAddress) }
        return result == KERN_SUCCESS ? log : nil
    }
}

/// Loads disk health for the window.
@MainActor @Observable
final class DiskHealthModel {
    enum State {
        case notLoaded, loading, unavailable, loaded(DiskHealth)
    }

    private(set) var state: State = .notLoaded

    init(state: State = .notLoaded) {
        self.state = state
    }

    func refresh() {
        if case .loading = state { return }
        state = .loading
        Task {
            let health = await Task.detached(priority: .userInitiated) { DiskHealth.readBuiltInDisk() }.value
            state = health.map(State.loaded) ?? .unavailable
        }
    }
}
