import AppKit
import CoreGraphics
import IOKit
import SwiftUI

/// Brightness of connected displays. Apple displays go through the system's DisplayServices;
/// other monitors are driven over DDC/CI (on Apple silicon). Both are private interfaces;
/// displays that support neither simply get no slider.
enum DisplayBrightness {
    enum Method: Sendable {
        case system
        case ddc(AVService)
    }

    /// A retained IOAVService for one external display's DDC channel.
    final class AVService: @unchecked Sendable {
        let handle: CFTypeRef
        /// The monitor's own maximum brightness value, learned from the first read (usually 100).
        var maximum = 100
        init(_ handle: CFTypeRef) { self.handle = handle }
    }

    /// Finds how each display's brightness can be controlled.
    static func methods(for displays: [CGDirectDisplayID]) -> [CGDirectDisplayID: Method] {
        var result: [CGDirectDisplayID: Method] = [:]
        var external = externalServices()
        for display in displays {
            var value: Float = 0
            if let systemGet, systemGet(display, &value) == 0 {
                result[display] = .system
                continue
            }
            // Pair a DDC channel by the monitor's vendor and model; identical monitors go in order.
            let vendor = Int(CGDisplayVendorNumber(display)), model = Int(CGDisplayModelNumber(display))
            if let index = external.firstIndex(where: { $0.vendor == vendor && $0.model == model }) ?? external.indices.first {
                result[display] = .ddc(external.remove(at: index).service)
            }
        }
        return result
    }

    /// 0...1, or nil when it couldn't be read.
    static func brightness(_ display: CGDirectDisplayID, _ method: Method) -> Double? {
        switch method {
        case .system:
            var value: Float = 0
            guard let systemGet, systemGet(display, &value) == 0 else { return nil }
            return Double(value)
        case let .ddc(service):
            return DDC.readBrightness(service)
        }
    }

    @discardableResult
    static func setBrightness(_ value: Double, _ display: CGDirectDisplayID, _ method: Method) -> Bool {
        let clamped = min(max(value, 0), 1)
        switch method {
        case .system:
            return systemSet?(display, Float(clamped)) == 0
        case let .ddc(service):
            return DDC.writeBrightness(clamped, service)
        }
    }

    // MARK: DisplayServices (private framework, loaded at run time)

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let displayServices = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let systemGet = dlsym(displayServices, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetBrightness.self) }
    private static let systemSet = dlsym(displayServices, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetBrightness.self) }

    // MARK: External DDC channels

    /// Walks the registry in order: each external DCPAVServiceProxy follows the framebuffer
    /// whose DisplayAttributes describe its monitor (vendor and model numbers only).
    private static func externalServices() -> [(vendor: Int, model: Int, service: AVService)] {
        var iterator: io_iterator_t = 0
        guard IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var found: [(Int, Int, AVService)] = []
        var lastVendor = 0, lastModel = 0
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
            if let attributes = IORegistryEntryCreateCFProperty(entry, "DisplayAttributes" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
               let product = attributes["ProductAttributes"] as? [String: Any] {
                lastVendor = product["LegacyManufacturerID"] as? Int ?? 0
                lastModel = product["ProductID"] as? Int ?? 0
            }
            guard IOObjectConformsTo(entry, "DCPAVServiceProxy") != 0,
                  IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String == "External",
                  let service = DDC.createService(entry) else { continue }
            found.append((lastVendor, lastModel, AVService(service)))
        }
        return found.map { (vendor: $0.0, model: $0.1, service: $0.2) }
    }
}

/// DDC/CI over I2C (VESA MCCS): VCP code 0x10 is brightness.
enum DDC {
    @_silgen_name("IOAVServiceCreateWithService")
    private static func avCreate(_ allocator: CFAllocator?, _ service: io_service_t) -> Unmanaged<CFTypeRef>?
    @_silgen_name("IOAVServiceReadI2C")
    private static func avRead(_ service: CFTypeRef, _ chip: UInt32, _ offset: UInt32, _ buffer: UnsafeMutableRawPointer, _ length: UInt32) -> IOReturn
    @_silgen_name("IOAVServiceWriteI2C")
    private static func avWrite(_ service: CFTypeRef, _ chip: UInt32, _ offset: UInt32, _ buffer: UnsafeMutableRawPointer, _ length: UInt32) -> IOReturn

    private static let displayAddress: UInt32 = 0x37
    private static let subAddress: UInt32 = 0x51
    private static let brightnessCode: UInt8 = 0x10
    /// DDC is slow and some monitors misbehave when rushed: one transaction at a time.
    private static let lock = NSLock()

    static func createService(_ entry: io_service_t) -> CFTypeRef? {
        avCreate(kCFAllocatorDefault, entry)?.takeRetainedValue()
    }

    /// A DDC/CI message with its length byte and checksum (XOR of the destination
    /// address 0x6E, the source 0x51 and every byte).
    static func packet(_ body: [UInt8]) -> [UInt8] {
        var message = [0x80 | UInt8(body.count)] + body
        message.append(message.reduce(UInt8(0x6E ^ 0x51)) { $0 ^ $1 })
        return message
    }

    static func readBrightness(_ service: DisplayBrightness.AVService) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        for _ in 0..<3 {
            var request = packet([0x01, brightnessCode])
            guard request.withUnsafeMutableBytes({ avWrite(service.handle, displayAddress, subAddress, $0.baseAddress!, UInt32($0.count)) }) == KERN_SUCCESS else { continue }
            usleep(40_000)
            var reply = [UInt8](repeating: 0, count: 12)
            guard reply.withUnsafeMutableBytes({ avRead(service.handle, displayAddress, subAddress, $0.baseAddress!, UInt32($0.count)) }) == KERN_SUCCESS,
                  let (current, maximum) = parseBrightnessReply(reply) else {
                usleep(40_000)
                continue
            }
            service.maximum = maximum
            return min(Double(current) / Double(maximum), 1)
        }
        return nil
    }

    /// Reply to "Get VCP Feature": 6E 88 02 <result> <code> <type> <max hi> <max lo> <cur hi> <cur lo> <checksum>.
    static func parseBrightnessReply(_ reply: [UInt8]) -> (current: Int, maximum: Int)? {
        guard reply.count >= 10, reply[2] == 0x02, reply[3] == 0x00, reply[4] == brightnessCode else { return nil }
        let maximum = Int(reply[6]) << 8 | Int(reply[7])
        let current = Int(reply[8]) << 8 | Int(reply[9])
        return maximum > 0 ? (current, maximum) : nil
    }

    /// Brightness 0...1 on the monitor's own scale.
    static func writeBrightness(_ value: Double, _ service: DisplayBrightness.AVService) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let level = UInt16((value * Double(service.maximum)).rounded())
        var message = packet([0x03, brightnessCode, UInt8(level >> 8), UInt8(level & 0xFF)])
        let result = message.withUnsafeMutableBytes { avWrite(service.handle, displayAddress, subAddress, $0.baseAddress!, UInt32($0.count)) }
        usleep(20_000)
        return result == KERN_SUCCESS
    }
}

/// Brightness sliders for the Devices tab and the menu bar panel.
@MainActor @Observable
final class BrightnessModel {
    struct Display: Identifiable, Equatable {
        let id: CGDirectDisplayID
        let name: String
        /// 0...1; nil while unknown or when the display can't be controlled.
        var value: Double?
        var supported: Bool
    }

    private(set) var displays: [Display] = []
    private var methods: [CGDirectDisplayID: DisplayBrightness.Method] = [:]
    /// While dragging, only the latest value is sent; a new write starts when the last one ends.
    private var pending: [CGDirectDisplayID: Double] = [:]
    private var writing: Set<CGDirectDisplayID> = []
    private var refreshing = false
    private let live: Bool

    init(displays: [Display] = [], live: Bool = true) {
        self.displays = displays
        self.live = live
    }

    func display(_ id: CGDirectDisplayID) -> Display? {
        displays.first { $0.id == id }
    }

    /// Finds each display's control and reads its brightness (DDC reads take ~100 ms, so off the main thread).
    func refresh() {
        guard live, !refreshing else { return }
        refreshing = true
        let screens = NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, String)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (number.uint32Value, screen.localizedName)
        }
        Task {
            let (methods, values) = await Task.detached(priority: .userInitiated) {
                let methods = DisplayBrightness.methods(for: screens.map(\.0))
                var values: [CGDirectDisplayID: Double] = [:]
                for (id, method) in methods {
                    values[id] = DisplayBrightness.brightness(id, method)
                }
                return (methods, values)
            }.value
            self.methods = methods
            displays = screens.map { id, name in
                Display(id: id, name: name, value: values[id], supported: values[id] != nil)
            }
            refreshing = false
        }
    }

    func set(_ value: Double, for id: CGDirectDisplayID) {
        guard let index = displays.firstIndex(where: { $0.id == id }), displays[index].supported else { return }
        displays[index].value = value
        guard live else { return }
        pending[id] = value
        if !writing.contains(id) { writeNext(id) }
    }

    private func writeNext(_ id: CGDirectDisplayID) {
        guard let value = pending.removeValue(forKey: id), let method = methods[id] else { return }
        writing.insert(id)
        Task {
            await Task.detached(priority: .userInitiated) {
                DisplayBrightness.setBrightness(value, id, method)
            }.value
            writing.remove(id)
            if pending[id] != nil { writeNext(id) }
        }
    }
}

/// A brightness slider with sun icons and the percentage.
struct BrightnessSlider: View {
    let model: BrightnessModel
    let display: BrightnessModel.Display

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sun.min").foregroundStyle(.secondary)
            Slider(value: Binding(get: { display.value ?? 0 }, set: { model.set($0, for: display.id) }), in: 0...1)
            Image(systemName: "sun.max").foregroundStyle(.secondary)
            Text(verbatim: "\(Int(((display.value ?? 0) * 100).rounded()))%")
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
    }
}
