// Thông tin hiển thị trên trang — sửa ở đây rồi đẩy lên là trang tự cập nhật.
window.SITE = {
  name: "Aurum Pro",
  // Nút "Nhận mã mời" mở liên kết này (Zalo, Telegram, Messenger…). Để trống = ẩn nút.
  contactUrl: "",
  contactLabel: "Nhắn để nhận mã mời",
  // Bảng giá gói thành viên. price để "Liên hệ" nếu chưa muốn ghi giá.
  plans: [
    {
      name: "Tín hiệu",
      price: "Liên hệ",
      period: "/ tháng",
      features: [
        "Lệnh vàng XAUUSD theo thời gian thực",
        "Giá vào, SL, TP rõ ràng",
        "Lịch sử thắng / thua minh bạch",
        "Biểu đồ ICT: Killzones, FVG, đỉnh đáy ngày",
        "Dòng tiền cá mập, tin tức đỏ báo tốt/xấu",
      ],
    },
    {
      name: "Tín hiệu + Copy",
      price: "Liên hệ",
      period: "/ tháng",
      highlight: true,
      features: [
        "Tất cả quyền lợi gói Tín hiệu",
        "Tự động copy lệnh vào tài khoản MT5 của bạn",
        "Tự chọn hệ số lot và lot tối đa",
        "SL/TP và đóng lệnh theo người dẫn",
        "Xem số lot đã copy trên từng tín hiệu",
      ],
    },
  ],
};
