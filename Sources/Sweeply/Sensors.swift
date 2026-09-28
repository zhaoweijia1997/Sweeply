import Foundation
import IOKit

/// Temperatures and fan speeds. Neither has a public API on Apple silicon:
/// temperatures come from the HID event system (as open-source monitors do) and fans
/// from the System Management Controller. Both are read-only.
struct SensorReadings: Equatable, Sendable {
    struct Fan: Equatable, Sendable {
        var rpm: Double
        var minimum: Double?
        var maximum: Double?
    }

    /// Hottest and average CPU die sensor ("PMU tdie…"), °C.
    var cpuHottest: Double?
    var cpuAverage: Double?
    /// SSD controller ("NAND … temp"), °C.
    var ssd: Double?
    /// nil when fans couldn't be read; empty when the Mac has none.
    var fans: [Fan]?

    var hasTemperatures: Bool { cpuHottest != nil || ssd != nil }
}

enum Sensors {
    static func read() -> SensorReadings {
        let temperatures = hidTemperatures()
        let dies = temperatures.filter { $0.name.contains("tdie") }.map(\.celsius)
        let nand = temperatures.filter { $0.name.hasPrefix("NAND") }.map(\.celsius)
        return SensorReadings(
            cpuHottest: dies.max(),
            cpuAverage: dies.isEmpty ? nil : dies.reduce(0, +) / Double(dies.count),
            ssd: nand.max(),
            fans: SMC.fans())
    }

    // MARK: HID temperature sensors (private IOKit symbols)

    @_silgen_name("IOHIDEventSystemClientCreate")
    private static func clientCreate(_ allocator: CFAllocator?) -> Unmanaged<CFTypeRef>?
    @_silgen_name("IOHIDEventSystemClientSetMatching")
    private static func clientSetMatching(_ client: CFTypeRef, _ matching: CFDictionary) -> Int32
    @_silgen_name("IOHIDEventSystemClientCopyServices")
    private static func clientCopyServices(_ client: CFTypeRef) -> Unmanaged<CFArray>?
    @_silgen_name("IOHIDServiceClientCopyProperty")
    private static func serviceCopyProperty(_ service: CFTypeRef, _ key: CFString) -> Unmanaged<CFTypeRef>?
    @_silgen_name("IOHIDServiceClientCopyEvent")
    private static func serviceCopyEvent(_ service: CFTypeRef, _ type: Int64, _ options: Int32, _ timestamp: Int64) -> Unmanaged<CFTypeRef>?
    @_silgen_name("IOHIDEventGetFloatValue")
    private static func eventFloatValue(_ event: CFTypeRef, _ field: Int32) -> Double

    private static let temperatureEvent: Int64 = 15  // kIOHIDEventTypeTemperature

    private static func hidTemperatures() -> [(name: String, celsius: Double)] {
        guard let client = clientCreate(kCFAllocatorDefault)?.takeRetainedValue() else { return [] }
        // Apple vendor page, temperature sensor usage.
        _ = clientSetMatching(client, ["PrimaryUsagePage": 0xFF00, "PrimaryUsage": 5] as CFDictionary)
        guard let services = clientCopyServices(client)?.takeRetainedValue() as? [CFTypeRef] else { return [] }
        return services.compactMap { service in
            guard let name = serviceCopyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String,
                  let event = serviceCopyEvent(service, temperatureEvent, 0, 0)?.takeRetainedValue() else { return nil }
            let celsius = eventFloatValue(event, Int32(temperatureEvent << 16))
            // Ignore sensors reporting nothing useful.
            return (0.5...150).contains(celsius) ? (name, celsius) : nil
        }
    }
}

/// Minimal read-only access to the System Management Controller.
private enum SMC {
    // Mirrors the C SMCKeyData_t (80 bytes); the explicit padding keeps Swift's layout
    // identical to C's, or the command byte lands in the wrong place.
    private struct Version { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0 }
    private struct Limits { var version: UInt16 = 0, length: UInt16 = 0, cpu: UInt32 = 0, gpu: UInt32 = 0, memory: UInt32 = 0 }
    private struct KeyInfo {
        var dataSize: UInt32 = 0, dataType: UInt32 = 0, attributes: UInt8 = 0
        var padding: (UInt8, UInt8, UInt8) = (0, 0, 0)
    }
    private struct Parameters {
        var key: UInt32 = 0
        var version = Version()
        var limits = Limits()
        var keyInfo = KeyInfo()
        var result: UInt8 = 0, status: UInt8 = 0, command: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)
    }

    private static let readKey: UInt8 = 5
    private static let readKeyInfo: UInt8 = 9
    private static let handleEvent: UInt32 = 2  // kSMCHandleYPCEvent

    static func fans() -> [SensorReadings.Fan]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
        defer { IOServiceClose(connection) }

        guard let count = number(connection, "FNum") else { return nil }
        return (0..<Int(count)).compactMap { index in
            guard let rpm = number(connection, "F\(index)Ac") else { return nil }
            return SensorReadings.Fan(
                rpm: rpm, minimum: number(connection, "F\(index)Mn"), maximum: number(connection, "F\(index)Mx"))
        }
    }

    private static func number(_ connection: io_connect_t, _ key: String) -> Double? {
        let code = key.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        var infoRequest = Parameters(key: code, command: readKeyInfo)
        guard let info = call(connection, &infoRequest)?.keyInfo else { return nil }
        var readRequest = Parameters(key: code, command: readKey)
        readRequest.keyInfo.dataSize = info.dataSize
        guard let reply = call(connection, &readRequest) else { return nil }
        let bytes = withUnsafeBytes(of: reply.bytes) { Array($0.prefix(Int(info.dataSize))) }

        switch info.dataType {
        case fourCC("flt ") where bytes.count >= 4:  // Apple silicon
            return Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
        case fourCC("fpe2") where bytes.count >= 2:  // Intel
            return Double((Int(bytes[0]) << 6) + (Int(bytes[1]) >> 2))
        case fourCC("ui8 ") where !bytes.isEmpty:
            return Double(bytes[0])
        default:
            return nil
        }
    }

    private static func call(_ connection: io_connect_t, _ input: inout Parameters) -> Parameters? {
        var output = Parameters()
        var size = MemoryLayout<Parameters>.stride
        let result = IOConnectCallStructMethod(connection, handleEvent, &input, MemoryLayout<Parameters>.stride, &output, &size)
        return result == KERN_SUCCESS && output.result == 0 ? output : nil
    }

    private static func fourCC(_ string: String) -> UInt32 {
        string.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }
}
