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
        Section("Chung") {
            Picker("Múi giờ", selection: $settings.config.timeZoneID) {
                ForEach(Self.zones, id: \.id) { Text($0.title).tag($0.id) }
            }
            Picker("Chỉ vẽ trên khung ≤", selection: $settings.config.timeframeLimitMinutes) {
                ForEach(Self.limits, id: \.self) { minutes in
                    Text(minutes >= 60 ? "\(Int(minutes / 60))h" : "\(Int(minutes))m").tag(minutes)
                }
            }
            Stepper("Số ngày hiển thị: \(settings.config.maxDays)", value: $settings.config.maxDays, in: 1...20)
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
                        Text("\(Self.clock(settings.config.sessions[index].start)) – \(Self.clock(settings.config.sessions[index].end))")
                            .font(.footnote.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
            }
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

    static func clock(_ hour: Double) -> String {
        let h = hour.truncatingRemainder(dividingBy: 24)
        return String(format: "%02d:%02d", Int(h), Int(((h - floor(h)) * 60).rounded()))
    }
}
