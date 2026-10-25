import SwiftUI
import UIKit
import BacktestKit

/// Controls of bar replay: exit, choose start, play/pause, one bar forward,
/// speed, and the replay account's result.
struct ReplayControlBar: View {
    @Bindable var replay: ReplaySession
    let profit: Double
    let trades: Int
    let theme: ChartTheme
    var onExit: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            if replay.isPicking {
                // Tap a bar to place the start line (tap again to move it), then Bắt đầu.
                HStack(spacing: 8) {
                    Image(systemName: "scissors")
                    Text(replay.candidate == nil ? "Chạm vào cây nến muốn bắt đầu replay"
                         : "Phần mờ sẽ bị ẩn · chạm nến khác để đổi")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if replay.candidate != nil {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            replay.startFromCandidate()
                        } label: {
                            Text("Bắt đầu")
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .foregroundColor(theme.accent)
                                .background(Color.white, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .padding(.leading, 12)
                .padding(.trailing, replay.candidate == nil ? 12 : 4)
                .padding(.vertical, 4)
                .frame(minHeight: 32)
                .background(theme.accent, in: Capsule())
            }
            HStack(spacing: 4) {
                button("xmark", action: onExit)
                    .accessibilityLabel("Thoát replay")
                button("scissors") { replay.repick() }
                    .accessibilityLabel("Chọn lại điểm bắt đầu")
                button(replay.isPlaying ? "pause.fill" : "play.fill", prominent: true) {
                    if replay.isPicking {
                        // Play while picking: start from the chosen bar and play at once.
                        replay.startFromCandidate()
                        replay.play()
                    } else {
                        replay.isPlaying ? replay.pause() : replay.play()
                    }
                }
                .disabled(replay.isPicking ? replay.candidate == nil : replay.atEnd)
                button("forward.frame.fill") { replay.step() }
                    .disabled(replay.isPicking || replay.atEnd)
                    .accessibilityLabel("Nến tiếp theo")
                Menu {
                    Picker("Tốc độ", selection: $replay.speed) {
                        ForEach(ReplaySession.speeds, id: \.self) { speed in
                            Text("\(String(format: "%g", speed)) nến/giây").tag(speed)
                        }
                    }
                } label: {
                    Text("\(String(format: "%g", replay.speed))x")
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .frame(width: 40, height: 36)
                        .foregroundColor(theme.primaryText)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(String(format: "%+.2f USD", profit))
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundColor(profit >= 0 ? theme.up : theme.down)
                    Text(replay.currentBar.map { $0.time.formatted(date: .abbreviated, time: .shortened) } ?? "")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundColor(theme.text)
                    Text("\(trades) lệnh")
                        .font(.system(size: 10))
                        .foregroundColor(theme.text)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 8)
    }

    private func button(_ systemName: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: prominent ? 18 : 15, weight: .semibold))
                .frame(width: 38, height: 36)
                .foregroundColor(prominent ? .white : theme.primaryText)
                .background(prominent ? theme.accent : .clear, in: Circle())
        }
    }
}
