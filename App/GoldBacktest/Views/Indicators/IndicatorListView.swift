import SwiftUI
import BacktestKit

struct IndicatorListView: View {
    @Environment(AppStore.self) private var store
    @State private var editing: CustomIndicator?
    @AppStorage(LiveIndicators.storageKey) private var liveIndicatorIDs = ""

    var body: some View {
        List {
            section("Vẽ trên nến", placement: .overlay)
            section("Khung riêng dưới biểu đồ", placement: .pane)
            if store.indicators.isEmpty {
                Text("Chưa có chỉ báo. Bấm + để viết, hoặc khôi phục mẫu bên dưới.").foregroundStyle(.secondary)
            }

            Section("Tham khảo") {
                NavigationLink {
                    FunctionReferenceView()
                } label: {
                    Label("Hàm & biến có sẵn", systemImage: "book")
                }
                NavigationLink {
                    ScriptGuideView()
                } label: {
                    Label("Hướng dẫn ngôn ngữ script", systemImage: "text.book.closed")
                }
                Button {
                    store.restoreSamples()
                } label: {
                    Label("Khôi phục chỉ báo & chiến lược mẫu", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("Chỉ báo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = CustomIndicator(
                        name: "my_indicator\(store.indicators.count + 1)",
                        title: "Chỉ báo mới",
                        parameters: [ScriptParameter(name: "length", defaultValue: 20)],
                        script: "// Dòng cuối cùng (hoặc các lệnh plot) là kết quả\nema(close, length)")
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editing) { indicator in
            IndicatorEditorView(indicator: indicator)
        }
    }

    /// Indicators of one placement; the switch draws it on the Live chart.
    @ViewBuilder
    private func section(_ title: String, placement: IndicatorPlacement) -> some View {
        let items = store.indicators.filter { $0.placement == placement }
        if !items.isEmpty {
            Section {
                ForEach(items) { indicator in row(indicator) }
                    .onDelete { offsets in
                        for index in offsets { store.deleteIndicator(items[index].id) }
                    }
            } header: {
                Text(title)
            } footer: {
                if placement == .pane || !store.indicators.contains(where: { $0.placement == .pane }) {
                    Text("Bật công tắc để hiện trên biểu đồ Live (cũng bật/tắt được ở nút f(x)). Chạm để sửa, vuốt trái để xoá.")
                }
            }
        }
    }

    private func row(_ indicator: CustomIndicator) -> some View {
        let on = LiveIndicators.ids(liveIndicatorIDs).contains(indicator.id)
        return HStack(spacing: 12) {
            Button {
                editing = indicator
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: indicator.placement == .overlay ? "chart.line.uptrend.xyaxis" : "waveform.path.ecg")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 34, height: 34)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(indicator.title)
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                        Text(indicator.summary.isEmpty ? callSignature(indicator) : indicator.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
            Toggle("Live", isOn: Binding(get: { on }, set: { _ in
                liveIndicatorIDs = LiveIndicators.toggled(indicator.id, in: liveIndicatorIDs)
            }))
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }

    private func callSignature(_ indicator: CustomIndicator) -> String {
        let params = indicator.parameters.map { "\($0.name) = \(Format.number($0.defaultValue, digits: $0.defaultValue == $0.defaultValue.rounded() ? 0 : 2))" }
        return "\(indicator.name)(\(params.joined(separator: ", ")))"
    }
}
