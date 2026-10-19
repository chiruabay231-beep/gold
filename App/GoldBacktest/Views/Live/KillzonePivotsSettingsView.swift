import SwiftUI
import BacktestKit

/// Inputs of "ICT Killzones + Pivots [TFO]", grouped like the indicator's
/// settings on TradingView.
struct KillzonePivotsSettingsView: View {
    @Binding var json: String
    @Environment(\.dismiss) private var dismiss
    @State private var settings = KillzonePivotsSettings()

    private static let zones: [(id: String, title: String)] = [
        ("America/New_York", "New York (mặc định ICT)"),
        ("UTC", "UTC"),
        ("Asia/Ho_Chi_Minh", "(UTC+7) Hà Nội"),
        ("Europe/London", "London"),
    ]
    private static let limits: [Double] = [1, 5, 15, 30, 60, 240]

    var body: some View {
        NavigationStack {
            Form {
                general
                killzones
                fvgSection
                structureSection
                macros
                boxes
                pivots
                opens
                timestamps
                cutoff
                periods
                other
                Section {
                    Button("Đặt lại mặc định", role: .destructive) { settings = KillzonePivotsSettings() }
                }
            }
            .navigationTitle("ICT Killzones + Pivots")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy bỏ") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ok") {
                        json = settings.json
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear { settings = KillzonePivotsSettings.decode(json) }
    }

    // MARK: - Sections

    private var general: some View {
        Section {
            Picker("Múi giờ", selection: $settings.config.timeZoneID) {
                ForEach(Self.zones, id: \.id) { Text($0.title).tag($0.id) }
            }
            Picker("Chỉ vẽ trên khung ≤", selection: $settings.config.timeframeLimitMinutes) {
                ForEach(Self.limits, id: \.self) { minutes in
                    Text(minutes >= 60 ? "\(Int(minutes / 60))h" : "\(Int(minutes))m").tag(minutes)
                }
            }
            Stepper("Số ngày hiển thị: \(settings.config.maxDays)", value: $settings.config.maxDays, in: 1...20)
        } header: {
            Text("Chung")
        } footer: {
            Text("Giờ các phiên nhập theo múi giờ ở trên (ICT dùng giờ New York); dòng \"VN\" là giờ Việt Nam tương ứng hôm nay. Trục thời gian của biểu đồ theo múi giờ trong Cài đặt biểu đồ. Phiên chỉ vẽ trên khung ≤ giới hạn ở trên, và cần màu khác màu nền biểu đồ.")
        }
    }

    private var killzones: some View {
        Section("Killzones") {
            ForEach(settings.config.sessions.indices, id: \.self) { index in
                DisclosureGroup {
                    TextField("Tên", text: $settings.config.sessions[index].name)
                    timeRow("Bắt đầu", hour: $settings.config.sessions[index].start)
                    timeRow("Kết thúc", hour: $settings.config.sessions[index].end)
                    HStack {
                        Text("Nhãn đỉnh / đáy")
                        Spacer()
                        TextField("H", text: $settings.config.sessions[index].highLabel)
                            .multilineTextAlignment(.trailing).frame(maxWidth: 80)
                        TextField("L", text: $settings.config.sessions[index].lowLabel)
                            .multilineTextAlignment(.trailing).frame(maxWidth: 80)
                    }
                    colorRow("Màu", color: $settings.sessionColors[index])
                } label: {
                    HStack {
                        Toggle(isOn: $settings.config.sessions[index].enabled) { EmptyView() }
                            .labelsHidden()
                        Circle().fill(settings.sessionColor(index)).frame(width: 10, height: 10)
                        Text(settings.config.sessions[index].name)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(Self.clock(settings.config.sessions[index].start)) – \(Self.clock(settings.config.sessions[index].end))")
                                .font(.footnote.monospacedDigit())
                                .foregroundColor(.secondary)
                            if let vn = Self.vietnamRange(settings.config.sessions[index].start, settings.config.sessions[index].end,
                                                          zoneID: settings.config.timeZoneID) {
                                Text("VN \(vn)").font(.caption2.monospacedDigit()).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var fvgSection: some View {
        Section {
            Toggle("Hiện FVG", isOn: $settings.config.showFVG)
            if settings.config.showFVG {
                Picker("Chỉ hiện trên khung ≥", selection: $settings.config.fvgMinTimeframeMinutes) {
                    ForEach([1.0, 5.0, 15.0, 30.0, 60.0, 240.0], id: \.self) { minutes in
                        Text(minutes >= 60 ? "H\(Int(minutes / 60))" : "M\(Int(minutes))").tag(minutes)
                    }
                }
                Stepper("Dài \(settings.config.fvgBoxBars) cây nến", value: $settings.config.fvgBoxBars, in: 1...30)
                Toggle("Đường giữa 50%", isOn: $settings.config.fvgMidline)
                Toggle("Ẩn FVG đã bị lấp", isOn: $settings.config.fvgHideFilled)
                Stepper("Lọc FVG nhỏ: \(String(format: "%.1f", settings.config.fvgMinSize)) × biên độ nến",
                        value: $settings.config.fvgMinSize, in: 0...2, step: 0.1)
                Stepper("Giữ \(settings.config.fvgCount) FVG gần nhất", value: $settings.config.fvgCount, in: 5...200, step: 5)
                colorRow("Màu FVG tăng", color: $settings.fvgBullColor)
                colorRow("Màu FVG giảm", color: $settings.fvgBearColor)
                HStack {
                    Text("Độ đậm")
                    Slider(value: $settings.fvgOpacity, in: 0.05...0.6)
                }
            }
        } header: {
            Text("FVG (Fair Value Gap)")
        } footer: {
            Text("Khoảng trống giữa nến 1 và nến 3. Hộp chỉ kẻ ngang qua các nến tạo FVG; FVG đã bị lấp được vẽ mờ hơn.")
        }
    }

    private var structureSection: some View {
        Section {
            Toggle("Hiện MSS (đổi cấu trúc)", isOn: $settings.config.showMSS)
            Toggle("Hiện BOS (phá cấu trúc cùng xu hướng)", isOn: $settings.config.showBOS)
            Stepper("Swing: \(settings.config.swingLength) nến mỗi bên", value: $settings.config.swingLength, in: 1...20)
            Stepper("Giữ \(settings.config.structureCount) lần phá gần nhất", value: $settings.config.structureCount, in: 2...100, step: 2)
            colorRow("Màu tăng", color: $settings.mssBullColor)
            colorRow("Màu giảm", color: $settings.mssBearColor)
        } header: {
            Text("Cấu trúc thị trường")
        } footer: {
            Text("Đường ngang từ đỉnh/đáy swing tới cây nến đóng cửa phá qua. MSS: phá ngược xu hướng trước đó (nét liền); BOS: phá cùng xu hướng (nét đứt).")
        }
    }

    private var macros: some View {
        Section {
            Toggle("Hiện macros", isOn: $settings.config.showMacros)
            if settings.config.showMacros {
                Picker("Chỉ vẽ trên khung ≤", selection: $settings.config.macroTimeframeLimitMinutes) {
                    ForEach([1.0, 5.0, 15.0, 30.0], id: \.self) { Text("\(Int($0))m").tag($0) }
                }
                Picker("Nhãn hộp", selection: $settings.config.macroTimeLabels) {
                    Text("Giờ (08:50–09:10)").tag(true)
                    Text("Tên macro").tag(false)
                }
                colorRow("Màu", color: $settings.macroColor)
                ForEach(settings.config.macros.indices, id: \.self) { index in
                    DisclosureGroup {
                        TextField("Tên", text: $settings.config.macros[index].name)
                        timeRow("Bắt đầu", hour: $settings.config.macros[index].start)
                        timeRow("Kết thúc", hour: $settings.config.macros[index].end)
                    } label: {
                        HStack {
                            Toggle(isOn: $settings.config.macros[index].enabled) { EmptyView() }.labelsHidden()
                            Text(settings.config.macros[index].name)
                            Spacer()
                            Text("\(Self.clock(settings.config.macros[index].start)) – \(Self.clock(settings.config.macros[index].end))")
                                .font(.footnote.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete { settings.config.macros.remove(atOffsets: $0) }
                Button {
                    settings.config.macros.append(KillzonePivots.Macro(name: "Macro \(settings.config.macros.count + 1)",
                                                                       start: 9, end: 9.5))
                } label: {
                    Label("Thêm macro", systemImage: "plus")
                }
            }
        } header: {
            Text("ICT Macros")
        } footer: {
            Text("Các khung giờ ngắn (thường 20 phút) mà ICT cho là thuật toán hay tạo cú quét thanh khoản hoặc lấp FVG. Vuốt sang trái để xoá một macro.")
        }
    }

    private var boxes: some View {
        Section("Hộp phiên") {
            Toggle("Hiện hộp", isOn: $settings.config.showBoxes)
            Toggle("Tên phiên trên hộp", isOn: $settings.config.showBoxLabels)
            Toggle("Viền hộp", isOn: $settings.showBoxBorder)
            HStack {
                Text("Độ đậm nền")
                Slider(value: $settings.boxOpacity, in: 0.03...0.4)
            }
        }
    }

    private var pivots: some View {
        Section {
            Toggle("Hiện pivot (đỉnh/đáy phiên)", isOn: $settings.config.showPivots)
            Toggle("Nhãn pivot (AS.H, LO.L…)", isOn: $settings.config.showPivotLabels)
            Picker("Kéo dài", selection: $settings.config.pivotExtension) {
                Text("Đến khi bị phá").tag(KillzonePivots.PivotExtension.untilMitigated)
                Text("Qua cả điểm bị phá").tag(KillzonePivots.PivotExtension.pastMitigation)
            }
            Toggle("Giữ pivot đã bị phá", isOn: $settings.config.showMitigated)
            stylePicker("Nét pivot", selection: $settings.pivotStyle)
            stylePicker("Nét pivot đã bị phá", selection: $settings.mitigatedStyle)
            Picker("Độ dày", selection: $settings.pivotWidth) {
                ForEach([1.0, 1.5, 2.0, 3.0], id: \.self) { Text(String(format: "%gpx", $0)).tag($0) }
            }
            Toggle("Đường giữa phiên (50%)", isOn: $settings.config.showMidpoints)
        } header: {
            Text("Pivots")
        } footer: {
            Text("Đỉnh và đáy của mỗi phiên được kéo sang phải sau khi phiên đóng, tới khi giá chạm qua (bị phá).")
        }
    }

    private var opens: some View {
        Section("Giá mở cửa") {
            ForEach(settings.config.opens.indices, id: \.self) { index in
                markRow($settings.config.opens[index], color: $settings.openColors[index])
            }
            stylePicker("Nét", selection: $settings.openStyle)
        }
    }

    private var timestamps: some View {
        Section("Mốc thời gian (đường dọc)") {
            ForEach(settings.config.timestamps.indices, id: \.self) { index in
                HStack {
                    Toggle(isOn: $settings.config.timestamps[index].enabled) { EmptyView() }.labelsHidden()
                    timePicker(hour: $settings.config.timestamps[index].hour)
                    Spacer()
                }
            }
            colorRow("Màu", color: $settings.timestampColor)
            stylePicker("Nét", selection: $settings.timestampStyle)
        }
    }

    private var cutoff: some View {
        Section {
            Toggle("Dừng các đường lúc", isOn: $settings.config.cutoffEnabled)
            if settings.config.cutoffEnabled {
                timeRow("Giờ cắt", hour: $settings.config.cutoffHour)
            }
        } header: {
            Text("Giờ cắt")
        } footer: {
            Text("Pivot và giá mở cửa ngừng kéo dài tại giờ này mỗi ngày, cho biểu đồ gọn.")
        }
    }

    private var periods: some View {
        Section("Ngày / Tuần / Tháng trước") {
            Toggle("PDH / PDL (ngày trước)", isOn: $settings.config.showPreviousDay)
            Toggle("PWH / PWL (tuần trước)", isOn: $settings.config.showPreviousWeek)
            Toggle("PMH / PML (tháng trước)", isOn: $settings.config.showPreviousMonth)
            colorRow("Màu", color: $settings.periodColor)
        }
    }

    private var other: some View {
        Section("Khác") {
            Toggle("Nhãn thứ trong tuần", isOn: $settings.config.showDayOfWeek)
            Toggle("Bảng biên độ phiên", isOn: $settings.config.showRangeTable)
            if settings.config.showRangeTable {
                Stepper("Trung bình \(settings.config.rangeAverageCount) phiên", value: $settings.config.rangeAverageCount, in: 1...30)
            }
        }
    }

    // MARK: - Rows

    private func markRow(_ mark: Binding<KillzonePivots.TimeMark>, color: Binding<RGBAColor>) -> some View {
        HStack {
            Toggle(isOn: mark.enabled) { EmptyView() }.labelsHidden()
            timePicker(hour: mark.hour)
            TextField("Nhãn", text: mark.label).frame(maxWidth: 70)
            Spacer()
            ColorPicker("", selection: Binding(get: { color.wrappedValue.color }, set: { color.wrappedValue = RGBAColor($0) }))
                .labelsHidden()
        }
    }

    private func timeRow(_ title: String, hour: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            timePicker(hour: hour)
        }
    }

    /// Hour of day edited with a time picker; the clock is shown as is (no time-zone shift).
    private func timePicker(hour: Binding<Double>) -> some View {
        let utc = TimeZone(identifier: "UTC")!
        let date = Binding<Date>(
            get: { Date(timeIntervalSince1970: (hour.wrappedValue.truncatingRemainder(dividingBy: 24)) * 3600) },
            set: { newValue in
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = utc
                let parts = calendar.dateComponents([.hour, .minute], from: newValue)
                hour.wrappedValue = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
            })
        return DatePicker("", selection: date, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .environment(\.timeZone, utc)
            .environment(\.locale, Locale(identifier: "vi_VN"))
    }

    private func colorRow(_ title: String, color: Binding<RGBAColor>) -> some View {
        ColorPicker(title, selection: Binding(get: { color.wrappedValue.color }, set: { color.wrappedValue = RGBAColor($0) }))
    }

    private func stylePicker(_ title: String, selection: Binding<LineStyle>) -> some View {
        Picker(title, selection: selection) {
            ForEach(LineStyle.allCases, id: \.self) { Text($0.title).tag($0) }
        }
    }

    /// The same hours in Vietnam time today (the gap changes with US daylight saving).
    static func vietnamRange(_ start: Double, _ end: Double, zoneID: String) -> String? {
        guard let vietnam = TimeZone(identifier: "Asia/Ho_Chi_Minh") else { return nil }
        let zone = TimeZone(identifier: zoneID) ?? TimeZone(identifier: "America/New_York")!
        let now = Date()
        let shift = Double(vietnam.secondsFromGMT(for: now) - zone.secondsFromGMT(for: now)) / 3600
        guard shift != 0 else { return nil }
        return "\(clock(start + shift + 48)) – \(clock(end + shift + 48))"
    }

    static func clock(_ hour: Double) -> String {
        let h = hour.truncatingRemainder(dividingBy: 24)
        return String(format: "%02d:%02d", Int(h), Int(((h - floor(h)) * 60).rounded()))
    }
}
