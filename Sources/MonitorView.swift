import SwiftUI

// MARK: - Bảng màu

enum Palette {
    static let backdropTop    = Color(red: 0.29, green: 0.11, blue: 0.52)
    static let backdropBottom = Color(red: 0.09, green: 0.03, blue: 0.21)
    static let glow           = Color(red: 0.45, green: 0.20, blue: 0.80)
    static let card           = Color.white.opacity(0.075)
    static let cardStroke     = Color.white.opacity(0.06)
    static let accent         = Color(red: 0.42, green: 0.80, blue: 1.00)
    static let good           = Color(red: 0.30, green: 0.90, blue: 0.78)
    static let warn           = Color(red: 1.00, green: 0.80, blue: 0.35)
    static let bad            = Color(red: 1.00, green: 0.45, blue: 0.45)
    static let dim            = Color.white.opacity(0.55)
}

// MARK: - Màn hình chính

struct MonitorView: View {
    @ObservedObject var monitor: SystemMonitor
    @State private var processMode = 0
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(spacing: 10) {
            header
            cpuCard
            grid
            processCard
            footer
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(backdrop)
        .preferredColorScheme(.dark)
    }

    private var backdrop: some View {
        ZStack {
            LinearGradient(colors: [Palette.backdropTop, Palette.backdropBottom],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Palette.glow.opacity(0.55), .clear],
                           center: .init(x: 0.15, y: -0.05),
                           startRadius: 0, endRadius: 320)
        }
        .ignoresSafeArea()
    }

    // MARK: Đầu trang

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text("Sức khoẻ máy:")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Text(health.label)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(health.color)
                }
                Text(SystemMonitor.deviceName)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.dim)
            }
            Spacer(minLength: 8)
            Image(systemName: "laptopcomputer")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(
                    LinearGradient(colors: [Palette.good, Palette.accent],
                                   startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: Palette.accent.opacity(0.6), radius: 10)
        }
        .padding(.bottom, 2)
    }

    private var health: (label: String, color: Color) {
        let memory = monitor.memory.fraction
        let diskFree = Double(monitor.diskFree) / Double(max(monitor.diskTotal, 1))
        if monitor.thermal == .critical || memory > 0.95 || diskFree < 0.05 {
            return ("Cần chú ý", Palette.bad)
        }
        if monitor.thermal == .serious || monitor.thermal == .fair
            || memory > 0.85 || diskFree < 0.12 {
            return ("Khá", Palette.warn)
        }
        return ("Tốt", Palette.good)
    }

    // MARK: Thẻ CPU chiếm trọn chiều ngang

    private var cpuCard: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "cpu")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.accent)
                    Text("CPU")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(monitor.cpuTemp.map { String(format: "%.0f°C", $0) } ?? "—")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                HStack(alignment: .bottom, spacing: 12) {
                    Text("\(Int(monitor.cpu * 100))%")
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .fixedSize()
                    Sparkline(values: monitor.cpuHistory,
                              colors: [Palette.accent, Palette.good])
                        .frame(height: 30)
                }
            }
        }
    }

    // MARK: Lưới 2 cột

    private var grid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                MetricCard(icon: "square.stack.3d.up.fill", tint: Color(red: 0.78, green: 0.45, blue: 1.0), title: "GPU",
                           subtitle: "Tải: \(Int(monitor.gpu * 100))%",
                           trailing: monitor.gpuTemp.map { String(format: "%.0f°C", $0) })
                MetricCard(icon: "memorychip", tint: Palette.good, title: "Bộ nhớ",
                           subtitle: "Dùng: \(SystemMonitor.bytes(monitor.memory.used))",
                           trailing: "\(Int(monitor.memory.fraction * 100))%")
            }
            HStack(spacing: 10) {
                MetricCard(icon: "internaldrive", tint: Palette.accent, title: "Ổ đĩa",
                           subtitle: "Còn trống",
                           trailing: SystemMonitor.bytes(monitor.diskFree))
                batteryCard
            }
            HStack(spacing: 10) {
                MetricCard(icon: "bolt.fill", tint: Palette.warn, title: "Nguồn",
                           subtitle: monitor.power.adapter > 0
                               ? String(format: "Sạc %.0f W", monitor.power.adapter)
                               : "Chạy pin",
                           trailing: String(format: "%.1f W", monitor.power.system))
                networkCard
            }
        }
    }

    private var batteryCard: some View {
        let battery = monitor.battery
        return MetricCard(
            icon: battery?.isCharging == true ? "battery.100.bolt" : "battery.50",
            tint: battery?.isCharging == true ? Palette.good : Palette.dim,
            title: "Pin",
            subtitle: battery.flatMap { b in
                b.minutesRemaining.map { "Còn \($0 / 60)h \($0 % 60)m" }
                    ?? b.cycleCount.map { "\($0) chu kỳ" }
            } ?? "—",
            trailing: battery.map { "\($0.percent)%" }
        )
    }

    private var networkCard: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Image(systemName: "wifi")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.accent)
                    Text("Mạng")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    thermalDot
                }
                VStack(alignment: .leading, spacing: 2) {
                    netRow("arrow.up", SystemMonitor.rate(monitor.net.up))
                    netRow("arrow.down", SystemMonitor.rate(monitor.net.down))
                }
            }
        }
    }

    private func netRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 8.5, weight: .bold))
            Text(text).font(.system(size: 10.5, design: .rounded)).monospacedDigit()
        }
        .foregroundStyle(Palette.dim)
    }

    private var thermalDot: some View {
        let color: Color = switch monitor.thermal {
        case .nominal: Palette.good
        case .fair: Palette.warn
        case .serious, .critical: Palette.bad
        @unknown default: Palette.dim
        }
        return Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .shadow(color: color.opacity(0.9), radius: 4)
    }

    // MARK: Tiến trình

    private var processCard: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Ngốn tài nguyên nhất")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    SegmentPills(selection: $processMode, titles: ["CPU", "RAM"])
                }
                let rows = processMode == 0 ? monitor.topCPU : monitor.topMemory
                VStack(spacing: 3) {
                    if rows.isEmpty {
                        Text("đang đọc…")
                            .font(.system(size: 10)).foregroundStyle(Palette.dim)
                    }
                    ForEach(rows.prefix(4)) { row in
                        HStack(spacing: 6) {
                            Text(row.name)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 4)
                            Text(processMode == 0
                                 ? String(format: "%.1f%%", row.cpu)
                                 : SystemMonitor.bytes(row.memory))
                                .font(.system(size: 10.5, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Palette.dim)
                        }
                    }
                }
            }
        }
    }

    // MARK: Chân trang

    private var footer: some View {
        HStack {
            Text("MonClean 0.4")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.dim)
            Spacer()
            Spacer()
            loginToggle
            Spacer()
            squareButton("power") { NSApplication.shared.terminate(nil) }
        }
        .padding(.top, 2)
    }

    private var loginToggle: some View {
        Button {
            launchAtLogin.toggle()
            LaunchAtLogin.set(launchAtLogin)
            launchAtLogin = LaunchAtLogin.isEnabled
        } label: {
            HStack(spacing: 5) {
                Image(systemName: launchAtLogin ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 10))
                Text("Mở khi đăng nhập")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(launchAtLogin ? Palette.good : Palette.dim)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(launchAtLogin
                               ? Palette.good.opacity(0.15)
                               : Color.white.opacity(0.07))
            )
        }
        .buttonStyle(.plain)
    }

    private func squareButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Thành phần dùng lại

struct CardBox<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Palette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(Palette.cardStroke, lineWidth: 1)
                    )
            )
    }
}

struct MetricCard: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    var trailing: String?

    var body: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(tint)
                        .frame(width: 17)
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .fixedSize()
                    Spacer(minLength: 2)
                    if let trailing {
                        Text(trailing)
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.dim)
                    .lineLimit(1)
                    .padding(.leading, 24)
            }
        }
    }
}

struct SegmentPills: View {
    @Binding var selection: Int
    let titles: [String]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(titles.indices, id: \.self) { index in
                Text(titles[index])
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(selection == index ? .white : Palette.dim)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(selection == index
                                       ? Color.white.opacity(0.18)
                                       : Color.clear)
                    )
                    .contentShape(Capsule())
                    .onTapGesture { selection = index }
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.07)))
    }
}

struct Sparkline: View {
    let values: [Double]
    let colors: [Color]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let step = values.count > 1 ? w / CGFloat(values.count - 1) : w
            // Co giãn theo đỉnh gần nhất, chặn dưới ở 25% để lúc máy nhàn rỗi
            // đường biểu đồ vẫn có hình dạng thay vì nằm bẹp dưới đáy.
            let ceiling = max(0.25, (values.max() ?? 0) * 1.15)
            let points = values.enumerated().map { index, value in
                CGPoint(x: CGFloat(index) * step,
                        y: h - CGFloat(min(max(value, 0), 1) / ceiling) * (h - 2) - 1)
            }
            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: 0, y: h))
                    path.addLine(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                    path.addLine(to: CGPoint(x: w, y: h))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [colors[0].opacity(0.50), colors[0].opacity(0.04)],
                                     startPoint: .top, endPoint: .bottom))
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                .stroke(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
