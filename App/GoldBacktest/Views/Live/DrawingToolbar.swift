import SwiftUI

/// Floating vertical tool bar, like TradingView's drawing panel.
struct DrawingToolbar: View {
    @Binding var activeTool: DrawingTool?
    /// Snap points to the bar's open/high/low/close.
    @Binding var magnet: Bool
    /// Stay on the tool after placing a drawing.
    @Binding var keepTool: Bool
    @Binding var hideDrawings: Bool
    let theme: ChartTheme
    var onClose: () -> Void

    private static let groups: [[DrawingTool]] = [
        [.trendLine, .trendRay, .horizontalLine, .horizontalRay, .verticalLine],
        [.fibRetracement, .rectangle, .priceRange],
        [.longPosition, .shortPosition, .text],
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 2) {
                ForEach(Self.groups.indices, id: \.self) { group in
                    ForEach(Self.groups[group]) { tool in
                        Button {
                            activeTool = activeTool == tool ? nil : tool
                        } label: {
                            icon(tool.systemImage, active: activeTool == tool)
                        }
                        .accessibilityLabel(tool.title)
                    }
                    Divider().frame(width: 28).padding(.vertical, 3)
                }
                Button { magnet.toggle() } label: { icon("scope", active: magnet) }
                    .accessibilityLabel("Nam châm: bám giá mở/cao/thấp/đóng")
                Button { keepTool.toggle() } label: { icon("repeat", active: keepTool) }
                    .accessibilityLabel("Giữ công cụ sau khi vẽ")
                Button { hideDrawings.toggle() } label: { icon(hideDrawings ? "eye.slash" : "eye", active: hideDrawings) }
                    .accessibilityLabel("Ẩn hình vẽ")
                Divider().frame(width: 28).padding(.vertical, 3)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 40, height: 36)
                        .foregroundColor(theme.text)
                }
            }
            .padding(.vertical, 6)
        }
        .frame(width: 52)
        .frame(maxHeight: 520)
        .background(theme.background, in: .rect(cornerRadius: 12))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
    }

    private func icon(_ systemName: String, active: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17))
            .frame(width: 40, height: 38)
            .foregroundColor(active ? .white : theme.primaryText)
            .background(active ? theme.accent : .clear, in: .rect(cornerRadius: 8))
    }
}

/// Actions for the selected drawing: colour, line style, risk/reward, label, delete.
struct DrawingActionsBar: View {
    let drawing: Drawing
    let theme: ChartTheme
    var onChange: (Drawing) -> Void
    var onEditText: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button {
                var d = drawing
                d.colorIndex = (d.colorIndex + 1) % DrawingPalette.colors.count
                onChange(d)
            } label: {
                Circle().fill(drawing.color).frame(width: 20, height: 20)
                    .overlay(Circle().stroke(theme.grid, lineWidth: 1))
            }
            if drawing.tool.isLine {
                Button {
                    var d = drawing
                    d.lineWidth = d.lineWidth >= 3 ? 1 : d.lineWidth + 1
                    onChange(d)
                } label: {
                    Text("\(Int(drawing.lineWidth.rounded(.down)))px")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                }
                Button {
                    var d = drawing
                    d.dashed.toggle()
                    onChange(d)
                } label: {
                    Text(drawing.dashed ? "- - -" : "——")
                        .font(.system(size: 13, weight: .bold))
                }
            }
            if drawing.positionLevels != nil {
                HStack(spacing: 6) {
                    Button {
                        var d = drawing
                        d.riskReward = max(0.5, d.riskReward - 0.5)
                        onChange(d)
                    } label: { Image(systemName: "minus") }
                    Text("RR \(String(format: "%.1f", drawing.riskReward))")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    Button {
                        var d = drawing
                        d.riskReward = min(20, d.riskReward + 0.5)
                        onChange(d)
                    } label: { Image(systemName: "plus") }
                }
            }
            if drawing.tool.isLine || drawing.tool == .text {
                Button(action: onEditText) { Image(systemName: "character.cursor.ibeam") }
            }
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
        }
        .font(.system(size: 15, weight: .medium))
        .foregroundColor(theme.primaryText)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(theme.background, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
    }
}
