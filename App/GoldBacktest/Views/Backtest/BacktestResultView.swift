import SwiftUI
import BacktestKit

struct BacktestResultView: View {
    let run: BacktestRun

    @State private var viewport = ChartViewport()
    @State private var focusedTrade: Trade?

    init(run: BacktestRun) {
        self.run = run
    }

    private var result: BacktestResult { run.result }
    private var metrics: BacktestMetrics { run.result.metrics }
    private var lines: [ChartLine] { ChartPalette.lines(from: result.plots.filter { !$0.isHorizontalLine }) }
    private var equityTimes: [Date] { Array(run.data.time[result.startIndex...]) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                MetricGrid(metrics: metrics)

                ForEach(result.warnings, id: \.self) { ErrorText(message: $0) }

                card("Đường vốn") {
                    SeriesChartView(title: "Vốn", times: equityTimes, values: result.equity,
                                    color: metrics.netProfit >= 0 ? .green : .red)
                        .frame(height: 180)
                }

                card("Drawdown (%)") {
                    SeriesChartView(title: "Drawdown", times: equityTimes, values: result.drawdown, color: .orange)
                        .frame(height: 120)
                }

                card("Biểu đồ giá & lệnh") {
                    ExpandableCandleChart(title: "\(run.strategy.name) · \(run.datasetName)",
                                          candles: run.data.candles, overlays: lines,
                                          markers: ChartMarker.from(trades: result.trades), interactive: false, viewport: $viewport)
                        .frame(height: 380)
                        .clipShape(.rect(cornerRadius: 8))
                    ChartLegend(lines: lines)
                    Text("Chạm vào biểu đồ để mở toàn màn hình: kéo ngang, chụm phóng to, kéo trục giá, giữ để xem OHLC")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                NavigationLink {
                    TradesListView(run: run) { trade in
                        focus(on: trade)
                    }
                } label: {
                    HStack {
                        Label("Danh sách lệnh (\(result.trades.count))", systemImage: "list.number")
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1), in: .rect(cornerRadius: 12))
                }
                .foregroundStyle(.primary)

                ShareLink(item: tradesCSV, preview: SharePreview("Lệnh \(run.strategy.name).csv")) {
                    Label("Xuất danh sách lệnh (CSV)", systemImage: "square.and.arrow.up")
                }
            }
            .padding()
        }
        .navigationTitle("Kết quả")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(run.strategy.name).font(.title2.bold())
            Text(run.datasetName).foregroundStyle(.secondary)
            if !run.parameterValues.isEmpty || !run.strategy.parameters.isEmpty {
                Text(run.strategy.parameters.map { p in
                    "\(p.name)=\(Format.number(run.parameterValues[p.name] ?? p.defaultValue, digits: 2))"
                }.joined(separator: "  "))
                .font(.caption.monospaced())
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        .padding()
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 12))
    }

    private func focus(on trade: Trade) {
        // Centre the trade on screen.
        let center = Double(trade.entryIndex + trade.exitIndex) / 2
        let end = center + viewport.visibleCount / 2
        viewport.rightOffset = max(0, Double(run.data.count) + viewport.rightPadding - end)
    }

    private var tradesCSV: String {
        var out = "id,direction,entry_time,entry_price,exit_time,exit_price,quantity,profit,return_pct,bars,exit_reason\n"
        let formatter = ISO8601DateFormatter()
        for t in result.trades {
            out += "\(t.id),\(t.direction.rawValue),\(formatter.string(from: t.entryTime)),\(t.entryPrice),"
            out += "\(formatter.string(from: t.exitTime)),\(t.exitPrice),\(t.quantity),\(t.profit),"
            out += "\(t.returnPercent),\(t.barsHeld),\(t.exitReason.rawValue)\n"
        }
        return out
    }
}

struct MetricGrid: View {
    let metrics: BacktestMetrics

    var body: some View {
        let profitColor: Color = metrics.netProfit >= 0 ? .green : .red
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
            MetricTile(title: "Lợi nhuận ròng", value: Format.signed(metrics.netProfit), color: profitColor)
            MetricTile(title: "Lợi nhuận %", value: Format.percent(metrics.netProfitPercent), color: profitColor)
            MetricTile(title: "Mua & giữ", value: Format.percent(metrics.buyAndHoldPercent))
            MetricTile(title: "Số lệnh", value: "\(metrics.totalTrades)")
            MetricTile(title: "Tỉ lệ thắng", value: Format.number(metrics.winRate, digits: 1) + "%")
            MetricTile(title: "Profit factor", value: Format.number(metrics.profitFactor))
            MetricTile(title: "Max drawdown", value: Format.number(metrics.maxDrawdownPercent, digits: 2) + "%", color: .orange)
            MetricTile(title: "Sharpe", value: Format.number(metrics.sharpeRatio))
            MetricTile(title: "Sortino", value: Format.number(metrics.sortinoRatio))
            MetricTile(title: "CAGR", value: Format.percent(metrics.cagr))
            MetricTile(title: "TB mỗi lệnh", value: Format.signed(metrics.averageTrade))
            MetricTile(title: "TB R", value: metrics.averageR.map { Format.number($0) + "R" } ?? "–")
            MetricTile(title: "TB thắng", value: Format.signed(metrics.averageWin), color: .green)
            MetricTile(title: "TB thua", value: Format.signed(metrics.averageLoss), color: .red)
            MetricTile(title: "Thua liên tiếp", value: "\(metrics.maxConsecutiveLosses)")
            MetricTile(title: "Thời gian giữ", value: Format.number(metrics.averageBarsHeld, digits: 1) + " nến")
            MetricTile(title: "Trong thị trường", value: Format.number(metrics.exposurePercent, digits: 1) + "%")
            MetricTile(title: "Tổng phí", value: Format.number(metrics.totalCommission))
        }
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 10))
    }
}

struct TradesListView: View {
    let run: BacktestRun
    var onSelect: (Trade) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(run.result.trades.reversed()) { trade in
            Button {
                onSelect(trade)
                dismiss()
            } label: {
                TradeRow(trade: trade)
            }
            .foregroundStyle(.primary)
        }
        .navigationTitle("Lệnh")
        .overlay {
            if run.result.trades.isEmpty {
                ContentUnavailableView("Không có lệnh nào", systemImage: "tray",
                                       description: Text("Điều kiện vào lệnh chưa từng đúng trên dữ liệu này."))
            }
        }
    }
}

struct TradeRow: View {
    let trade: Trade

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(trade.direction == .long ? "MUA" : "BÁN")
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((trade.direction == .long ? Color.green : Color.red).opacity(0.2), in: Capsule())
                Text("#\(trade.id)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(Format.signed(trade.profit))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(trade.isWin ? Color.green : Color.red)
            }
            HStack {
                Text("\(Format.date(trade.entryTime)) @ \(Format.price(trade.entryPrice))")
                Spacer()
                Text(Format.percent(trade.returnPercent))
            }
            .font(.caption.monospacedDigit())
            HStack {
                Text("\(Format.date(trade.exitTime)) @ \(Format.price(trade.exitPrice))")
                Spacer()
                Text("\(trade.exitReason.label) · \(trade.barsHeld) nến")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}
