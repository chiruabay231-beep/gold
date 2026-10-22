import SwiftUI
import UIKit

/// First screen without access: a member enters the invite code they were sent
/// (or pastes the whole invite message); the owner signs in with the VPS
/// address and password. Nothing else of the app shows until then.
struct WelcomeGate: View {
    @Environment(MemberFeed.self) private var feed

    @State private var urlText = MemberSettings.url
    @State private var codeText = ""
    @State private var busy = false
    @State private var error: String?
    @State private var showOwner = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(LinearGradient(colors: [Color(red: 0.98, green: 0.82, blue: 0.35),
                                                                     Color(red: 0.8, green: 0.55, blue: 0.1)],
                                                            startPoint: .top, endPoint: .bottom))
                        Text("Aurum Pro").font(.system(size: 30, weight: .bold))
                        Text("Nhập mã mời để xem tín hiệu").font(.subheadline).foregroundColor(.secondary)
                    }
                    .padding(.top, 40)

                    if feed.revoked {
                        Label("Mã của bạn đã bị khoá hoặc hết hạn. Liên hệ người cung cấp để có mã mới.",
                              systemImage: "lock.fill")
                            .font(.footnote)
                            .foregroundColor(.orange)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }

                    VStack(spacing: 12) {
                        Button {
                            pasteInvite()
                        } label: {
                            Label("Dán tin nhắn mời", systemImage: "doc.on.clipboard")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        field("Địa chỉ máy chủ (https://…)", text: $urlText, keyboard: .URL)
                        field("Mã mời, vd ABCD-EFGH-JKLM", text: $codeText, keyboard: .asciiCapable, monospaced: true)
                        Button {
                            connect()
                        } label: {
                            HStack {
                                if busy { ProgressView().tint(.white) }
                                Text("Vào app").bold()
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy || urlText.isEmpty || codeText.isEmpty)
                        if let error {
                            Text(error).font(.footnote).foregroundColor(.red).multilineTextAlignment(.center)
                        }
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                    Text("Người cung cấp tín hiệu gửi cho bạn tin nhắn có địa chỉ và mã mời: chép cả tin nhắn rồi bấm \"Dán tin nhắn mời\".")
                        .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)

                    Button("Tôi là chủ máy chủ") { showOwner = true }
                        .font(.footnote)
                        .padding(.top, 20)
                }
                .padding(.horizontal, 20)
            }
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $showOwner) { OwnerSignIn() }
        }
    }

    private func field(_ title: String, text: Binding<String>, keyboard: UIKeyboardType, monospaced: Bool = false) -> some View {
        TextField(title, text: text)
            .keyboardType(keyboard)
            .textInputAutocapitalization(monospaced ? .characters : .never)
            .autocorrectionDisabled()
            .font(monospaced ? .body.monospaced() : .body)
            .padding(12)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Reads "Địa chỉ: …" and "Mã mời: …" from the invite message on the clipboard.
    private func pasteInvite() {
        guard let text = UIPasteboard.general.string else { return }
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else {
                if line.hasPrefix("https://") { urlText = String(line) }
                continue
            }
            let key = parts[0].lowercased()
            if key.hasPrefix("địa chỉ") || key.hasPrefix("dia chi") { urlText = parts[1] }
            if key.hasPrefix("mã") || key.hasPrefix("ma moi") || key.hasPrefix("code") { codeText = parts[1] }
        }
        if codeText.isEmpty, text.count <= 20 { codeText = text.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func connect() {
        busy = true
        error = nil
        let url = urlText, code = codeText
        Task {
            let ok = await feed.connect(url: url, code: code)
            busy = false
            if !ok {
                let message = feed.error ?? "Không kết nối được"
                error = message.contains("Sai mật khẩu") ? "Mã mời không đúng" : message
            }
        }
    }
}

/// The owner opens the app with their VPS address and password (checked first).
struct OwnerSignIn: View {
    @Environment(MemberFeed.self) private var feed
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = RemoteBotSettings.url
    @State private var passwordText = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Địa chỉ máy chủ (https://…)", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("Mật khẩu máy chủ", text: $passwordText)
                } footer: {
                    Text("Địa chỉ và mật khẩu hiện ra khi cài bot trên VPS (file config.json). Chỉ lưu trong Keychain của máy này.")
                }
                if let error {
                    Section { Text(error).font(.footnote).foregroundColor(.red) }
                }
            }
            .navigationTitle("Chủ máy chủ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy {
                        ProgressView()
                    } else {
                        Button("Vào") { signIn() }
                            .disabled(RemoteBotClient.normalizedURL(urlText) == nil || passwordText.isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func signIn() {
        guard let url = RemoteBotClient.normalizedURL(urlText) else { return }
        busy = true
        error = nil
        let password = passwordText
        Task {
            defer { busy = false }
            do {
                // Only the owner's password opens /status.
                _ = try await RemoteBotClient(baseURL: url, password: password).status()
                RemoteBotSettings.url = urlText
                RemoteBotSettings.savePassword(password)
                feed.ownerChanged()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
