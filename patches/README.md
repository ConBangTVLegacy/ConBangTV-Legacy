# Bản vá tạm cho lõi chung (repo chính) — tools/build-core.sh áp mọi *.patch ở đây sau khi lấy repo chính.

Đã đưa vào repo chính (14/11/2026, commit 7fe04fa..7eeb5e9): tcp_info trên Apple, Range đóng ở cổng phát nội bộ, nhịp 50 ms trên iOS.

Đang giữ ở đây (chưa đưa lên repo chính):
- `0001-sync-ios-platform.patch` — đồng bộ trong nhà: trên iOS báo nền tảng `ios` (biểu tượng 📱 ở máy kia, như bản iPad),
  tên máy lấy từ biến `CONBANG_DEVICE_NAME` (app đặt bằng tên máy có dấu; hostname của iOS chỉ là «iPhone-cua-…»).
- `0002-revive-local-ports.patch` — iOS thu hồi cổng nghe 127.0.0.1 của app nằm nền lâu: cổng SOCKS nội bộ (đường ra mạng của
  client HTTP — vượt chặn / proxy) và cổng phát chết hẳn tới khi tắt app. Bản vá: hai cổng mở lại được (`net.revive`: thử kết
  nối vào chính cổng, chết thì mở lại đúng số cổng cũ nếu được, bỏ kết nối cũ của client HTTP). App gọi mỗi lần hoạt động lại.
  Đã thử trên Linux bằng `ss -K` (giả thu hồi cổng): mở lại đúng cổng, tải lại được.
- `0003-fmp4-to-ts-for-old-avplayer.patch` — trang dexter.pw phát HLS dạng **fMP4** (`#EXT-X-MAP` + `moof` / `mdat`, H.264 +
  AAC), AVPlayer của iOS 6 chỉ phát HLS dạng **MPEG-TS** (fMP4 có từ iOS 10). Cổng phát nội bộ (khi dựng cho iOS —
  `media_proxy::set_remux_fmp4` để thử trên máy khác) đổi vỏ từng đoạn fMP4 thành MPEG-TS (`fmp4_ts.rs`: H.264 → Annex B
  + AUD + SPS / PPS trước khung khoá, AAC → ADTS, mốc thời gian từ `tfdt` + 10 s, độ lệch hiển thị âm thì lùi DTS cả rãnh)
  qua địa chỉ `m/<đoạn>-<khởi tạo>.ts`, và dọn danh sách phát chính cho AVPlayer cũ (bỏ bản > 1080p, bản ~720p lên đầu,
  bỏ thuộc tính / phụ đề trong luồng iOS 6 không biết); danh sách chính có `?h=<chiều cao>` (app — mục «Chất lượng») thì
  chỉ giữ bản cao nhất không quá mức đó (+ rãnh tiếng riêng). Đã thử bằng ffmpeg với luồng thật (Coco: 432 khung hình + tiếng giải
  mã ra giống hệt bản fMP4 gốc; Dexter server 20 hình / tiếng tách riêng). 8 phép thử `fmp4_ts`, 2 phép thử `media_proxy`.
- `0004-flv-live-hls-and-stream-headers.patch` — kênh truyền hình (IPTV) trên iOS cũ:
  - **Tiêu đề riêng của luồng**: `media.open` nhận thêm `referer` (gửi đúng như danh sách kênh M3U ghi — `#EXTVLCOPT:http-referrer`,
    `url|Referer=` — thay vì chỉ gốc trang), `ua` (`http-user-agent`: máy chủ thể thao chỉ trả cho trình phát nó quen) và
    `origin`; mọi yêu cầu của phiên (danh sách phát, đoạn, khoá, tệp) đều gửi kèm (`media_proxy::Hdr`, `open_ex`).
  - **HTTP-FLV trực tiếp → HLS trực tiếp** (`flv: true`): AVPlayer iOS 5 / 6 chỉ phát HLS dạng TS. Việc nền của phiên đọc luồng
    FLV, đổi vỏ (`flv_hls.rs`, dùng chung bộ ghi TS của `fmp4_ts`: H.264 → Annex B + SPS / PPS trước khung khoá, AAC → ADTS),
    cắt đoạn ~2 s ở khung khoá, giữ 8 đoạn trong bộ nhớ; cổng phát trả `w/live.m3u8` (6 đoạn mới nhất, chờ đủ 3 đoạn lần đầu)
    và `w/<số>.ts`. Đứt thì nối lại, đoạn sau có `#EXT-X-DISCONTINUITY` (mốc thời gian lùi / nhảy cũng vậy); dừng khi phiên
    đóng hoặc trình phát thôi hỏi 90 s. H.265 / AV1 trong FLV báo lỗi rõ (máy chỉ giải mã H.264).
  - Đã thử: ffmpeg phát qua cổng một luồng FLV 720p (B-frame + AAC) nhả theo nhịp thời gian thật — máy chủ nhận đúng UA /
    Referer, danh sách phát có sau ~4 s, 20 s lấy ra giải mã hết không lỗi. 4 phép thử `flv_hls`, thêm phép thử phiên FLV /
    tiêu đề trong `media_proxy`.
