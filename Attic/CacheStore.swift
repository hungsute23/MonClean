import Foundation
import SwiftUI

@MainActor
final class CacheStore: ObservableObject {
    @Published private(set) var sizes: [String: Int64] = [:]
    @Published private(set) var isScanning = false
    @Published private(set) var isCleaning = false
    @Published private(set) var lastFreed: Int64?
    @Published var selected: Set<String> = Set(
        CacheTarget.catalog.filter(\.checkedByDefault).map(\.id)
    )

    var targets: [CacheTarget] { CacheTarget.catalog }

    var totalFound: Int64 { sizes.values.reduce(0, +) }

    var totalSelected: Int64 {
        selected.reduce(0) { $0 + (sizes[$1] ?? 0) }
    }

    var menuBarText: String {
        if isScanning && sizes.isEmpty { return "…" }
        return Self.format(totalFound)
    }

    // MARK: - Quét

    func scan() async {
        isScanning = true
        defer { isScanning = false }

        let targets = CacheTarget.catalog
        let results = await withTaskGroup(of: (String, Int64).self) { group in
            for target in targets {
                group.addTask {
                    var total: Int64 = 0
                    for path in target.expandedPaths {
                        total += await Self.diskUsage(of: path)
                    }
                    return (target.id, total)
                }
            }
            var acc: [String: Int64] = [:]
            for await (id, bytes) in group { acc[id] = bytes }
            return acc
        }
        sizes = results
    }

    /// Dùng `du -sk` vì nhanh hơn nhiều so với duyệt cây thư mục bằng FileManager.
    private static func diskUsage(of path: String) async -> Int64 {
        guard FileManager.default.fileExists(atPath: path) else { return 0 }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
                process.arguments = ["-sk", path]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let text = String(decoding: data, as: UTF8.self)
                    let kb = Int64(text.split(separator: "\t").first ?? "") ?? 0
                    continuation.resume(returning: kb * 1024)
                } catch {
                    continuation.resume(returning: 0)
                }
            }
        }
    }

    // MARK: - Dọn

    func clean() async {
        guard !selected.isEmpty else { return }
        isCleaning = true
        let before = totalSelected
        let chosen = CacheTarget.catalog.filter { selected.contains($0.id) }

        await withTaskGroup(of: Void.self) { group in
            for target in chosen {
                for path in target.expandedPaths {
                    group.addTask { await Self.emptyDirectory(at: path) }
                }
            }
        }

        isCleaning = false
        lastFreed = before
        await scan()
    }

    /// Xoá *nội dung* thư mục, giữ lại chính thư mục đó.
    /// Chỉ chạy với đường dẫn có trong danh mục và nằm dưới home.
    private static func emptyDirectory(at path: String) async {
        let home = NSHomeDirectory()
        guard path.hasPrefix(home + "/"),
              CacheTarget.allowedPaths.contains(path) else {
            assertionFailure("Từ chối xoá đường dẫn ngoài danh mục: \(path)")
            return
        }
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(atPath: path) else { return }
        for child in children {
            try? fm.removeItem(atPath: (path as NSString).appendingPathComponent(child))
        }
    }

    // MARK: - Hiển thị

    static func format(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}
