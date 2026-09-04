import Foundation
import ServiceManagement

/// Bật/tắt tự chạy khi đăng nhập.
///
/// Ưu tiên `SMAppService` — cách chuẩn từ macOS 13, mục sẽ hiện trong
/// System Settings › General › Login Items và người dùng tắt được ở đó.
/// Nếu API này từ chối (hay gặp với app ký ad-hoc), lùi về LaunchAgent thủ công.
enum LaunchAtLogin {

    private static let agentID = "me.monstudio.monclean"

    private static var agentURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/LaunchAgents/\(agentID).plist")
    }

    enum Backend: String {
        case service = "SMAppService"
        case agent = "LaunchAgent"
        case off = "tắt"
    }

    static var state: Backend {
        if SMAppService.mainApp.status == .enabled { return .service }
        if FileManager.default.fileExists(atPath: agentURL.path) { return .agent }
        return .off
    }

    static var isEnabled: Bool { state != .off }

    @discardableResult
    static func set(_ enabled: Bool) -> Backend {
        guard enabled else {
            try? SMAppService.mainApp.unregister()
            try? FileManager.default.removeItem(at: agentURL)
            return .off
        }
        do {
            try SMAppService.mainApp.register()
            if SMAppService.mainApp.status == .enabled { return .service }
        } catch {
            // rơi xuống LaunchAgent bên dưới
        }
        return writeAgent() ? .agent : .off
    }

    private static func writeAgent() -> Bool {
        let executable = Bundle.main.bundleURL.path
        let plist: [String: Any] = [
            "Label": agentID,
            "ProgramArguments": ["/usr/bin/open", "-a", executable],
            "RunAtLoad": true,
        ]
        do {
            try FileManager.default.createDirectory(
                at: agentURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0
            )
            try data.write(to: agentURL)
            return true
        } catch {
            return false
        }
    }
}
