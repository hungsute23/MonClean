import SwiftUI

struct ContentView: View {
    @ObservedObject var store: CacheStore
    @State private var confirming = false
    @State private var expanded: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
                .task { if store.sizes.isEmpty { await store.scan() } }
    }

    private var header: some View {
        HStack {
            Text("Có thể dọn")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            if store.isScanning {
                ProgressView().controlSize(.small)
            } else {
                Text(CacheStore.format(store.totalFound))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(store.targets) { target in
                    row(for: target)
                    if target.id != store.targets.last?.id {
                        Divider().padding(.leading, 34)
                    }
                }
            }
        }
        .frame(maxHeight: 320)
    }

    private func row(for target: CacheTarget) -> some View {
        let size = store.sizes[target.id] ?? 0
        let isOn = store.selected.contains(target.id)
        let isOpen = expanded == target.id

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Toggle("", isOn: Binding(
                    get: { isOn },
                    set: { on in
                        if on { store.selected.insert(target.id) }
                        else { store.selected.remove(target.id) }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(size == 0)

                VStack(alignment: .leading, spacing: 1) {
                    Text(target.name)
                        .font(.system(size: 12))
                        .foregroundStyle(size == 0 ? .secondary : .primary)
                    Text(target.what)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Text(size == 0 ? "—" : CacheStore.format(size))
                    .font(.system(size: 11, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(size == 0 ? .tertiary : .secondary)

                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.12)) {
                    expanded = isOpen ? nil : target.id
                }
            }

            if isOpen {
                Text(target.afterDelete)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 34)
                    .padding(.bottom, 8)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let freed = store.lastFreed {
                Text("Đã giải phóng \(CacheStore.format(freed))")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            }

            Button {
                confirming = true
            } label: {
                Text(store.isCleaning
                     ? "Đang dọn…"
                     : "Dọn \(CacheStore.format(store.totalSelected))")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(store.totalSelected == 0 || store.isCleaning || store.isScanning)

            HStack {
                Button("Quét lại") { Task { await store.scan() } }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                    .disabled(store.isScanning)
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .confirmationDialog(
            "Dọn \(CacheStore.format(store.totalSelected))?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button("Dọn", role: .destructive) { Task { await store.clean() } }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Xoá vĩnh viễn nội dung của \(store.selected.count) mục đã chọn. "
                 + "Tất cả đều tự tạo lại được — chỉ mất thời gian tải hoặc build lần sau.")
        }
    }
}
