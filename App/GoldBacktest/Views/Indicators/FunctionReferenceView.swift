import SwiftUI
import BacktestKit

struct FunctionReferenceView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""

    var body: some View {
        let functions = store.library.all.filter { function in
            query.isEmpty || function.name.localizedCaseInsensitiveContains(query)
                || function.summary.localizedCaseInsensitiveContains(query)
        }
        let categories = Array(Set(functions.map(\.category))).sorted()
        List {
            if query.isEmpty {
                Section("Biến có sẵn") {
                    ForEach(ReferenceItem.variables) { item in
                        ReferenceRow(code: item.name, summary: item.summary)
                    }
                }
                Section("Biến tín hiệu của chiến lược") {
                    ForEach(ReferenceItem.signals) { item in
                        ReferenceRow(code: item.name, summary: item.summary)
                    }
                }
            }
            ForEach(categories, id: \.self) { category in
                Section(category) {
                    ForEach(functions.filter { $0.category == category }, id: \.name) { function in
                        ReferenceRow(code: function.signature, summary: function.summary)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Tìm hàm")
        .navigationTitle("Hàm có sẵn")
    }
}

struct ReferenceItem: Identifiable {
    var id: String { name }
    var name: String
    var summary: String

    static var variables: [ReferenceItem] {
        EvaluationContext.builtinVariables.map { ReferenceItem(name: $0.name, summary: $0.summary) }
    }

    static var signals: [ReferenceItem] {
        StrategyDefinition.signalVariables.map { ReferenceItem(name: $0.name, summary: $0.summary) }
    }
}

struct ReferenceRow: View {
    let code: String
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(code)
                .font(.callout.monospaced())
                .textSelection(.enabled)
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct ScriptGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GuideSection(title: "Cơ bản", text: """
                Mỗi dòng là một lệnh. Gán biến bằng `=`, dòng cuối cùng là kết quả của chỉ báo. Chú thích bắt đầu bằng `//` hoặc `#`.
                """, code: """
                fast = ema(close, 12)
                slow = ema(close, 26)
                fast - slow
                """)
                GuideSection(title: "Phép toán", text: """
                `+ - * / % ^`, so sánh `> < >= <= == !=`, logic `and or not` (hoặc `&& || !`), điều kiện `a ? b : c`. Điều kiện đúng = 1, sai = 0.
                """, code: """
                trend_up = close > ema(close, 200) and adx(14) > 20
                trend_up ? 1 : -1
                """)
                GuideSection(title: "Dữ liệu quá khứ", text: """
                `x[n]` là giá trị của x cách đây n nến. Không thể nhìn vào tương lai (n âm bị báo lỗi).
                """, code: """
                // Fair value gap tăng: đáy nến hiện tại cao hơn đỉnh 2 nến trước
                low > high[2]
                """)
                GuideSection(title: "Nhiều đường", text: """
                Dùng `plot(x, "tên")` để vẽ nhiều đường, `hline(giá trị)` cho đường ngang. Khi chỉ báo được gọi từ script khác, đường plot đầu tiên được trả về.
                """, code: """
                mid = sma(close, length)
                dev = 2 * stdev(close, length)
                plot(mid, "Giữa")
                plot(mid + dev, "Trên")
                plot(mid - dev, "Dưới")
                """)
                GuideSection(title: "Dùng lại chỉ báo của bạn", text: """
                Chỉ báo có tên hàm `my_osc` với tham số `length` được gọi là `my_osc(20)`. Bỏ trống tham số để dùng giá trị mặc định: `my_osc()`.
                """, code: """
                signal = ema(my_osc(20), 9)
                crossover(my_osc(20), signal)
                """)
                GuideSection(title: "Chiến lược", text: """
                Script chiến lược gán `long_entry`, `long_exit`, `short_entry`, `short_exit`. Tuỳ chọn `long_stop`, `long_target`, `short_stop`, `short_target` là giá cắt lỗ/chốt lời, tính tại nến tín hiệu. Lệnh khớp ở giá mở của nến kế tiếp.
                """, code: """
                long_entry  = crossover(ema(close, 9), ema(close, 21))
                long_exit   = crossunder(ema(close, 9), ema(close, 21))
                long_stop   = close - 2 * atr(14)
                long_target = close + 4 * atr(14)
                """)
                GuideSection(title: "Phiên giao dịch", text: """
                `session(start, end)` trả về 1 trong khung giờ (giờ thập phân, theo múi giờ chọn ở màn Backtest). Ví dụ giờ VN: London 14–17, New York 19–22.
                """, code: """
                killzone = session(14, 17) or session(19.5, 22)
                long_entry = killzone and crossover(close, daily_high())
                """)
                GuideSection(title: "Chỉ báo viết bằng Swift", text: """
                Logic phức tạp, có trạng thái theo từng nến (trailing stop, order block…) nên viết bằng Swift trong `NativeIndicators.swift` rồi gọi từ script như hàm bình thường. Xem README.
                """, code: nil)
            }
            .padding()
        }
        .navigationTitle("Hướng dẫn")
    }
}

private struct GuideSection: View {
    let title: String
    let text: String
    let code: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(LocalizedStringKey(text)).font(.callout)
            if let code {
                Text(code)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: 8))
            }
        }
    }
}
