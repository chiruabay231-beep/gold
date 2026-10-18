import SwiftUI
import UIKit
import BacktestKit

/// Enter, check and save the OANDA API token.
struct OandaSettingsView: View {
    /// Called after the token was saved or deleted.
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var environment = OandaSettings.environment
    @State private var token = OandaSettings.token ?? ""
    @State private var checking = false
    @State private var checkResult: String?
    @State private var checkOK = false

    private var trimmedToken: String { token.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Loại tài khoản", selection: $environment) {
                        ForEach(OandaClient.Environment.allCases, id: \.self) { env in
                            Text(env.title).tag(env)
                        }
                    }
                    SecureField("API token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    Button {
                        if let text = UIPasteboard.general.string { token = text.trimmingCharacters(in: .whitespacesAndNewlines) }
                    } label: {
                        Label("Dán token đã copy", systemImage: "doc.on.clipboard")
                    }
                } footer: {
                    if !trimmedToken.isEmpty && !OandaClient.looksLikeToken(trimmedToken) {
                        Text("Token OANDA có dạng 32 ký tự - 32 ký tự (tổng 65 ký tự, chỉ gồm 0-9 và a-f). Kiểm tra lại đã copy đủ chưa.")
                            .foregroundColor(.orange)
                    } else {
                        Text("Token chỉ lưu trong Keychain của máy này, không gửi đi đâu ngoài OANDA.")
                    }
                }

                Section {
                    Button {
                        Task { await check() }
                    } label: {
                        HStack {
                            Text("Kiểm tra kết nối")
                            Spacer()
                            if checking { ProgressView() }
                        }
                    }
                    .disabled(trimmedToken.isEmpty || checking)
                    if let checkResult {
                        Label(checkResult, systemImage: checkOK ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundColor(checkOK ? .green : .red)
                            .font(.footnote)
                    }
                }

                Section("Lấy token ở đâu") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Đăng nhập oanda.com bằng tài khoản fxTrade hoặc fxTrade Practice (demo).")
                        Text("2. Mở menu tài khoản, tìm mục **Manage API Access** (Quản lý truy cập API).")
                        Text("3. Bấm **Generate**, rồi copy toàn bộ token.")
                        Text("4. Token tạo từ tài khoản demo thì chọn **Demo**, từ tài khoản thật thì chọn **Live**.")
                        Text("Tài khoản loại MT4/MT5 không có API. Cần tài khoản loại fxTrade (v20).")
                            .foregroundColor(.secondary)
                    }
                    .font(.footnote)
                }

                if OandaSettings.hasToken {
                    Section {
                        Button("Xoá token khỏi máy", role: .destructive) {
                            OandaSettings.deleteToken()
                            onSaved()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("OANDA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        OandaSettings.environment = environment
                        OandaSettings.saveToken(trimmedToken)
                        onSaved()
                        dismiss()
                    }
                    .disabled(trimmedToken.isEmpty)
                }
            }
        }
    }

    @MainActor
    private func check() async {
        checking = true
        defer { checking = false }
        do {
            let accounts = try await OandaClient(environment: environment, token: trimmedToken).fetchAccounts()
            checkOK = true
            checkResult = accounts.isEmpty
                ? "Token đúng nhưng chưa có tài khoản nào."
                : "Kết nối được · tài khoản \(accounts.joined(separator: ", "))"
        } catch {
            checkOK = false
            checkResult = error.localizedDescription
        }
    }
}
