import SwiftUI
import BacktestKit

struct BinanceDownloadView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var symbol = "PAXGUSDT"
    @State private var interval: BinanceClient.Interval = .h1
    @State private var count = 5000
    @State private var loading = false
    @State private var error: String?

    private let popular = ["PAXGUSDT", "BTCUSDT", "ETHUSDT", "SOLUSDT", "BNBUSDT"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Mã", text: $symbol)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(popular, id: \.self) { item in
                                Button(item) { symbol = item }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                    }
                } header: {
                    Text("Cặp giao dịch")
                } footer: {
                    Text("PAXGUSDT là token được bảo chứng bằng vàng, giá bám sát XAUUSD. Để backtest XAUUSD từ sàn Exness, hãy xuất CSV từ MT5 và nhập file.")
                }
                Section("Khung thời gian") {
                    Picker("Khung", selection: $interval) {
                        ForEach(BinanceClient.Interval.allCases.filter { !$0.isSeconds }, id: \.self) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    Stepper("Số nến: \(count)", value: $count, in: 500...50_000, step: 500)
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .navigationTitle("Tải từ Binance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if loading {
                        ProgressView()
                    } else {
                        Button("Tải") { download() }
                            .disabled(symbol.isEmpty)
                    }
                }
            }
        }
    }

    @MainActor
    private func download() {
        loading = true
        error = nil
        let symbol = symbol.uppercased()
        let interval = interval
        let count = count
        Task {
            do {
                let candles = try await BinanceClient().fetchCandles(symbol: symbol, interval: interval, count: count)
                guard !candles.isEmpty else { throw CSVParseError.empty }
                try store.addDataset(name: "\(symbol) \(interval.rawValue)", symbol: symbol, source: .binance, candles: candles)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }
}
