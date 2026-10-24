# Trang web Aurum Pro (Cloudflare Pages)

Thư mục `web/` là trang tĩnh, không cần build:

- `index.html` — trang giới thiệu + web app thành viên (`#member`).
- `site.config.js` — liên kết liên hệ, tên và giá các gói: sửa ở đây.
- `assets/app.js`, `assets/style.css` — giao diện và logic.
- `assets/ict.js` — chỉ báo ICT Killzones + Pivots, FVG/VI, MSS/BOS, quét thanh khoản, dòng tiền
  cá mập (cùng quy tắc và cài đặt với BacktestKit trong app), vẽ trong khung hình của biểu đồ.
- `assets/drawings.js` — công cụ vẽ (xu hướng, Fib, mô hình, vị thế, đo giá, khối lượng, hình, chữ).

Trên biểu đồ: nút ƒx (bật/tắt + cài đặt chi tiết), ✎ (công cụ vẽ), ⏮ (replay: chạm nến bắt đầu,
▶/⏭/tốc độ, lệnh BUY/SELL thử, giữ đúng thời điểm khi đổi khung). Chuột phải (giữ lâu trên điện
thoại) mở menu: Đặt lại biểu đồ, Replay từ nến này, đường ngang, lệnh chờ tại giá, bản vẽ, chỉ báo.

Thành viên chỉ nhập mã mời, chủ chỉ nhập mật khẩu máy chủ: trang tìm địa chỉ máy chủ
qua ntfy.sh (giống app iPhone).

- **Chủ** có các tab: Biểu đồ (nến Exness, chỉ báo, BUY/SELL, lệnh chờ, chạm đường giá vào
  để chọn lệnh rồi kéo SL/TP, đóng nhanh), Lệnh (tài khoản, đóng từng phần, sửa SL/TP, huỷ lệnh
  chờ), Lịch sử (Hôm nay/Hôm qua/7/30 ngày, SL/TP lúc vào và lúc đóng, trượt giá), Tin tức,
  Copy (bật/tắt, thêm/sửa/xoá tài khoản copy), Thành viên (tạo mã, khoá, gia hạn, đổi mã,
  quyền dùng) và Máy chủ (bot, cho phép đặt lệnh, lot tối đa, cập nhật, nhật ký).
- **Thành viên**: Biểu đồ (tín hiệu tím + chỉ báo nếu được mở), Tín hiệu, Tin tức, Copy lệnh
  (mã có quyền copy).

Máy chủ VPS cần bản 2.4+ (tin tức đi qua `/news`, `/member/news` vì trình duyệt không đọc
thẳng được lịch Forex Factory). Không có MT5 thì biểu đồ dùng Binance XAUUSDT.

Khung **5s / 10s / 15s / 30s**: MT5 không có nến dưới 1 phút nên nến giây dựng từ Binance ngay trên
trình duyệt — vàng/bạc từ lệnh khớp hợp đồng XAUUSDT/XAGUSDT (futures), crypto từ nến 1 giây spot
(BTCUSDT, ETHUSDT…), kéo sang trái để tải thêm, chạy trực tiếp qua websocket. Nến được dời theo
chênh lệch với giá Exness lúc mở (ghi cạnh tên mã) để đường lệnh/SL/TP và bản vẽ khớp; nút MUA/BÁN
vẫn đặt vào MT5 theo giá Exness. Mã khác (ngoại hối, chỉ số) không có khung giây.

## Đăng lên Cloudflare Pages (miễn phí, tên dạng `aurumpro.pages.dev`)

1. Tạo tài khoản tại https://dash.cloudflare.com (miễn phí).
2. Workers & Pages → Create → tab **Pages** → **Connect to Git** → nối GitHub, chọn repo `gold`.
3. Project name: `aurumpro` (đây là tên miền: `aurumpro.pages.dev`).
4. Production branch: `claude/ios-backtest-custom-indicators-jptyoz`.
5. Framework preset: **None**, Build command: để trống, Build output directory: `web`.
6. Save and Deploy. Mỗi lần đẩy code lên nhánh này, trang tự cập nhật.

## Thông báo & giọng nói (nút 🔔 trên thanh trên)

Giống app: đọc to khi lệnh khớp ("Order filled"), chạm TP ("Target fill"), chạm SL ("Stop loss fill"),
đóng tay; thành viên nghe khi có tín hiệu MUA/BÁN và khi tín hiệu đóng. Chọn giọng Anh/Việt, tự sửa
câu đọc, đọc thêm mã/giá/lãi lỗ, hiện thông báo trên trang hoặc thông báo trình duyệt khi ở tab khác.
Chỉ báo khi trang đang mở. Điện thoại cần chạm vào trang một lần thì trình duyệt mới cho đọc.

Ô "N lệnh · lot · lãi/lỗ" kéo được tới bất kỳ đâu trên trang (giữ vị trí, hiện ở mọi tab);
bấm đúp vào ⋮⋮ để trả về góc biểu đồ.
