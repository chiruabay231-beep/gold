# Gold Backtest — app iOS backtest & chỉ báo tự phát triển

App iOS (SwiftUI) để chạy backtest chiến lược giao dịch (XAUUSD, BTC, …) và tự
viết thêm chỉ báo ngay trên điện thoại, không cần build lại app.

```
├── Package.swift            # BacktestKit — lõi backtest (Swift thuần, có unit test)
├── Sources/BacktestKit/
│   ├── Data/                # Đọc CSV (MT4/MT5/Exness, TradingView), tải nến Binance
│   ├── Script/              # Ngôn ngữ script cho chỉ báo & chiến lược
│   ├── Indicators/          # Hàm TA, chỉ báo tự tạo, chỉ báo native viết bằng Swift
│   ├── Strategy/            # Định nghĩa chiến lược + mẫu
│   └── Engine/              # Engine backtest, thống kê, tối ưu tham số
├── Tests/BacktestKitTests/
└── App/                     # App iOS (SwiftUI + Swift Charts), project tạo bằng XcodeGen
```

## Chạy app

Yêu cầu: macOS, Xcode 15 trở lên, iOS 17 trở lên.

```bash
brew install xcodegen
cd App
xcodegen generate
open GoldBacktest.xcodeproj
```

### Cài lên iPhone thật

1. Xcode → *Settings… → Accounts* → **+** → đăng nhập Apple ID.
2. Cắm iPhone, mở khoá, bấm *Tin cậy* máy tính này. Bật *Cài đặt → Quyền riêng tư & Bảo mật →
   Chế độ nhà phát triển* (iPhone khởi động lại).
3. Xcode: target **GoldBacktest** → *Signing & Capabilities* → **Team** = Apple ID của bạn,
   **Bundle Identifier** đổi thành tên riêng, ví dụ `com.andy.goldbacktest`.
4. Lưu lại để lần sau không phải chọn lại: `./save-signing.sh`
5. Chọn iPhone ở thanh trên của Xcode → bấm ▶︎. Lần đầu trên iPhone vào *Cài đặt → Cài đặt chung →
   Quản lý VPN & thiết bị* → tin cậy Apple ID của bạn.

Với Apple ID miễn phí, app chạy được 7 ngày, sau đó cắm máy và bấm ▶︎ lại.

### Cập nhật khi có code mới

```bash
cd gold/App
./update.sh
```

Rồi bấm ▶︎ trong Xcode.

### Đưa dữ liệu vào app

Mọi file `.csv` trong thư mục Documents của app được tự nhập khi mở tab *Dữ liệu*.

Simulator (app đang chạy; đổi `com.gold.backtest` nếu bạn dùng Bundle ID khác):

```bash
cp ~/Downloads/XAUUSD_H1.csv "$(xcrun simctl get_app_container booted com.gold.backtest data)/Documents/"
```

iPhone thật: cắm vào Mac → Finder → chọn iPhone → tab *Tệp* → kéo file CSV thả vào *GoldBacktest*.
Hoặc AirDrop / iCloud Drive rồi trong app chọn *+ → Nhập file CSV*.

Chạy test phần lõi (macOS hoặc Linux):

```bash
swift test
```

## Tính năng

**Live (Binance)**
- Nến realtime qua WebSocket của Binance (BTC, ETH, PAXG… hoặc nhập mã bất kỳ), khung 1m → 1D,
  thông tin 24h, tự kết nối lại, tự dùng máy chủ dự phòng `binance.vision` nếu bị chặn.
- Biểu đồ nến kiểu Binance: nền tối, MA(7/25/99), volume, trục giá bên phải, đường giá hiện tại;
  kéo để xem lịch sử, chụm để phóng to, giữ để hiện crosshair + OHLC.
- Chọn một chiến lược để theo dõi: mỗi khi đóng nến app chạy chiến lược, đánh dấu B/S trên biểu đồ,
  liệt kê tín hiệu kèm SL/TP và gửi thông báo. Chỉ chạy khi app đang mở (giới hạn của iOS).

**Live (Binance Futures: XAUUSDT, XAGUSDT, miễn phí)**
- Bấm tên mã ở thanh dưới, mục Binance Futures, chọn XAU/USDT. Đây là hợp đồng vĩnh cửu vàng của
  Binance, giá bám vàng giao ngay XAU, không cần tài khoản hay key, nến realtime qua WebSocket.
- Khung giây 5s, 10s, 15s, 30s: Binance không có sẵn nến này nên app tự ghép từ từng giao dịch
  (aggTrade); lịch sử lấy từ nến 1 giây (spot) hoặc các giao dịch gần nhất (futures). OANDA có sẵn S5–S30.
- Ngoài giờ thị trường vàng (cuối tuần) Binance giữ chỉ số ở giá đóng cửa, nên nến gần như đi ngang.

**Live (OANDA: XAUUSD thật, forex, chỉ số)**
- Bấm tên mã ở thanh dưới, mục OANDA, chọn XAUUSD (hoặc XAGUSD, EURUSD, NAS100USD…).
- Lần đầu app hỏi token: đăng nhập oanda.com, vào **Manage API Access**, bấm **Generate**, copy token
  (65 ký tự), dán vào app, chọn Demo/Live đúng loại tài khoản, bấm **Kiểm tra kết nối** rồi **Lưu**.
- Token chỉ lưu trong Keychain của máy. Đừng gửi token cho ai và đừng commit token vào repo.
- Cần tài khoản fxTrade hoặc fxTrade Practice (v20). Tài khoản loại MT4/MT5 không có API.
- Nến lấy theo giá Bid (giống MT5), cập nhật mỗi giây.

**Live kiểu TradingView**
- Giao diện sáng kiểu TradingView (đổi sang tối kiểu Binance ở menu ⋯), thanh dưới: mã · khung ·
  ✏️ vẽ · ƒ chỉ báo · ⋯ · hoàn tác · toàn màn hình.
- Công cụ vẽ: đường ngang, tia ngang, đường dọc, đường xu hướng, hộp vùng giá, vị thế Long/Short
  (SL/TP + RR chỉnh được), chữ. Chạm để chọn, kéo để di chuyển, đổi màu, xoá, hoàn tác; lưu theo mã.
- Lớp ICT: Midnight Open, AM Open (09:30 NY), Prev Day High/Low, Asian/London High/Low với nhãn trên
  trục giá; hộp killzone Asia/London/NY AM; hộp ICT macro (08:50–09:10 NY…) kèm giờ địa phương.

**Cài đặt biểu đồ (⋯ → Cài đặt biểu đồ)**, giống trang "Mã" của TradingView
- Kiểu nến (nến, nến rỗng, thanh OHLC, đường); màu theo giá đóng cửa phiên trước.
- Thân / Đường viền / Bóng nến: bật tắt và chọn màu tăng, màu giảm; có sẵn vài mẫu màu nhanh.
- Độ chính xác giá, múi giờ trục thời gian (theo máy, UTC, Hà Nội, New York…).
- Vốn, % rủi ro, hợp đồng/lot để công cụ Vị thế hiện số lot.

**Thanh vẽ kiểu TradingView**
- Bên trái: Con trỏ, Đường (xu hướng, tia, ngang, tia ngang, dọc), Fibonacci, Hình, Dự báo
  (Long/Short), Chú thích, Đo; Nam châm, Giữ chế độ vẽ, Khoá tất cả, Ẩn tất cả, Xoá tất cả.
- Khi chọn một hình: thanh kiểu nổi với màu (bảng màu + màu tuỳ ý), độ dày, kiểu nét, RR, chữ,
  khoá, nhân bản, ⚙️ cài đặt (nhập giá chính xác, SL/TP, số lot) và xoá.

**Dữ liệu**
- Nhập CSV xuất từ MT5/Exness (kể cả file UTF-16, cột `<DATE>` `<TIME>` riêng),
  TradingView, Binance… Tự nhận dấu phân cách `,` `;` tab và nhiều định dạng thời gian.
- Tải nến từ Binance (BTCUSDT, ETHUSDT, PAXGUSDT — token vàng bám XAUUSD…), tối đa 50.000 nến.
- Dữ liệu mẫu giả lập để thử ngay khi chưa có dữ liệu.
- Xem biểu đồ nến, bật/tắt chỉ báo, xuất lại CSV.

**Chỉ báo tự phát triển**
- Viết bằng script ngay trong app, có xem trước trực tiếp trên biểu đồ khi gõ.
- Có tham số (`length`, `mult`…), vẽ nhiều đường (`plot`), đường ngang (`hline`).
- Mỗi chỉ báo thành một hàm: gọi lại được trong chỉ báo khác và trong chiến lược.
- Hiển thị trên giá hoặc trong khung riêng.

**Chiến lược & backtest**
- Chiến lược là một script gán `long_entry`, `long_exit`, `short_entry`, `short_exit`,
  và tuỳ chọn `long_stop`, `long_target`, `short_stop`, `short_target` (giá SL/TP).
- Tín hiệu tính ở giá đóng cửa, khớp lệnh ở giá mở nến kế tiếp (không nhìn trước tương lai).
- SL/TP kiểm tra trong nến bằng high/low; nếu chạm cả hai trong một nến thì tính SL trước
  (thận trọng); nhảy giá qua mức SL/TP thì khớp ở giá mở.
- Khối lượng: % vốn, số lượng cố định (VD 100 oz = 1 lot vàng), số tiền cố định,
  hoặc **% rủi ro theo khoảng cách SL**.
- Phí % / phí cố định mỗi chiều, trượt giá/spread, cho phép Mua/Bán riêng.
- Múi giờ cho `hour`, `session()`, `daily_high()`… (mặc định UTC, có giờ Việt Nam).
- Giới hạn khoảng ngày; dữ liệu trước ngày bắt đầu vẫn dùng để "làm nóng" chỉ báo.
- Kết quả: lợi nhuận, tỉ lệ thắng, profit factor, max drawdown, Sharpe, Sortino, CAGR,
  so với mua & giữ, R trung bình, đường vốn, drawdown, biểu đồ có đánh dấu từng lệnh,
  danh sách lệnh và xuất CSV.
- **Tối ưu tham số** (grid search) theo lợi nhuận, profit factor, Sharpe, tỉ lệ thắng
  hoặc lợi nhuận/drawdown.

## Ngôn ngữ script

```
// Chú thích bằng // hoặc #
fast = ema(close, 12)          // gán biến
slow = ema(close, 26)
diff = fast - slow
plot(diff, "MACD")             // vẽ đường
hline(0)                       // đường ngang
```

| Cú pháp | Ý nghĩa |
|---|---|
| `open high low close volume hl2 hlc3 ohlc4` | Giá của nến |
| `bar_index time year month dayofmonth dayofweek hour minute` | Chỉ số nến & thời gian |
| `x[1]`, `x[n]` | Giá trị của `x` cách đây 1 / n nến |
| `+ - * / % ^` | Số học |
| `> < >= <= == !=` | So sánh (đúng = 1, sai = 0) |
| `and or not` (`&& \|\| !`) | Logic |
| `cond ? a : b` | Điều kiện |
| `ta.ema(...)`, `math.abs(...)` | Tiền tố kiểu Pine được chấp nhận |

Hàm có sẵn (xem đủ trong app: *Chỉ báo → Hàm & biến có sẵn*):

- Trung bình: `sma ema rma wma hma vwma kama`
- Dao động: `rsi macd macd_signal macd_hist stoch cci roc mom`
- Biến động: `tr atr bb_upper bb_mid bb_lower kc_upper kc_lower stdev variance zscore`
- Xu hướng: `adx plus_di minus_di highest lowest pivothigh pivotlow`
- Khối lượng: `obv vwap`
- Tín hiệu: `crossover crossunder cross rising falling barssince valuewhen change`
- Phiên: `session(start, end)` `newday daily_high daily_low`
- Toán: `abs sqrt log exp pow round floor ceil sign min max avg clamp nz na iff sum cum`
- Native (Swift): `supertrend supertrend_dir fvg_bull fvg_bear swing_high swing_low`

### ICT

Bộ hàm ICT tính giờ theo **New York** (tự đổi EDT/EST), không phụ thuộc múi giờ backtest.
Nên dùng dữ liệu M1–M15.

| Nhóm | Hàm |
|---|---|
| Killzone | `kz_asia()` `kz_london()` `kz_ny_am()` `kz_london_close()` `silver_bullet_london()` `silver_bullet()` `silver_bullet_pm()` `ny_session(start, end)` |
| Mức giá | `asia_high()` `asia_low()` `ny_midnight_open()` `prev_week_high()` `prev_week_low()` `daily_high()` `daily_low()` |
| Cấu trúc `(left, right)` | `structure` (1/−1) `bos_bull` `bos_bear` `mss_bull` `mss_bear` `sweep_ssl` `sweep_bsl` `dr_high` `dr_low` `equilibrium` |
| PD array | `bull_fvg_top/bottom/ce(min_size)` `bear_fvg_top/bottom/ce` `bull_ob_top/bottom(left, right, lookback)` `bear_ob_top/bottom` |

- FVG tăng: `high(n1) < low(n3)`, vùng `[high(n1), low(n3)]`, mất hiệu lực khi bị lấp hết.
- Swing được xác nhận sau `right` nến (đúng thời điểm có thể biết khi chạy thật).
- MSS = phá swing ngược cấu trúc hiện tại; BOS = phá swing nói chung; sweep = râu vượt swing nhưng đóng cửa quay lại.

Chỉ báo mẫu: *ICT Killzones, ICT Levels, ICT Fair Value Gaps, ICT Dealing Range, ICT Order Blocks,
ICT Market Structure*. Chiến lược mẫu: *ICT Silver Bullet, ICT Judas Swing (quét Asia + MSS),
ICT FVG trong Discount/Premium*. Đã cài app từ trước: *Chỉ báo → Khôi phục chỉ báo & chiến lược mẫu*.

Chưa có: SMT divergence (cần dữ liệu 2 mã cùng lúc).

### Ví dụ chỉ báo: dải biến động theo ATR

Tên hàm `atr_band`, tham số `length = 20`, `mult = 2`, hiển thị *Trên giá*.

```
mid = ema(close, length)
band = mult * atr(length)
plot(mid, "Giữa")
plot(mid + band, "Trên")
plot(mid - band, "Dưới")
```

Gọi lại trong chiến lược: `atr_band(20, 2)` trả về đường đầu tiên (`mid`).

### Ví dụ chiến lược: ICT killzone + phá đỉnh ngày trước (giờ VN)

Đặt múi giờ backtest là *Việt Nam (UTC+7)*.

```
in_kz = session(14, 17) or session(19, 22)
long_entry  = in_kz and crossover(close, daily_high())
short_entry = in_kz and crossunder(close, daily_low())
long_stop   = lowest(low, 5)
long_target = close + 2 * (close - lowest(low, 5))
short_stop  = highest(high, 5)
short_target = close - 2 * (highest(high, 5) - close)
long_exit  = session(23, 24)
short_exit = session(23, 24)
```

## Viết chỉ báo bằng Swift (native)

Script tính theo cả chuỗi dữ liệu (vectorised) nên rất nhanh nhưng không có
biến "nhớ trạng thái" giữa các nến. Logic kiểu trailing stop, máy trạng thái,
theo dõi order block… nên viết bằng Swift trong
[`Sources/BacktestKit/Indicators/NativeIndicators.swift`](Sources/BacktestKit/Indicators/NativeIndicators.swift):

```swift
public static var myIndicator: ScriptFunction {
    ScriptFunction("my_indicator", [.source(), .length(default: 14)],
                   category: category, summary: "Mô tả ngắn") { args in
        let source = args.series(0)       // series (số được nhân thành chuỗi)
        let length = try args.length(1)   // hằng số >= 1
        let d = args.data                 // open/high/low/close/volume/time
        var out = Series(repeating: .nan, count: args.count)
        var state = 0.0
        for i in stride(from: length, to: args.count, by: 1) {
            state = max(state, d.high[i]) // trạng thái giữ qua từng nến
            out[i] = source[i] - state
        }
        return .series(out)
    }
}
```

Thêm nó vào `NativeIndicators.all` là dùng được trong mọi script: `my_indicator(close, 20)`.
Hàm `TA.*` trong [`TA.swift`](Sources/BacktestKit/Indicators/TA.swift) có thể dùng lại.

## Lưu ý

- Kết quả backtest không đảm bảo lợi nhuận tương lai. Luôn kiểm tra lại bộ tham số
  tối ưu trên khoảng thời gian khác (out-of-sample) để tránh overfitting.
- Spread/trượt giá thực tế của XAUUSD thay đổi theo phiên và tin tức; nên đặt chi phí
  thận trọng.
- Dữ liệu được lưu trong thư mục Application Support của app trên máy.
