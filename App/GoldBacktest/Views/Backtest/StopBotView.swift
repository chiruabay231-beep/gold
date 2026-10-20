import SwiftUI
import BacktestKit

/// Settings, quick test and start/stop of the "Stop theo nến" bot.
struct StopBotView: View {
    @Environment(LiveMarket.self) private var market
    @Environment(PaperTrader.self) private var trader
    @Environment(StopBotController.self) private var bot
    @State private var report: CandleStopBot.Report?
    @State private var testedBars = 0

    var body: some View {
        @Bindable var bot = bot
        List {
            Section {
                Picker("Hướng", selection: $bot.config.direction) {
                    Text("Buy Stop + Sell Stop").tag(CandleStopBot.Direction.both)
                    Text("Chỉ Buy Stop").tag(CandleStopBot.Direction.long)
                    Text("Chỉ Sell Stop").tag(CandleStopBot.Direction.short)
                }
                numberRow("Khối lượng (lot)", value: $bot.config.lots, minimum: 0.01)
                numberRow("Cách đỉnh/đáy nến (giá)", value: $bot.config.offset)
                Picker("Stop loss", selection: $bot.config.stopMode) {
                    Text("Đầu kia của nến").tag(CandleStopBot.StopMode.candle)
                    Text("Cố định").tag(CandleStopBot.StopMode.fixed)
                }
                if bot.config.stopMode == .fixed {
                    numberRow("SL cách giá vào", value: $bot.config.stopDistance)
                }
                numberRow("TP = R × rủi ro (0 = không TP)", value: $bot.config.rr)
            } header: {
                Text("Lệnh")
            } footer: {
                Text("Mỗi nến đóng: Buy Stop trên đỉnh nến, Sell Stop dưới đáy nến. SL ở đầu kia của nến (hoặc cố định), TP = R × khoảng SL. Lệnh chưa khớp được thay bằng lệnh của nến mới.")
            }

            Section {
                Toggle("Khớp một bên thì huỷ bên kia (OCO)", isOn: $bot.config.oco)
                Toggle("Chỉ một lệnh mở mỗi lúc", isOn: $bot.config.onePosition)
                numberRow("Bỏ nến nhỏ hơn (giá, 0 = không lọc)", value: $bot.config.minRange)
                numberRow("Bỏ nến lớn hơn (giá, 0 = không lọc)", value: $bot.config.maxRange)
            } header: {
                Text("Lọc")
            }

            Section {
                LabeledContent("Mã", value: LiveView.displayName(market.symbol))
                LabeledContent("Khung", value: LiveView.label(market.interval))
                Button {
                    runTest()
                } label: {
                    Label("Test trên \(market.closedCandles.count) nến của biểu đồ", systemImage: "flask")
                }
                .disabled(market.closedCandles.count < 3)
                if let report {
                    results(report)
                }
            } header: {
                Text("Test nhanh")
            } footer: {
                Text("Chạy bot trên các nến đang có ở tab Live (đổi mã/khung ở đó, kéo biểu đồ sang trái để tải thêm nến). Không tính spread và trượt giá; lệnh khớp đúng giá stop.")
            }

            Section {
                if bot.isRunning {
                    if bot.chartMoved {
                        Label("Tab Live đang mở mã/khung khác: bot chờ cho tới khi quay lại \(bot.symbolKey.map { LiveView.displayName(PaperTrader.bareSymbol($0)) } ?? "") \(bot.interval.map(LiveView.label) ?? "").",
                              systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundColor(.orange)
                    }
                    Button(role: .destructive) { bot.stop() } label: {
                        Label("Dừng bot (huỷ lệnh chờ)", systemImage: "stop.circle.fill").frame(maxWidth: .infinity)
                    }
                } else {
                    Button { bot.start() } label: {
                        Label("Chạy bot trên tài khoản demo", systemImage: "play.circle.fill").frame(maxWidth: .infinity)
                    }
                    .disabled(market.closedCandles.isEmpty || trader.isReplaying)
                }
            } footer: {
                Text("Bot đặt lệnh chờ trên tài khoản demo trong app (thấy trên biểu đồ Live và tab Giao dịch), khớp lệnh và TP/SL có thông báo, giọng nói. Chạy khi app đang mở (hoặc bật Chạy nền). Nút ▶︎/⏸ cạnh BUY/SELL ở tab Live cũng bật/tắt bot này.")
            }

            Section("Nhật ký") {
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
        .navigationTitle("Bot Stop theo nến")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: bot.config) { _, _ in report = nil }
    }

    @ViewBuilder
    private func results(_ r: CandleStopBot.Report) -> some View {
        let trades = r.account.history.count
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                stat("Lệnh", "\(trades)")
                stat("Thắng", String(format: "%.0f%%", r.winRate * 100))
                stat("Lãi/lỗ", String(format: "%+.2f", r.netProfit), color: r.netProfit >= 0 ? OrderRow.profitColor : OrderRow.lossColor)
            }
            GridRow {
                stat("Sụt giảm max", String(format: "%.2f", r.maxDrawdown))
                stat("Lệnh chờ đặt", "\(r.ordersPlaced)")
                stat("Nến", "\(testedBars)")
            }
        }
        .padding(.vertical, 4)
        ForEach(Array(r.trades.suffix(15).reversed())) { t in
            HStack {
                Text(t.side == .long ? "BUY" : "SELL")
                    .font(.caption.bold())
                    .foregroundColor(t.side == .long ? OrderRow.profitColor : OrderRow.lossColor)
                    .frame(width: 38, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(StopBotController.format(t.entryPrice)) → \(StopBotController.format(t.exitPrice))")
                        .font(.caption.monospacedDigit())
                    Text("\(t.openTime.formatted(date: .abbreviated, time: .shortened)) · \(reason(t.reason))")
                        .font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                Text(String(format: "%+.2f", t.profit))
                    .font(.caption.monospacedDigit().bold())
                    .foregroundColor(t.profit >= 0 ? OrderRow.profitColor : OrderRow.lossColor)
            }
        }
    }

    private func stat(_ title: String, _ value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.subheadline.monospacedDigit().bold()).foregroundColor(color)
        }
    }

    private func reason(_ r: PaperAccount.ExitReason) -> String {
        switch r {
        case .target: return "TP"
        case .stop: return "SL"
        case .manual: return "đóng cuối test"
        case .reversal: return "đảo chiều"
        }
    }

    private func numberRow(_ title: String, value: Binding<Double>, minimum: Double = 0) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = max(minimum, $0) }),
                      format: .number.precision(.fractionLength(0...4)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
        }
    }

    private func runTest() {
        let candles = market.closedCandles
        testedBars = candles.count
        let balance = UserDefaults.standard.double(forKey: "position.balance")
        report = CandleStopBot.backtest(candles: candles, symbol: market.symbolKey, config: bot.config,
                                        startingBalance: balance > 0 ? balance : 10_000)
    }
}
