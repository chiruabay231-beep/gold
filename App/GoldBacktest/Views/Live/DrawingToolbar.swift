import SwiftUI

/// Drawing panel on the left of the chart: the favourite tools, a button for
/// all of them (the "Bản vẽ" sheet), then magnet, stay in drawing mode, lock
/// all, hide all and remove all.
struct DrawingToolbar: View {
    @Binding var activeTool: DrawingTool?
    /// Snap points to the bar's open/high/low/close.
    @Binding var magnet: Bool
    /// Stay on the tool after placing a drawing.
    @Binding var keepTool: Bool
    @Binding var lockAll: Bool
    @Binding var hideDrawings: Bool
    let theme: ChartTheme
    /// Opens the "Bản vẽ" sheet with every tool.
    var onAllTools: () -> Void = {}
    var onUndo: () -> Void
    var onRemoveAll: () -> Void
    var onClose: () -> Void

    @AppStorage(DrawingFavorites.key) private var favoritesText = DrawingFavorites.defaultText

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 2) {
                Button { activeTool = nil } label: { icon("cursorarrow", active: activeTool == nil) }
                    .accessibilityLabel("Con trỏ")
                separator
                // Favourite tools, then the sheet with all of them.
                ForEach(DrawingFavorites.decode(favoritesText)) { tool in
                    Button { activeTool = activeTool == tool ? nil : tool } label: {
                        icon(tool.systemImage, active: activeTool == tool)
                    }
                    .accessibilityLabel(tool.title)
                }
                if let tool = activeTool, !DrawingFavorites.decode(favoritesText).contains(tool) {
                    Button { activeTool = nil } label: { icon(tool.systemImage, active: true) }
                        .accessibilityLabel(tool.title)
                }
                Button(action: onAllTools) { icon("square.grid.2x2", active: false) }
                    .accessibilityLabel("Tất cả công cụ vẽ")
                separator
                Button { magnet.toggle() } label: { icon("scope", active: magnet) }
                    .accessibilityLabel("Nam châm")
                Button { keepTool.toggle() } label: { icon("pencil.and.outline", active: keepTool) }
                    .accessibilityLabel("Giữ chế độ vẽ")
                Button { lockAll.toggle() } label: { icon(lockAll ? "lock.fill" : "lock.open", active: lockAll) }
                    .accessibilityLabel("Khoá tất cả hình vẽ")
                Button { hideDrawings.toggle() } label: { icon(hideDrawings ? "eye.slash" : "eye", active: hideDrawings) }
                    .accessibilityLabel("Ẩn tất cả hình vẽ")
                Button(action: onUndo) { icon("arrow.uturn.backward", active: false) }
                    .accessibilityLabel("Hoàn tác")
                Button(action: onRemoveAll) { icon("trash", active: false) }
                    .accessibilityLabel("Xoá tất cả hình vẽ")
                separator
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 40, height: 34)
                        .foregroundColor(theme.text)
                }
            }
            .padding(.vertical, 6)
        }
        .frame(width: 52)
        .frame(maxHeight: 560)
        .background(theme.background, in: .rect(cornerRadius: 12))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
    }

    private var separator: some View {
        Divider().frame(width: 28).padding(.vertical, 3)
    }

    private func icon(_ systemName: String, active: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17))
            .frame(width: 40, height: 38)
            .foregroundColor(active ? .white : theme.primaryText)
            .background(active ? theme.accent : .clear, in: .rect(cornerRadius: 8))
    }
}

/// Floating style bar for the selected drawing, like TradingView's:
/// colour, line width, line style, risk/reward, text, lock, clone,
/// settings and delete.
struct DrawingActionsBar: View {
    let drawing: Drawing
    let theme: ChartTheme
    var onChange: (Drawing) -> Void
    var onEditText: () -> Void
    var onClone: () -> Void
    var onSettings: () -> Void
    var onDelete: () -> Void
    /// Sends a long/short position drawing to the demo account.
    var onPlaceOrder: (() -> Void)? = nil

    @State private var showColors = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button { showColors = true } label: {
                    item {
                        Image(systemName: "paintbrush.pointed.fill")
                            .foregroundColor(theme.primaryText)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(drawing.color).frame(height: 3).offset(y: 6)
                            }
                    }
                }
                .popover(isPresented: $showColors) {
                    ColorPalettePicker(color: drawing.color) { color in
                        var d = drawing
                        d.customColor = RGBAColor(color)
                        onChange(d)
                    }
                    .presentationCompactAdaptation(.popover)
                }
                if drawing.tool.isLine {
                    Menu {
                        ForEach([0.5, 1.0, 1.5, 2.0, 3.0, 4.0], id: \.self) { width in
                            Button {
                                var d = drawing
                                d.lineWidth = width
                                onChange(d)
                            } label: {
                                Label(String(format: "%gpx", width), systemImage: drawing.lineWidth == width ? "checkmark" : "line.horizontal.3")
                            }
                        }
                    } label: {
                        item { Text(String(format: "%gpx", drawing.lineWidth)).font(.system(size: 13, weight: .semibold).monospacedDigit()) }
                    }
                    Menu {
                        ForEach(LineStyle.allCases, id: \.self) { style in
                            Button {
                                var d = drawing
                                d.lineStyle = style
                                onChange(d)
                            } label: {
                                Label(style.title, systemImage: drawing.lineStyle == style ? "checkmark" : "minus")
                            }
                        }
                    } label: {
                        item { LineStylePreview(style: drawing.lineStyle, color: theme.primaryText) }
                    }
                }
                if drawing.positionLevels != nil {
                    Button {
                        var d = drawing
                        d.riskReward = max(0.5, d.riskReward - 0.5)
                        onChange(d)
                    } label: { item { Image(systemName: "minus") } }
                    Text("RR \(String(format: "%.1f", drawing.riskReward))")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    Button {
                        var d = drawing
                        d.riskReward = min(50, d.riskReward + 0.5)
                        onChange(d)
                    } label: { item { Image(systemName: "plus") } }
                }
                if drawing.positionLevels != nil, let onPlaceOrder {
                    Button(action: onPlaceOrder) {
                        item { Image(systemName: "paperplane.fill").foregroundColor(theme.accent) }
                    }
                    .accessibilityLabel("Vào lệnh demo")
                }
                if drawing.tool.isLine || drawing.tool == .text {
                    Button(action: onEditText) { item { Image(systemName: "textformat") } }
                }
                Button {
                    var d = drawing
                    d.locked.toggle()
                    onChange(d)
                } label: { item { Image(systemName: drawing.locked ? "lock.fill" : "lock.open") } }
                Button(action: onClone) { item { Image(systemName: "plus.square.on.square") } }
                Button(action: onSettings) { item { Image(systemName: "gearshape") } }
                Button(role: .destructive, action: onDelete) {
                    item { Image(systemName: "trash").foregroundColor(theme.down) }
                }
            }
            .padding(.horizontal, 8)
        }
        .font(.system(size: 15, weight: .medium))
        .foregroundColor(theme.primaryText)
        .frame(height: 44)
        .background(theme.background, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.grid, lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .padding(.horizontal, 8)
    }

    private func item<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().frame(minWidth: 34, minHeight: 34)
    }
}

/// A short line drawn in a line style, for the style menu.
struct LineStylePreview: View {
    let style: LineStyle
    let color: Color

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 2, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width - 2, y: size.height / 2))
            context.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: 2, lineCap: style == .dotted ? .round : .butt, dash: style.dash))
        }
        .frame(width: 26, height: 14)
    }
}

/// TradingView-like colour grid plus the system colour picker.
struct ColorPalettePicker: View {
    @State var color: Color
    var onPick: (Color) -> Void

    private static let grid: [Color] = DrawingPalette.colors + CandleColors.swatches

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 8), count: 6), spacing: 8) {
                ForEach(Self.grid.indices, id: \.self) { index in
                    Button {
                        color = Self.grid[index]
                        onPick(Self.grid[index])
                    } label: {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Self.grid[index])
                            .frame(width: 28, height: 28)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            ColorPicker("Màu khác…", selection: Binding(get: { color }, set: { color = $0; onPick($0) }),
                        supportsOpacity: true)
                .font(.footnote)
        }
        .padding(14)
        .frame(width: 240)
    }
}

/// Settings of one drawing (gear button): style, label and exact prices.
struct DrawingSettingsView: View {
    @State var drawing: Drawing
    let decimals: Int
    let sizing: PositionSizing?
    var onSave: (Drawing) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var templates: [DrawingStyles.Template] = []
    @State private var naming = false
    @State private var templateName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Kiểu") {
                    ColorPicker("Màu", selection: Binding(get: { drawing.color },
                                                          set: { drawing.customColor = RGBAColor($0) }),
                                supportsOpacity: true)
                    if drawing.tool.isLine {
                        Picker("Độ dày", selection: $drawing.lineWidth) {
                            ForEach([0.5, 1.0, 1.5, 2.0, 3.0, 4.0], id: \.self) { Text(String(format: "%gpx", $0)).tag($0) }
                        }
                        Picker("Nét", selection: $drawing.lineStyle) {
                            ForEach(LineStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                    }
                    if drawing.tool.isLine || drawing.tool == .text {
                        TextField("Nhãn / ghi chú", text: $drawing.text)
                    }
                    Toggle("Khoá (không cho kéo)", isOn: $drawing.locked)
                }

                Section {
                    ForEach(templates) { template in
                        Button {
                            drawing.style = template.style
                        } label: {
                            HStack {
                                Circle().fill(template.style.customColor?.color
                                              ?? DrawingPalette.colors[template.style.colorIndex % DrawingPalette.colors.count])
                                    .frame(width: 14, height: 14)
                                Text(template.name).foregroundColor(.primary)
                                Spacer()
                                Text(String(format: "%gpx · %@", template.style.lineWidth, template.style.lineStyle.title))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { DrawingStyles.deleteTemplate(templates[index], for: drawing.tool) }
                        templates = DrawingStyles.templates(for: drawing.tool)
                    }
                    Button {
                        templateName = ""
                        naming = true
                    } label: {
                        Label("Lưu kiểu này thành mẫu…", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        DrawingStyles.setDefault(drawing.style, for: drawing.tool)
                    } label: {
                        Label("Dùng kiểu này cho hình mới", systemImage: "checkmark.seal")
                    }
                    Button(role: .destructive) {
                        DrawingStyles.setDefault(nil, for: drawing.tool)
                    } label: {
                        Label("Về kiểu gốc cho hình mới", systemImage: "arrow.counterclockwise")
                    }
                } header: {
                    Text("Mẫu kiểu \(drawing.tool.title)")
                } footer: {
                    Text("Hình mới của công cụ này tự dùng kiểu bạn chỉnh lần gần nhất. Lưu mẫu để có nhiều kiểu (vd: kháng cự đỏ 0.5px, hỗ trợ xanh), chạm để áp dụng, vuốt trái để xoá.")
                }

                if drawing.positionLevels != nil {
                    positionSection
                } else {
                    Section("Toạ độ") {
                        ForEach(drawing.points.indices, id: \.self) { index in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Điểm \(index + 1)")
                                    Text(drawing.points[index].time.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                priceField($drawing.points[index].price)
                            }
                        }
                    }
                }
            }
            .navigationTitle(drawing.tool.title)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { templates = DrawingStyles.templates(for: drawing.tool) }
            .alert("Lưu mẫu kiểu", isPresented: $naming) {
                TextField("Tên mẫu, vd: Kháng cự", text: $templateName)
                Button("Huỷ", role: .cancel) {}
                Button("Lưu") {
                    let name = templateName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    DrawingStyles.saveTemplate(name: name, style: drawing.style, for: drawing.tool)
                    templates = DrawingStyles.templates(for: drawing.tool)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy bỏ") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ok") {
                        onSave(drawing)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private var positionSection: some View {
        let levels = drawing.positionLevels!
        let isLong = drawing.tool == .longPosition
        Section("Lệnh") {
            HStack { Text("Giá vào"); Spacer(); priceField($drawing.points[0].price) }
            HStack { Text("Cắt lỗ (SL)"); Spacer(); priceField($drawing.points[1].price) }
            HStack {
                Text("Chốt lời (TP)")
                Spacer()
                priceField(Binding(get: { levels.target }, set: { target in
                    let risk = abs(levels.entry - levels.stop)
                    let reward = isLong ? target - levels.entry : levels.entry - target
                    if risk > 0, reward > 0 { drawing.riskReward = (reward / risk * 100).rounded() / 100 }
                }))
            }
            Stepper("RR \(String(format: "%.2f", drawing.riskReward))", value: $drawing.riskReward, in: 0.25...50, step: 0.25)
        }
        Section("Khối lượng") {
            let risk = abs(levels.entry - levels.stop)
            LabeledContent("Khoảng SL", value: CandleChart.format(risk, decimals))
            LabeledContent("Khoảng TP", value: CandleChart.format(abs(levels.target - levels.entry), decimals))
            if let sizing, let lots = sizing.lots(entry: levels.entry, stop: levels.stop) {
                LabeledContent("Số lot", value: String(format: "%.2f", lots))
                LabeledContent("Rủi ro", value: String(format: "$%.2f", sizing.balance * sizing.riskPercent / 100))
                LabeledContent("Lợi nhuận dự kiến",
                               value: String(format: "$%.2f", sizing.balance * sizing.riskPercent / 100 * drawing.riskReward))
            } else {
                Text("Nhập vốn tài khoản trong ⋯ → Cài đặt biểu đồ để tính số lot.")
                    .font(.footnote).foregroundColor(.secondary)
            }
        }
    }

    private func priceField(_ value: Binding<Double>) -> some View {
        TextField("Giá", value: value, format: .number.precision(.fractionLength(decimals)))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 140)
    }
}
