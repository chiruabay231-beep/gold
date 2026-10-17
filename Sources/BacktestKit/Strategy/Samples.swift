import Foundation

/// Starter indicators and strategies shown on first launch.
public enum Samples {
    public static var indicators: [CustomIndicator] {
        [
            CustomIndicator(
                name: "ema_ribbon", title: "EMA Ribbon",
                summary: "Ba đường EMA để xem cấu trúc xu hướng",
                parameters: [ScriptParameter(name: "fast", defaultValue: 9, minValue: 2, maxValue: 100, step: 1),
                             ScriptParameter(name: "mid", defaultValue: 21, minValue: 2, maxValue: 200, step: 1),
                             ScriptParameter(name: "slow", defaultValue: 50, minValue: 2, maxValue: 400, step: 1)],
                script: """
                plot(ema(close, fast), "EMA nhanh")
                plot(ema(close, mid), "EMA giữa")
                plot(ema(close, slow), "EMA chậm")
                """,
                placement: .overlay),
            CustomIndicator(
                name: "trend_strength", title: "Trend Strength",
                summary: "Khoảng cách giá tới EMA tính theo ATR, > 0 là trên EMA",
                parameters: [ScriptParameter(name: "length", defaultValue: 50, minValue: 5, maxValue: 300, step: 1),
                             ScriptParameter(name: "atr_len", defaultValue: 14, minValue: 2, maxValue: 100, step: 1)],
                script: """
                // Độ lệch của giá so với EMA, chuẩn hoá theo ATR
                (close - ema(close, length)) / atr(atr_len)
                """,
                placement: .pane),
            CustomIndicator(
                name: "rsi_bands", title: "RSI + vùng quá mua/bán",
                parameters: [ScriptParameter(name: "length", defaultValue: 14, minValue: 2, maxValue: 100, step: 1)],
                script: """
                r = rsi(close, length)
                plot(r, "RSI")
                hline(70, "Quá mua")
                hline(30, "Quá bán")
                """,
                placement: .pane),
            CustomIndicator(
                name: "squeeze", title: "Bollinger Squeeze",
                summary: "1 khi dải Bollinger nằm trong dải Keltner (biến động bị nén)",
                parameters: [ScriptParameter(name: "length", defaultValue: 20, minValue: 5, maxValue: 100, step: 1)],
                script: """
                bb_upper(close, length, 2) < kc_upper(length, 1.5) and bb_lower(close, length, 2) > kc_lower(length, 1.5)
                """,
                placement: .pane),
            CustomIndicator(
                name: "killzone", title: "ICT Killzone (giờ VN)",
                summary: "1 trong phiên London 14h–17h và New York 19h–22h giờ Việt Nam. Đặt múi giờ backtest là Asia/Ho_Chi_Minh.",
                script: """
                session(14, 17) or session(19, 22)
                """,
                placement: .pane),
            CustomIndicator(
                name: "pd_levels", title: "Đỉnh/đáy ngày hôm trước",
                summary: "PDH / PDL — vùng thanh khoản quan trọng",
                script: """
                plot(daily_high(), "PDH")
                plot(daily_low(), "PDL")
                """,
                placement: .overlay),
        ]
    }

    public static var strategies: [StrategyDefinition] {
        [
            StrategyDefinition(
                name: "EMA Cross + ATR",
                summary: "Mua khi EMA nhanh cắt lên EMA chậm, bán khi cắt xuống. Cắt lỗ 2 ATR, chốt lời 3 ATR.",
                parameters: [ScriptParameter(name: "fast_len", defaultValue: 9, minValue: 2, maxValue: 50, step: 1),
                             ScriptParameter(name: "slow_len", defaultValue: 21, minValue: 5, maxValue: 200, step: 1),
                             ScriptParameter(name: "sl_atr", defaultValue: 2, minValue: 0.5, maxValue: 5, step: 0.5),
                             ScriptParameter(name: "tp_atr", defaultValue: 3, minValue: 0.5, maxValue: 10, step: 0.5)],
                script: """
                fast = ema(close, fast_len)
                slow = ema(close, slow_len)
                a = atr(14)

                long_entry  = crossover(fast, slow)
                short_entry = crossunder(fast, slow)

                long_stop    = close - sl_atr * a
                long_target  = close + tp_atr * a
                short_stop   = close + sl_atr * a
                short_target = close - tp_atr * a

                plot(fast, "EMA nhanh")
                plot(slow, "EMA chậm")
                """),
            StrategyDefinition(
                name: "RSI Mean Reversion",
                summary: "Mua khi RSI thoát vùng quá bán trong xu hướng tăng (giá trên EMA), thoát khi RSI vượt 50.",
                parameters: [ScriptParameter(name: "rsi_len", defaultValue: 7, minValue: 2, maxValue: 50, step: 1),
                             ScriptParameter(name: "oversold", defaultValue: 30, minValue: 5, maxValue: 45, step: 5),
                             ScriptParameter(name: "trend_len", defaultValue: 100, minValue: 50, maxValue: 400, step: 50)],
                script: """
                r = rsi(close, rsi_len)
                trend = ema(close, trend_len)

                long_entry = close > trend and crossover(r, oversold)
                long_exit  = r > 50
                long_stop  = lowest(low, 10)

                plot(trend, "EMA xu hướng")
                """),
            StrategyDefinition(
                name: "Supertrend",
                summary: "Đi theo hướng Supertrend (chỉ báo native viết bằng Swift).",
                parameters: [ScriptParameter(name: "length", defaultValue: 10, minValue: 5, maxValue: 50, step: 1),
                             ScriptParameter(name: "mult", defaultValue: 3, minValue: 1, maxValue: 6, step: 0.5)],
                script: """
                dir = supertrend_dir(length, mult)
                long_entry  = dir == 1 and dir[1] == -1
                short_entry = dir == -1 and dir[1] == 1
                plot(supertrend(length, mult), "Supertrend")
                """),
            StrategyDefinition(
                name: "Breakout PDH/PDL trong Killzone",
                summary: "Phá đỉnh/đáy ngày trước trong giờ London/New York (giờ VN). Đặt múi giờ Asia/Ho_Chi_Minh.",
                parameters: [ScriptParameter(name: "rr", defaultValue: 2, minValue: 1, maxValue: 5, step: 0.5)],
                script: """
                in_kz = session(14, 17) or session(19, 22)
                pdh = daily_high()
                pdl = daily_low()

                long_entry  = in_kz and crossover(close, pdh)
                short_entry = in_kz and crossunder(close, pdl)

                long_stop    = lowest(low, 5)
                long_target  = close + rr * (close - lowest(low, 5))
                short_stop   = highest(high, 5)
                short_target = close - rr * (highest(high, 5) - close)

                // Đóng lệnh khi hết phiên New York
                long_exit  = session(23, 24)
                short_exit = session(23, 24)

                plot(pdh, "PDH")
                plot(pdl, "PDL")
                """),
        ]
    }
}
