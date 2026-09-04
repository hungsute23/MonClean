import SwiftUI
import AppKit

// Dựng giao diện ra file PNG để xem mà không cần quyền quay màn hình.
@MainActor
func renderPreview() {
    let monitor = SystemMonitor()
    monitor.start()

    // Chờ lấy đủ mẫu và dò xong cảm biến SMC
    let deadline = Date().addingTimeInterval(12)
    while Date() < deadline && !monitor.sensorsReady {
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
    RunLoop.current.run(until: Date().addingTimeInterval(3))

    let renderer = ImageRenderer(content: MonitorView(monitor: monitor).frame(width: 360))
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("render thất bại"); exit(1)
    }
    let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/preview.png"
    try? png.write(to: URL(fileURLWithPath: out))
    print("đã ghi \(out) — \(Int(image.size.width))x\(Int(image.size.height)) pt")
    print("CPU \(Int(monitor.cpu * 100))%  GPU \(Int(monitor.gpu * 100))%  "
          + "cpuTemp \(monitor.cpuTemp.map { String(format: "%.1f", $0) } ?? "nil")  "
          + "gpuTemp \(monitor.gpuTemp.map { String(format: "%.1f", $0) } ?? "nil")")
    exit(0)
}

MainActor.assumeIsolated {
    if let index = CommandLine.arguments.firstIndex(of: "--icon") {
        let out = index + 1 < CommandLine.arguments.count
            ? CommandLine.arguments[index + 1] : "/tmp/icon.png"
        renderIcon(out)
    }
    renderPreview()
}
