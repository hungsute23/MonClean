import Foundation

/// Một mục cache có thể dọn. Mọi đường dẫn đều nằm trong thư mục home
/// và được đối chiếu lại với danh mục này trước khi xoá.
struct CacheTarget: Identifiable, Hashable {
    let id: String
    let name: String
    let paths: [String]
    let what: String          // nó chứa gì
    let afterDelete: String   // xoá xong thì sao
    let checkedByDefault: Bool

    static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    var expandedPaths: [String] { paths.map(Self.expand) }
}

extension CacheTarget {
    static let catalog: [CacheTarget] = [
        CacheTarget(
            id: "gradle",
            name: "Gradle",
            paths: ["~/.gradle/caches", "~/.gradle/daemon", "~/.gradle/wrapper"],
            what: "Thư viện Android, bản build trung gian và bộ cài Gradle",
            afterDelete: "Lần build Flutter/Android kế tiếp tải lại — chậm hơn vài phút, không mất gì",
            checkedByDefault: true
        ),
        CacheTarget(
            id: "homebrew",
            name: "Homebrew",
            paths: ["~/Library/Caches/Homebrew"],
            what: "File cài đặt đã tải về, giữ lại sau khi cài xong",
            afterDelete: "Không ảnh hưởng gì. Chỉ tải lại nếu cài lại đúng phiên bản cũ",
            checkedByDefault: true
        ),
        CacheTarget(
            id: "derived",
            name: "Xcode DerivedData",
            paths: ["~/Library/Developer/Xcode/DerivedData"],
            what: "Kết quả build trung gian của Xcode",
            afterDelete: "Build lại từ đầu lần sau. Thường còn sửa được các lỗi Xcode khó hiểu",
            checkedByDefault: true
        ),
        CacheTarget(
            id: "pub",
            name: "Dart pub-cache",
            paths: ["~/.pub-cache"],
            what: "Package Dart/Flutter dùng chung cho mọi project",
            afterDelete: "flutter pub get tải lại. Ảnh hưởng tất cả project Flutter",
            checkedByDefault: true
        ),
        CacheTarget(
            id: "uv",
            name: "uv cache",
            paths: ["~/.cache/uv"],
            what: "Package Python dùng chung cho mọi venv",
            afterDelete: "uv add tải lại. Các .venv đang có vẫn chạy bình thường",
            checkedByDefault: true
        ),
        CacheTarget(
            id: "cocoapods",
            name: "CocoaPods",
            paths: ["~/Library/Caches/CocoaPods"],
            what: "Pod đã tải cho project iOS",
            afterDelete: "pod install tải lại",
            checkedByDefault: true
        ),
        CacheTarget(
            id: "npm",
            name: "npm / pnpm",
            paths: ["~/.npm/_cacache", "~/Library/pnpm/store"],
            what: "Package Node dùng chung",
            afterDelete: "npm/pnpm install tải lại",
            checkedByDefault: true
        ),
        CacheTarget(
            id: "devicesupport",
            name: "iOS DeviceSupport",
            paths: ["~/Library/Developer/Xcode/iOS DeviceSupport"],
            what: "Symbol debug cho từng phiên bản iOS đã từng cắm vào máy",
            afterDelete: "Xcode tải lại khi cắm thiết bị đó lần sau, mất 2–3 phút",
            checkedByDefault: false
        ),
        CacheTarget(
            id: "librarycaches",
            name: "~/Library/Caches",
            paths: ["~/Library/Caches"],
            what: "Cache của mọi ứng dụng, gồm cả app không phải dev tool",
            afterDelete: "Một số app phải đăng nhập lại hoặc dựng lại chỉ mục. Cân nhắc kỹ",
            checkedByDefault: false
        ),
    ]

    /// Tập đường dẫn hợp lệ — mọi thao tác xoá phải nằm trong đây.
    static let allowedPaths: Set<String> = Set(catalog.flatMap(\.expandedPaths))
}
