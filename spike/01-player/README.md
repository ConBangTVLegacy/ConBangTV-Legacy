# Bước 1 — app thử trên iOS 6

App UIKit tối giản (Objective-C, ARC) để kiểm 3 điều trước khi chọn hướng làm bản iOS 6:

1. **Bộ dựng:** Theos + SDK 9.3, armv7, deploy 6.0 → `.deb` cài được, mở được trên iPad mini 1 / iPhone 5 (iOS 6, jailbreak).
2. **TLS:** iOS 6 có tin chứng chỉ của các máy chủ không (phimapi: gốc GlobalSign; phimimg / CDN video: Let's Encrypt;
   api.github.com: USERTrust ECC), và khi đưa gốc ISRG X1/X2 đóng kèm thì `SecTrustEvaluate` của iOS 6 có kiểm nổi chuỗi
   Let's Encrypt (có ECDSA P-384) không.
3. **Phát:** AVPlayer phát luồng KKPhim 1080p (H.264 High@4.0, MPEG-TS) — kích thước hình, bitrate, khựng, tua, RAM.

## Dựng và cài (trên máy Linux có Theos)

Lần đầu: `bash tools/setup-theos.sh` (ở gốc dự án) — cài Theos + toolchain + SDK 9.3 vào `~/theos` và vá SDK (thiếu
`liblaunch.tbd`, thiếu `memset` / `memcpy`… cho armv7 — ld64-609 báo lỗi). Máy Ubuntu thử: dự án chép ở `~/conbang-legacy`.

```sh
export THEOS=~/theos
make package                                   # → packages/vn.conbangtv.legacy.spike_<bản>_iphoneos-arm.deb
make package install THEOS_DEVICE_IP=<ip máy>  # cài qua SSH (root), chạy uicache
```

Chạy tự động qua SSH (không cần chạm máy): cài `tools/cblaunch` và `tools/symcheck` vào `/usr/bin` của máy, ghi lệnh vào
`/var/mobile/Documents/ConBangLegacy-autorun.txt` (`net` | `play-http <giây>` | `play-https <giây>` | `play-url <giây> <url>`), rồi
`cblaunch wake; cblaunch launch vn.conbangtv.legacy.spike`. Trước khi chạy bản mới: `python3 tools/symlist.py <tệp chạy> | ssh … cbsymcheck`
liệt kê ký hiệu iOS 6 không có.

## Kết quả trên iPhone 5 (iPhone5,2, iOS 6.1.4, jailbreak) — 14/11/2026

- **Bộ dựng:** chạy được sau 3 lần vá SDK (xem `tools/setup-theos.sh`; lần vá 3 — ký hiệu NS* của bộ tải URL phải gắn vào
  Foundation, không phải CFNetwork — là lỗi «dyld: Symbol not found» thật trên máy) + ký `ldid -Hsha1`.
- **Mạng / TLS:** HTTP và HTTPS tới phimapi, phimimg, CDN a.kvp726.com, api.github.com đều qua. Máy này có hồ sơ cấu hình cài thêm
  ~30 gốc mới (ISRG X1/X2, GTS, USERTrust…) nên bài «kho gốc iOS» không đại diện máy iOS 6 nguyên bản. Bài «gốc đóng kèm» (chỉ tin
  ISRG X1/X2 trong app) qua cả chuỗi RSA lẫn ECDSA của Let's Encrypt (`… ← YR1 ← Root YR ← ISRG Root X1`, `… ← YE2 ← Root YE ←
  ISRG Root X2`) → `SecTrustEvaluate` của iOS 6 kiểm được, đóng gốc vào app là dùng được trên máy không có hồ sơ.
- **Phát (AVPlayer, KKPhim):** khung hình giải mã **1920×1080 `420v`** (phần cứng; `presentationSize` iOS 6 báo 853×480 — chỉ là
  cách báo), mở 0,9 s (HTTPS 1,5 s), tua tới phút 33 trong 0,3 s, 150 s không khựng, rơi 3–4 khung ngay sau tua, RAM app 14 MB.
- **Phải nhớ cho app thật:** `idleTimerDisabled = YES` khi đang phát — không có thì máy tự khoá sau 1 phút và AVPlayer dừng.
- **Chưa làm:** khối quảng cáo chèn giữa phim (DISCONTINUITY) vẫn phát — cần cổng phát nội bộ (bước 3). iPad mini 1 chưa thử.

Log: tệp `ConBangLegacy-spike.log` trong thư mục Documents của app (đường dẫn hiện ở cuối màn hình chính).

## Tệp

- `Resources/isrg-root-x1.der`, `isrg-root-x2.der` — gốc Let's Encrypt (tải từ letsencrypt.org, SHA-256
  `96:BC:EC:06…:08:C6` và `69:72:9B:8E…:14:70`).
- `Resources/Default*.png` — ảnh khởi động; `Default-568h@2x.png` bắt buộc để iPhone 5 chạy đủ màn 4".
