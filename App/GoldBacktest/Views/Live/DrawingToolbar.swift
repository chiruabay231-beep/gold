import SwiftUI

/// Floating vertical tool bar, like TradingView's drawing panel.
struct DrawingToolbar: View {
    @Binding var activeTool: DrawingTool?
    let theme: ChartTheme
    var onClose: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 4) {
                ForEach(DrawingTool.allCases) { tool in
                    Button {
                        activeTool = activeTool == tool ? nil : tool
                    } label: {
                        Image(systemName: tool.systemImage)
                            .font(.system(size: 17))
                            .frame(width: 40, height: 40)
                            .foregroundColor(activeTool == tool ? .white : theme.primaryText)
                            .background(activeTool == tool ? theme.accent : .clear, in: .rect(cornerRadius: 8))
                    }
                    .accessibilityLabel(tool.title)
                }
                Divider().frame(width: 28)
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
        .frame(maxHeight: 440)
        .background(theme.background, in: .rect(cornerRadius: 12))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
    }
}

/// Actions for the selected drawing: colour, risk/reward, label, delete.
struct DrawingActionsBar: View {
    let drawing: Drawing
    let theme: ChartTheme
    var onChange: (Drawing) -> Void
    var onEditText: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button {
                var d = drawing
                d.colorIndex = (d.colorIndex + 1) % DrawingPalette.colors.count
                onChange(d)
            } label: {
                Circle().fill(drawing.color).frame(width: 20, height: 20)
                    .overlay(Circle().stroke(theme.grid, lineWidth: 1))
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
            if drawing.tool == .text || drawing.tool == .horizontalLine || drawing.tool == .horizontalRay {
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
