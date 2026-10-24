# Trang web Aurum Pro (Cloudflare Pages)

Thư mục `web/` là trang tĩnh, không cần build:

- `index.html` — trang giới thiệu + web app thành viên (`#member`).
- `site.config.js` — liên kết liên hệ, tên và giá các gói: sửa ở đây.
- `assets/app.js`, `assets/style.css` — giao diện và logic.

Thành viên chỉ nhập mã mời: trang tìm địa chỉ máy chủ qua ntfy.sh (giống app iPhone),
rồi đọc `/member/me` và `/member/signals`. Máy chủ VPS cần bản 2.2+ (cho phép trình
duyệt gọi các đường dẫn `/member/`).

## Đăng lên Cloudflare Pages (miễn phí, tên dạng `aurumpro.pages.dev`)

1. Tạo tài khoản tại https://dash.cloudflare.com (miễn phí).
2. Workers & Pages → Create → tab **Pages** → **Connect to Git** → nối GitHub, chọn repo `gold`.
3. Project name: `aurumpro` (đây là tên miền: `aurumpro.pages.dev`).
4. Production branch: `claude/ios-backtest-custom-indicators-jptyoz`.
5. Framework preset: **None**, Build command: để trống, Build output directory: `web`.
6. Save and Deploy. Mỗi lần đẩy code lên nhánh này, trang tự cập nhật.
