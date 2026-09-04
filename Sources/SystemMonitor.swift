import Foundation
import Darwin
import IOKit
import IOKit.ps
import SwiftUI

struct ProcRow: Identifiable, Hashable {
    let id: Int32
    let name: String
    let cpu: Double
    let memory: Int64
}

struct MemoryBreakdown {
    var app: Int64 = 0
    var wired: Int64 = 0
    var compressed: Int64 = 0
    var cached: Int64 = 0
    var total: Int64 = 1
    var used: Int64 { app + wired + compressed }
    var fraction: Double { Double(used) / Double(max(total, 1)) }
}

struct NetRate { var down: Int64 = 0; var up: Int64 = 0 }

struct BatteryInfo {
    var percent: Int
    var isCharging: Bool
    var minutesRemaining: Int?
    var cycleCount: Int?
    var health: Double?
    var celsius: Double?
}

struct PowerInfo {
    var system: Double = 0    // W máy đang tiêu thụ
    var adapter: Double = 0   // W sạc đang cấp
}

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var cpu: Double = 0
    @Published private(set) var cpuHistory: [Double] = Array(repeating: 0, count: 40)
    @Published private(set) var memory = MemoryBreakdown()
    @Published private(set) var diskFree: Int64 = 0
    @Published private(set) var diskTotal: Int64 = 1
    @Published private(set) var net = NetRate()
    @Published private(set) var battery: BatteryInfo?
    @Published private(set) var gpu: Double = 0
    @Published private(set) var power = PowerInfo()
    @Published private(set) var thermal: ProcessInfo.ThermalState = .nominal
    @Published private(set) var cpuTemp: Double?
    @Published private(set) var gpuTemp: Double?
    @Published private(set) var memTemp: Double?
    @Published private(set) var sensorsReady = false
    @Published private(set) var topCPU: [ProcRow] = []
    @Published private(set) var topMemory: [ProcRow] = []

    private let smc = SMCReader()
    private var timer: Timer?
    private var prevTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var prevNet: (down: Int64, up: Int64, at: Date)?
    private var tickCount = 0

    var menuBarText: String {
        String(format: "%.0f%%", cpu * 100)
    }

    func start() {
        guard timer == nil else { return }
        // Dò bảng khoá SMC mất vài giây — chạy nền để không chặn giao diện
        if let smc {
            Task { @MainActor [weak self] in
                await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .utility).async {
                        smc.discover()
                        continuation.resume()
                    }
                }
                self?.sensorsReady = smc.isReady
            }
        }
        sample()
        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func sample() {
        sampleCPU()
        sampleGPU()
        sampleTemperature()
        sampleMemory()
        thermal = ProcessInfo.processInfo.thermalState
        sampleDisk()
        sampleNetwork()
        sampleBattery()
        if tickCount % 2 == 0 { sampleProcesses() }
        tickCount += 1
    }

    // MARK: - CPU

    private func sampleCPU() {
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)

        defer { prevTicks = (user, system, idle, nice) }
        guard let prev = prevTicks else { return }

        let dUser = user &- prev.user
        let dSystem = system &- prev.system
        let dIdle = idle &- prev.idle
        let dNice = nice &- prev.nice
        let busy = dUser + dSystem + dNice
        let total = busy + dIdle
        guard total > 0 else { return }

        cpu = Double(busy) / Double(total)
        cpuHistory.removeFirst()
        cpuHistory.append(cpu)
    }

    // MARK: - Nhiệt độ

    private func sampleTemperature() {
        guard let smc, smc.isReady else { return }
        cpuTemp = smc.temperature(.cpu)
        gpuTemp = smc.temperature(.gpu)
        memTemp = smc.temperature(.memory)
    }

    // MARK: - GPU

    private func sampleGPU() {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator
        ) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }

        var highest: Double = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            guard let stats = IORegistryEntryCreateCFProperty(
                service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any],
                  let used = stats["Device Utilization %"] as? Int else { continue }
            highest = max(highest, Double(used) / 100.0)
        }
        gpu = highest
    }

    // MARK: - Bộ nhớ

    private func sampleMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let page = Int64(vm_kernel_page_size)
        var m = MemoryBreakdown()
        m.total = Int64(ProcessInfo.processInfo.physicalMemory)
        m.wired = Int64(stats.wire_count) * page
        m.compressed = Int64(stats.compressor_page_count) * page
        m.cached = Int64(stats.external_page_count) * page
        // "App Memory" của Activity Monitor = trang internal trừ phần có thể thu hồi
        m.app = max(0, Int64(stats.internal_page_count) - Int64(stats.purgeable_count)) * page
        memory = m
    }

    // MARK: - Đĩa

    private func sampleDisk() {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey
        ]) else { return }
        diskFree = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        diskTotal = Int64(values.volumeTotalCapacity ?? 1)
    }

    // MARK: - Mạng

    private func sampleNetwork() {
        var down: Int64 = 0
        var up: Int64 = 0
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let start = head else { return }
        defer { freeifaddrs(head) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = start
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            let name = String(cString: cur.pointee.ifa_name)
            guard name != "lo0",
                  Int32(cur.pointee.ifa_addr?.pointee.sa_family ?? 0) == AF_LINK,
                  let data = cur.pointee.ifa_data else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            down += Int64(stats.ifi_ibytes)
            up += Int64(stats.ifi_obytes)
        }

        let now = Date()
        defer { prevNet = (down, up, now) }
        guard let prev = prevNet else { return }
        let seconds = now.timeIntervalSince(prev.at)
        guard seconds > 0.1 else { return }
        net = NetRate(
            down: Int64(max(0, Double(down - prev.down) / seconds)),
            up: Int64(max(0, Double(up - prev.up) / seconds))
        )
    }

    // MARK: - Pin

    private func sampleBattery() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = list.first,
              let desc = IOPSGetPowerSourceDescription(snapshot, source)?
                  .takeUnretainedValue() as? [String: Any]
        else { battery = nil; return }

        let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
        let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
        let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
        let minutes = desc[kIOPSTimeToEmptyKey] as? Int

        var info = BatteryInfo(
            percent: max > 0 ? Int(Double(current) / Double(max) * 100) : 0,
            isCharging: charging,
            minutesRemaining: (minutes ?? -1) > 0 ? minutes : nil,
            cycleCount: nil,
            health: nil
        )

        // Số chu kỳ sạc và độ chai pin nằm trong IORegistry, không có trong IOPS
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleSmartBattery")
        )
        if service != 0 {
            defer { IOObjectRelease(service) }
            if let props = IORegistryEntryCreateCFProperty(
                service, "CycleCount" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? Int {
                info.cycleCount = props
            }
            let design = IORegistryEntryCreateCFProperty(
                service, "DesignCapacity" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? Int
            let raw = IORegistryEntryCreateCFProperty(
                service, "AppleRawMaxCapacity" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? Int
            if let d = design, let r = raw, d > 0 {
                info.health = Double(r) / Double(d)
            }
            // Temperature trả về đơn vị 0.01 °C
            if let t = IORegistryEntryCreateCFProperty(
                service, "Temperature" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? Int {
                info.celsius = Double(t) / 100.0
            }
            if let data = IORegistryEntryCreateCFProperty(
                service, "BatteryData" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any] {
                power = PowerInfo(
                    system: data["SystemPower"] as? Double ?? 0,
                    adapter: data["AdapterPower"] as? Double ?? 0
                )
            }
        }
        battery = info
    }

    // MARK: - Tiến trình

    private func sampleProcesses() {
        guard let output = Self.run("/bin/ps", ["-Aceo", "pid,pcpu,rss,comm", "-r"]) else { return }
        var rows: [ProcRow] = []
        for line in output.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 4,
                  let pid = Int32(parts[0]),
                  let pcpu = Double(parts[1]),
                  let rss = Int64(parts[2]) else { continue }
            let name = parts[3...].joined(separator: " ")
            rows.append(ProcRow(id: pid, name: name, cpu: pcpu, memory: rss * 1024))
        }
        topCPU = Array(rows.prefix(5))
        topMemory = Array(rows.sorted { $0.memory > $1.memory }.prefix(5))
    }

    private static func run(_ path: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// Tên máy dạng người đọc được, ví dụ "MacBook Pro (16-inch, M5 Pro)".
    static let deviceName: String = {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/")
        guard entry != 0 else { return "Mac" }
        defer { IOObjectRelease(entry) }
        guard let data = IORegistryEntrySearchCFProperty(
            entry, kIOServicePlane, "product-name" as CFString,
            kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively)
        ) as? Data else { return "Mac" }
        return String(decoding: data.prefix(while: { $0 != 0 }), as: UTF8.self)
    }()

    /// Gọn hơn ByteCountFormatter: số càng lớn càng ít chữ số thập phân,
    /// để giá trị không bao giờ dài quá và làm vỡ layout thẻ.
    static func bytes(_ value: Int64) -> String {
        let kb = 1024.0, mb = kb * 1024, gb = mb * 1024, tb = gb * 1024
        let units: [(Double, String)] = [(tb, "TB"), (gb, "GB"), (mb, "MB"), (kb, "KB")]
        let v = Double(value)
        for (scale, name) in units where v >= scale {
            let n = v / scale
            return n >= 100 ? String(format: "%.0f %@", n, name)
                            : String(format: "%.1f %@", n, name)
        }
        return "\(value) B"
    }

    static func rate(_ value: Int64) -> String {
        bytes(value) + "/s"
    }
}
