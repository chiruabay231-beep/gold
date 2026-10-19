import SwiftUI
import BacktestKit

struct IndicatorListView: View {
    @Environment(AppStore.self) private var store
    @State private var editing: CustomIndicator?
    @AppStorage(LiveIndicators.storageKey) private var liveIndicatorIDs = ""

    var body: some View {
        List {
            Section {
                ForEach(store.indicators) { indicator in
                    HStack(alignment: .top, spacing: 10) {
                        // Tick to draw it on the Live chart.
                        Button {
                            liveIndicatorIDs = LiveIndicators.toggled(indicator.id, in: liveIndicatorIDs)
                        } label: {
                            let on = LiveIndicators.ids(liveIndicatorIDs).contains(indicator.id)
                            VStack(spacing: 1) {
                                Image(systemName: on ? "checkmark.square.fill" : "square")
                                    .font(.title3)
                                    .foregroundStyle(on ? Color.accentColor : .secondary)
                                Text("Live").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.borderless)
                        Button {
                            editing = indicator
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(indicator.title).font(.headline)
                                    Spacer()
                                    Image(systemName: indicator.placement == .overlay ? "chart.line.uptrend.xyaxis" : "waveform.path.ecg")
                                        .foregroundStyle(.secondary)
                                }
                                Text(callSignature(indicator))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(Color.accentColor)
                                if !indicator.summary.isEmpty {
                                    Text(indicator.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.primary)
                    }
                }
                .onDelete { offsets in
                    for index in offsets { store.deleteIndicator(store.indicators[index].id) }
                }
            } header: {
                Text("Chỉ báo của bạn")
            } footer: {
                Text("Tích ô Live để vẽ chỉ báo lên biểu đồ Live (vẽ trên nến hoặc thành khung riêng bên dưới, theo mục Hiển thị của chỉ báo); bật/tắt nhanh cũng có trong nút f(x) ở Live. Mỗi chỉ báo là một hàm: gọi được trong chỉ báo khác và trong chiến lược bằng tên hàm của nó.")
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

    private func callSignature(_ indicator: CustomIndicator) -> String {
        let params = indicator.parameters.map { "\($0.name) = \(Format.number($0.defaultValue, digits: $0.defaultValue == $0.defaultValue.rounded() ? 0 : 2))" }
        return "\(indicator.name)(\(params.joined(separator: ", ")))"
    }
}
