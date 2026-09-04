import Foundation
import IOKit

/// Đọc cảm biến nhiệt qua AppleSMC. Không cần quyền root —
/// khác với `powermetrics`, vốn bắt buộc chạy bằng superuser.
///
/// `discover()` chạy ở luồng nền còn `temperature()` gọi từ main, nên mọi
/// truy cập vào bảng khoá và vào cổng IOKit đều phải đi qua `lock`.
final class SMCReader: @unchecked Sendable {

    private let lock = NSLock()

    // MARK: - Cấu trúc giao tiếp với AppleSMC

    private typealias Bytes = (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                               UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                               UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                               UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8)

    private struct Version { var major: UInt8=0; var minor: UInt8=0; var build: UInt8=0
                             var reserved: UInt8=0; var release: UInt16=0 }
    private struct PLimit  { var version: UInt16=0; var length: UInt16=0; var cpu: UInt32=0
                             var gpu: UInt32=0; var mem: UInt32=0 }
    private struct KeyInfo { var dataSize: UInt32=0; var dataType: UInt32=0; var attributes: UInt8=0 }

    private struct Param {
        var key: UInt32 = 0
        var vers = Version()
        var pLimit = PLimit()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                            0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    }

    private enum Selector: UInt8 {
        case readKey = 5
        case keyFromIndex = 8
        case keyInfo = 9
    }

    /// Nhóm cảm biến theo tiền tố khoá mà Apple Silicon dùng.
    enum Sensor: String, CaseIterable {
        case cpu = "Tp"      // P-core
        case gpu = "Tg"
        case memory = "Tm"
        case skin = "Ts"     // vỏ máy
        case ambient = "TA"
    }

    private var conn: io_connect_t = 0
    private var keys: [Sensor: [(key: UInt32, info: KeyInfo)]] = [:]
    private var ready = false

    var isReady: Bool { lock.withLock { ready } }

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return nil }
    }

    deinit { if conn != 0 { IOServiceClose(conn) } }

    // MARK: - Gọi SMC

    private func call(_ input: inout Param) -> Param? {
        lock.lock()
        defer { lock.unlock() }
        var output = Param()
        var size = MemoryLayout<Param>.stride
        let rc = IOConnectCallStructMethod(
            conn, 2, &input, MemoryLayout<Param>.stride, &output, &size
        )
        return (rc == KERN_SUCCESS && output.result == 0) ? output : nil
    }

    private func info(of key: UInt32) -> KeyInfo? {
        var input = Param(); input.key = key; input.data8 = Selector.keyInfo.rawValue
        return call(&input)?.keyInfo
    }

    private func value(of key: UInt32, _ keyInfo: KeyInfo) -> Double? {
        var input = Param()
        input.key = key; input.keyInfo = keyInfo; input.data8 = Selector.readKey.rawValue
        guard var out = call(&input) else { return nil }
        // Chỉ quan tâm kiểu "flt " — mọi cảm biến nhiệt trên Apple Silicon đều dùng kiểu này
        guard Self.fourCCString(keyInfo.dataType) == "flt ", keyInfo.dataSize == 4 else { return nil }
        return withUnsafeBytes(of: &out.bytes) { Double($0.load(as: Float32.self)) }
    }

    // MARK: - Dò cảm biến (chỉ chạy một lần lúc khởi động)

    /// Duyệt hết bảng khoá SMC để tìm cảm biến nào thật sự tồn tại trên máy này.
    /// Tốn vài giây nên phải gọi ngoài main thread; sau đó chỉ đọc đúng các khoá đã tìm được.
    func discover() {
        guard let countInfo = info(of: Self.fourCC("#KEY")),
              let count = value(of: Self.fourCC("#KEY"), countInfo) ?? readUInt32("#KEY", countInfo)
        else { return }

        var found: [Sensor: [(key: UInt32, info: KeyInfo)]] = [:]
        for index in 0..<Int(count) {
            var input = Param()
            input.data8 = Selector.keyFromIndex.rawValue
            input.data32 = UInt32(index)
            guard let out = call(&input) else { continue }
            let name = Self.fourCCString(out.key)
            guard let sensor = Sensor.allCases.first(where: { name.hasPrefix($0.rawValue) }),
                  let keyInfo = info(of: out.key),
                  let reading = value(of: out.key, keyInfo),
                  reading > 0, reading < 130
            else { continue }
            found[sensor, default: []].append((out.key, keyInfo))
        }
        lock.withLock {
            keys = found
            ready = !found.isEmpty
        }
    }

    /// `#KEY` trả về kiểu ui32 chứ không phải flt, nên cần đọc riêng.
    private func readUInt32(_ name: String, _ keyInfo: KeyInfo) -> Double? {
        var input = Param()
        input.key = Self.fourCC(name); input.keyInfo = keyInfo
        input.data8 = Selector.readKey.rawValue
        guard var out = call(&input) else { return nil }
        return withUnsafeBytes(of: &out.bytes) {
            Double(UInt32(bigEndian: $0.load(as: UInt32.self)))
        }
    }

    // MARK: - Đọc nhiệt độ

    /// Trung bình của cụm cảm biến. Dùng trung bình thay vì giá trị đỉnh
    /// vì từng lõi đơn lẻ dao động rất mạnh.
    func temperature(_ sensor: Sensor) -> Double? {
        guard let list = lock.withLock({ keys[sensor] }), !list.isEmpty else { return nil }
        let readings = list.compactMap { value(of: $0.key, $0.info) }
        guard !readings.isEmpty else { return nil }
        return readings.reduce(0, +) / Double(readings.count)
    }

    func peak(_ sensor: Sensor) -> Double? {
        guard let list = lock.withLock({ keys[sensor] }) else { return nil }
        return list.compactMap { value(of: $0.key, $0.info) }.max()
    }

    func sensorCount(_ sensor: Sensor) -> Int { lock.withLock { keys[sensor]?.count ?? 0 } }

    // MARK: - Tiện ích

    private static func fourCC(_ s: String) -> UInt32 {
        s.utf8.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private static func fourCCString(_ v: UInt32) -> String {
        String(bytes: [UInt8((v >> 24) & 0xff), UInt8((v >> 16) & 0xff),
                       UInt8((v >> 8) & 0xff), UInt8(v & 0xff)], encoding: .ascii) ?? "????"
    }
}
