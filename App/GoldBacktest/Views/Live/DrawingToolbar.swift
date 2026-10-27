import SwiftUI

/// Drawing panel on the left of the chart: the favourite tools, a button for
/// all of them (the "Bản vẽ" sheet), then magnet, stay in drawing mode, lock
/// all, hide all and remove all.
struct DrawingToolbar: View {
    @Binding var activeTool: DrawingTool?
    /// Thước ngắm (crosshair) mode.
    @Binding var crosshair: Bool
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
                Button {
                    activeTool = nil
                    crosshair = false
                } label: { icon("cursorarrow", active: activeTool == nil && !crosshair) }
                    .accessibilityLabel("Con trỏ")
                Button { crosshair.toggle() } label: { icon("plus.viewfinder", active: crosshair) }
                    .accessibilityLabel("Thước ngắm")
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
        HStack(spacing: 0) {
            // Moves the bar (where it was left is kept; a double tap puts it back).
            BarGrip(key: Self.barKey, theme: theme)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    templatesMenu
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
                    Button(action: onEditText) { item { Image(systemName: "textformat") } }
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
                .padding(.trailing, 8)
            }
        }
        .font(.system(size: 15, weight: .medium))
        .foregroundColor(theme.primaryText)
        .frame(height: 44)
        .background(theme.background, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.grid, lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .padding(.horizontal, 8)
    }

    static let barKey = "drawingActions"

    /// The styles saved for this tool (Cài đặt → Mẫu), one tap away; the settings manage them.
    private var templatesMenu: some View {
        let templates = DrawingStyles.templates(for: drawing.tool)
        return Menu {
            if templates.isEmpty {
                Text("Chưa có mẫu cho \(drawing.tool.title)")
            }
            ForEach(templates) { template in
                Button {
                    var d = drawing
                    d.style = template.style
                    onChange(d)
                } label: {
                    Label("\(template.name) · \(String(format: "%gpx", template.style.lineWidth))",
                          systemImage: drawing.style == template.style ? "checkmark" : "circle.fill")
                }
            }
            Divider()
            Button(action: onSettings) { Label(templates.isEmpty ? "Lưu mẫu…" : "Quản lý mẫu…", systemImage: "gearshape") }
        } label: {
            item {
                Image(systemName: templates.isEmpty ? "square.stack" : "square.stack.fill")
                    .foregroundColor(templates.isEmpty ? theme.primaryText : theme.accent)
            }
        }
        .accessibilityLabel("Mẫu đã lưu")
    }

    private func item<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().frame(minWidth: 34, minHeight: 34)
    }
}

/// The grip of a bar on the chart: dragging it moves the bar, which stays where it was left
/// (per bar, kept across launches); a double tap puts it back in its place.
struct BarGrip: View {
    let theme: ChartTheme
    @AppStorage private var x: Double
    @AppStorage private var y: Double
    @State private var start: CGPoint?

    init(key: String, theme: ChartTheme) {
        self.theme = theme
        _x = AppStorage(wrappedValue: 0, "bar.\(key).x")
        _y = AppStorage(wrappedValue: 0, "bar.\(key).y")
    }

    var body: some View {
        Image(systemName: "circle.grid.2x1.fill")
            .rotationEffect(.degrees(90))
            .font(.system(size: 9))
            .foregroundColor(theme.text.opacity(0.7))
            .frame(width: 18, height: 34)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let from = start ?? CGPoint(x: x, y: y)
                        start = from
                        x = from.x + value.translation.width
                        y = from.y + value.translation.height
                    }
                    .onEnded { _ in start = nil }
            )
            .onTapGesture(count: 2) { x = 0; y = 0 }
            .accessibilityLabel("Kéo để di chuyển thanh")
    }
}

extension View {
    /// Offsets a bar by where its `BarGrip` (same key) left it.
    func movableBar(_ key: String) -> some View { modifier(MovableBarOffset(key: key)) }
}

private struct MovableBarOffset: ViewModifier {
    @AppStorage private var x: Double
    @AppStorage private var y: Double

    init(key: String) {
        _x = AppStorage(wrappedValue: 0, "bar.\(key).x")
        _y = AppStorage(wrappedValue: 0, "bar.\(key).y")
    }

    func body(content: Content) -> some View { content.offset(x: x, y: y) }
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
                    Toggle("Khoá (không cho kéo)", isOn: $drawing.locked)
                }

                Section("Văn bản") {
                    TextField(drawing.tool == .text ? "Nội dung" : "Văn bản trên hình vẽ", text: $drawing.text, axis: .vertical)
                        .lineLimit(1...4)
                    Picker("Căn chữ", selection: $drawing.textAlign) {
                        ForEach(TextAlign.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                if drawing.tool == .fibRetracement || drawing.tool == .fibExtension {
                    FibSettingsSection(fib: Binding(get: { drawing.fibSettings }, set: { drawing.fib = $0 }),
                                       tool: drawing.tool)
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
                        Label("Lưu dưới dạng…", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        DrawingStyles.setDefault(drawing.style, for: drawing.tool)
                    } label: {
                        Label("Lưu làm mặc định cho hình mới", systemImage: "checkmark.seal")
                    }
                    Button {
                        var fresh = Drawing(tool: drawing.tool, points: drawing.points)
                        if let style = DrawingStyles.defaultStyle(for: drawing.tool) { fresh.style = style }
                        drawing.style = fresh.style
                        drawing.fib = fresh.fib
                    } label: {
                        Label("Áp dụng mặc định", systemImage: "arrow.uturn.backward")
                    }
                    Button(role: .destructive) {
                        DrawingStyles.setDefault(nil, for: drawing.tool)
                        let fresh = Drawing(tool: drawing.tool, points: drawing.points)
                        drawing.style = fresh.style
                        drawing.fib = nil
                    } label: {
                        Label("Về kiểu gốc của app", systemImage: "arrow.counterclockwise")
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

/// TradingView-like Fibonacci settings: trend line, extend, each level (on/off,
/// value, colour), background, reverse, prices, level values and label side.
struct FibSettingsSection: View {
    @Binding var fib: FibSettings
    let tool: DrawingTool

    var body: some View {
        Section {
            Toggle("Đường xu hướng", isOn: $fib.showTrendLine)
            Picker("Kéo dài", selection: $fib.extend) {
                ForEach(FibSettings.Extend.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            ForEach($fib.levels) { $level in
                HStack(spacing: 10) {
                    Button { level.enabled.toggle() } label: {
                        Image(systemName: level.enabled ? "checkmark.square.fill" : "square")
                            .font(.system(size: 20))
                            .foregroundColor(level.enabled ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                    TextField("Mức", value: $level.value, format: .number.precision(.fractionLength(0...4)))
                        .keyboardType(.numbersAndPunctuation)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundColor(level.enabled ? .primary : .secondary)
                    ColorPicker("", selection: Binding(get: { level.color?.color ?? .gray },
                                                       set: { level.color = RGBAColor($0) }))
                        .labelsHidden()
                        .opacity(level.enabled ? 1 : 0.4)
                }
            }
            .onDelete { fib.levels.remove(atOffsets: $0) }
            Button {
                fib.levels.append(FibLevel(value: (fib.levels.map(\.value).max() ?? 1) + 0.5))
            } label: {
                Label("Thêm mức", systemImage: "plus")
            }
        } header: {
            Text(tool == .fibExtension ? "Các mức mở rộng" : "Các mức Fib")
        } footer: {
            Text(tool == .fibExtension ? "Mức tính từ điểm thứ 3 theo độ dài sóng 1→2." : "1 = điểm đầu, 0 = điểm cuối, số âm = mục tiêu vượt điểm cuối. Vuốt trái để xoá một mức.")
        }
        Section("Hiển thị") {
            Toggle(isOn: Binding(get: { fib.singleColor != nil }, set: { fib.singleColor = $0 ? RGBAColor(Color(red: 0.16, green: 0.38, blue: 1)) : nil })) {
                Text("Sử dụng một màu")
            }
            if fib.singleColor != nil {
                ColorPicker("Màu chung", selection: Binding(get: { fib.singleColor?.color ?? .blue }, set: { fib.singleColor = RGBAColor($0) }))
            }
            Toggle("Hình nền", isOn: $fib.background)
            if fib.background {
                HStack {
                    Text("Độ đậm")
                    Slider(value: $fib.backgroundOpacity, in: 0.03...0.5)
                }
            }
            if tool == .fibRetracement {
                Toggle("Vùng OTE (0.62–0.79)", isOn: $fib.oteZone)
            }
            Toggle("Đảo ngược", isOn: $fib.reverse)
            Toggle("Các mức giá", isOn: $fib.showPrices)
            Toggle("Mức độ (giá trị)", isOn: $fib.showLevels)
            Picker("Nhãn", selection: $fib.labelsLeft) {
                Text("Bên trái").tag(true)
                Text("Bên phải").tag(false)
            }
            .pickerStyle(.segmented)
        }
    }
}
