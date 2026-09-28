import Darwin
import Foundation

/// CPU, memory and storage readings from public macOS APIs. Read-only.
enum SystemStats {
    struct CPUTicks: Equatable, Sendable {
        var busy: [UInt64]
        var total: [UInt64]
    }

    struct Memory: Equatable, Sendable {
        enum Pressure: Equatable, Sendable {
            case normal, warning, critical
        }

        var total: UInt64
        /// Same split as Activity Monitor.
        var app: UInt64
        var wired: UInt64
        var compressed: UInt64
        var cachedFiles: UInt64
        var swapUsed: UInt64
        var pressure: Pressure

        var used: UInt64 { app + wired + compressed }
    }

    struct Storage: Equatable, Sendable {
        var total: Int64
        var available: Int64
    }

    struct Machine: Equatable, Sendable {
        var chip: String
        var performanceCores: Int
        var efficiencyCores: Int
        var logicalCores: Int
        var bootDate: Date
    }

    // MARK: CPU

    /// Cumulative ticks per core since boot; usage is the difference between two samples.
    static func cpuTicks() -> CPUTicks? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        var ticks = CPUTicks(busy: [], total: [])
        for core in 0..<Int(count) {
            let base = core * Int(CPU_STATE_MAX)
            let user = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]))
            let system = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]))
            let idle = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]))
            let nice = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            ticks.busy.append(user + system + nice)
            ticks.total.append(user + system + nice + idle)
        }
        return ticks
    }

    /// Busy fraction (0...1) per core between two samples.
    static func usage(from old: CPUTicks, to new: CPUTicks) -> [Double] {
        guard old.total.count == new.total.count else { return [] }
        return zip(zip(old.busy, new.busy), zip(old.total, new.total)).map { busy, total in
            let elapsed = total.1 &- total.0
            return elapsed == 0 ? 0 : Double(busy.1 &- busy.0) / Double(elapsed)
        }
    }

    // MARK: Memory

    static func memory() -> Memory? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = UInt64(vm_kernel_page_size)
        let purgeable = UInt64(stats.purgeable_count)

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0)

        let pressure: Memory.Pressure = switch sysctlInt("kern.memorystatus_vm_pressure_level") {
        case 4: .critical
        case 2: .warning
        default: .normal
        }

        return Memory(
            total: UInt64(sysctlInt("hw.memsize") ?? 0),
            app: (UInt64(stats.internal_page_count) - min(purgeable, UInt64(stats.internal_page_count))) * page,
            wired: UInt64(stats.wire_count) * page,
            compressed: UInt64(stats.compressor_page_count) * page,
            cachedFiles: (UInt64(stats.external_page_count) + purgeable) * page,
            swapUsed: swap.xsu_used,
            pressure: pressure)
    }

    // MARK: Storage & machine

    /// The startup disk, as Finder counts it ("available" includes purgeable space).
    static func storage(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Storage? {
        let values = try? home.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        guard let total = values?.volumeTotalCapacity, let available = values?.volumeAvailableCapacityForImportantUsage else { return nil }
        return Storage(total: Int64(total), available: available)
    }

    static func machine() -> Machine {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        sysctlbyname("kern.boottime", &boot, &size, nil, 0)
        return Machine(
            chip: sysctlString("machdep.cpu.brand_string") ?? "Mac",
            performanceCores: sysctlInt("hw.perflevel0.logicalcpu") ?? 0,
            efficiencyCores: sysctlInt("hw.perflevel1.logicalcpu") ?? 0,
            logicalCores: sysctlInt("hw.logicalcpu") ?? 0,
            bootDate: Date(timeIntervalSince1970: TimeInterval(boot.tv_sec)))
    }

    static func sysctlInt(_ name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        // Some keys are 32-bit; the rest of the buffer stays zero.
        return Int(size == 4 ? Int64(Int32(truncatingIfNeeded: value)) : value)
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}

/// Refreshes the System tab every two seconds while it's on screen.
@MainActor @Observable
final class SystemModel {
    private(set) var coreUsage: [Double] = []
    private(set) var memory: SystemStats.Memory?
    private(set) var storage: SystemStats.Storage?
    private(set) var sensors: SensorReadings?
    let machine: SystemStats.Machine
    private var readingSensors = false

    private var lastTicks: SystemStats.CPUTicks?
    private var timer: Timer?
    /// False for made-up snapshot data, so it's never replaced with this Mac's real readings.
    private let live: Bool

    init(machine: SystemStats.Machine = SystemStats.machine(), live: Bool = true) {
        self.machine = machine
        self.live = live
    }

    var cpuUsage: Double? {
        coreUsage.isEmpty ? nil : coreUsage.reduce(0, +) / Double(coreUsage.count)
    }

    /// Several views (System tab, menu bar panel) can use it at once; it runs while any does.
    private var users = 0

    func start() {
        users += 1
        guard live, timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        users = max(users - 1, 0)
        guard users == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        if let ticks = SystemStats.cpuTicks() {
            if let lastTicks { coreUsage = SystemStats.usage(from: lastTicks, to: ticks) }
            lastTicks = ticks
        }
        memory = SystemStats.memory()
        storage = SystemStats.storage()
        // Sensors take ~70 ms, so they're read off the main thread (tested safe, also concurrently).
        guard !readingSensors else { return }
        readingSensors = true
        Task {
            let readings = await Task.detached(priority: .utility) { Sensors.read() }.value
            sensors = readings
            readingSensors = false
        }
    }

    /// Only for `--snapshot` renders.
    func showForSnapshot(coreUsage: [Double], memory: SystemStats.Memory, storage: SystemStats.Storage, sensors: SensorReadings) {
        self.coreUsage = coreUsage
        self.memory = memory
        self.storage = storage
        self.sensors = sensors
    }
}
