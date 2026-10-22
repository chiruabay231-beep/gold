import SwiftUI
import UIKit

/// First screen without access: a member enters the invite code they were sent
/// (or pastes the invite message) — nothing about servers; the owner signs in
/// from the small link at the bottom. Nothing else of the app shows until then.
struct WelcomeGate: View {
    @Environment(MemberFeed.self) private var feed

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
                        Text("Nhập mã mời để bắt đầu").font(.subheadline).foregroundColor(.secondary)
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
                        HStack(spacing: 8) {
                            field("ABCD-EFGH-JKLM", text: $codeText, keyboard: .asciiCapable, monospaced: true)
                            Button {
                                pasteInvite()
                            } label: {
                                Image(systemName: "doc.on.clipboard")
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Dán mã")
                        }
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
                        .disabled(busy || codeText.filter(\.isLetter).count + codeText.filter(\.isNumber).count < 12)
                        if let error {
                            Text(error).font(.footnote).foregroundColor(.red).multilineTextAlignment(.center)
                        }
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                    Text("Chưa có mã? Liên hệ người giới thiệu app để nhận mã mời.")
                        .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)

                    Button("Đăng nhập chủ") { showOwner = true }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 30)
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

    /// Finds the code (XXXX-XXXX-XXXX) in what was copied: the code or the whole message.
    private func pasteInvite() {
        guard let text = UIPasteboard.general.string?.uppercased() else { return }
        let pattern = #/[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}/#
        if let match = text.firstMatch(of: pattern) {
            codeText = String(match.output)
        } else {
            codeText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func connect() {
        busy = true
        error = nil
        let code = codeText
        Task {
            let ok = await feed.connect(code: code)
            busy = false
            if !ok { error = feed.error ?? "Không vào được, thử lại sau ít phút" }
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
                    Text("Dành cho chủ ứng dụng. Mật khẩu chỉ lưu trong Keychain của máy này.")
                }
                if let error {
                    Section { Text(error).font(.footnote).foregroundColor(.red) }
                }
            }
            .navigationTitle("Đăng nhập chủ")
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
