import SwiftUI

/// Icon ứng dụng. Vẽ trên canvas 1024×1024 rồi thu nhỏ ra các cỡ trong .icns.
/// Nội dung nằm gọn trong hình squircle chừa lề theo đúng cách macOS bố trí icon.
struct IconView: View {
    var side: CGFloat = 1024

    private var inset: CGFloat { side * 0.094 }
    private var art: CGFloat { side - inset * 2 }

    var body: some View {
        ZStack {
            squircle
            ring
            pulse
        }
        .frame(width: side, height: side)
    }

    // Nền tím gradient, cùng tông với giao diện app
    private var squircle: some View {
        RoundedRectangle(cornerRadius: art * 0.225, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.47, green: 0.20, blue: 0.90),
                        Color(red: 0.29, green: 0.10, blue: 0.58),
                        Color(red: 0.11, green: 0.04, blue: 0.26),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: art * 0.225, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.28), .clear],
                            center: .init(x: 0.25, y: 0.12),
                            startRadius: 0, endRadius: art * 0.62
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: art * 0.225, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: art * 0.006)
            )
            .frame(width: art, height: art)
            .shadow(color: .black.opacity(0.35), radius: art * 0.045, y: art * 0.022)
    }

    // Vòng cung gợi lại đồng hồ đo trong app
    private var ring: some View {
        Circle()
            .trim(from: 0.08, to: 0.92)
            .stroke(
                AngularGradient(
                    colors: [
                        Color(red: 0.35, green: 0.95, blue: 0.85),
                        Color(red: 0.42, green: 0.80, blue: 1.00),
                        Color(red: 0.75, green: 0.45, blue: 1.00),
                        Color(red: 0.35, green: 0.95, blue: 0.85),
                    ],
                    center: .center,
                    startAngle: .degrees(90), endAngle: .degrees(450)
                ),
                style: StrokeStyle(lineWidth: art * 0.052, lineCap: .round)
            )
            .rotationEffect(.degrees(90))
            .frame(width: art * 0.60, height: art * 0.60)
            .opacity(0.9)
            .shadow(color: Color(red: 0.42, green: 0.80, blue: 1.0).opacity(0.55),
                    radius: art * 0.03)
    }

    // Nhịp đập ở giữa — biểu tượng "đang theo dõi"
    private var pulse: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let midY = h / 2
            let amp = art * 0.105

            Path { path in
                path.move(to: CGPoint(x: w * 0.340, y: midY))
                path.addLine(to: CGPoint(x: w * 0.395, y: midY))
                path.addLine(to: CGPoint(x: w * 0.435, y: midY - amp))
                path.addLine(to: CGPoint(x: w * 0.495, y: midY + amp * 1.15))
                path.addLine(to: CGPoint(x: w * 0.545, y: midY - amp * 0.55))
                path.addLine(to: CGPoint(x: w * 0.590, y: midY))
                path.addLine(to: CGPoint(x: w * 0.660, y: midY))
            }
            .stroke(
                LinearGradient(
                    colors: [Color(red: 0.40, green: 0.98, blue: 0.88),
                             Color.white,
                             Color(red: 0.45, green: 0.85, blue: 1.00)],
                    startPoint: .leading, endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: art * 0.055, lineCap: .round, lineJoin: .round)
            )
            .shadow(color: Color(red: 0.40, green: 0.98, blue: 0.88).opacity(0.9),
                    radius: art * 0.035)
        }
    }
}
