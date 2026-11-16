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
- `0005-ios-tick-thread.patch` — **runtime tokio ngủ hẳn ngay lúc mở app** (iOS armv7 hai nhân — iPhone 5 / iPad mini; iPad 1 một
  nhân chưa gặp): nhịp 50 ms (đã vào repo chính) là một việc đẩy vào runtime, mà chính việc đẩy đó có lúc không đánh thức luồng
  nào → nhịp không bao giờ chạy, mọi `cbtv_call` sau đó nằm im (không tải được danh sách kênh / trang chủ, không lỗi, không hết
  giờ); cổng đồng bộ bị huỷ lúc app vào nền nhưng không đóng được → mở lại báo «Address already in use (os error 48)». Ngăn
  xếp lúc kẹt (gửi SIGABRT lấy báo cáo của iOS): 3 luồng `cbtv-net` ở condvar, 1 luồng trong `kevent`. Bản vá: nhịp chạy trên
  luồng riêng `cbtv-tick` bằng `block_on` — hẹn giờ của luồng đó đánh thức thẳng bộ điều khiển (kqueue `EVFILT_USER`), luồng
  giữ bộ điều khiển dậy mỗi 50 ms và lấy việc trong hàng đợi chung, không qua bước chọn luồng để đánh thức của bộ lập lịch.
- `0006-radio-streams.patch` — **đài radio** trong danh sách kênh IPTV (luồng MP3 / AAC liền của Icecast / Shoutcast — AVPlayer iOS
  5 / 6 phát được luồng này, nhưng link đài hay không có đuôi nên app không đoán được loại):
  - `media.sniff` (gọi nền): đọc ≤ 4 KB đầu của link (theo chuyển hướng) → `kind` = hls | audio (+ `codec` mp3 / aac, tìm hai
    khung MPEG / ADTS liền nhau — Icecast cắt luồng giữa khung) | flv | ts | mp4 | ogg | html | playlist | http (mã lỗi) | error;
    danh sách `.pls` / `.m3u` của đài thì đọc tiếp địa chỉ bên trong (tối đa 2 lớp); `icy-name`, `icy-br`.
  - `media.openRadio` → `r/<n>.mp3|aac`: mỗi lần trình phát mở là một kết nối tới đài kèm `Icy-MetaData: 1`; trả luồng liền
    (200, không độ dài, không Range — như Icecast) đã bỏ khối ICY (mỗi `icy-metaint` byte); tên bài `StreamTitle` (UTF-8, không
    phải UTF-8 thì Windows-1251 / Latin-1) giữ ở phiên, app hỏi bằng `media.radioInfo`.
  - `radio.rs` (nhận dạng, bỏ khối ICY, giải mã tên bài) — 5 phép thử; thử với 27 đài thật trong danh sách: 23 MP3 nhận đúng,
    2 đài chết (404 / 403), luồng ra giải mã sạch bằng ffmpeg, đọc được tên bài Kirin («NILETTO - ТЫ ТАКАЯ КРАСИВАЯ»).
- `0007-ts-live-hls.patch` — **luồng MPEG-TS liền** (IPTV kiểu Xtream «http://máy-chủ/tên/mật-khẩu/123», link .ts — nhiều nhà
  cung cấp chỉ cho TS, HLS `/live/…m3u8` bị 403): AVPlayer iOS 5 / 6 chỉ phát HLS. `media.open` với `ts: true` → `open_ts` →
  việc nền (`run_live`, chung với FLV — `Feeder::Flv | Ts`) đọc luồng, `ts_hls::Segmenter` cắt đoạn ~2 s tại khung khoá H.264 (cờ
  random_access / NAL IDR, SPS), không đổi vỏ; mỗi đoạn mở đầu bằng PAT + PMT (bộ đếm riêng), bỏ bảng phụ; đoạn giữ trong
  `flv_hls::Live` (`w/live.m3u8`). H.265 / MPEG-2 → lỗi rõ. **Tiếng MP1 / MP2** (AVPlayer không giải mã, và kênh tiếng hỏng thì
  cả hình đứng): xét tầng ở gói tiếng đầu (chưa biết thì chờ tối đa 2 s mới cắt đoạn đầu), MP2 thì bỏ kênh tiếng, viết lại PMT
  (CRC-32 MPEG-2), ghi `# cb-note:` vào danh sách phát (app báo «phát hình không tiếng»). **Hình xen kẽ dạng trường (PAFF —
  field_pic_flag = 1, kiểu bộ mã hoá đài phát sóng 1080i)**: bộ giải mã của iPad 1 không nhận (MBAFF của x264 thì được) — đọc SPS
  + đầu lát (exp-Golomb, bỏ 00 00 03), ghi `# cb-hint:`; app canh 20 s chưa lên hình thì báo rõ, ghi «không phát được» cho máy đó.
  Thử: 6 phép thử `ts_hls`; luồng thật (H.264 1080i PAFF + MP2) ra HLS giải mã sạch bằng ffmpeg; trên iPad 1 iOS 5 các luồng thử
  720p / 1080p High AAC, MP3, chỉ hình, 1080i MBAFF đều phát; MP2 → hình không tiếng; PAFF → báo lỗi sau 21 s.
