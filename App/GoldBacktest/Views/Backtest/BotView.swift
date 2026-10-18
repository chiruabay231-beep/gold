import SwiftUI
import BacktestKit

/// Runs a strategy script as an auto-trading bot on the demo account.
struct BotView: View {
    @Environment(AppStore.self) private var store
    @Environment(LiveMarket.self) private var market
    @Environment(BotController.self) private var bot

    private var strategy: StrategyDefinition? { store.strategies.first { $0.id == bot.strategyID } }

    var body: some View {
        @Bindable var bot = bot
        List {
            Section {
                Picker("Chiến lược", selection: $bot.strategyID) {
                    Text("Chọn…").tag(UUID?.none)
                    ForEach(store.strategies) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                .disabled(bot.isRunning)
                if let strategy {
                    Text(strategy.summary.isEmpty ? "Không có mô tả" : strategy.summary)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                NavigationLink { StrategyListView() } label: {
                    Label("Viết / sửa code chiến lược", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            } header: {
                Text("Code của bot")
            } footer: {
                Text("Bot dùng đúng code chiến lược như khi Backtest: long_entry / short_entry để vào lệnh, long_exit / short_exit để thoát, long_stop / long_target / short_stop / short_target cho SL và TP.")
            }

            Section {
                NavigationLink { RemoteBotView() } label: {
                    Label("Bot trên VPS (chạy 24/7)", systemImage: "server.rack")
                }
            } footer: {
                Text("Bot trong app chỉ chạy khi app mở. Trên VPS, bot chạy cả khi tắt điện thoại và bật/tắt được từ đây.")
            }

            Section("Chạy trên") {
                LabeledContent("Mã", value: LiveView.displayName(market.symbol))
                LabeledContent("Khung", value: LiveView.label(market.interval))
                Text("Đổi mã và khung ở tab Live. Bot kiểm tra tín hiệu mỗi khi một cây nến đóng.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Section("Lệnh") {
                Toggle("Cho phép MUA", isOn: $bot.allowLong)
                Toggle("Cho phép BÁN", isOn: $bot.allowShort)
                Toggle("Đảo lệnh khi có tín hiệu ngược chiều", isOn: $bot.reverse)
                Toggle("Khối lượng theo % rủi ro", isOn: $bot.useRiskSizing)
                if !bot.useRiskSizing {
                    Stepper("Khối lượng \(String(format: "%.2f", bot.lots)) lot", value: $bot.lots, in: 0.01...100, step: 0.01)
                } else {
                    Text("Dùng vốn và % rủi ro trong ⋯ → Cài đặt biểu đồ; cần chiến lược có SL.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                if bot.isRunning {
                    Button(role: .destructive) { bot.stop() } label: {
                        Label("Dừng bot", systemImage: "stop.circle.fill").frame(maxWidth: .infinity)
                    }
                } else {
                    Button {
                        if let strategy { bot.start(strategyName: strategy.name) }
                    } label: {
                        Label("Chạy bot (tài khoản demo)", systemImage: "play.circle.fill").frame(maxWidth: .infinity)
                    }
                    .disabled(strategy == nil)
                }
                if let error = market.strategyError, bot.isRunning {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundColor(.orange).font(.footnote)
                }
            } footer: {
                Text("Bot đặt lệnh trên tài khoản demo trong app (tab Giao dịch), có SL/TP tự động, quản lý lệnh và cảnh báo giọng nói như lệnh tay. Chỉ chạy khi app đang mở (hoặc bật Chạy nền). Hãy Backtest chiến lược trước khi chạy.")
            }

            Section("Nhật ký bot") {
                if bot.log.isEmpty {
                    Text("Chưa có hoạt động").foregroundColor(.secondary)
                }
                ForEach(bot.log) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.text).font(.subheadline.monospacedDigit())
                        Text(entry.time.formatted(date: .omitted, time: .standard)).font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Bot")
    }
}
