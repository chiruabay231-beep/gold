import SwiftUI
import BacktestKit

/// One-click SELL | lot | BUY panel for the top right of the live screen,
/// like MT5's one-click trading.
struct QuickTradePanel: View {
    let price: Double
    let decimals: Int
    @Binding var lots: Double
    var onSell: () -> Void
    var onBuy: () -> Void

    @State private var showLots = false

    var body: some View {
        HStack(spacing: 0) {
            sideButton("SELL", color: Color(red: 0.949, green: 0.212, blue: 0.271), action: onSell)
            Button { showLots = true } label: {
                Text(Self.lotText(lots))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundColor(.primary)
                    .frame(width: 40, height: 34)
                    .background(Color(.systemBackground))
            }
            .popover(isPresented: $showLots) {
                LotPicker(lots: $lots).presentationCompactAdaptation(.popover)
            }
            sideButton("BUY", color: Color(red: 0.161, green: 0.384, blue: 1.0), action: onBuy)
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.gray.opacity(0.3), lineWidth: 1))
        .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
        .fixedSize()
    }

    private func sideButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(title).font(.system(size: 8, weight: .bold))
                Text(CandleChart.format(price, decimals))
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundColor(.white)
            .frame(width: 62, height: 34)
            .background(color)
        }
        .disabled(price <= 0 || lots <= 0)
    }

    static func lotText(_ lots: Double) -> String { String(format: "%.2f", lots) }
}

/// Starts or cancels a limit order placed by dragging its line.
struct LimitToggleButton: View {
    let active: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Lệnh Limit", systemImage: active ? "xmark" : "arrow.up.arrow.down")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(active ? Color.blue : Color(.systemBackground), in: Capsule())
                .foregroundColor(active ? .white : .blue)
                .overlay(Capsule().stroke(Color.blue.opacity(0.5), lineWidth: 1))
        }
        .fixedSize()
    }
}

/// Lot size picker like MT5: presets, quick increments and a stepper.
struct LotPicker: View {
    @Binding var lots: Double

    private static let presets: [Double] = [0.01, 0.02, 0.05, 0.1, 0.2, 0.3, 0.5, 1, 2, 5]

    var body: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(Self.presets, id: \.self) { value in
                    Button { lots = value } label: {
                        Text(String(format: "%g", value))
                            .font(.system(size: 17, weight: value == lots ? .bold : .regular))
                            .foregroundColor(value == lots ? .blue : .primary)
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                }
            }
            HStack {
                ForEach([0.01, 0.1, 0.5], id: \.self) { step in
                    Button("+\(String(format: "%g", step))") { set(lots + step) }
                        .frame(maxWidth: .infinity)
                }
            }
            .font(.system(size: 16))
            Divider()
            HStack {
                Button { set(lots - 0.01) } label: { Image(systemName: "chevron.down").frame(width: 44, height: 32) }
                Spacer()
                Text(QuickTradePanel.lotText(lots)).font(.system(size: 18, weight: .semibold).monospacedDigit())
                Spacer()
                Button { set(lots + 0.01) } label: { Image(systemName: "chevron.up").frame(width: 44, height: 32) }
            }
        }
        .padding(14)
        .frame(width: 250)
    }

    private func set(_ value: Double) {
        lots = min(100, max(0.01, (value * 100).rounded() / 100))
    }
}

/// A limit order being placed by dragging its line: below the price it is a
/// buy limit, above it a sell limit. SL/TP are kept as distances from the entry.
struct LimitDraft: Equatable {
    var entry: Double
    var stopDistance: Double?
    var targetDistance: Double?

    func side(price: Double) -> PaperAccount.Side { entry > price ? .short : .long }

    func stop(price: Double) -> Double? {
        stopDistance.map { side(price: price) == .long ? entry - $0 : entry + $0 }
    }

    func target(price: Double) -> Double? {
        targetDistance.map { side(price: price) == .long ? entry + $0 : entry - $0 }
    }
}

/// Bottom bar while a limit order is being placed: send, SL and TP toggles, cancel.
struct LimitOrderBar: View {
    let title: String
    let isBuy: Bool
    let hasStop: Bool
    let hasTarget: Bool
    var onSend: () -> Void
    var onToggleStop: () -> Void
    var onToggleTarget: () -> Void
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSend) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.right.circle.fill").font(.system(size: 22))
                    Text(title).font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(isBuy ? Color(red: 0.161, green: 0.384, blue: 1.0) : Color(red: 0.949, green: 0.212, blue: 0.271),
                            in: Capsule())
            }
            Spacer(minLength: 4)
            toggle("SL", on: hasStop, color: Color(red: 0.949, green: 0.212, blue: 0.271), action: onToggleStop)
            toggle("TP", on: hasTarget, color: Color(red: 0.031, green: 0.6, blue: 0.506), action: onToggleTarget)
            Button(action: onCancel) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 8)
    }

    private func toggle(_ title: String, on: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 40, height: 40)
                .foregroundColor(on ? .white : color)
                .background(on ? color : .clear, in: Circle())
                .overlay(Circle().stroke(color, lineWidth: 1.5))
        }
    }
}
