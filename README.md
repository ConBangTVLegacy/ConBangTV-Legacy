# Côn Bằng TV Legacy — bản iOS 6

**Trang giới thiệu, cách cài:** <https://conbangtvlegacy.github.io> · **Tải bản mới nhất:** [GitHub Releases](https://github.com/ConBangTVLegacy/ConBangTV-Legacy/releases/latest)


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
| `patches/` | Bản vá tạm cho lõi chung (3 bản vá đầu đã vào repo chính 14/11/2026; còn `0001-sync-ios-platform` — xem README trong đó) |
| `app/` | **App thật — Côn Bằng TV Legacy** (`vn.conbangtv.legacy`; tên dưới biểu tượng: «Côn Bằng TV») — các màn ở mục «App» dưới đây |

## App (`app/`)

| Màn | Có gì |
| --- | --- |
| Trang chủ | «Có tập mới», «Xem tiếp», các hàng của trang chủ tổng hợp (`home.load` / `home.late`); cuối trang: ★ Điểm IMDb cao (`imdb.page`), danh mục của trang, Thể loại… / Quốc gia… (`api.filters` / `next.filters`) |
| Tìm kiếm | tìm trên mọi trang (`site.searchAll`) |
| Trang phim | thông tin, Xem / Xem tiếp, Theo dõi, chọn bản (Vietsub / Thuyết minh), lưới tập, mô tả, **phim liên quan** (`related.load`) |
| Trình phát | AVPlayer qua cổng phát nội bộ, tự chọn server phát được trên iOS 6, nhớ chỗ xem, tự chuyển tập, **bảng chọn tập «☰ Tập»** (đổi bản Vietsub / Thuyết minh), điều khiển trên màn khoá |
| Người xem | «Ai đang xem?» (thêm người, mã PIN), đổi người xem — cùng khoá dữ liệu với bản Windows |
| Cài đặt | người xem, trang chủ tổng hợp, **hồ sơ trẻ em** (tắt cần mã phụ huynh), trang phim, phát video, mạng, **Đồng bộ trong nhà**, xoá lịch sử, miễn trừ |
| Theo dõi / Lịch sử | nút «☆ Theo dõi» đầu trang chủ, «Xem thêm» của «Có tập mới» / «Xem tiếp»: lưới phim, kiểm tập mới khi mở, nhấn giữ để bỏ theo dõi / xoá |
| Proxy | Cài đặt → Mạng → Proxy: SOCKS5 (có đăng nhập) hoặc Shadowsocks (dán link `ss://`), DNS qua proxy, chỉ trang phim, thử kết nối; lõi lo hết (trang, video qua cổng phát nội bộ, ảnh tải qua lõi khi proxy cho cả app); proxy lỗi thì báo lỗi, không đi thẳng |
| Giới hạn giờ xem | từng người xem: số phút mỗi ngày, giờ đi ngủ (tới 6 giờ sáng); hết giờ phim dừng, xem thêm cần mã PIN phụ huynh — cùng khoá với bản Windows / TV / iPad |
| Đồng bộ trong nhà | ghép với tivi / Windows / iPad bằng mã 4 số (lõi `sync_service`, cổng 8791): lịch sử, chỗ xem, theo dõi, người xem, trang phim |

Bản thử (không `FINALPACKAGE=1`) có `Debug/CBDebug.m`: đọc lệnh từ `Documents/ConBangTV-cmd.txt` (`shot`, `film`, `play`, `search`,
`settings`, `profiles`, `sync`, `syncpair`, `pick`, `scroll`, `wait`, `status`, `core`, `pref`…) để thử tự động qua SSH.

## Dựng (máy Linux, vd Ubuntu 22.04+)

Thư mục làm việc: `<làm việc>/src/` = repo này, `<làm việc>/upstream/` = clone repo chính (build-core.sh tự clone),
`<làm việc>/target-core/` = lõi đã dựng (Makefile của app tự tìm ở đó; đổi bằng `CORE_LIB_DIR=…`). Lần đầu: `bash src/tools/setup-theos.sh`,
Rust nightly có `rust-src` (`rustup toolchain install nightly --profile minimal --component rust-src`). Sau đó:

```sh
bash src/tools/build-core.sh [--pull]                # → target-core/armv7-apple-ios6/release/libconbang_core.a (~22 MB)
cd src/app && THEOS=~/theos make package               # bản thử (có Debug/: lệnh gỡ lỗi qua Documents/ConBangTV-cmd.txt)
bash src/tools/build-release.sh [--core]              # bản phát hành → app/packages/vn.conbangtv.legacy_<bản>_iphoneos-arm.deb
```

Bản phát hành bỏ hẳn `Debug/` (không đọc lệnh, không giữ màn hình sáng khi mở app); số bản ở `app/control` và
`CFBundleShortVersionString` (script kiểm hai chỗ khớp nhau). Cài tay: chép .deb vào máy rồi `dpkg -i` (lần đầu thêm
`su mobile -c uicache` để hiện biểu tượng — **không** chạy uicache lúc app đang mở). 14/11/2026: bản **0.2.0** đã cài trên
iPhone 5 và iPad mini 1.

## Cập nhật OTA và phát hành

App (từ 0.4.0) tự kiểm [GitHub Releases](https://github.com/ConBangTVLegacy/ConBangTV-Legacy/releases) lúc mở / quay lại app
(tối đa 6 giờ một lần) và khi chạm «Phiên bản» trong Cài đặt (`Core/CBUpdate.m`): bản mới hơn có tệp
`vn.conbangtv.legacy_<bản>_iphoneos-arm.deb` thì hỏi «Cập nhật / Để sau», tải qua lõi (iOS 6 không tự vào được GitHub), kiểm
kích thước + SHA-256 (`digest` GitHub ghi sẵn), rồi gọi `/usr/libexec/conbangtv/cbupdate` (`Helper/cbupdate.c`, setuid root —
`layout/DEBIAN/postinst` đặt quyền): chỉ cài `.deb` trong `Documents/ConBangTV-update/` đúng gói `vn.conbangtv.legacy`, đóng app,
`dpkg -i`, `uicache`, mở lại app (nhật ký `Documents/ConBangTV-update/install.log`). Thử: pref `update_api` trỏ tới danh sách
release khác.

Phát hành bản mới:

1. Đổi số bản ở `app/control` (`Version:`) và `CFBundleShortVersionString` trong `app/Resources/Info.plist`.
2. Trên máy dựng: `bash tools/build-release.sh` → `app/packages/vn.conbangtv.legacy_<bản>_iphoneos-arm.deb` (+ tra ký hiệu bằng
   `cbsymcheck` trên một máy iOS 6).
3. `gh release create v<bản> <tệp .deb> -R ConBangTVLegacy/ConBangTV-Legacy --title "Côn Bằng TV Legacy <bản>" --notes "…"`.
   Đừng thay tệp của bản đã phát hành (CDN còn giữ tệp cũ vài phút → app báo sai kích thước) — sửa thì ra bản mới.
4. Nguồn Cydia (`https://conbangtvlegacy.github.io/repo/`, repo ConBangTVLegacy/conbangtvlegacy.github.io): trên máy dựng
   `bash tools/update-cydia-repo.sh <…>/conbangtvlegacy.github.io/repo app/packages/vn.conbangtv.legacy_<bản>_iphoneos-arm.deb`
   (chép .deb vào `repo/debs`, giữ 3 bản, tạo `Packages` / `Release`), sửa mục «Mới trong bản» của `repo/depiction.html`, rồi
   đẩy repo trang lên. Trang `depiction.html` / `index.html` phải chạy trên Safari iOS 6 (không biến CSS, grid, flex gap, fetch).

Máy đang chạy bản cũ hơn 0.4.0 (chưa có `cbupdate`) cài bản mới một lần bằng Cydia (thêm nguồn ở trên) hoặc `dpkg -i`.

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
2. Thử iPad mini 1 (A5, 512 MB RAM).
3. Đóng gói / cập nhật (OTA): .deb trên GitHub Releases + kiểm bản mới trong app, hoặc repo Cydia riêng.
