import SwiftUI

@main
struct MonCleanApp: App {
    @StateObject private var monitor = SystemMonitor()

    init() {
        // Cho phép bật/tắt tự khởi động từ dòng lệnh:
        //   MonClean.app/Contents/MacOS/MonClean --login on|off|status
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--login") else { return }
        let action = index + 1 < args.count ? args[index + 1] : "status"
        switch action {
        case "on":  print("bật  -> \(LaunchAtLogin.set(true).rawValue)")
        case "off": print("tắt  -> \(LaunchAtLogin.set(false).rawValue)")
        default:    print("hiện tại: \(LaunchAtLogin.state.rawValue)")
        }
        exit(0)
    }

    var body: some Scene {
        MenuBarExtra {
            MonitorView(monitor: monitor)
                .frame(width: 360)
                .task { monitor.start() }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "waveform.path.ecg")
                Text(monitor.menuBarText).monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
