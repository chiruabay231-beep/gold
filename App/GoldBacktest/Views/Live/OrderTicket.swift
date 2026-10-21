import SwiftUI
import BacktestKit

/// The order being prepared in the order sheet; its entry, SL and TP are
/// drawn on the chart and can be dragged there.
struct OrderTicket: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case market, limit, stop
        var id: String { rawValue }

        var title: String {
            switch self {
            case .market: return "Thị trường"
            case .limit: return "Limit"
            case .stop: return "Stop"
            }
        }
    }

    var side: PaperAccount.Side
    var kind: Kind
    /// Price of a pending order (unused for market orders).
    var entry: Double
    var stop: Double?
    var target: Double?

    var isPending: Bool { kind != .market }

    /// "Sell Limit", "Buy Stop", "Buy"…
    var name: String {
        let side = self.side == .long ? "Buy" : "Sell"
        switch kind {
        case .market: return side
        case .limit: return side + " Limit"
        case .stop: return side + " Stop"
        }
    }

    /// Where the order opens: the pending price, or the ask for a buy and the bid for a sell.
    func openPrice(bid: Double, ask: Double) -> Double {
        isPending ? entry : (side == .long ? ask : bid)
    }

    /// A new ticket with a sensible entry for the side and kind, keeping SL/TP distances.
    static func make(side: PaperAccount.Side, kind: Kind, bid: Double, ask: Double, distance: Double,
                     stopDistance: Double?, targetDistance: Double?) -> OrderTicket {
        let entry: Double
        switch (kind, side) {
        case (.market, .long): entry = ask
        case (.market, .short): entry = bid
        case (.limit, .long): entry = bid - distance * 3       // buy the dip
        case (.limit, .short): entry = ask + distance * 3      // sell the rally
        case (.stop, .long): entry = ask + distance * 3        // buy the breakout
        case (.stop, .short): entry = bid - distance * 3       // sell the breakdown
        }
        return OrderTicket(side: side, kind: kind, entry: entry,
                           stop: stopDistance.map { entry - side.sign * $0 },
                           target: targetDistance.map { entry + side.sign * $0 })
    }

    /// Moves a pending order's entry. A limit or stop takes the side that fits where it
    /// now sits (under the price: Buy Limit / Sell Stop, over it: Sell Limit / Buy Stop);
    /// SL and TP keep their distances and turn over with the side.
    mutating func move(to price: Double, bid: Double, ask: Double) {
        var stopOffset = stop.map { $0 - entry }
        var targetOffset = target.map { $0 - entry }
        entry = price
        if isPending, bid > 0 {
            var newSide = side
            if price < bid { newSide = kind == .limit ? .long : .short }
            if price > ask { newSide = kind == .limit ? .short : .long }
            if newSide != side {
                side = newSide
                stopOffset = stopOffset.map { -$0 }
                targetOffset = targetOffset.map { -$0 }
            }
        }
        stop = stopOffset.map { entry + $0 }
        target = targetOffset.map { entry + $0 }
    }

    /// Why the order can't be sent as it is, if it can't.
    func problem(bid: Double, ask: Double) -> String? {
        switch (kind, side) {
        case (.limit, .long) where entry >= ask: return "Buy Limit phải thấp hơn giá Ask"
        case (.limit, .short) where entry <= bid: return "Sell Limit phải cao hơn giá Bid"
        case (.stop, .long) where entry <= ask: return "Buy Stop phải cao hơn giá Ask"
        case (.stop, .short) where entry >= bid: return "Sell Stop phải thấp hơn giá Bid"
        default: break
        }
        let open = openPrice(bid: bid, ask: ask)
        if let stop, (stop - open) * side.sign >= 0 {
            return side == .long ? "SL của lệnh Mua phải thấp hơn giá vào" : "SL của lệnh Bán phải cao hơn giá vào"
        }
        if let target, (target - open) * side.sign <= 0 {
            return side == .long ? "TP của lệnh Mua phải cao hơn giá vào" : "TP của lệnh Bán phải thấp hơn giá vào"
        }
        return nil
    }
}

/// Price split like broker apps: "4146." small, "67" big, last digit raised.
struct BigPrice: View {
    let price: Double
    let decimals: Int
    var size: CGFloat = 26

    var body: some View {
        let text = CandleChart.format(price, decimals)
        let raised = decimals >= 3 ? String(text.suffix(1)) : ""
        let main = decimals >= 3 ? String(text.dropLast()) : text
        let big = String(main.suffix(2))
        let small = String(main.dropLast(2))
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(small).font(.system(size: size * 0.6, weight: .semibold))
            Text(big).font(.system(size: size, weight: .bold))
            if !raised.isEmpty {
                Text(raised).font(.system(size: size * 0.45, weight: .semibold)).baselineOffset(size * 0.45)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// One-click bar under the chart, like broker apps: SELL at the bid, the
/// lot size, BUY at the ask. Holding SELL or BUY opens the order sheet.
struct TradeBar: View {
    let bid: Double
    let ask: Double
    let decimals: Int
    @Binding var lots: Double
    var onSell: () -> Void
    var onBuy: () -> Void
    var onTicket: (PaperAccount.Side) -> Void

    @State private var showLots = false

    static let sellColor = Color(red: 0.92, green: 0.27, blue: 0.24)
    static let buyColor = Color(red: 0.16, green: 0.45, blue: 0.95)

    var body: some View {
        HStack(spacing: 8) {
            side("SELL", price: bid, color: Self.sellColor, alignment: .leading, action: onSell) { onTicket(.short) }
            VStack(spacing: 1) {
                HStack(spacing: 2) {
                    Button { set(lots - 0.01) } label: { Image(systemName: "minus").frame(width: 24, height: 24) }
                    Button { showLots = true } label: {
                        Text(QuickTradePanel.lotText(lots))
                            .font(.system(size: 15, weight: .semibold).monospacedDigit())
                            .foregroundColor(.primary)
                            .frame(minWidth: 38)
                    }
                    .popover(isPresented: $showLots) {
                        LotPicker(lots: $lots).presentationCompactAdaptation(.popover)
                    }
                    Button { set(lots + 0.01) } label: { Image(systemName: "plus").frame(width: 24, height: 24) }
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                Text("Spread \(CandleChart.format(max(0, ask - bid), decimals))")
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)
            .frame(height: 44)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            side("BUY", price: ask, color: Self.buyColor, alignment: .trailing, action: onBuy) { onTicket(.long) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(.systemBackground))
    }

    private func side(_ title: String, price: Double, color: Color, alignment: HorizontalAlignment,
                      action: @escaping () -> Void, hold: @escaping () -> Void) -> some View {
        VStack(alignment: alignment, spacing: -1) {
            Text(title).font(.system(size: 9, weight: .bold)).opacity(0.85)
            BigPrice(price: price, decimals: decimals, size: 19)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44, alignment: alignment == .leading ? .leading : .trailing)
        .background(color, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { if price > 0 { action() } }
        .onLongPressGesture(minimumDuration: 0.4) { hold() }
    }

    private func set(_ value: Double) {
        lots = min(100, max(0.01, (value * 100).rounded() / 100))
    }
}

/// The order sheet: buy or sell, market / limit / stop, price, lots, SL, TP.
/// The chart stays usable behind it, and its lines can be dragged there.
struct OrderTicketSheet: View {
    @Binding var ticket: OrderTicket?
    @Binding var lots: Double
    let bid: Double
    let ask: Double
    let decimals: Int
    let contractSize: Double
    /// Typical bar range, used for default distances and the +/- step.
    let distance: Double
    /// Where the order goes ("Tài khoản demo", "Exness #123 · THẬT").
    let accountLabel: String
    /// Low sheet: one row like MT5 (order button, SL, TP); pull up for everything.
    var compact = false
    var onExpand: () -> Void = {}
    var onSubmit: () -> Void

    var body: some View {
        if let current = ticket {
            if compact {
                compactRow(current)
            } else {
                content(current)
            }
        }
    }

    /// "→ Buy Limit 0.10" · SL · TP · ⌃ — the side follows where the entry line is dragged.
    private func compactRow(_ t: OrderTicket) -> some View {
        let problem = t.problem(bid: bid, ask: ask)
        let color = t.side == .long ? TradeBar.buyColor : TradeBar.sellColor
        return VStack(spacing: 6) {
            HStack(spacing: 10) {
                HStack(spacing: 0) {
                    Button(action: onSubmit) {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(.white.opacity(0.2)))
                            Text(t.name)
                                .font(.system(size: 17, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Spacer(minLength: 4)
                        }
                        .padding(.leading, 6)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(problem != nil || bid <= 0)
                    Menu {
                        ForEach([0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2], id: \.self) { value in
                            Button(String(format: "%g lot", value)) { lots = value }
                        }
                    } label: {
                        Text(QuickTradePanel.lotText(lots))
                            .font(.system(size: 16, weight: .semibold).monospacedDigit())
                            .padding(.horizontal, 12)
                            .frame(maxHeight: .infinity)
                            .background(Capsule().fill(.black.opacity(0.15)))
                    }
                    .padding(4)
                }
                .foregroundColor(.white)
                .frame(height: 50)
                .background(Capsule().fill(color.opacity(problem == nil ? 1 : 0.45)))
                levelToggle("SL", value: t.stop, color: TradeBar.sellColor, current: t, isStop: true)
                levelToggle("TP", value: t.target, color: .green, current: t, isStop: false)
                Button(action: onExpand) {
                    Image(systemName: "chevron.up.circle")
                        .font(.system(size: 26))
                        .foregroundColor(TradeBar.buyColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mở bảng lệnh đầy đủ (Stop, giá, SL/TP)")
            }
            Text(problem ?? "Kéo đường lệnh trên biểu đồ: dưới giá = Buy Limit, trên giá = Sell Limit")
                .font(.caption2)
                .foregroundColor(problem == nil ? .secondary : .orange)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 14)
        .padding(.top, 18)
    }

    /// The round SL / TP button: on puts the level at a default distance, off removes it.
    private func levelToggle(_ title: String, value: Double?, color: Color, current: OrderTicket, isStop: Bool) -> some View {
        Button {
            guard var updated = ticket else { return }
            let open = current.openPrice(bid: bid, ask: ask)
            let distance = self.distance * 3
            let price: Double? = value == nil
                ? open + current.side.sign * (isStop ? -distance : distance * AutoStops.riskReward) : nil
            if isStop { updated.stop = price } else { updated.target = price }
            ticket = updated
        } label: {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundColor(value == nil ? color : .white)
                .background(Circle().fill(value == nil ? Color.clear : color))
                .overlay(Circle().stroke(color, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private var step: Double {
        let raw = max(distance / 4, pow(10, -Double(decimals)))
        let magnitude = pow(10, floor(log10(raw)))
        for factor in [1.0, 2.0, 5.0, 10.0] where raw <= magnitude * factor { return magnitude * factor }
        return magnitude * 10
    }

    private func content(_ t: OrderTicket) -> some View {
        let problem = t.problem(bid: bid, ask: ask)
        let color = t.side == .long ? TradeBar.buyColor : TradeBar.sellColor
        return ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Text(accountLabel).font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text("Spread \(CandleChart.format(max(0, ask - bid), decimals))")
                        .font(.caption.monospacedDigit()).foregroundColor(.secondary)
                }
                HStack(spacing: 8) {
                    sideButton(.short, price: bid, current: t)
                    sideButton(.long, price: ask, current: t)
                }
                Picker("Loại lệnh", selection: Binding(get: { t.kind }, set: { retarget(side: t.side, kind: $0) })) {
                    ForEach(OrderTicket.Kind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                if t.isPending {
                    stepperRow("Giá", value: Binding(get: { ticket?.entry ?? t.entry }, set: { new in
                        // SL and TP move with the entry; the side follows the price.
                        guard var updated = ticket else { return }
                        updated.move(to: new, bid: bid, ask: ask)
                        ticket = updated
                    }), step: step, color: color)
                }
                lotRow
                levelRow("SL", value: t.stop, color: TradeBar.sellColor, current: t, isStop: true)
                levelRow("TP", value: t.target, color: Color.green, current: t, isStop: false)

                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundColor(.orange)
                }
                Button(action: onSubmit) {
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                        Text("\(t.name)  \(QuickTradePanel.lotText(lots))")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundColor(.white)
                    .background(color.opacity(problem == nil ? 1 : 0.4), in: Capsule())
                }
                .disabled(problem != nil || bid <= 0)
            }
            .padding(16)
        }
    }

    private func sideButton(_ side: PaperAccount.Side, price: Double, current: OrderTicket) -> some View {
        let selected = current.side == side
        let color = side == .long ? TradeBar.buyColor : TradeBar.sellColor
        return Button { retarget(side: side, kind: current.kind) } label: {
            VStack(alignment: side == .long ? .trailing : .leading, spacing: 0) {
                Text(side == .long ? "MUA" : "BÁN").font(.system(size: 11, weight: .bold))
                BigPrice(price: price, decimals: decimals, size: 22)
            }
            .frame(maxWidth: .infinity, alignment: side == .long ? .trailing : .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundColor(selected ? .white : color)
            .background(selected ? color : color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var lotRow: some View {
        HStack {
            Text("Khối lượng").font(.subheadline)
            Spacer()
            Button { lots = max(0.01, ((lots - 0.01) * 100).rounded() / 100) } label: { Image(systemName: "minus") }
                .buttonStyle(.bordered)
            Text(QuickTradePanel.lotText(lots))
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                .frame(minWidth: 56)
            Button { lots = min(100, ((lots + 0.01) * 100).rounded() / 100) } label: { Image(systemName: "plus") }
                .buttonStyle(.bordered)
            Menu {
                ForEach([0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2], id: \.self) { value in
                    Button(String(format: "%g lot", value)) { lots = value }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private func stepperRow(_ title: String, value: Binding<Double>, step: Double, color: Color) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            Button { value.wrappedValue -= step } label: { Image(systemName: "minus") }
                .buttonStyle(.bordered)
            TextField(title, value: value, format: .number.precision(.fractionLength(decimals)).grouping(.never))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                .foregroundColor(color)
                .frame(width: 110)
            Button { value.wrappedValue += step } label: { Image(systemName: "plus") }
                .buttonStyle(.bordered)
        }
    }

    /// SL or TP: a round toggle like broker apps, then its price and money.
    private func levelRow(_ title: String, value: Double?, color: Color, current: OrderTicket, isStop: Bool) -> some View {
        let open = current.openPrice(bid: bid, ask: ask)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    guard var updated = ticket else { return }
                    let distance = self.distance * 3
                    let price: Double? = value == nil
                        ? open + current.side.sign * (isStop ? -distance : distance * AutoStops.riskReward) : nil
                    if isStop { updated.stop = price } else { updated.target = price }
                    ticket = updated
                } label: {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 40, height: 40)
                        .foregroundColor(value == nil ? color : .white)
                        .background(Circle().fill(value == nil ? Color.clear : color))
                        .overlay(Circle().stroke(color, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                if let value {
                    let money = (value - open) * current.side.sign * lots * contractSize
                    Text(String(format: "%+.2f USD", money))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(money >= 0 ? .green : .red)
                    Spacer()
                    Button {
                        guard var updated = ticket else { return }
                        if isStop { updated.stop = value - step } else { updated.target = value - step }
                        ticket = updated
                    } label: { Image(systemName: "minus") }
                        .buttonStyle(.bordered)
                    TextField(title, value: Binding(get: { value }, set: { new in
                        guard var updated = ticket else { return }
                        if isStop { updated.stop = new } else { updated.target = new }
                        ticket = updated
                    }), format: .number.precision(.fractionLength(decimals)).grouping(.never))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .frame(width: 96)
                    Button {
                        guard var updated = ticket else { return }
                        if isStop { updated.stop = value + step } else { updated.target = value + step }
                        ticket = updated
                    } label: { Image(systemName: "plus") }
                        .buttonStyle(.bordered)
                } else {
                    Text(isStop ? "Không cắt lỗ" : "Không chốt lời").font(.caption).foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
    }

    /// Switching side or kind puts the entry where that order makes sense, keeping SL/TP distances.
    private func retarget(side: PaperAccount.Side, kind: OrderTicket.Kind) {
        guard let current = ticket else { return }
        let open = current.openPrice(bid: bid, ask: ask)
        ticket = OrderTicket.make(side: side, kind: kind, bid: bid, ask: ask, distance: distance,
                                  stopDistance: current.stop.map { abs(open - $0) },
                                  targetDistance: current.target.map { abs(open - $0) })
    }
}
