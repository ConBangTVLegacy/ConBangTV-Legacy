# Bản vá tạm cho lõi chung (repo chính) — tools/build-core.sh áp mọi *.patch ở đây sau khi lấy repo chính.

Đã đưa vào repo chính (14/11/2026, commit 7fe04fa..7eeb5e9): tcp_info trên Apple, Range đóng ở cổng phát nội bộ, nhịp 50 ms trên iOS.

Đang giữ ở đây (chưa đưa lên repo chính):
- `0001-sync-ios-platform.patch` — đồng bộ trong nhà: trên iOS báo nền tảng `ios` (biểu tượng 📱 ở máy kia, như bản iPad),
  tên máy lấy từ biến `CONBANG_DEVICE_NAME` (app đặt bằng tên máy có dấu; hostname của iOS chỉ là «iPhone-cua-…»).
