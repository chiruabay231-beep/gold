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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = CopyFollowerDraft() } label: { Image(systemName: "plus") }
                    .disabled(RemoteBotSettings.client() == nil || outdated)
            }
        }
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
                 + (status?.followers.contains { $0.allowReal && $0.enabled } == true ? ", có cả tài khoản TIỀN THẬT." : "."))
        }
        .alert("Copy trade", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    // MARK: - Sections

    private var mainSection: some View {
        Section {
            Toggle(isOn: Binding(get: { status?.enabled ?? false }, set: { on in
                if on { confirmEnable = true } else { Task { await perform { try await $0.copySettings(enabled: false) } } }
            })) {
                Label("Copy trade", systemImage: "doc.on.doc")
            }
            .disabled(status == nil || busy)
            if let m = status?.master {
                if m.connected == true, let login = m.login {
                    LabeledContent("Tài khoản chính", value: "#\(login) · \(m.server ?? "")")
                    LabeledContent("Lệnh đang mở", value: "\(m.positions ?? 0)")
                } else if status?.enabled == true {
                    Text(m.error ?? "Đang đọc tài khoản chính…").font(.footnote).foregroundColor(.orange)
                }
            }
        } footer: {
            Text("Tài khoản chính là tài khoản MT5 đang đăng nhập ở trang Đăng nhập. Mọi lệnh mới của nó (đặt từ app, bot hay MT5) được mở trên các tài khoản copy, SL/TP sửa theo, đóng cùng lúc. Lệnh đã mở trước khi bật copy không được copy.")
        }
    }

    private var followersSection: some View {
        Section {
            if let followers = status?.followers, !followers.isEmpty {
                ForEach(followers) { f in
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
            } else {
                Button { editing = CopyFollowerDraft() } label: {
                    Label("Thêm tài khoản copy", systemImage: "plus.circle.fill")
                }
            }
        } header: {
            Text("Tài khoản copy")
        } footer: {
            Text("Mỗi tài khoản copy chạy một MT5 riêng trên VPS (app tự sao chép MT5 đã cài), tốn khoảng 200–300 MB RAM mỗi tài khoản. Chạm để sửa, vuốt trái để xoá.")
        }
    }

    private func followerRow(_ f: CopyTradeStatus.Follower) -> some View {
        let s = f.status
        let connected = s?.connected == true && f.enabled
        return HStack(alignment: .top) {
            Circle()
                .fill(!f.enabled ? Color.gray : (connected && (s?.error ?? "").isEmpty ? Color.green : Color.orange))
                .frame(width: 9, height: 9)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(f.title).font(.headline).foregroundColor(.primary)
                    if s?.mode == "real" {
                        Text("THẬT").font(.caption2.bold()).foregroundColor(.white)
                            .padding(.horizontal, 4).background(Color.red, in: Capsule())
                    }
                }
                Text("#\(f.login) · \(f.server)").font(.caption).foregroundColor(.secondary)
                Text(f.fixedLots > 0 ? "Lot cố định \(Self.lots(f.fixedLots))" : "Lot × \(Self.lots(f.multiplier))"
                     + " · tối đa \(Self.lots(f.maxLots))")
                    .font(.caption).foregroundColor(.secondary)
                if let error = s?.error, !error.isEmpty {
                    Text(error).font(.caption).foregroundColor(.orange)
                }
            }
            Spacer()
            if connected, let balance = s?.balance {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.2f %@", balance, s?.currency ?? "")).font(.subheadline.monospacedDigit())
                    Text("\(s?.positions ?? 0) lệnh · \(String(format: "%+.2f", s?.profit ?? 0))")
                        .font(.caption.monospacedDigit())
                        .foregroundColor((s?.profit ?? 0) >= 0 ? OrderRow.profitColor : OrderRow.lossColor)
                }
            }
        }
    }

    private var eventsSection: some View {
        Section("Hoạt động") {
            if (status?.events ?? []).isEmpty {
                Text("Chưa có").foregroundColor(.secondary)
            }
            ForEach(status?.events ?? []) { e in
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.text).font(.subheadline)
                    Text(Date(timeIntervalSince1970: e.time).formatted(date: .omitted, time: .standard))
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
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
                    Text("Cần mật khẩu chính (mật khẩu investor không đặt lệnh được). Mật khẩu chỉ lưu trên VPS của bạn.")
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
                    Toggle("Cho phép tài khoản THẬT", isOn: Binding(get: { draft.allowReal }, set: { on in
                        if on { confirmReal = true } else { draft.allowReal = false }
                    }))
                    .tint(.red)
                } header: {
                    Text("Lệnh")
                } footer: {
                    Text("Ví dụ hệ số 2: lệnh chính 0.05 lot → tài khoản này 0.10 lot (không quá mức tối đa). Tài khoản thật bị bỏ qua nếu chưa bật cho phép.")
                }

                Section {
                    TextField("XAUUSDm=XAUUSD", text: $draft.symbolMap, axis: .vertical)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(1...5)
                    TextField("Đường dẫn terminal64.exe (để trống = tự sao chép MT5)", text: $draft.path)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Nâng cao")
                } footer: {
                    Text("Đổi tên mã: mỗi dòng 'mã chính=mã copy' khi hai tài khoản đặt tên khác nhau. Mặc định tự tìm (XAUUSDm ↔ XAUUSD ↔ XAUUSD.r). Đường dẫn MT5: chỉ cần khi muốn dùng một MT5 riêng đã cài (vd sàn khác).")
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
            .confirmationDialog("Copy vào tài khoản TIỀN THẬT?", isPresented: $confirmReal, titleVisibility: .visible) {
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
