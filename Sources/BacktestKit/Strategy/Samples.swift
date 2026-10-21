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
        ] + ictIndicators
    }

    /// ICT toolkit: sessions, key levels, PD arrays and market structure.
    public static var ictIndicators: [CustomIndicator] {
        [
            CustomIndicator(
                name: "ict_killzones", title: "ICT Killzones",
                summary: "Asia = 1, London = 2, NY AM = 3, Silver Bullet = 4 (giờ New York, tự đổi EDT/EST)",
                script: """
                plot(kz_asia(), "Asia")
                plot(kz_london() * 2, "London")
                plot(kz_ny_am() * 3, "NY AM")
                plot(max(silver_bullet(), silver_bullet_london()) * 4, "Silver Bullet")
                """,
                placement: .pane),
            CustomIndicator(
                name: "ict_levels", title: "ICT Levels (Asia, PDH/PDL, Midnight Open)",
                summary: "Thanh khoản phiên Á, đỉnh/đáy ngày trước, giá mở 00:00 NY. PDH/PDL theo múi giờ backtest.",
                script: """
                plot(asia_high(), "Asia High")
                plot(asia_low(), "Asia Low")
                plot(daily_high(), "PDH")
                plot(daily_low(), "PDL")
                plot(ny_midnight_open(), "Midnight Open")
                """,
                placement: .overlay),
            CustomIndicator(
                name: "ict_fvg", title: "ICT Fair Value Gaps",
                summary: "FVG tăng/giảm gần nhất chưa bị lấp hết",
                parameters: [ScriptParameter(name: "min_size", defaultValue: 0, minValue: 0, maxValue: 20, step: 0.1)],
                script: """
                plot(bull_fvg_top(min_size), "FVG tăng - trên")
                plot(bull_fvg_bottom(min_size), "FVG tăng - dưới")
                plot(bear_fvg_top(min_size), "FVG giảm - trên")
                plot(bear_fvg_bottom(min_size), "FVG giảm - dưới")
                """,
                placement: .overlay),
            CustomIndicator(
                name: "ict_dealing_range", title: "ICT Dealing Range",
                summary: "Đỉnh/đáy swing gần nhất và Equilibrium: trên EQ = premium, dưới EQ = discount",
                parameters: [ScriptParameter(name: "swing", defaultValue: 10, minValue: 2, maxValue: 50, step: 1)],
                script: """
                plot(dr_high(swing, swing), "Đỉnh range (BSL)")
                plot(equilibrium(swing, swing), "Equilibrium")
                plot(dr_low(swing, swing), "Đáy range (SSL)")
                """,
                placement: .overlay),
            CustomIndicator(
                name: "ict_order_blocks", title: "ICT Order Blocks",
                parameters: [ScriptParameter(name: "swing", defaultValue: 5, minValue: 2, maxValue: 30, step: 1)],
                script: """
                plot(bull_ob_top(swing, swing), "OB tăng - trên")
                plot(bull_ob_bottom(swing, swing), "OB tăng - dưới")
                plot(bear_ob_top(swing, swing), "OB giảm - trên")
                plot(bear_ob_bottom(swing, swing), "OB giảm - dưới")
                """,
                placement: .overlay),
            CustomIndicator(
                name: "ict_structure", title: "ICT Market Structure",
                summary: "1 = cấu trúc tăng, −1 = giảm; cột MSS đánh dấu điểm đổi cấu trúc",
                parameters: [ScriptParameter(name: "swing", defaultValue: 5, minValue: 2, maxValue: 30, step: 1)],
                script: """
                plot(structure(swing, swing), "Cấu trúc")
                plot(mss_bull(swing, swing) * 0.5 - mss_bear(swing, swing) * 0.5, "MSS")
                hline(0)
                """,
                placement: .pane),
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
        ] + ictStrategies
    }

    /// ICT setups. Sessions use New York time (EDT/EST handled), so they work
    /// whatever time zone the backtest is set to. Use M1–M15 data.
    public static var ictStrategies: [StrategyDefinition] {
        [
            StrategyDefinition(
                name: "ICT Silver Bullet",
                summary: "Trong giờ Silver Bullet (03–04, 10–11, 14–15 NY), giá hồi vào FVG theo hướng cấu trúc. SL dưới/trên swing gần nhất, TP theo RR, chỉ vào khi RR ≥ 2.",
                parameters: [ScriptParameter(name: "swing", defaultValue: 5, minValue: 2, maxValue: 20, step: 1),
                             ScriptParameter(name: "rr", defaultValue: 2, minValue: 1, maxValue: 5, step: 0.5),
                             ScriptParameter(name: "min_fvg", defaultValue: 0, minValue: 0, maxValue: 5, step: 0.1)],
                script: """
                sb = silver_bullet() or silver_bullet_london() or silver_bullet_pm()
                bias = structure(swing, swing)

                // Giá hồi vào FVG còn hiệu lực
                in_bull_fvg = low <= bull_fvg_top(min_fvg) and close >= bull_fvg_bottom(min_fvg)
                in_bear_fvg = high >= bear_fvg_bottom(min_fvg) and close <= bear_fvg_top(min_fvg)

                long_stop    = lowest(low, swing * 2)
                long_target  = close + rr * (close - long_stop)
                short_stop   = highest(high, swing * 2)
                short_target = close - rr * (short_stop - close)

                long_entry  = sb and bias == 1 and in_bull_fvg
                short_entry = sb and bias == -1 and in_bear_fvg

                // Đóng lệnh còn lại trước phiên Á
                long_exit  = ny_session(16, 20)
                short_exit = ny_session(16, 20)

                plot(bull_fvg_top(min_fvg), "FVG tăng")
                plot(bear_fvg_bottom(min_fvg), "FVG giảm")
                """),
            StrategyDefinition(
                name: "ICT Judas Swing (quét Asia + MSS)",
                summary: "Trong London/NY AM killzone: giá quét đáy (đỉnh) phiên Á rồi có MSS ngược lại → vào theo hướng MSS. SL ở đáy/đỉnh vừa quét, TP theo RR.",
                parameters: [ScriptParameter(name: "swing", defaultValue: 3, minValue: 2, maxValue: 10, step: 1),
                             ScriptParameter(name: "window", defaultValue: 30, minValue: 5, maxValue: 120, step: 5),
                             ScriptParameter(name: "rr", defaultValue: 2, minValue: 1, maxValue: 5, step: 0.5)],
                script: """
                kz = kz_london() or kz_ny_am()

                // Thanh khoản phiên Á bị quét trong 'window' nến gần nhất
                ssl_taken = barssince(low < asia_low()) <= window
                bsl_taken = barssince(high > asia_high()) <= window

                long_stop    = lowest(low, window)
                long_target  = close + rr * (close - long_stop)
                short_stop   = highest(high, window)
                short_target = close - rr * (short_stop - close)

                long_entry  = kz and ssl_taken and mss_bull(swing, swing)
                short_entry = kz and bsl_taken and mss_bear(swing, swing)

                long_exit  = ny_session(16, 20)
                short_exit = ny_session(16, 20)

                plot(asia_high(), "Asia High")
                plot(asia_low(), "Asia Low")
                """),
            StrategyDefinition(
                name: "ICT FVG trong Discount/Premium",
                summary: "Cấu trúc tăng + giá ở vùng discount (dưới EQ) + hồi vào FVG tăng trong killzone → mua, TP tại đỉnh range (BSL). Ngược lại cho bán. Chỉ vào khi RR ≥ min_rr.",
                parameters: [ScriptParameter(name: "swing", defaultValue: 10, minValue: 3, maxValue: 30, step: 1),
                             ScriptParameter(name: "min_rr", defaultValue: 2, minValue: 1, maxValue: 5, step: 0.5)],
                script: """
                trend = structure(swing, swing)
                eq = equilibrium(swing, swing)
                kz = kz_london() or kz_ny_am()

                long_stop    = dr_low(swing, swing)
                long_target  = dr_high(swing, swing)
                short_stop   = dr_high(swing, swing)
                short_target = dr_low(swing, swing)

                long_rr  = (long_target - close) / (close - long_stop)
                short_rr = (close - short_target) / (short_stop - close)

                long_entry = kz and trend == 1 and close < eq and long_rr >= min_rr and low <= bull_fvg_top() and close >= bull_fvg_bottom()
                short_entry = kz and trend == -1 and close > eq and short_rr >= min_rr and high >= bear_fvg_bottom() and close <= bear_fvg_top()

                plot(dr_high(swing, swing), "Đỉnh range")
                plot(eq, "Equilibrium")
                plot(dr_low(swing, swing), "Đáy range")
                """),
            StrategyDefinition(
                name: "ICT M1 Trend · FVG Killzone",
                summary: "Khung M1, chỉ đánh thuận xu hướng: giá và EMA 50 trên EMA 200 + cấu trúc swing tăng → chờ giá hồi vào FVG tăng trong killzone London / NY AM, nến đóng bật lên thì MUA. Ngược lại cho BÁN. SL dưới FVG/đáy gần, TP = RR × rủi ro, thoát sớm khi có MSS ngược chiều.",
                parameters: [ScriptParameter(name: "fast_len", defaultValue: 50, minValue: 10, maxValue: 200, step: 10),
                             ScriptParameter(name: "trend_len", defaultValue: 200, minValue: 50, maxValue: 500, step: 50),
                             ScriptParameter(name: "swing", defaultValue: 3, minValue: 2, maxValue: 10, step: 1),
                             ScriptParameter(name: "rr", defaultValue: 2, minValue: 1, maxValue: 5, step: 0.5),
                             ScriptParameter(name: "sl_buffer", defaultValue: 0.3, minValue: 0, maxValue: 2, step: 0.1)],
                script: """
                // 1. Xu hướng: EMA nhanh / EMA 200 và cấu trúc swing cùng hướng
                fast = ema(close, fast_len)
                trend = ema(close, trend_len)
                ms = structure(swing, swing)
                uptrend   = close > trend and fast > trend and ms == 1
                downtrend = close < trend and fast < trend and ms == -1

                // 2. Thời gian: chỉ trong killzone London và New York AM (giờ New York, tự đổi giờ mùa hè)
                kz = kz_london() or kz_ny_am()

                // 3. Vùng vào lệnh: FVG gần nhất thuận xu hướng chưa bị lấp
                up_top = bull_fvg_top()
                up_bot = bull_fvg_bottom()
                dn_top = bear_fvg_top()
                dn_bot = bear_fvg_bottom()

                // 4. Kích hoạt: giá hồi chạm FVG rồi nến đóng cửa bật lại theo xu hướng
                long_entry  = kz and uptrend and low <= up_top and close > up_bot and close > open
                short_entry = kz and downtrend and high >= dn_bot and close < dn_top and close < open

                // 5. Quản lý: SL ngoài FVG / đỉnh-đáy 5 nến + đệm ATR, TP theo RR
                a = atr(14)
                long_stop    = min(up_bot, lowest(low, 5)) - sl_buffer * a
                short_stop   = max(dn_top, highest(high, 5)) + sl_buffer * a
                long_target  = close + rr * (close - long_stop)
                short_target = close - rr * (short_stop - close)

                // 6. Thoát sớm khi cấu trúc đảo chiều (MSS ngược chiều)
                long_exit  = mss_bear(swing, swing)
                short_exit = mss_bull(swing, swing)

                plot(fast, "EMA nhanh")
                plot(trend, "EMA xu hướng")
                """),
            StrategyDefinition(
                name: "ICT M1 · FVG/VI + Dòng tiền cá mập",
                summary: "Khung M1. MUA khi: giá trên EMA 200 và cấu trúc tăng, trong killzone London / NY AM, giá hồi chạm FVG MẠNH hoặc VI tăng rồi nến đóng bật lên, và dòng tiền đang VÀO (tuỳ chọn: có cá mập mua trong 15 nến). BÁN ngược lại. SL dưới đáy 5 nến + đệm ATR, TP = RR × rủi ro; thoát sớm khi có MSS ngược chiều hoặc dòng tiền đảo chiều mạnh.",
                parameters: [ScriptParameter(name: "trend_len", defaultValue: 200, minValue: 50, maxValue: 500, step: 50),
                             ScriptParameter(name: "swing", defaultValue: 3, minValue: 2, maxValue: 10, step: 1),
                             ScriptParameter(name: "disp", defaultValue: 1.5, minValue: 1, maxValue: 4, step: 0.25),
                             ScriptParameter(name: "flow_len", defaultValue: 20, minValue: 5, maxValue: 60, step: 5),
                             ScriptParameter(name: "flow_min", defaultValue: 0.05, minValue: 0, maxValue: 0.5, step: 0.05),
                             ScriptParameter(name: "exit_flow", defaultValue: 0.35, minValue: 0.1, maxValue: 1, step: 0.05),
                             ScriptParameter(name: "use_shark", defaultValue: 0, minValue: 0, maxValue: 1, step: 1),
                             ScriptParameter(name: "shark_mult", defaultValue: 2.5, minValue: 1.5, maxValue: 5, step: 0.5),
                             ScriptParameter(name: "rr", defaultValue: 2, minValue: 1, maxValue: 5, step: 0.5),
                             ScriptParameter(name: "sl_buffer", defaultValue: 0.3, minValue: 0, maxValue: 2, step: 0.1)],
                script: """
                // 1. Xu hướng: giá so với EMA 200 và cấu trúc swing cùng hướng
                trend = ema(close, trend_len)
                ms = structure(swing, swing)
                up   = close > trend and ms == 1
                down = close < trend and ms == -1

                // 2. Thời gian: killzone London hoặc New York AM (giờ New York)
                kz = kz_london() or kz_ny_am()

                // 3. Vùng ICT: FVG mạnh hoặc VI thuận chiều, giá hồi chạm vùng
                in_bull = (low <= bull_sfvg_top(disp) and close > bull_sfvg_bottom(disp)) or (low <= bull_vi_top() and close > bull_vi_bottom())
                in_bear = (high >= bear_sfvg_bottom(disp) and close < bear_sfvg_top(disp)) or (high >= bear_vi_bottom() and close < bear_vi_top())

                // 4. Dòng tiền: tiền đang vào để mua, đang ra để bán; use_shark = 1 đòi thêm cá mập gần đây
                mf = money_flow(flow_len)
                shark_up = highest(shark_buy(shark_mult), 15) > 0
                shark_dn = highest(shark_sell(shark_mult), 15) > 0
                money_up = mf > flow_min and (use_shark == 0 or shark_up)
                money_dn = mf < -flow_min and (use_shark == 0 or shark_dn)

                // 5. Vào lệnh khi nến đóng bật lại theo hướng
                long_entry  = kz and up and in_bull and money_up and close > open
                short_entry = kz and down and in_bear and money_dn and close < open

                // 6. SL dưới/trên đỉnh-đáy 5 nến + đệm ATR, TP theo RR
                a = atr(14)
                long_stop    = lowest(low, 5) - sl_buffer * a
                short_stop   = highest(high, 5) + sl_buffer * a
                long_target  = close + rr * (close - long_stop)
                short_target = close - rr * (short_stop - close)

                // 7. Thoát sớm: MSS ngược chiều hoặc dòng tiền đảo chiều mạnh
                long_exit  = mss_bear(swing, swing) or mf < -exit_flow
                short_exit = mss_bull(swing, swing) or mf > exit_flow

                plot(trend, "EMA xu hướng")
                plot(mf, "Dòng tiền")
                """),
        ]
    }
}
