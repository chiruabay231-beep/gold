import SwiftUI
import UIKit

/// "Tín hiệu" page of the Giao dịch tab. A member connects with the owner's
/// address and invite code and sees the owner's trades as signals (and copies them
/// with the "copy" role). The owner manages members and codes from here too.
struct SignalsView: View {
    @Environment(MemberFeed.self) private var feed

    @State private var copy: MemberCopyStatus?
    @State private var editingCopy: CopyFollowerDraft?
    @State private var confirmDisconnect = false

    private var ownerConnected: Bool { RemoteBotSettings.client() != nil }

    var body: some View {
        List {
            if feed.isConnected, let info = feed.info {
                memberHeader(info)
                openSection
                if info.canCopy { copySection }
                closedSection
            } else if feed.memberMode {
                // Signed in but the code no longer answers.
                Section { Text(feed.error ?? "Đang tải tín hiệu…").foregroundColor(.secondary) }
            }
            if ownerConnected && !feed.memberMode {
                Section {
                    NavigationLink { MembersView() } label: {
                        Label("Thành viên & mã mời", systemImage: "person.2.badge.key")
                    }
                } header: {
                    Text("Chủ máy chủ")
                } footer: {
                    Text("Tạo mã cho người dùng: họ thấy lệnh của bạn thành tín hiệu (và copy được nếu bạn cho phép). Họ không thấy chiến lược, số lot hay tài khoản của bạn. Muốn xem giao diện của họ: Thành viên & mã mời → Xem thử như thành viên.")
                }
            }
        }
        .navigationTitle("Tín hiệu")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: feed.connectionID) {
            await feed.refresh()
            await loadCopy()
        }
        .refreshable {
            await feed.refresh()
            await loadCopy()
        }
        .sheet(isPresented: Binding(get: { editingCopy != nil }, set: { if !$0 { editingCopy = nil } })) {
            if let draft = editingCopy {
                CopyFollowerForm(draft: draft, forMember: true,
                                 realAllowed: feed.info?.features?[MemberFeature.copyReal.rawValue] ?? false) { saved in
                    guard let client = MemberSettings.client() else { return }
                    copy = try await client.memberCopySave(saved)
                }
            }
        }
        .confirmationDialog("Ngắt kết nối tín hiệu?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Ngắt kết nối", role: .destructive) {
                feed.disconnect()
                copy = nil
            }
        } message: {
            Text("Bạn cần nhập lại mã mời để vào app. Copy lệnh (nếu có) vẫn tiếp tục.")
        }
    }

    // MARK: - Member

    private func memberHeader(_ info: MemberInfo) -> some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: info.canCopy ? "doc.on.doc.fill" : "antenna.radiowaves.left.and.right")
                    .font(.system(size: 18))
                    .foregroundColor(.accentColor)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.name).font(.headline)
                    Text((info.canCopy ? "Xem tín hiệu + copy lệnh" : "Xem tín hiệu")
                         + (info.expires.map { " · hết hạn \(Self.date($0))" } ?? " · không hết hạn"))
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if feed.isPreview {
                    Button("Thoát xem thử") { feed.disconnect() }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .font(.footnote.weight(.semibold))
                } else {
                    Button { confirmDisconnect = true } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right").foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Ngắt kết nối")
                }
            }
            if let error = feed.error {
                Text(Self.plain(error)).font(.footnote).foregroundColor(.orange)
            }
        }
    }

    private var openSection: some View {
        Section {
            if feed.openSignals.isEmpty {
                Text("Chưa có lệnh đang mở").foregroundColor(.secondary)
            }
            ForEach(feed.openSignals) { s in SignalRow(signal: s) }
        } header: {
            Text("Đang mở")
        } footer: {
            Text("Tín hiệu cũng được vẽ trên biểu đồ Live của cùng mã (đường tím: vào lệnh, SL, TP).")
        }
    }

    private var closedSection: some View {
        let closed = feed.signals.filter { !$0.isOpen }
        let wins = closed.filter { ($0.result ?? 0) > 0 }.count
        return Section {
            if closed.isEmpty {
                Text("Chưa có").foregroundColor(.secondary)
            }
            ForEach(closed.prefix(40)) { s in SignalRow(signal: s) }
        } header: {
            Text(closed.isEmpty ? "Đã đóng" : "Đã đóng · thắng \(wins)/\(closed.count)")
        }
    }

    private var copySection: some View {
        Section {
            if let f = copy?.follower {
                let s = f.status
                HStack {
                    Circle()
                        .fill(f.enabled && s?.connected == true && (s?.error ?? "").isEmpty ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("#\(f.login) · \(f.server)").font(.subheadline.weight(.semibold))
                        Text(f.fixedLots > 0 ? "Lot cố định \(CopyTradeView.lots(f.fixedLots))"
                             : "Lot × \(CopyTradeView.lots(f.multiplier)) · tối đa \(CopyTradeView.lots(f.maxLots))")
                            .font(.caption).foregroundColor(.secondary)
                        if let error = s?.error, !error.isEmpty {
                            Text(Self.plain(error)).font(.caption).foregroundColor(.orange)
                        }
                    }
                    Spacer()
                    if let balance = s?.balance {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.2f", balance)).font(.subheadline.monospacedDigit())
                            Text("\(s?.positions ?? 0) lệnh · \(String(format: "%+.2f", s?.profit ?? 0))")
                                .font(.caption.monospacedDigit())
                                .foregroundColor((s?.profit ?? 0) >= 0 ? OrderRow.profitColor : OrderRow.lossColor)
                        }
                    }
                }
                Button("Sửa tài khoản copy") { editingCopy = CopyFollowerDraft(f) }
                Button("Ngừng copy và xoá tài khoản", role: .destructive) {
                    Task {
                        guard let client = MemberSettings.client() else { return }
                        copy = try? await client.memberCopyRemove()
                    }
                }
            } else {
                Button {
                    var draft = CopyFollowerDraft()
                    draft.name = feed.info?.name ?? ""
                    editingCopy = draft
                } label: {
                    Label("Copy tín hiệu vào tài khoản MT5 của tôi", systemImage: "plus.circle")
                }
            }
        } header: {
            Text("Copy lệnh")
        } footer: {
            if copy?.ownerCopyOn == false {
                Text("Người cung cấp đang tắt copy trade: tài khoản của bạn sẽ copy khi họ bật lại.")
            } else {
                Text("Mỗi tín hiệu mới được mở trên tài khoản MT5 của bạn, SL/TP và đóng theo.")
            }
        }
    }

    private func loadCopy() async {
        guard feed.info?.canCopy == true, let client = MemberSettings.client() else {
            copy = nil
            return
        }
        copy = try? await client.memberCopy()
    }

    /// Messages for members never name the server behind the app.
    static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: " trên VPS", with: "")
            .replacingOccurrences(of: " VPS", with: "")
            .replacingOccurrences(of: "VPS", with: "hệ thống")
    }

    static func date(_ time: Double) -> String {
        Date(timeIntervalSince1970: time).formatted(date: .abbreviated, time: .omitted)
    }
}

/// "MUA XAUUSD 4091.16 · SL · TP" with the running or final move.
struct SignalRow: View {
    let signal: TradeSignal

    static let purple = Color(red: 0.55, green: 0.3, blue: 0.95)

    var body: some View {
        let s = signal
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(s.isOpen ? Self.purple : ((s.result ?? 0) > 0 ? Color.green : ((s.result ?? 0) < 0 ? Color.red : Color.gray)))
                .frame(width: 4)
                .padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(s.symbol).font(.system(size: 17, weight: .bold).width(.condensed))
                    Text(s.isBuy ? "MUA" : "BÁN")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(s.isBuy ? OrderRow.profitColor : OrderRow.lossColor, in: Capsule())
                    Text(Self.price(s.entry)).font(.subheadline.monospacedDigit())
                }
                Text("SL \(s.stop.map(Self.price) ?? "–") · TP \(s.target.map(Self.price) ?? "–")"
                     + (s.isOpen ? "" : " · ra \(s.exit.map(Self.price) ?? "–")"))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if let move = s.move {
                    Text(String(format: "%+.2f", move))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundColor(move >= 0 ? OrderRow.profitColor : OrderRow.lossColor)
                }
                Text(Self.time(s.isOpen ? s.openTime : (s.closeTime ?? s.openTime)))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
    }

    static func price(_ value: Double) -> String { CandleChart.format(value, CandleChart.decimals(for: value)) }

    static func time(_ value: Double) -> String {
        let date = Date(timeIntervalSince1970: value)
        return Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.day().month().hour().minute())
    }
}

// MARK: - Owner: members and invite codes

struct MembersView: View {
    @Environment(MemberFeed.self) private var memberFeed
    @Environment(AppStore.self) private var store
    @State private var list: MembersList?
    @State private var startingPreview = false
    @State private var error: String?
    @State private var editing: MemberRow?
    @State private var adding = false
    /// A code just made: shown once, to send to the member.
    @State private var newCode: (member: MemberRow, code: String)?
    @State private var removing: MemberRow?

    var body: some View {
        List {
            if let error {
                Section { Text(error).font(.footnote).foregroundColor(.orange) }
            }
            Section {
                ForEach(list?.members ?? []) { m in
                    Button { editing = m } label: { row(m) }
                        .foregroundColor(.primary)
                        .swipeActions {
                            Button("Xoá", role: .destructive) { removing = m }
                            Button(m.enabled ? "Khoá" : "Mở") {
                                Task { await perform { try await $0.memberSave(id: m.id, name: m.name, role: m.role,
                                                                               enabled: !m.enabled, days: nil) } }
                            }
                            .tint(m.enabled ? .orange : .green)
                        }
                }
                Button { adding = true } label: {
                    Label("Thêm thành viên", systemImage: "person.badge.plus")
                }
            } header: {
                Text("Thành viên")
            } footer: {
                Text("Chạm để sửa quyền, hạn dùng hoặc đổi mã. Vuốt trái để khoá hoặc xoá. Khoá hay hết hạn thì người đó mất tín hiệu và ngừng copy ngay.")
            }
            if let list {
                Section {
                    ForEach(MemberFeature.allCases) { feature in
                        Toggle(feature.title, isOn: Binding(
                            get: { list.features?[feature.rawValue] ?? feature.defaultOn },
                            set: { on in
                                var features = list.features ?? [:]
                                features[feature.rawValue] = on
                                Task { await perform { try await $0.memberFeatures(features) } }
                            }))
                    }
                } header: {
                    Text("Thành viên được xem")
                } footer: {
                    Text("Biểu đồ Live và trang Tín hiệu luôn có. Thành viên không bao giờ thấy Bot, tài khoản sàn, copy trade, chiến lược hay đăng nhập của bạn; nút BUY/SELL của họ chỉ đặt lệnh demo trong app.")
                }
                Section {
                    Menu {
                        Button("Như người mới cài app (nhập mã từ đầu)") { startPreview(role: "copy", fresh: true) }
                        Button("Xem như: chỉ tín hiệu") { startPreview(role: "signals") }
                        Button("Xem như: tín hiệu + copy lệnh") { startPreview(role: "copy") }
                    } label: {
                        HStack {
                            Label("Xem thử như thành viên", systemImage: "eye")
                            Spacer()
                            if startingPreview { ProgressView() }
                        }
                    }
                    .disabled(startingPreview)
                } footer: {
                    Text("\"Như người mới cài app\": app hiện màn hình nhập mã như máy mới, mã thử đã chép sẵn để dán. Hai lựa chọn còn lại vào thẳng giao diện thành viên. Bấm \"Thoát xem thử\" để quay lại.")
                }
                Section {
                    LabeledContent("Tín hiệu đang mở", value: "\(list.openSignals ?? 0)")
                    LabeledContent("Tín hiệu đã ghi", value: "\(list.signals ?? 0)")
                } footer: {
                    Text("Tín hiệu là các lệnh của tài khoản MT5 chính (bot, app hay MT5) — hoặc của bot demo trên VPS khi chưa đăng nhập MT5. Copy cho thành viên chạy khi bạn bật Copy trade.")
                }
            }
        }
        .navigationTitle("Thành viên")
        .navigationBarTitleDisplayMode(.inline)
        .task { await perform { try await $0.members() } }
        .refreshable { await perform { try await $0.members() } }
        .sheet(isPresented: $adding) {
            MemberEditSheet(member: nil) { name, role, enabled, days in
                await save(id: nil, name: name, role: role, enabled: enabled, days: days)
            }
        }
        .sheet(item: $editing) { m in
            MemberEditSheet(member: m, onNewCode: {
                await perform { try await $0.memberNewCode(id: m.id) }
            }) { name, role, enabled, days in
                await save(id: m.id, name: name, role: role, enabled: enabled, days: days)
            }
        }
        .sheet(isPresented: Binding(get: { newCode != nil }, set: { if !$0 { newCode = nil } })) {
            if let newCode {
                MemberCodeSheet(name: newCode.member.name, code: newCode.code)
            }
        }
        .confirmationDialog("Xoá \(removing?.name ?? "")?", isPresented: Binding(get: { removing != nil },
                                                                              set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Xoá thành viên", role: .destructive) {
                if let m = removing { Task { await perform { try await $0.memberRemove(id: m.id) } } }
                removing = nil
            }
        } message: {
            Text("Mã của người này hết dùng được; tài khoản copy của họ bị gỡ (lệnh đang mở giữ nguyên).")
        }
    }

    private func row(_ m: MemberRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: m.role == "copy" ? "doc.on.doc.fill" : "antenna.radiowaves.left.and.right")
                .foregroundColor(m.enabled && !m.expired ? .accentColor : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.name).font(.body.weight(.semibold))
                Text((m.role == "copy" ? "Tín hiệu + copy" : "Chỉ tín hiệu")
                     + (m.expires.map { " · đến \(SignalsView.date($0))" } ?? " · không hết hạn")
                     + (m.hasCopy ? " · đã nối MT5" : ""))
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if !m.enabled {
                badge("Đã khoá", .orange)
            } else if m.expired {
                badge("Hết hạn", .red)
            } else if let seen = m.lastSeen {
                Text(Date(timeIntervalSince1970: seen).formatted(.relative(presentation: .named)))
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption2.weight(.semibold)).foregroundColor(.white)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color, in: Capsule())
    }

    static let previewName = "🧪 Xem thử (chủ)"

    /// Makes (or re-codes) a test member and switches this phone to its view.
    private func startPreview(role: String, fresh: Bool = false) {
        guard let client = RemoteBotSettings.client() else { return }
        startingPreview = true
        Task {
            defer { startingPreview = false }
            do {
                let existing = list?.members.first { $0.name == Self.previewName }
                var result: MembersList
                if let existing {
                    result = try await client.memberSave(id: existing.id, name: Self.previewName, role: role, enabled: true, days: 0)
                    result = try await client.memberNewCode(id: existing.id)
                } else {
                    result = try await client.memberSave(id: nil, name: Self.previewName, role: role, enabled: true, days: 0)
                }
                list = result
                guard let code = result.code else { return }
                if fresh {
                    // The code screen comes up as on a new phone; the code is ready to paste.
                    UIPasteboard.general.string = code
                    store.selectedTab = .live
                    memberFeed.startFresh(testCode: code)
                    return
                }
                if await memberFeed.connect(url: RemoteBotSettings.url, code: code, preview: true) {
                    store.selectedTab = .live
                } else {
                    error = memberFeed.error ?? "Không vào được chế độ xem thử"
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func save(id: String?, name: String, role: String, enabled: Bool, days: Double?) async {
        await perform { try await $0.memberSave(id: id, name: name, role: role, enabled: enabled, days: days) }
    }

    private func perform(_ action: (RemoteBotClient) async throws -> MembersList) async {
        guard let client = RemoteBotSettings.client() else {
            error = "Chưa kết nối máy chủ VPS"
            return
        }
        do {
            let result = try await action(client)
            list = result
            error = nil
            if let code = result.code, let member = result.member {
                newCode = (member, code)
            }
        } catch {
            self.error = ServerUpdate.isOutdated(error)
                ? "Máy chủ VPS chưa có phần thành viên: vào Bot trên VPS → Cập nhật máy chủ (bản \(ServerUpdate.latestVersion))."
                : error.localizedDescription
        }
    }
}

/// Add or change a member: name, role, how long the code works.
struct MemberEditSheet: View {
    let member: MemberRow?
    var onNewCode: (() async -> Void)? = nil
    var onSave: (String, String, Bool, Double?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var role = "signals"
    @State private var enabled = true
    /// nil = keep the expiry (editing), 0 = no expiry.
    @State private var days: Double?
    @State private var saving = false

    static let durations: [(String, Double)] = [("7 ngày", 7), ("30 ngày", 30), ("90 ngày", 90), ("1 năm", 365),
                                                 ("Không hết hạn", 0)]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tên (vd: Anh Nam, nhóm VIP)", text: $name)
                    Picker("Quyền", selection: $role) {
                        Text("Chỉ xem tín hiệu").tag("signals")
                        Text("Xem + copy lệnh").tag("copy")
                    }
                    if member != nil {
                        Toggle("Đang mở", isOn: $enabled)
                    }
                }
                Section {
                    Picker(member == nil ? "Hạn dùng" : "Gia hạn từ hôm nay", selection: $days) {
                        if member != nil { Text("Giữ nguyên").tag(Double?.none) }
                        ForEach(Self.durations, id: \.1) { item in Text(item.0).tag(Optional(item.1)) }
                    }
                } footer: {
                    if let member {
                        Text(member.expires.map { "Hiện tại: đến \(SignalsView.date($0))" } ?? "Hiện tại: không hết hạn")
                    }
                }
                if let onNewCode {
                    Section {
                        Button("Đổi mã mời (mã cũ hết dùng được)") {
                            Task {
                                await onNewCode()
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle(member == nil ? "Thêm thành viên" : "Sửa thành viên")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(member == nil ? "Tạo mã" : "Lưu") {
                        saving = true
                        Task {
                            await onSave(name, role, enabled, days)
                            saving = false
                            dismiss()
                        }
                    }
                    .disabled(saving)
                }
            }
            .onAppear {
                name = member?.name ?? ""
                role = member?.role ?? "signals"
                enabled = member?.enabled ?? true
                days = member == nil ? 30 : nil
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// The invite code, shown once: copy or share it with the server address.
struct MemberCodeSheet: View {
    let name: String
    let code: String

    @Environment(\.dismiss) private var dismiss

    private var message: String {
        "Aurum Pro · mã mời cho \(name)\nMở app Aurum Pro và nhập mã: \(code)"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("Mã mời của \(name)").font(.headline)
                Text(code)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)
                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = message
                    } label: {
                        Label("Sao chép", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    ShareLink(item: message) {
                        Label("Gửi", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Text("Mã chỉ hiện một lần: hãy gửi ngay. Mất mã thì vào thành viên → Đổi mã mời. Người nhận chỉ cần nhập mã, app tự kết nối.")
                    .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                Spacer()
            }
            .padding(24)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Xong") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
