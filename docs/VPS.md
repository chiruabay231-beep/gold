# Chạy bot 24/7 trên VPS Windows

Bot trong app chỉ chạy khi app đang mở. Trên VPS, bot chạy liên tục, kể cả khi
bạn tắt điện thoại, và bạn bật/tắt nó ngay trong app
(**Backtest → Bot → Bot trên VPS**).

```
iPhone (app)  ──HTTPS + mật khẩu──►  Cloudflare Tunnel  ──►  VPS Windows
                                                              ├─ bot_server.py  (máy chủ bot)
                                                              ├─ botkit.exe     (chạy code chiến lược, giống hệt Backtest)
                                                              ├─ giá: Binance  hoặc  MT5 Exness
                                                              └─ Telegram: báo mọi lệnh
```

* **Giai đoạn 1:** giá Binance Futures XAUUSDT, lệnh vào tài khoản demo trên VPS. Không cần tài khoản sàn.
* **Giai đoạn 2:** giá và lệnh qua MT5 của Exness: lệnh demo trước, rồi lệnh thật.

## 1. Thuê VPS

* Hệ điều hành **Windows Server 2022** (hoặc 2019/2025), **2 GB RAM** trở lên, 1–2 vCPU.
* Vị trí gần máy chủ Exness: London / Amsterdam / Frankfurt.
* Nhà cung cấp gửi cho bạn **IP**, tên đăng nhập (thường là `Administrator`) và mật khẩu.
  **Không gửi mật khẩu VPS cho ai, kể cả trong chat.**

## 2. Vào VPS từ iPhone hoặc Mac

1. Cài app **Windows App** (Microsoft) từ App Store.
2. **+ → Add PC** → nhập IP → **Add**.
3. Bấm vào máy vừa thêm, đăng nhập bằng tên và mật khẩu VPS.

## 3. Cài bot (một lệnh)

Trên VPS: chuột phải nút **Start → Terminal (Admin)** (hoặc *Windows PowerShell (Admin)*), dán:

```powershell
irm https://raw.githubusercontent.com/chiruabay231-beep/gold/claude/ios-backtest-custom-indicators-jptyoz/bot-server/install.ps1 | iex
```

Script tự làm hết:

* tải `botkit.exe` và máy chủ bot (bản build mới nhất `bot-latest`) vào `C:\GoldBot`;
* cài Python 3.12, Visual C++ runtime, thư viện MetaTrader5 và Cloudflare Tunnel;
* tự kiểm tra botkit với các chiến lược mẫu;
* tạo `config.json` với **mật khẩu máy chủ ngẫu nhiên**, hỏi token Telegram (Enter để bỏ qua);
* đăng ký tác vụ **GoldBot** tự chạy khi bật máy và tự khởi động lại nếu lỗi.

Cuối cùng màn hình hiện:

```
Địa chỉ máy chủ : https://xxxx-yyyy.trycloudflare.com
Mật khẩu máy chủ: ••••••••••••••••
```

Chạy lại đúng lệnh trên để **cập nhật** bot; `config.json` và lịch sử lệnh được giữ.

## 4. Telegram (khuyên dùng)

1. Trong Telegram tìm **@BotFather** → `/newbot` → đặt tên → nhận **token**.
2. Dán token khi script cài hỏi (hoặc sửa `C:\GoldBot\config.json` → `telegram.token`, rồi khởi động lại VPS).
3. Nhắn bất kỳ chữ nào cho bot của bạn: bot trả lời "Đã liên kết". Từ đó mọi lệnh, TP/SL, dời SL đều báo về Telegram.

Lệnh Telegram: `/status` trạng thái · `/url` địa chỉ máy chủ · `/start` chạy lại · `/stop` dừng · `/close` đóng mọi lệnh của bot.

> Địa chỉ `trycloudflare.com` **đổi mỗi khi VPS khởi động lại**. Bot Telegram tự gửi địa chỉ mới; trong app bấm **Sửa** và dán địa chỉ mới (mật khẩu giữ nguyên).

## 5. Kết nối app

1. App → **Backtest → Bot → Bot trên VPS (chạy 24/7)**.
2. Nhập **địa chỉ** và **mật khẩu máy chủ** → **Lưu và kết nối**. Mật khẩu lưu trong Keychain của iPhone.
3. Chọn chiến lược, nguồn giá **Binance Futures**, mã `XAUUSDT`, khung (1m…1d), khối lượng hoặc % rủi ro.
4. **Chạy bot 24/7 (demo)**.

App gửi lên VPS: code chiến lược, chỉ báo tự viết, cài đặt Backtest và cài đặt dời SL / tự chốt khi đảo chiều.
Bot kiểm tra tín hiệu mỗi khi một nến đóng, SL/TP kiểm tra mỗi 2 giây.
**Dừng bot không đóng lệnh đang mở** (lệnh vẫn giữ SL/TP); đóng lệnh bằng nút ✕ trong app hoặc `/close`.

## 6. Giai đoạn 2: Exness MT5

1. Trên VPS tải **MetaTrader 5** từ trang Exness, cài và đăng nhập tài khoản (demo trước).
   Tick **Save password**. Trong MT5: **Tools → Options → Expert Advisors → Allow algorithmic trading**.
2. Sửa `C:\GoldBot\config.json`, mục `mt5`:

   ```json
   "mt5": {
     "path": "C:\\Program Files\\MetaTrader 5 EXNESS\\terminal64.exe",
     "login": 12345678,
     "password": "",
     "server": "Exness-MT5Trial7",
     "trading_enabled": false,
     "allow_real_account": false,
     "max_lots": 0.1
   }
   ```

   * Chỉ lấy giá: dùng **mật khẩu investor** (chỉ đọc), `trading_enabled: false`.
   * Cho bot đặt lệnh: mật khẩu chính và `trading_enabled: true`.
   * Tài khoản **thật** còn cần `allow_real_account: true`. `max_lots` là khối lượng tối đa mỗi lệnh.
   * Có thể để trống `login/password/server` nếu MT5 đã đăng nhập sẵn.
3. MT5 cần phiên Windows đang đăng nhập, nên đổi tác vụ sang "chạy khi đăng nhập". Mở PowerShell (Admin):

   ```powershell
   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/chiruabay231-beep/gold/claude/ios-backtest-custom-indicators-jptyoz/bot-server/install.ps1))) -Mt5
   ```

4. Khi thoát Windows App: **chỉ đóng cửa sổ (Disconnect)**, **không Sign out**, để MT5 và bot chạy tiếp.
   Nếu VPS khởi động lại, đăng nhập lại một lần bằng Windows App.
5. Trong app chọn nguồn **MT5 (Exness)**, mã `XAUUSDm` (Standard) hoặc `XAUUSD` (tuỳ loại tài khoản),
   **Đặt lệnh: Demo trên VPS** để thử với giá Exness, rồi **MT5 (lệnh thật)** khi đã yên tâm.
   App luôn hỏi xác nhận trước khi chạy lệnh MT5.

Lệnh của bot trên MT5 có magic number `20260` và ghi chú `GoldBot`; bot chỉ quản lý lệnh của chính nó, không đụng lệnh tay.

## Xem giá realtime Exness / sàn MT5 khác trên iPhone

Sau khi cài MT5 trên VPS (mục 6, bước 1):

1. App → **Giao dịch → Đăng nhập sàn**.
2. Chọn **Exness** (hoặc **Sàn MT5 khác**), nhập **server** (ví dụ `Exness-MT5Trial7`), **số tài khoản** và **mật khẩu**.
   Mật khẩu investor (chỉ đọc) là đủ để xem giá.
3. **Mở biểu đồ realtime** → tìm mã (Exness Standard: `XAUUSDm`, `XAGUSDm`, `US30m`…) → biểu đồ Live chạy giá Exness, cập nhật mỗi giây.
   Mã được thêm vào danh sách mã với nguồn **MT5 (VPS)**.

"Ghi nhớ trên VPS" lưu đăng nhập vào `C:\GoldBot\config.json` để tự đăng nhập lại khi VPS khởi động lại.
"Lưu vào danh sách trên iPhone" giữ tài khoản (mật khẩu trong Keychain) để chạm là đổi tài khoản.
Đăng xuất trong app sẽ xoá mật khẩu đã lưu trên VPS. Mỗi lúc MT5 trên VPS chỉ đăng nhập một tài khoản.
Giờ nến được đổi về UTC tự động (nhiều sàn để giờ máy chủ UTC+2/+3).

## Giao dịch tài khoản Exness từ app

1. Đăng nhập bằng **mật khẩu chính** (investor chỉ xem được giá). Trong MT5 trên VPS bật nút **Algo Trading**.
2. App → **Giao dịch → Đăng nhập sàn → Giao dịch tài khoản này từ app**: bật **Cho phép đặt lệnh từ app**,
   đặt **Tối đa … lot mỗi lệnh**. Tài khoản thật cần bật thêm **Cho phép tài khoản THẬT**.
3. Mở biểu đồ mã MT5 (ví dụ `XAUUSDm`, nguồn **MT5 (VPS)**): nút **BUY/SELL**, lệnh **Limit**, kéo **SL/TP** và **✕**
   gửi thẳng vào tài khoản Exness. Chú thích trên biểu đồ ghi "💼 Lệnh vào MT5 #… · demo / TIỀN THẬT".
   Tài khoản thật luôn hỏi xác nhận (có thể bỏ hỏi cho phiên đang mở).
4. Lệnh đang mở, lệnh chờ và lệnh đã đóng 24 giờ cũng có trong trang **Đăng nhập sàn**; khớp lệnh, chạm TP/SL được đọc bằng giọng nói và thông báo.

Lệnh đặt tay có magic `20261` (ghi chú `GoldApp`); bot chỉ quản lý lệnh magic `20260` của nó.

## Gỡ lỗi

| Hiện tượng | Cách xử lý |
| --- | --- |
| App báo "Không kết nối được" | VPS vừa khởi động lại → gõ `/url` cho bot Telegram, dán địa chỉ mới. Hoặc mở `C:\GoldBot\tunnel.txt` trên VPS. |
| "Sai mật khẩu máy chủ" | Mật khẩu ở `C:\GoldBot\config.json` → `password`. |
| Không có lệnh nào | Xem **Nhật ký VPS** trong app; chiến lược chỉ vào lệnh khi nến đóng có tín hiệu. |
| Lỗi MT5 | Xem dòng cảnh báo trong app; kiểm tra `path`, `login`, `server`, đã bật Algo Trading chưa. |
| Xem log trên VPS | `C:\GoldBot\server.log` (và `crash.log` nếu máy chủ bị lỗi). |
| Dừng hẳn bot trên VPS | PowerShell (Admin): `Stop-ScheduledTask GoldBot; Disable-ScheduledTask GoldBot` |

## Bảo mật

* Máy chủ chỉ nghe trên `127.0.0.1`; từ Internet chỉ vào được qua Cloudflare Tunnel (HTTPS) và cần mật khẩu.
  Sai mật khẩu bị làm chậm để chống dò.
* Không đưa `config.json` cho ai: trong đó có mật khẩu máy chủ, token Telegram và mật khẩu MT5.
* Không cần mở cổng tường lửa nào trên VPS.
* Chạy demo ít nhất vài tuần trước khi bật lệnh thật. Kết quả quá khứ không bảo đảm lợi nhuận.
