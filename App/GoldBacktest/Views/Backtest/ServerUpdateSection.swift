import SwiftUI
import UIKit

/// Updating the bot server on the VPS.
enum ServerUpdate {
    /// Version of bot-server/bot_server.py this app expects.
    static let latestVersion = "2.0"
    static let installCommand = "irm https://raw.githubusercontent.com/chiruabay231-beep/gold/claude/ios-backtest-custom-indicators-jptyoz/bot-server/install.ps1 | iex"

    /// The server answered "no such path": it predates the feature.
    static func isOutdated(_ error: Error) -> Bool {
        error.localizedDescription.contains("Không có đường dẫn")
    }

    static func isOlder(_ version: String?) -> Bool {
        (version ?? "0").compare(latestVersion, options: .numeric) == .orderedAscending
    }
}

/// "Update the server" from the app (servers from 1.1 on), or the command to
/// paste on the VPS for older ones.
struct ServerUpdateSection: View {
    let message: String
    @State private var busy = false
    @State private var result: String?
    @State private var manual = false
    @State private var copied = false

    var body: some View {
        Section {
            Label(message, systemImage: "arrow.down.circle")
                .foregroundColor(.orange)
            Button {
                Task { await update() }
            } label: {
                HStack {
                    Text("Cập nhật máy chủ VPS")
                    Spacer()
                    if busy { ProgressView() }
                }
            }
            .disabled(busy)
            if let result {
                Text(result).font(.footnote).foregroundColor(.secondary)
            }
            if manual {
                Text("Bản đang chạy trên VPS chưa tự cập nhật được (chỉ lần này). Vào VPS bằng Windows App, chuột phải Start → Terminal (Admin), dán lệnh:")
                    .font(.footnote)
                Text(ServerUpdate.installCommand)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Button {
                    UIPasteboard.general.string = ServerUpdate.installCommand
                    copied = true
                } label: {
                    Label(copied ? "Đã sao chép" : "Sao chép lệnh", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                Text("Cài đặt, lịch sử và tài khoản MT5 được giữ nguyên. Từ máy chủ 1.8, cập nhật xong bot tự chạy lại; nếu địa chỉ đổi, app tự tìm địa chỉ mới.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("Cập nhật máy chủ")
        }
    }

    private func update() async {
        guard let client = RemoteBotSettings.client() else { return }
        busy = true
        defer { busy = false }
        do {
            let version = try await client.updateServer()
            manual = false
            result = "Đã tải bản \(version). Máy chủ khởi động lại trong khoảng 10 giây, giữ nguyên địa chỉ."
        } catch {
            if ServerUpdate.isOutdated(error) {
                manual = true
                result = nil
            } else {
                result = error.localizedDescription
            }
        }
    }
}

extension RemoteBotClient {
    /// Asks the server to download the latest bot and restart; returns the new version.
    func updateServer() async throws -> String {
        struct Reply: Decodable { var version: String? }
        let data = try await send("/update", method: "POST", body: Data("{}".utf8), timeout: 200)
        return try JSONDecoder().decode(Reply.self, from: data).version ?? "?"
    }
}
