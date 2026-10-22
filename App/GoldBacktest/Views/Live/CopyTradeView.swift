import SwiftUI

/// Copy trade: every order on the main MT5 account (app, bot, MT5 itself) is
/// opened on the follower accounts by the VPS, SL/TP followed, closed together.
struct CopyTradeView: View {
    @State private var status: CopyTradeStatus?
    @State private var error: String?
    @State private var busy = false
    @State private var editing: CopyFollowerDraft?
    @State private var removing: CopyTradeStatus.Follower?
    @State private var confirmEnable = false
    /// The VPS runs a server version without copy trade.
    @State private var outdated = false

    var body: some View {
        List {
            if RemoteBotSettings.client() == nil {
                Text("Kết nối máy chủ VPS trước (Giao dịch → Đăng nhập → Máy chủ VPS).").foregroundColor(.secondary)
            } else if outdated {
                ServerUpdateSection(message: "Máy chủ VPS đang chạy bản cũ, chưa có Copy trade. Cập nhật máy chủ rồi quay lại trang này.")
            } else {
                mainSection
                followersSection
                eventsSection
            }
        }
        .navigationTitle("Copy trade")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
        .refreshable { await refresh() }
        .sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            if let draft = editing {
                CopyFollowerForm(draft: draft) { saved in
                    try await save(saved)
                }
            }
        }
        .confirmationDialog("Xoá tài khoản copy \(removing?.title ?? "")?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Xoá, giữ các lệnh copy đang mở", role: .destructive) { remove(closePositions: false) }
            Button("Xoá và đóng các lệnh copy", role: .destructive) { remove(closePositions: true) }
        }
        .confirmationDialog("Bật copy trade?", isPresented: $confirmEnable, titleVisibility: .visible) {
            Button("Bật copy") { Task { await perform { try await $0.copySettings(enabled: true) } } }
        } message: {
            Text("Từ bây giờ mọi lệnh mới trên tài khoản chính được mở trên các tài khoản copy đang bật"
                 + (status?.followers.contains { $0.allowReal && $0.enabled } == true ? ", có cả tài khoản thật." : "."))
        }
        .alert("Copy trade", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    // MARK: - Sections

    /// One line: on/off and where the orders come from.
    private var mainSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Copy trade").font(.headline)
                    Text(summary).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Toggle("Copy trade", isOn: Binding(get: { status?.enabled ?? false }, set: { on in
                    if on { confirmEnable = true } else { Task { await perform { try await $0.copySettings(enabled: false) } } }
                }))
                .labelsHidden()
                .disabled(status == nil || busy)
            }
            if status?.enabled == true, let m = status?.master, m.connected != true {
                Text(m.error ?? "Đang đọc tài khoản chính…").font(.caption).foregroundColor(.orange)
            }
        } footer: {
            Text("Lệnh mới của tài khoản chính (app, bot hay MT5) được mở trên các tài khoản copy, SL/TP và đóng theo.")
        }
    }

    private var summary: String {
        let followers = status?.followers.filter(\.enabled).count ?? 0
        if let m = status?.master, m.connected == true, let login = m.login {
            return "Từ #\(login) → \(followers) tài khoản · \(m.positions ?? 0) lệnh mở"
        }
        return "Tài khoản chính: MT5 đang đăng nhập · \(followers) tài khoản copy"
    }

    private var followersSection: some View {
        Section {
            ForEach(status?.followers ?? []) { f in
                Button { editing = CopyFollowerDraft(f) } label: { followerRow(f) }
                    .swipeActions {
                        Button("Xoá", role: .destructive) { removing = f }
                        if (f.status?.positions ?? 0) > 0 {
                            Button("Đóng lệnh") {
                                Task { await perform { try await $0.copyCloseAll(id: f.id) } }
                            }
                            .tint(.orange)
                        }
                    }
            }
            Button { editing = CopyFollowerDraft() } label: {
                Label("Thêm tài khoản copy", systemImage: "plus.circle")
            }
        } header: {
            Text("Tài khoản copy")
        } footer: {
            Text("Chạm để sửa, vuốt trái để xoá hoặc đóng lệnh.")
        }
    }

    private func followerRow(_ f: CopyTradeStatus.Follower) -> some View {
        let s = f.status
        let connected = s?.connected == true && f.enabled
        return HStack(spacing: 10) {
            Circle()
                .fill(!f.enabled ? Color.gray : (connected && (s?.error ?? "").isEmpty ? Color.green : Color.orange))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(f.title).font(.system(size: 16, weight: .semibold)).foregroundColor(.primary)
                Text("#\(f.login) · \(f.server) · "
                     + (f.fixedLots > 0 ? "\(Self.lots(f.fixedLots)) lot" : "× \(Self.lots(f.multiplier))"))
                    .font(.caption).foregroundColor(.secondary)
                    .lineLimit(1)
                if let error = s?.error, !error.isEmpty {
                    Text(error).font(.caption).foregroundColor(.orange).lineLimit(2)
                }
            }
            Spacer()
            if connected, let balance = s?.balance {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.2f", balance)).font(.subheadline.monospacedDigit()).foregroundColor(.primary)
                    Text(String(format: "%+.2f", s?.profit ?? 0))
                        .font(.caption.monospacedDigit())
                        .foregroundColor((s?.profit ?? 0) >= 0 ? OrderRow.profitColor : OrderRow.lossColor)
                }
            }
        }
    }

    /// The latest few; the rest one tap away.
    private var eventsSection: some View {
        let events = status?.events ?? []
        return Section("Hoạt động") {
            if events.isEmpty {
                Text("Chưa có").foregroundColor(.secondary)
            }
            ForEach(events.prefix(4)) { e in eventRow(e) }
            if events.count > 4 {
                NavigationLink("Xem tất cả · \(events.count)") {
                    List(events) { e in eventRow(e) }
                        .navigationTitle("Hoạt động copy")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }

    private func eventRow(_ e: CopyTradeStatus.Event) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(e.text).font(.footnote)
            Spacer()
            Text(Date(timeIntervalSince1970: e.time).formatted(date: .omitted, time: .shortened))
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    // MARK: - Actions

    private func refresh() async {
        guard let client = RemoteBotSettings.client() else { return }
        do {
            status = try await client.copyStatus()
            outdated = false
        } catch {
            if ServerUpdate.isOutdated(error) {
                outdated = true
            } else if status == nil {
                self.error = error.localizedDescription
            }
        }
    }

    private func perform(_ action: (RemoteBotClient) async throws -> CopyTradeStatus) async {
        guard let client = RemoteBotSettings.client() else { return }
        busy = true
        defer { busy = false }
        do {
            status = try await action(client)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save(_ draft: CopyFollowerDraft) async throws {
        guard let client = RemoteBotSettings.client() else { return }
        status = try await client.copySave(draft)
    }

    private func remove(closePositions: Bool) {
        guard let f = removing else { return }
        removing = nil
        Task { await perform { try await $0.copyRemove(id: f.id, closePositions: closePositions) } }
    }

    static func lots(_ value: Double) -> String { String(format: "%g", value) }
}

/// Add or edit a follower account.
struct CopyFollowerForm: View {
    @State var draft: CopyFollowerDraft
    /// A member copying the signals into their own account: no server details.
    var forMember = false
    /// Whether a real-money account may be chosen (members: the owner decides).
    var realAllowed = true
    var onSave: (CopyFollowerDraft) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var error: String?
    @State private var confirmReal = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tên (vd: TK vợ, TK quỹ)", text: $draft.name)
                    TextField("Số tài khoản", text: $draft.login).keyboardType(.numberPad)
                    HStack {
                        TextField("Server, vd Exness-MT5Trial7", text: $draft.server)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Menu {
                            Button("Demo: Exness-MT5Trial…") { draft.server = "Exness-MT5Trial" }
                            Button("Thật: Exness-MT5Real…") { draft.server = "Exness-MT5Real" }
                        } label: {
                            Image(systemName: "list.bullet.circle")
                        }
                    }
                    SecureField(draft.id == nil ? "Mật khẩu chính" : "Mật khẩu (để trống = giữ nguyên)", text: $draft.password)
                        .textContentType(.password)
                    Toggle("Đang bật", isOn: $draft.enabled)
                } header: {
                    Text("Tài khoản copy")
                } footer: {
                    Text(forMember ? "Mật khẩu chính (không phải investor) của tài khoản MT5 của bạn: chỉ dùng để đặt lệnh copy."
                         : "Mật khẩu chính (không phải investor), chỉ lưu trên VPS của bạn.")
                }

                Section {
                    Picker("Khối lượng", selection: Binding(get: { draft.fixedLots > 0 }, set: { fixed in
                        draft.fixedLots = fixed ? max(draft.fixedLots, 0.01) : 0
                    })) {
                        Text("Theo lệnh chính × hệ số").tag(false)
                        Text("Cố định").tag(true)
                    }
                    if draft.fixedLots > 0 {
                        Stepper("Lot cố định \(CopyTradeView.lots(draft.fixedLots))", value: $draft.fixedLots, in: 0.01...100, step: 0.01)
                    } else {
                        Stepper("Hệ số × \(CopyTradeView.lots(draft.multiplier))", value: $draft.multiplier, in: 0.1...20, step: 0.1)
                    }
                    Stepper("Tối đa \(CopyTradeView.lots(draft.maxLots)) lot / lệnh", value: $draft.maxLots, in: 0.01...100, step: 0.01)
                    if realAllowed {
                        Toggle("Cho phép tài khoản thật", isOn: Binding(get: { draft.allowReal }, set: { on in
                            if on { confirmReal = true } else { draft.allowReal = false }
                        }))
                        .tint(.red)
                    }
                } header: {
                    Text("Lệnh")
                } footer: {
                    Text("Hệ số 2: lệnh chính 0.05 lot → 0.10 lot (không quá mức tối đa)."
                         + (realAllowed ? "" : " Chỉ copy vào tài khoản demo."))
                }

                Section {
                    DisclosureGroup("Nâng cao") {
                        TextField("Đổi tên mã, vd XAUUSDm=XAUUSD", text: $draft.symbolMap, axis: .vertical)
                            .font(.body.monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .lineLimit(1...5)
                        if !forMember {
                            TextField("terminal64.exe riêng (trống = tự sao chép MT5)", text: $draft.path)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                } footer: {
                    Text("Mã tự khớp (XAUUSDm ↔ XAUUSD ↔ XAUUSD.r); chỉ đổi khi hai sàn đặt tên khác hẳn.")
                }
            }
            .navigationTitle(draft.id == nil ? "Thêm tài khoản copy" : "Sửa tài khoản copy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Lưu") { save() }
                            .disabled(draft.login.isEmpty || draft.server.isEmpty || (draft.id == nil && draft.password.isEmpty))
                    }
                }
            }
            .confirmationDialog("Copy vào tài khoản thật?", isPresented: $confirmReal, titleVisibility: .visible) {
                Button("Cho phép tài khoản thật", role: .destructive) { draft.allowReal = true }
            } message: {
                Text("Mọi lệnh của tài khoản chính sẽ được mở bằng tiền thật trên tài khoản này. Hãy thử với tài khoản demo trước.")
            }
            .alert("Không lưu được", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func save() {
        saving = true
        Task {
            defer { saving = false }
            do {
                try await onSave(draft)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
