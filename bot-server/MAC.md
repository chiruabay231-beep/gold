# Chuyển máy chủ bot sang Mac (Windows ảo chạy MT5)

Máy chủ bot cần **Windows** vì thư viện MT5 cho Python chỉ chạy trên Windows. Trên Mac ta cài **Windows ảo**
(Parallels hoặc UTM), trong đó chạy **MT5 Exness + máy chủ bot**. Web và app vẫn kết nối như với VPS.

Thời gian làm: khoảng **1 – 1,5 giờ** (phần lớn là chờ tải Windows).

---

## 0. Trước khi bắt đầu

**Mac cần có:** RAM từ **8 GB** (nên 16 GB), ổ trống từ **60 GB**, luôn **cắm sạc** và có mạng ổn định.
Xem loại chip: menu  → *Giới thiệu về máy Mac* → **Chip Apple M1/M2/M3/M4** hay **Intel**.

**Nếu VPS cũ còn vào được** (nên làm, để giữ nguyên mọi thứ):

1. Trên web: tab **Bot** → **tắt tất cả bot** đang chạy trên **tài khoản MT5 thật**; mở app Exness kiểm tra
   lệnh đang mở (đóng, hoặc đặt SL) — trong lúc chuyển sẽ không có bot nào quản lý lệnh.
2. Trên VPS cũ: mở **PowerShell**, dán lệnh sao lưu:

   ```powershell
   irm https://raw.githubusercontent.com/chiruabay231-beep/gold/claude/ios-backtest-custom-indicators-jptyoz/bot-server/backup.ps1 | iex
   ```

   Lệnh tạo file **`GoldBot-backup.zip`** trên Desktop của VPS: mật khẩu máy chủ, đăng nhập MT5, Telegram,
   **thành viên và mã mời**, cài đặt các bot, bản vẽ, tài khoản ảo và thống kê.
3. Chép `GoldBot-backup.zip` về Mac (Google Drive, email cho chính mình…). **Không gửi file này cho ai.**
4. Sau khi máy mới chạy ổn (bước 5) mới tắt hẳn máy chủ trên VPS cũ — **không để 2 máy chủ chạy cùng lúc**
   (cả hai sẽ cùng đặt lệnh và tranh nhau địa chỉ).

**Nếu VPS cũ đã mất:** vẫn làm được, nhưng sẽ là máy chủ mới: **mật khẩu mới** (nhập lại trên web / app),
**cấp lại mã mời** cho thành viên, cài đặt bot làm lại, tài khoản ảo và thống kê bắt đầu từ đầu.

---

## 1. Cài Windows ảo trên Mac

### Cách A — Parallels Desktop (dễ nhất, khuyên dùng)

1. Tải **Parallels Desktop** tại parallels.com (dùng thử 14 ngày, sau đó khoảng 100 USD/năm).
2. Mở Parallels → **Get Windows 11 from Microsoft** → Parallels tự tải và cài Windows 11 (Mac chip M: bản ARM,
   chạy được MT5 bình thường).
3. Khi cài xong, tắt máy ảo, vào **Cấu hình máy ảo (biểu tượng bánh răng)**:
   - **Hardware → CPU & Memory**: 4 CPU, **6 – 8 GB RAM**.
   - **Options → Startup and Shutdown**: *Start automatically* → **When Mac starts**;
     *On Mac shutdown* → **Suspend**.
   - **Options → Optimization**: tắt **Pause Windows when possible**.
   - Tắt **Travel Mode** (nếu có).

### Cách B — UTM (miễn phí, chậm hơn, nhiều bước hơn)

1. Tải **UTM** tại mac.getutm.app, tải file cài **Windows 11 ARM** bằng **CrystalFetch** (miễn phí).
2. UTM → *Create a New Virtual Machine* → *Virtualize* → *Windows* → chọn file ISO, 4 CPU, 6 – 8 GB RAM,
   ổ 64 GB, bật *Install drivers and SPICE tools*.
3. Thêm UTM vào *Cài đặt hệ thống → Cài đặt chung → Mục đăng nhập* để mở cùng Mac, và trong UTM bật tự chạy
   máy ảo khi mở (nếu bản UTM của bạn có tuỳ chọn này; nếu không thì mở máy ảo bằng tay sau mỗi lần bật Mac).

---

## 2. Trong Windows ảo: cài MT5 Exness

1. Mở trình duyệt trong Windows, vào **exness.com** → tải **MetaTrader 5 cho Windows** → cài.
2. Mở MT5 → **đăng nhập** tài khoản Exness (demo hoặc thật) như trên VPS cũ.
3. MT5 → **Tools → Options → Expert Advisors** → bật **Allow algorithmic trading** → OK.
4. Có thể đóng MT5 (bot tự mở lại khi cần).

## 3. Trong Windows ảo: cài máy chủ bot

1. Kéo thả file **`GoldBot-backup.zip`** từ Mac vào **Desktop** của Windows ảo (bỏ qua nếu không có).
2. Bấm **Start** → gõ `PowerShell` → chuột phải → **Run as Administrator**, dán:

   ```powershell
   irm https://raw.githubusercontent.com/chiruabay231-beep/gold/claude/ios-backtest-custom-indicators-jptyoz/bot-server/install.ps1 | iex
   ```

   - Có file sao lưu trên Desktop: bộ cài **tự khôi phục** (dòng *Khôi phục dữ liệu từ máy cũ*).
   - Không có: bộ cài tạo cấu hình mới và hỏi token Telegram (Enter để bỏ qua).
   - Cuối cùng in ra **Địa chỉ máy chủ** và **Mật khẩu máy chủ**: ghi lại, **không gửi cho ai**.
3. Chạy tiếp **giai đoạn MT5** (vẫn PowerShell Administrator):

   ```powershell
   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/chiruabay231-beep/gold/claude/ios-backtest-custom-indicators-jptyoz/bot-server/install.ps1))) -Mt5
   ```

   - Bộ cài chỉnh Windows **không ngủ**, **không tự khởi động lại khi cập nhật**.
   - Hỏi *Tự đăng nhập Windows khi bật máy?* → gõ **y**, nhập mật khẩu Windows (để trống nếu không đặt).
     Nhờ vậy khi máy ảo bật lại, Windows tự vào và bot + MT5 tự chạy, không cần ai bấm.

## 4. Trên Mac: giữ Mac luôn thức

1. Mở **Terminal** trên Mac, dán (sẽ hỏi mật khẩu Mac một lần):

   ```bash
   curl -fsSL https://raw.githubusercontent.com/chiruabay231-beep/gold/claude/ios-backtest-custom-indicators-jptyoz/bot-server/mac-setup.sh | bash
   ```

   Mac sẽ **không ngủ khi cắm sạc** (màn hình vẫn tắt), **tự bật lại sau khi mất điện**. Muốn trả lại như cũ:
   chạy lại lệnh trên với `bash -s -- --undo` thay cho `bash`.
2. **Cài đặt hệ thống → Người dùng & Nhóm → Tự động đăng nhập**: chọn tài khoản của bạn
   (nếu đang bật FileVault thì macOS không cho tự đăng nhập — khi đó sau mỗi lần mất điện phải mở Mac bằng tay).
3. **Cài đặt hệ thống → Cài đặt chung → Cập nhật phần mềm → Tự động cập nhật**: tắt *Cài đặt bản cập nhật macOS*
   (để Mac không tự khởi động lại giữa đêm).
4. **MacBook**: luôn cắm sạc; **gập máy là Mac ngủ** (trừ khi có màn hình ngoài) → để mở nắp.

## 5. Kết nối web / app và kiểm tra

1. **Có khôi phục sao lưu**: web và app **tự tìm địa chỉ mới** sau 1 – 2 phút (tải lại trang web, mở lại app).
   **Không có sao lưu**: web → tab **Máy chủ** (app: *Máy chủ VPS*) → nhập **địa chỉ** và **mật khẩu** mới.
2. Tab **Máy chủ → Cập nhật** lên bản mới nhất.
3. Tab **Bot**: bật lại bot ở **🎮 Chạy thử** trước, xem dòng 🤖 trạng thái chạy bình thường, rồi mới bật trên MT5.
4. Kiểm tra tự chạy lại: **khởi động lại Mac một lần** → chờ 3 – 5 phút → web vẫn kết nối được là đạt
   (Mac tự đăng nhập → Parallels mở máy ảo → Windows tự đăng nhập → bot và MT5 tự chạy).
5. Mọi thứ ổn → tắt máy chủ trên VPS cũ (hoặc để VPS hết hạn).

---

## Sự cố thường gặp

| Hiện tượng | Cách xử lý |
|---|---|
| Web báo không kết nối được máy chủ | Máy ảo có đang chạy không? Mac có ngủ không? Trong Windows mở `C:\GoldBot\tunnel.txt` xem địa chỉ, nhập vào tab Máy chủ |
| Bot báo lỗi MT5 / không có giá | Mở MT5 trong Windows ảo, kiểm tra đã đăng nhập và đã bật *Allow algorithmic trading* |
| Sau khi bật lại Mac bot không chạy | Kiểm tra: Mac tự đăng nhập (bước 4.2), Parallels tự mở máy ảo (bước 1), Windows tự đăng nhập (bước 3.3) |
| Mac nóng / chậm | Giảm RAM máy ảo còn 6 GB, đóng các app khác; MT5 + bot dùng ít CPU |
| Muốn chạy lại bộ cài / cập nhật | Chạy lại lệnh giai đoạn MT5 ở bước 3.3 — giữ nguyên cài đặt |

**Lưu ý an toàn:** Mac ở nhà có thể mất điện, rớt mạng, tự cập nhật. Khi chạy bot trên **tài khoản thật**, luôn
đặt **SL rổ / cắt lỗ chung** (đã đặt sẵn trên sàn) để lệnh vẫn được bảo vệ khi máy chủ dừng đột ngột.
