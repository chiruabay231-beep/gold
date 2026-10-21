import SwiftUI
import UIKit
import BacktestKit

/// Inputs of "ICT Killzones + Pivots [TFO]", grouped like the indicator's
/// settings on TradingView.
struct KillzonePivotsSettingsView: View {
    @Binding var json: String
    @Environment(\.dismiss) private var dismiss
    @State private var settings = KillzonePivotsSettings()
    @State private var cancelled = false
    @State private var presets = IndicatorPresets.all(Self.presetKey)
    @State private var naming = false
    @State private var presetName = ""
    @State private var notice: String?

    static let presetKey = "killzonePivots"

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
                presetsSection
                general
                killzones
                fvgSection
                structureSection
                liquiditySection
                smtSection
                macros
                boxes
                pivots
                lineWidths
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy bỏ") {
                        cancelled = true
                        dismiss()
                    }
                }
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
        // Swiping the sheet down keeps the changes too; only "Hủy bỏ" drops them.
        .onDisappear { if !cancelled { json = settings.json } }
        .alert("Lưu thành mẫu", isPresented: $naming) {
            TextField("Tên mẫu, vd: Scalp M1", text: $presetName)
            Button("Huỷ", role: .cancel) {}
            Button("Lưu") {
                let name = presetName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                IndicatorPresets.save(name: name, json: settings.json, indicator: Self.presetKey)
                presets = IndicatorPresets.all(Self.presetKey)
            }
        } message: {
            Text("Lưu toàn bộ cài đặt hiện tại để dùng lại sau.")
        }
        .alert("Cài đặt", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notice ?? "")
        }
    }

    private var presetsSection: some View {
        Section {
            ForEach(presets) { preset in
                Button {
                    settings = KillzonePivotsSettings.decode(preset.json)
                    notice = "Đã dùng mẫu \"\(preset.name)\". Bấm Ok để áp dụng lên biểu đồ."
                } label: {
                    HStack {
                        Label(preset.name, systemImage: "square.stack.3d.up")
                        Spacer()
                        Text(preset.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets { IndicatorPresets.delete(presets[index], indicator: Self.presetKey) }
                presets = IndicatorPresets.all(Self.presetKey)
            }
            Button {
                presetName = ""
                naming = true
            } label: {
                Label("Lưu cài đặt hiện tại thành mẫu…", systemImage: "square.and.arrow.down")
            }
            Button {
                UIPasteboard.general.string = settings.json
                notice = "Đã sao chép cài đặt. Dán vào Ghi chú để giữ, kể cả khi cài lại app hoặc dùng máy khác."
            } label: {
                Label("Sao chép cài đặt (sao lưu)", systemImage: "doc.on.doc")
            }
            Button {
                let text = UIPasteboard.general.string ?? ""
                if let data = text.data(using: .utf8),
                   let pasted = try? JSONDecoder().decode(KillzonePivotsSettings.self, from: data) {
                    settings = pasted
                    notice = "Đã dán cài đặt. Bấm Ok để áp dụng."
                } else {
                    notice = "Trong bộ nhớ tạm không có cài đặt chỉ báo này."
                }
            } label: {
                Label("Dán cài đặt đã sao chép", systemImage: "doc.on.clipboard")
            }
        } header: {
            Text("Mẫu cài đặt")
        } footer: {
            Text("Cài đặt luôn được giữ tự động cho lần sau. Mẫu giúp đổi nhanh giữa các kiểu cài đặt; vuốt trái để xoá một mẫu.")
        }
    }

    private var lineWidths: some View {
        Section {
            Picker("Đường pivot", selection: $settings.pivotWidth) {
                ForEach([0.5, 0.75, 1.0, 1.5, 2.0, 3.0], id: \.self) { Text(String(format: "%gpx", $0)).tag($0) }
            }
            Picker("Các đường khác (FVG, MSS, SMT…)", selection: $settings.lineScale) {
                Text("Rất mỏng").tag(0.5)
                Text("Mỏng").tag(0.75)
                Text("Vừa").tag(1.0)
                Text("Dày").tag(1.5)
                Text("Rất dày").tag(2.0)
            }
            Picker("Viền hộp phiên / macro", selection: $settings.boxBorderWidth) {
                ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { Text(String(format: "%gpx", $0)).tag($0) }
            }
        } header: {
            Text("Độ dày đường kẻ")
        }
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

    static let fvgTimeframes: [Double] = [1, 5, 15, 30, 60, 240, 1440]

    static func timeframeName(_ minutes: Double) -> String {
        minutes >= 1440 ? "D1" : (minutes >= 60 ? "H\(Int(minutes / 60))" : "M\(Int(minutes))")
    }

    private var fvgSection: some View {
        Section {
            Toggle("Hiện FVG", isOn: $settings.config.showFVG)
            if settings.config.showFVG {
                Picker("Từ khung", selection: $settings.config.fvgFromMinutes) {
                    ForEach(Self.fvgTimeframes, id: \.self) { minutes in Text(Self.timeframeName(minutes)).tag(minutes) }
                }
                Picker("Đến khung", selection: $settings.config.fvgToMinutes) {
                    ForEach(Self.fvgTimeframes, id: \.self) { minutes in Text(Self.timeframeName(minutes)).tag(minutes) }
                }
                Toggle("Chỉ vẽ FVG mạnh (lọc FVG yếu)", isOn: $settings.config.fvgStrongOnly)
                if settings.config.fvgStrongOnly {
                    Stepper("Nến tạo FVG ≥ \(String(format: "%.2g", settings.config.fvgDisplacement)) × thân nến TB",
                            value: $settings.config.fvgDisplacement, in: 1...4, step: 0.25)
                }
                Toggle("Tô nền khi trùng FVG khung lớn hơn", isOn: $settings.config.fvgConfluence)
                Toggle("Hiện VI (Volume Imbalance)", isOn: $settings.config.showVI)
                if settings.config.showVI {
                    Stepper("Giữ \(settings.config.viCount) VI gần nhất", value: $settings.config.viCount, in: 5...100, step: 5)
                    Toggle("Ẩn VI đã bị chạm", isOn: $settings.config.viHideTouched)
                    colorRow("Màu VI", color: $settings.viColor)
                }
                Toggle("Đường giữa 50% (chữ FVG)", isOn: $settings.config.fvgMidline)
                Toggle("Ẩn FVG đã bị chạm", isOn: $settings.config.fvgHideFilled)
                Stepper("Chạm rồi bật ngược: giữ \(Int(settings.config.gapKeepMinutes)) phút",
                        value: $settings.config.gapKeepMinutes, in: 5...120, step: 5)
                Stepper("Lọc FVG nhỏ: \(String(format: "%.1f", settings.config.fvgMinSize)) × biên độ nến",
                        value: $settings.config.fvgMinSize, in: 0...2, step: 0.1)
                Stepper("Giữ \(settings.config.fvgCount) FVG gần nhất", value: $settings.config.fvgCount, in: 5...200, step: 5)
                colorRow("Màu FVG tăng", color: $settings.fvgBullColor)
                colorRow("Màu FVG giảm", color: $settings.fvgBearColor)
                colorRow("Nền FVG trùng khung", color: $settings.fvgZoneColor)
                colorRow("Đường giữa FVG trùng khung", color: $settings.fvgZoneMidColor)
                HStack {
                    Text("Độ đậm nền")
                    Slider(value: $settings.fvgOpacity, in: 0.05...0.6)
                }
            }
        } header: {
            Text("FVG (Fair Value Gap)")
        } footer: {
            Text("Khoảng trống giữa nến 1 và nến 3: hai đường cạnh và đường giữa có chữ FVG, kéo dài tới khi có nến chạm vào. Nến chạm vùng rồi bật ngược: FVG/VI dừng ở nến đó và còn hiện thêm số phút đã chọn (mặc định 15) rồi tắt; nến xuyên qua hết vùng: tắt ngay. FVG mạnh: nến giữa là nến đẩy mạnh (thân lớn hơn nhiều lần thân nến trung bình 20 cây trước, cùng chiều khoảng trống); FVG yếu bị lọc. FVG trùng FVG cùng chiều của khung lớn hơn được tô nền. VI: hai nến cùng chiều, thân cách nhau còn râu chồng lên nhau; vẽ nét đứt mảnh, kéo tới khi bị chạm.")
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

    private var liquiditySection: some View {
        Section {
            Toggle("Hiện quét thanh khoản", isOn: $settings.config.showSweeps)
            if settings.config.showSweeps {
                Stepper("Giữ \(settings.config.sweepCount) lần quét gần nhất", value: $settings.config.sweepCount, in: 2...100, step: 2)
                colorRow("Màu", color: $settings.sweepColor)
            }
        } header: {
            Text("Quét thanh khoản (Liquidity sweep)")
        } footer: {
            Text("Giá râu nến vượt đỉnh/đáy phiên (AS.H, LO.L…) hoặc đỉnh/đáy ngày trước (PDH/PDL) rồi đóng cửa quay lại: nét đứt ngắn có nhãn \"$ LO.H\" tại cây nến quét. Quét đỉnh thường báo giảm, quét đáy báo tăng.")
        }
    }

    private var smtSection: some View {
        Section {
            Toggle("Hiện SMT", isOn: $settings.config.showSMT)
            if settings.config.showSMT {
                HStack {
                    Text("So với mã")
                    TextField("Tự động (XAG cho vàng)", text: $settings.smtSymbol)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                Toggle("Mã so sánh chạy ngược chiều (DXY)", isOn: $settings.config.smtInverse)
                Stepper("Swing: \(settings.config.smtSwingLength) nến mỗi bên", value: $settings.config.smtSwingLength, in: 1...10)
                Stepper("Hai đỉnh/đáy cách tối đa \(settings.config.smtLookback) nến", value: $settings.config.smtLookback,
                        in: 10...300, step: 10)
                Stepper("Giữ \(settings.config.smtCount) SMT gần nhất", value: $settings.config.smtCount, in: 2...50, step: 2)
                colorRow("Màu SMT tăng", color: $settings.smtBullColor)
                colorRow("Màu SMT giảm", color: $settings.smtBearColor)
            }
        } header: {
            Text("SMT divergence")
        } footer: {
            Text("So 2 đỉnh (hoặc 2 đáy) liên tiếp với thị trường liên quan cùng khung: vàng tạo đỉnh cao hơn mà bạc không (SMT giảm), hoặc vàng tạo đáy thấp hơn mà bạc không (SMT tăng). Tự động: XAUUSDT ↔ XAGUSDT (Binance Futures), XAU_USD ↔ XAG_USD (OANDA), BTC ↔ ETH. SMT chỉ hiện khi bấm nút \"So sánh\" dưới biểu đồ (chia 2 màn hình), trên cả 2 mã. Mã phải cùng nguồn dữ liệu với biểu đồ; không dùng cho khung giây.")
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
            Toggle("Hiện đỉnh/đáy khi phiên đang chạy", isOn: $settings.config.livePivots)
            Picker("Kéo dài", selection: $settings.config.pivotExtension) {
                Text("Đến khi bị phá").tag(KillzonePivots.PivotExtension.untilMitigated)
                Text("Qua cả điểm bị phá").tag(KillzonePivots.PivotExtension.pastMitigation)
            }
            Toggle("Giữ pivot đã bị phá", isOn: $settings.config.showMitigated)
            stylePicker("Nét pivot", selection: $settings.pivotStyle)
            stylePicker("Nét pivot đã bị phá", selection: $settings.mitigatedStyle)
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

    @ViewBuilder
    private var periods: some View {
        Section {
            Toggle("Đỉnh / đáy từng ngày", isOn: $settings.config.showDailyLevels)
            if settings.config.showDailyLevels {
                Stepper("\(settings.config.dailyLevelDays) ngày gần nhất", value: $settings.config.dailyLevelDays, in: 1...20)
                Toggle("Giá chạm: dừng lại, nét chấm ……", isOn: $settings.config.dailyLevelsKeepTouched)
                colorRow("Màu đỉnh ngày", color: $settings.dayHighColor)
                colorRow("Màu đáy ngày", color: $settings.dayLowColor)
                stylePicker("Nét", selection: $settings.dayLevelStyle)
            }
        } header: {
            Text("Đỉnh / đáy ngày")
        } footer: {
            Text("Đỉnh và đáy của mỗi ngày đã đóng, ghi rõ thứ (vd: Đỉnh T3, Đáy T5), kéo sang phải tới khi có nến chạm vào: đường dừng ngay ở cây nến đó và chuyển sang nét chấm …… (tắt “Giá chạm” thì đường bị chạm biến mất). Ngày tính theo múi giờ của chỉ báo (mặc định New York, giống ICT).")
        }
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
