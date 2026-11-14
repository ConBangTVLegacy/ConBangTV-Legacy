# Côn Bằng TV Legacy — bản iOS 6

Bản Côn Bằng TV cho máy iOS 6 đã jailbreak (máy thử: **iPhone 5 iOS 6.1.4**, **iPad mini 1** — chưa thử). App gốc và lõi chung ở repo
[repo chính](https://github.com/Circling5714/ChimToTV); bản iPad hiện tại (Swift / SwiftUI / WKWebView, iOS 15+) không
chạy được trên iOS 6 nên bản này viết riêng.

## Kiến trúc (đã chứng minh chạy trên iPhone 5 — 14/11/2026)

```
UIKit + Objective-C (vỏ app, armv7, iOS 6.0)
  │  JSON qua 4 hàm C: cbtv_init / cbtv_call / cbtv_call_sync / cbtv_free   (như bản Windows)
  ▼
Lõi Rust chung của repo chính (linux/core + linux/ffi) dựng cho armv7 iOS 6 → libconbang_core.a
  │  đọc trang / API phim, cài đặt, mạng (rustls + gốc Mozilla đóng kèm, DNS mã hoá, vượt chặn, proxy), đồng bộ…
  ▼
Cổng phát nội bộ 127.0.0.1 (media_proxy: bỏ quảng cáo, cắt PNG ngụy trang…) ──► AVPlayer (giải mã phần cứng 1080p)
```

## Thư mục

| Đường dẫn | Nội dung |
| --- | --- |
| `spike/01-player/` | App thử (Theos): bài kiểm mạng / TLS, phát AVPlayer, gọi lõi Rust; chạy tự động qua SSH — xem README trong đó |
| `spike/02-rust/` | Thử Rust tối thiểu (std + tokio + reqwest) — bước đệm, nay dùng lõi thật |
| `tools/setup-theos.sh` | Cài Theos + toolchain (clang 11, ld64-609) + SDK iPhoneOS 9.3 vào `~/theos`, **vá SDK** cho iOS 6 |
| `tools/build-core.sh` | Dựng lõi chung: clone repo chính vào `upstream/`, áp `patches/*.patch`, dựng `conbang-ffi` thành thư viện tĩnh |
| `tools/rust/` | Target `armv7-apple-ios6.json`, `cargo-ios6.sh` (cargo nightly + build-std), `vendor-ring.sh` (vá ring) |
| `tools/cblaunch/` | Mở app / đánh thức / mở khoá máy từ SSH (SpringBoardServices) |
| `tools/symcheck/`, `tools/symlist.py` | Tra trên máy iOS 6 mọi ký hiệu tệp chạy cần — bắt lỗi «dyld: Symbol not found» trước khi chạy |
| `patches/` | Bản vá tạm cho lõi chung (hiện trống — 3 bản vá cho iOS đã vào repo chính 14/11/2026) |
| `app/` | **App thật — Côn Bằng TV Legacy** (`vn.conbangtv.legacy`): trang chủ, tìm kiếm, trang phim, trình phát, người xem, cài đặt |

## Dựng (máy Linux)

`src/` = bản chép thư mục này, `upstream/` = clone repo chính, `target-core/` = lõi đã dựng. Lần đầu: `bash src/tools/setup-theos.sh`,
Rust nightly có `rust-src` (`rustup toolchain install nightly --profile minimal --component rust-src`). Sau đó:

```sh
bash src/tools/build-core.sh [--pull]                # → target-core/armv7-apple-ios6/release/libconbang_core.a (~22 MB)
cd src/spike/01-player && THEOS=~/theos make package  # → packages/*.deb (ký ldid SHA-1, nén gzip)
```

## Bẫy của iOS 6 đã gặp (và cách xử lý)

- **Xcode 14+ bỏ armv7** → Theos trên Linux + SDK 9.3 (bản cuối còn armv7).
- **SDK 9.3 của Theos thiếu / sai chỗ ký hiệu:** thiếu `liblaunch.tbd`, thiếu `memset` / `memcpy`… cho armv7; ký hiệu `NSURL*` ghi ở
  CFNetwork (iOS 7+) trong khi iOS 6 để ở Foundation → «dyld: Symbol not found» thật trên máy. Vá trong `setup-theos.sh`.
- **ldid mặc định ký SHA-256** → nhân iOS 6 chỉ hiểu SHA-1: `ldid -Hsha1`.
- **Rust chỉ hỗ trợ từ iOS 10:** target tự định nghĩa (cortex-a9, không vfp4, không thread-local TLV, panic = abort) + build-std. Hàm
  iOS 6 không có thì tự cài trong `spike/01-player/shims_ios6.c`: `clock_gettime`, `CCRandomGenerateBytes`, `fclonefileat`,
  `__exp10` (LLVM tự sinh).
- **ring** (mã hoá của rustls) tắt hẳn assembly ARM 32-bit trên Apple và không có bản `ios32` → `vendor-ring.sh` sinh assembly
  `ios32`, bỏ khối tắt trong `target.h`, poly1305 dùng bản thường.
- **Chứng chỉ:** iOS 6 không tin Let's Encrypt (CDN video, ảnh); chuỗi Cloudflare dựa vào gốc GlobalSign R1 hết hạn 28/01/2028 →
  lõi dùng rustls + `cacert.pem` (Mozilla) đóng kèm qua `SSL_CERT_FILE`, không phụ thuộc kho gốc của máy.
- **AVPlayer dừng khi máy tự khoá** → `idleTimerDisabled = YES` lúc phát.
- **Ảnh WebP** (ảnh bìa KKPhim, yanhh3d…): iOS 6 không đọc được → libwebp (chỉ phần giải mã, `tools/vendor-libwebp.sh`).
- **MP4 tải tuần tự:** đọc `AVPlayerItem.duration` trước khi sẵn sàng là chặn luồng chính, mà bộ tải tệp của AVPlayer lại cần luồng
  chính → kẹt tới hết hạn (lỗi CoreMedia -12935). Chỉ đọc duration khi `ReadyToPlay`. AVPlayer xin Range kiểu đóng
  (`bytes=0-<cuối>`) → vá cổng phát nội bộ.
- **tokio trên armv7 iOS 6:** việc đẩy vào từ ngoài (`cbtv_call`) có lúc không đánh thức luồng nào — ngăn xếp lấy bằng lệnh gỡ lỗi
  `crash`: mọi luồng ngủ ở `park_condvar` / `Driver::turn` (kqueue `EVFILT_USER` thì chạy đúng, đã kiểm bằng `tools/kqtest`) → nhịp
  50 ms (`ffi-ios-wakeup.patch`).
- **Cài bản mới:** đừng chạy `uicache` lúc app đang mở (SpringBoard đơ, phải respring); cài xong mở lại app ngay — bản thử giữ màn
  hình sáng, máy khoá lâu thì tắt Wi-Fi, mất SSH.

## Kết quả trên iPhone 5 (iOS 6.1.4)

| Mục | Kết quả |
| --- | --- |
| App ObjC + AVPlayer phát thẳng KKPhim (HLS, H.264 High 1080p) | giải mã phần cứng 1920×1080, mở 0,9 s, tua 0,3 s, 150 s không khựng, RAM 14 MB |
| Lõi Rust chung (`cbtv_init`, `http.get` HTTP / HTTPS / Let's Encrypt / HTTP/2) | chạy, không thiếu ký hiệu (237 ký hiệu đã tra) |
| Phát qua cổng phát nội bộ của lõi (`media.open`) | phát 1080p, mở 1,4 s, **đã cắt ~35 s quảng cáo chèn giữa phim**, RAM 20 MB |
| Tốc độ tải | Wi-Fi của máy thử yếu lúc đo (mất 10% gói, trễ ~88 ms): NSURLConnection 0,16–0,68 MB/s, lõi Rust 0,06–0,29 MB/s — cần đo lại khi sóng tốt |

## Việc tiếp theo

1. Đo lại tốc độ / phát qua lõi khi Wi-Fi tốt; nếu lõi vẫn chậm hơn NSURLConnection thì dò (DNS mã hoá, cổng SOCKS nội bộ, IPv6).
2. Vỏ app thật bằng UIKit: chọn người xem, trang chủ tổng hợp (`home.load`), danh sách / tìm kiếm, trang phim (`site.detail`),
   trình phát (AVPlayer + `media.open`, nhớ vị trí, tự chuyển tập), cài đặt — theo bản Windows (cùng FFI JSON).
3. Thử iPad mini 1 (A5, 512 MB RAM).
4. Đóng gói / cập nhật: repo Cydia riêng hoặc .deb trên GitHub Releases.
