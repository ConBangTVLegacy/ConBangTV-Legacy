# Côn Bằng TV Legacy — bản iOS 5 / iOS 6

**Trang giới thiệu, cách cài:** <https://conbangtvlegacy.github.io> · **Tải bản mới nhất:** [GitHub Releases](https://github.com/ConBangTVLegacy/ConBangTV-Legacy/releases/latest)


Bản Côn Bằng TV cho máy iOS 5 / iOS 6 đã jailbreak — một gói `.deb` chạy cả hai (máy thử: **iPhone 5 iOS 6.1.4**,
**iPad mini 1 iOS 6.1.3**, **iPad 1 iOS 5.1.1** — xem mục «Bản iOS 5»). App gốc và lõi chung ở repo
[repo chính](https://github.com/conbangtv/ChimToTV); bản iPad hiện tại (Swift / SwiftUI / WKWebView, iOS 15+) không
chạy được trên iOS cũ nên bản này viết riêng.

## Kiến trúc (đã chứng minh chạy trên iPhone 5 — 14/11/2026)

```
UIKit + Objective-C (vỏ app, armv7, dựng cho iOS 5.0 — chạy cả iOS 5 và 6)
  │  JSON qua 4 hàm C: cbtv_init / cbtv_call / cbtv_call_sync / cbtv_free   (như bản Windows)
  ▼
Lõi Rust chung của repo chính (linux/core + linux/ffi) dựng cho armv7 Cortex-A8 (A4 trở lên) → libconbang_core.a
  │  đọc trang / API phim, cài đặt, mạng (rustls + gốc Mozilla đóng kèm, DNS mã hoá, vượt chặn, proxy), đồng bộ…
  ▼
Cổng phát nội bộ 127.0.0.1 (media_proxy: bỏ quảng cáo, cắt PNG ngụy trang…) ──► AVPlayer (giải mã phần cứng 1080p)
```

## Thư mục

| Đường dẫn | Nội dung |
| --- | --- |
| `spike/01-player/` | App thử (Theos): bài kiểm mạng / TLS, phát AVPlayer, gọi lõi Rust; chạy tự động qua SSH — xem README trong đó |
| `spike/02-rust/` | Thử Rust tối thiểu (std + tokio + reqwest) — bước đệm, nay dùng lõi thật |
| `tools/setup-theos.sh` | Cài Theos + toolchain (clang 11, ld64-609) + SDK iPhoneOS 9.3 vào `~/theos`, **vá SDK** cho iOS 5 / 6 |
| `tools/build-core.sh` | Dựng lõi chung: clone repo chính vào `upstream/`, áp `patches/*.patch`, dựng `conbang-ffi` thành thư viện tĩnh |
| `tools/rust/` | Target `armv7-apple-ios6.json`, `cargo-ios6.sh` (cargo nightly + build-std), `vendor-ring.sh` (vá ring) |
| `tools/cblaunch/` | Mở app / đánh thức / mở khoá máy từ SSH (SpringBoardServices); `cblaunch unlock` mở khoá iOS 5 nhờ `cbwake`, `cblaunch mem` in bộ nhớ máy (trống / wired) |
| `tools/cbwake/` | Công cụ thử, chỉ cài trên máy thử: thư viện nạp vào SpringBoard (MobileSubstrate) — nhận thông báo `vn.conbangtv.legacy.unlock` thì bật sáng + mở khoá (iOS 5 không có hàm mở khoá trong SpringBoardServices) |
| `tools/cbscreen/` | Chụp toàn màn hình máy (cả màn hình chính / màn khoá) ra PNG, nhấn nút Home giả — từ SSH (`cbscreen <tệp.png> [rộng cao [cw]]`, `cbscreen home`; iPad 1 iOS 5: `cbscreen x.png 1024 768 cw` — khung hình nằm ngang, `cw` xoay lại) |
| `design/` | Nguồn logo / biểu tượng (SVG trong `icon.html`: vòng ensō vàng + ấn 鵬 nổi khối 3D trên đĩa kính tròn trong suốt); `node design/render.mjs ios a` xuất `Icon*.png` + `Default*.png` vào `app/Resources`, `web a <thư mục>` xuất logo cho trang giới thiệu / nguồn Cydia |
| `tools/symcheck/`, `tools/symlist.py` | Tra trên máy iOS 5 / 6 mọi ký hiệu tệp chạy cần — bắt lỗi «dyld: Symbol not found» trước khi chạy |
| `patches/` | Bản vá tạm cho lõi chung (3 bản vá đầu đã vào repo chính 14/11/2026; còn `0001` đồng bộ, `0002` mở lại cổng nội bộ, `0003` đổi fMP4 → MPEG-TS — xem README trong đó) |
| `app/` | **App thật — Côn Bằng TV Legacy** (`vn.conbangtv.legacy`; tên dưới biểu tượng: «Côn Bằng TV») — các màn ở mục «App» dưới đây |

## App (`app/`)

| Màn | Có gì |
| --- | --- |
| Trang chủ | «Có tập mới» (phim theo dõi + phim đang xem dở có tập mới ở bất kỳ nguồn nào — `fresh` của lõi, lọc theo `seen_eps`), «Xem tiếp», các hàng của trang chủ tổng hợp (`home.load` / `home.late`); dải nút đầu trang: ★ Điểm IMDb cao (`imdb.page`), Thể loại… / Quốc gia… (`api.filters` / `next.filters`), danh mục của trang; quay lại app sau ≥ 20 phút thì tải lại; trang phim đổi tên miền (`movedTo`) thì đổi theo |
| Tìm kiếm | tìm trên mọi trang (`site.searchAll`) |
| Trang phim | thông tin, Xem / Xem tiếp, Theo dõi, «Mới nhất: Tập N» / «Từ tập đầu» (đang xem dở), **«⇄ đổi nguồn»** (phim có ở nhiều trang — `links` của thẻ trang chủ tổng hợp), chọn bản (Vietsub / Thuyết minh), lưới tập, mô tả, **phim liên quan** (`related.load`); **phim chia mùa** (phim bộ dexter.pw — `seasons`): dải chọn mùa, «Xem tiếp / Mới nhất: Mùa n, Tập m», «Từ tập đầu» = Mùa 1 |
| Trình phát | AVPlayer qua cổng phát nội bộ, tự chọn server phát được trên iOS 6, nhớ chỗ xem, tự chuyển tập, **bảng chọn tập «☰ Tập»** (đổi bản Vietsub / Thuyết minh), điều khiển trên màn khoá, **menu «⋯»**: tốc độ phát (iOS 6 chỉ đổi được với tệp video — luồng HLS báo không đổi được), đánh dấu / tự bỏ qua đoạn mở đầu (khoá `intro@<phim>` như bản Windows), hẹn giờ tắt (15–90 phút / hết tập), tải lại; **phụ đề rời** (WebVTT / SRT của server riêng PhimMoi — tự vẽ, AVPlayer iOS 6 không gắn được), **phụ đề chọn được** của dexter.pw (menu «⋯» → Phụ đề: tiếng Việt / Anh từ OpenSubtitles / Subsource, tải qua lõi, tệp lỗi thì tự thử tệp sau, phim bộ «đang tìm» thì hỏi lại ~3 phút, chữ sớm / muộn 0,5 s nhớ theo tập, ngôn ngữ nhớ theo người xem — khoá `sub_lang` / `sub_delay` như lõi), **chất lượng** (menu «⋯» → Chất lượng: Tự động / 1080p / 720p… khi luồng có nhiều bản — nhớ theo người xem, khoá `video_quality`; lõi chỉ giữ đúng một bản khi địa chỉ danh sách chính có `?h=<chiều cao>`), server rớt giữa chừng thì thử lại server đó rồi mới sang server khác; phim chia mùa: hết mùa tự sang mùa sau; bản đang xem (vd Thuyết Minh) không có server phát được thì tự mở cùng tập ở bản khác (Vietsub); tập chỉ có trình phát có khoá (streamfree / NguonC) thì báo rõ, kèm nút **«Báo khi xem được»** (`Core/CBWaitPlayable.m`: nhớ tập theo người xem — khoá `wait_playable`; lúc mở / quay lại app và 30 phút một lần — không lúc đang xem phim — hỏi lại lõi như trình phát (`kk.source` → `site.videoOf`, cả cùng tập ở bản khác); có server phát thẳng được thì hộp «Đã xem được — Xem ngay»; bỏ sau 14 ngày); máy đã cài **Venetium** (Chromium cho iOS 5–10 đã jailbreak — nguồn Cydia computershik73.github.io/repo/beta) thì có nút **«Mở trong Venetium»** (màn lỗi + menu «⋯»): `venetium://open?url=…` mở trang tập (trang web thường) hoặc trang trình phát nhúng (trang dạng API — `api.isKnown`), trang tự phát bằng trình phát của chính nó trong một trình duyệt thật (đã thử streamfree / hhkungfu trên iPad mini 1); app không ghi chỗ xem của lần xem đó; tập NguonC → trang phim `phim.nguonc.com/phim/<tên>` (trang nhúng mở thẳng bị Cloudflare chặn) + hộp nhắc tắt «Chặn quảng cáo» của Venetium (Guard của trang dừng video khi thấy chặn quảng cáo); **luồng không bản nào máy giải mã được** (đọc danh sách chính trước khi phát — vd 2542×1080 H.264 mức 5.0) thì bỏ server ngay và báo rõ khổ của bản đó; link gốc 404 (trang đã thêm tập, chưa có video) thì báo đúng + «Báo khi xem được» (cũng tải thử link / xét khổ trước khi báo «Đã xem được») |
| Người xem | «Ai đang xem?» (thêm người, mã PIN), đổi người xem — cùng khoá dữ liệu với bản Windows |
| Cài đặt | người xem (mã PIN nhập hai lần, bỏ khoá cần mã cũ), trang chủ tổng hợp, **hồ sơ trẻ em** (tắt cần mã phụ huynh), trang phim + **đo tốc độ các trang** (`site.check`, ★ nhanh nhất), phát video (**xem riêng** — `private_mode`, không ghi lịch sử / «đã thấy tập», chỗ xem chỉ trong RAM; **server dự phòng KKPhim** — `kk_backup`; đặt lại server đã chọn), mạng (DNS mã hoá, **vượt chặn Tắt / Mức 1 / Mức 2** — `unblock` + `unblock_level`, proxy), **Đồng bộ trong nhà**, xoá lịch sử, **xoá ảnh đã lưu**, **tự kiểm tra bản mới** (`auto_update`), miễn trừ, liên hệ |
| Theo dõi / Lịch sử | nút «☆ Theo dõi» đầu trang chủ, «Xem thêm» của «Có tập mới» / «Xem tiếp»: lưới phim, kiểm tập mới khi mở, nhấn giữ để bỏ theo dõi / xoá |
| Proxy | Cài đặt → Mạng → Proxy: SOCKS5 (có đăng nhập) hoặc Shadowsocks (dán link `ss://`), DNS qua proxy, chỉ trang phim, thử kết nối; lõi lo hết (trang, video qua cổng phát nội bộ, ảnh tải qua lõi khi proxy cho cả app); proxy lỗi thì báo lỗi, không đi thẳng |
| Giới hạn giờ xem | từng người xem: số phút mỗi ngày, giờ đi ngủ (tới 6 giờ sáng); hết giờ phim dừng, xem thêm cần mã PIN phụ huynh — cùng khoá với bản Windows / TV / iPad |
| Đồng bộ trong nhà | ghép với tivi / Windows / iPad bằng mã 4 số (lõi `sync_service`, cổng 8791): lịch sử, chỗ xem, theo dõi, người xem, trang phim |
| Truyền hình (IPTV) | chip «Truyền hình» + hàng «Kênh vừa xem» ở trang chủ, Cài đặt › Dữ liệu › Truyền hình. **App không kèm sẵn kênh**: người xem tự thêm danh sách M3U / M3U8 (`Core/CBIPTV.m` — #EXTINF tvg-id / tvg-name / tvg-logo / group-title / tvg-chno, #EXTGRP, #EXTVLCOPT `http-referrer` / `http-user-agent`, `url\|Referer=…&User-Agent=…`; kênh trùng tên trong nhóm gộp thành nhiều nguồn; đệm `Library/Caches/iptv`; **tự làm mới** — lúc vào màn Truyền hình, mỗi 30 s khi màn đang mở và lúc app trở lại từ nền: tải lại khi danh sách cũ quá 6 giờ, danh sách có trận 30 phút, có trận sắp / đang đá mà chưa có link thật 5 phút; tải hỏng thì 3 phút sau mới thử lại; không tải lúc đang xem kênh). Lịch phát sóng XMLTV (địa chỉ trong đầu danh sách hoặc tự đặt; `.gz` giải nén ra đĩa, đọc dần bằng NSXMLParser — iPad 1 chỉ 256 MB), «Nhắc tôi» 5 phút trước giờ phát. Lưới kênh: nhóm, tìm / gõ số kênh, ★ yêu thích, chương trình đang phát + thanh tiến độ. Trình phát trực tiếp (`UI/CBLivePlayerViewController.m`): toàn màn hình, «☰ Kênh» mở bảng kênh, nút tự ẩn sau 6 s, vuốt lên / xuống đổi kênh, tạm dừng → «CHẬM m:ss» / «Về trực tiếp», nguồn lỗi tự sang nguồn sau, hỏng hết nguồn thì tải lại danh sách (cũ quá 10 phút) tìm link mới — link có hạn dùng — một lần mỗi lần phát được, «Thử lại» cũng vậy; bảng kênh lấy bản mới của danh sách, luồng máy không giải mã được (H.265 / AV1 / quá khổ) ghi «không phát được», giới hạn giờ xem. Referer / User-Agent riêng của nguồn gửi lên máy chủ qua lõi; **luồng HTTP-FLV** (.flv — kênh thể thao) lõi đổi sang HLS trực tiếp (bản vá 0004). **Danh sách thể thao** (giờ trận trong tên: «20:00 16/11 ⚽ A vs B (BLV …) [hls]»): mỗi BLV một kênh, bản HLS / FLV thành nhiều nguồn; dòng «● Đang đá» / «Sắp đá 20:00 · còn 25 phút» / «Đã xong», trận đang đá lên đầu; trận còn > 30 phút thì hỏi «Nhắc lúc bóng lăn / Vẫn mở»; trận sắp / đang đá mà chưa có hình (kể cả link giả «no-signal» của danh sách) thì chờ, tải lại danh sách và thử lại mỗi 20 s; danh sách có trận tải lại sau 30 phút |

Bản thử (không `FINALPACKAGE=1`) có `Debug/CBDebug.m`: đọc lệnh từ `Documents/ConBangTV-cmd.txt` (`shot`, `film`, `play`, `search`,
`settings`, `profiles`, `sync`, `syncpair`, `pick`, `scroll`, `wait`, `status`, `core`, `pref`, `notifyadd` / `notifycheck` /
`notifylist` / `notifydel` — «Báo khi xem được», `touch <x> <y>` / `hold <x> <y> [giây]` / `drag <x1> <y1> <x2> <y2> [giây]` — chạm / nhấn giữ / vuốt giả đi qua đường xử lý chạm
thật của UIKit (`Debug/CBTouch.m`, toạ độ là điểm trong cửa sổ, hệ dọc), `orient <1–4>` giả xoay máy, `memwarn` giả thiếu bộ nhớ, `pull` giả kéo trang chủ
để tải lại, `rawplay` / `rawmedia <url>` phát thử có khung hình + `rawstop`, `web <url> [referer]` / `webframe <url> <trang gốc>`
mở trang trong UIWebView (kèm trang gốc — trang nhúng chặn yêu cầu không có), `wkinfo` / `js <biểu thức>` xem WebKit đang nạp
và tính năng / thẻ `<video>` của trang, `browserpage` / `venetium` trang mà nút «Mở trong Venetium» sẽ mở / bấm nút đó; truyền
hình: `tv`, `tvadd <url>`, `tvlists`, `tvuse <số>`, `tvrefresh`, `tvepg`, `tvepgurl`, `tvguide <ô>`, `tvgroup <số>`, `tvq <chữ>`,
`tvplay <ô>`, `tvnext` / `tvprev` / `tvch <số>` / `tvpanel` / `tvpause` / `tvlive` / `tvsrc` / `tvclose`, `tvstatus`,
`tvsettings`, `tvmatches [từ ô]` (trạng thái trận, nguồn HLS / FLV), `tvremind <ô>`, `tvage <phút>` (lùi giờ cập nhật danh sách để thử tự làm mới)…) để thử tự động qua SSH. Lệnh mới đừng đặt
tên bắt đầu bằng «wait» (bị hiểu là lệnh chờ).

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
`dpkg -i`, **khởi động lại SpringBoard** (nhận biểu tượng / tên mới) rồi mở lại app (thử tới khi app thật sự ở trước màn hình,
tối đa ~90 giây) — **không `uicache`** (trên iOS 6 từng làm SpringBoard của iPad treo; chỉ khi đổi tên hiện dưới biểu tượng)
(nhật ký `Documents/ConBangTV-update/install.log`). Thử: pref `update_api` trỏ tới danh sách release khác.

`cbupdate` ≤ 0.4.2 không khởi động lại SpringBoard: `postinst` của gói mới nhận ra (không có biến `CONBANG_OTA` mà `cbupdate`
mới đặt, tệp .deb còn trong thư mục tải) và gọi `cbupdate --respring` của bản vừa cài — chờ bản cũ cài xong (xoá tệp .deb), khởi
động lại SpringBoard, mở lại app. Cài bằng Cydia: `postinst` xin nút «Restart SpringBoard». 15/11/2026 đã thử cả hai đường trên
iPhone 5 (0.4.2 → 0.4.3 và 0.4.3 → 0.4.3): app mở lại sau ~15 giây, biểu tượng mới.

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

## Bản iOS 5 (iPad 1 iOS 5.1.1 — 16/11/2026)

Cùng một gói `.deb` với iOS 6: app dựng cho iOS 5.0 (`TARGET := iphone:clang:9.3:5.0`, `MinimumOSVersion` 5.0, `Depends:
firmware (>= 5.0)`); phần của iOS 6 thì hỏi lúc chạy, thiếu thì dùng bản tự làm. Lõi Rust dựng cho Cortex-A8 (A4 — iPad 1,
iPhone 4 / 3GS) — vẫn chạy tốt trên A5 / A6.

| Bẫy của iOS 5 | Cách xử lý |
| --- | --- |
| Tệp chạy dựng cho iOS 6 dùng lệnh nạp `LC_MAIN` → iOS 5 lỗi ngay khi mở | Dựng cho iOS 5.0: ld64 tự dùng `LC_UNIXTHREAD` + `crt1.3.1.o` (SDK 9.3 có sẵn) |
| Lớp `NSObject` ở libobjc từ iOS 6; iOS 5 để ở CoreFoundation / Foundation → «Symbol not found: _OBJC_CLASS_$_NSObject» | `setup-theos.sh` vá 4: NSObject gắn vào Foundation.tbd (iOS 5 và 6 đều tìm thấy qua Foundation) |
| `dirfd` là macro trên iOS 5 (hàm từ iOS 6) — std::fs của Rust gọi hàm | `Core/CBShims.c` tự định nghĩa `dirfd` |
| `a[i]` / `d[k]` (subscripting) cần `objectAtIndexedSubscript:`… (iOS 6); Xcode bù bằng libarclite, bộ dựng Linux không có | `Core/CBCompat.m`: thêm hàm lúc nạp app nếu iOS thiếu (cả `NSIndexPath.item`, `UILabel.minimumScaleFactor` → `minimumFontSize`, `AVPlayerItem.canPlaySlowForward`) |
| `UICollectionView` chỉ có từ iOS 6 (lưới phim, hàng ngang, lưới tập, bảng tập trong trình phát) | `UI/CBCollectionView.m`: lưới tự viết, cùng tên hàm / hàm uỷ quyền, dùng chung cho mọi bản iOS |
| `UIRefreshControl` (iOS 6) | Trang chủ iOS 5: «kéo xuống để tải lại» tự vẽ |
| `tableView:willDisplayHeaderView:` (iOS 6) không gọi → chữ đầu mục bảng nhóm có bóng trắng trên nền tối | `UI/CBGroupedTableViewController.m`: iOS 5 tự vẽ nhãn (gắn hàm lúc chạy, iOS 6 giữ nhãn hệ thống) |
| Xoay màn hình: iOS 5 hỏi `shouldAutorotateToInterfaceOrientation:` | `CBCompat.m` cho màn nào khai `supportedInterfaceOrientations` thì iOS 5 theo đúng mặt nạ đó; `CBNavController` tự trả lời |
| Thiếu bộ nhớ: iOS 5 gỡ view của màn đang khuất (`viewDidUnload`) — màn dựng lại sẽ tải lại / đăng ký thông báo hai lần | `CBCompat.m`: các màn của app giữ view (như iOS 6) |
| iPad 1 chỉ 256 MB: phát video chiếm ~65 MB bộ nhớ «wired» của hệ thống (phát thẳng hay qua cổng nội bộ đều vậy) — đã bị iOS tắt app (jetsam) sau ~3 phút khi app còn giữ ảnh bìa | Máy RAM < 300 MB: mở trình phát thì bỏ ảnh bìa của các màn bên dưới (`CBImages purgeOffscreen`, hiện lại thì tự nạp từ đĩa), bộ đệm ảnh 8 MB; có cảnh báo bộ nhớ cũng bỏ |
| `▶` (U+25B6) thành emoji xanh, ký tự chọn kiểu U+FE0E hiện ô vuông | `CBPlayIcon()`: iOS 5 dùng «►» |
| Khởi động lại SpringBoard xong iOS 5 về màn khoá (kể cả không đặt mật khẩu) → không mở lại app được (SpringBoardServices báo lỗi 3) | `cbupdate` trên iOS 5 không respring, chỉ mở lại app (biểu tượng mới hiện ở lần respring sau) |
| Ảnh bìa vài trang: NSURLConnection lỗi -1003 / -1004 (DNS nhà mạng chặn) | `CBImages` chuyển sang tải qua lõi (DNS mã hoá, vượt chặn) — áp dụng cả iOS 6 |
| A4 một nhân: mở app giải mã vài chục ảnh WebP cùng lúc (mỗi ảnh một việc trên hàng đồng thời GCD) → luồng chính không kịp chạy, iOS tắt app «quá 20 giây chưa mở xong» (0x8badf00d); vuốt nhanh danh sách dài thì RAM app vọt ~100 MB và ảnh của màn mở sau phải chờ cả phút | `CBImages`: giải mã trên hàng tuần tự ưu tiên thấp (mỗi nhân một hàng, tối đa 2); ảnh đang xếp hàng mà ô đã đổi ảnh / màn đã đóng thì bỏ, ảnh tải xong không ai cần thì chỉ lưu đĩa — mở app còn ~1,9 giây, vuốt nhanh 8 trang RAM ~26 MB (áp dụng cả iOS 6) |
| Công cụ thử: không mở khoá được từ SSH; ảnh chụp màn hình nằm ngang; chép đè tệp chạy bằng scp → «Killed: 9» | `cbwake` + `cblaunch unlock`; `cbscreen … 1024 768 cw`; chép ra tệp tạm rồi `mv` |

Lõi cũng nhận `app.setVersion` = `ios5-<bản>` trên iOS 5 (Cài đặt → Phiên bản: «lõi ios5-…»).

Đã thử trên iPad 1 (A4, 256 MB, bản thử 16/11): mọi màn (trang chủ tổng hợp, ★ IMDb, tìm kiếm 7 trang, trang phim — Conan 1203
tập, Cài đặt, Người xem, Đồng bộ — thấy tivi TX3 trong mạng, xoay ngang, giả thiếu bộ nhớ), trình phát (KKPhim HLS, dexter.pw
fMP4 → TS kèm phụ đề 1700 câu, bảng chọn tập, menu «⋯», ép 720p / 1080p của dexter.pw — phát liên tục, rớt 4 khung), phát 6
phút liền không bị tắt (RAM app 14–30 MB), OTA bằng `cbupdate` (đóng → cài → mở lại app sau ~7 giây). Chạm thật (lệnh `touch` / `hold` /
`drag`, 16/11): ô phim trong hàng ngang và lưới, ô tập, bảng tập trong trình phát, nút trong phần đầu lưới, nhấn giữ ở lưới lịch
sử, vuốt ngang hàng phim, kéo xuống để tải lại, cuộn tự tải trang sau — trên cả iPad 1 (iOS 5) và iPhone 5 (iOS 6). Thử lại trên iPhone 5 iOS
6.1.4: trang chủ, lưới, trang phim, bảng tập, menu «⋯», Cài đặt, Đồng bộ như cũ, kéo xuống để tải lại (UIRefreshControl), OTA
(respring rồi tự mở lại app sau ~14 giây); tra ký hiệu bản phát hành: iOS 6 đủ, iOS 5 chỉ thiếu hai lớp iOS
6 đã rẽ nhánh (`UIRefreshControl`, `UITableViewHeaderFooterView` — gắn yếu, không dùng trên iOS 5).

## Bẫy của iOS 6 đã gặp (và cách xử lý)

- **AVPlayer lỗi -11819** (`AVErrorMediaServicesWereReset` — dịch vụ phát của iOS vừa khởi động lại, thoáng qua, gặp cả lúc
  vừa mở): thử lại đúng server đó một lần; server phát thẳng được mà vẫn lỗi thì báo đúng lỗi + «Thử lại» (trước đây sang các
  server nhúng rồi báo nhầm «chỉ có trình phát có khoá»).
- **Luồng quá khổ** (KKPhim Tiên Nghịch tập 166–167: một bản duy nhất 2542×1080, H.264 High mức 5.0): AVPlayer chờ ~40 giây
  rồi dịch vụ phát của iOS sập (-11819), thử lại lại sập. Giới hạn chung của máy iOS 5 / 6 là 1920×1088, mức 4.2 → trình phát
  đọc danh sách chính trước khi phát, không bản nào trong giới hạn thì bỏ server ngay và báo khổ của bản đó. Giới hạn 720p của A4
  chỉ dùng để chọn bản ưu tiên: iPad 1 thực tế phát được 1920×816 mức 4.0.
- **Trang thêm tập trước khi có video** (KKPhim: API có tập, link m3u8 404 vài phút): AVPlayer chỉ báo -11800 / -12666 → app
  hỏi lại link gốc qua lõi (`http.get`), 404 / 410 thì báo «máy chủ phim chưa có video» + «Báo khi xem được».
- **WebKit mới cho iOS 6 (tweak Web Port của lululab, WebKit 2026):** bật được cho cả app khác (UIWebView của app chạy WebKit
  mới), nhưng tweak tắt MediaSource cho mọi trang (phát video bằng VLC / trình phát gốc) → trình phát NguonC dùng HLS gốc và máy
  chủ đoạn phim của NguonC từ chối — không giúp xem NguonC. Venetium (Chromium, có MediaSource) xem được: mở trang phim NguonC,
  tắt «Chặn quảng cáo» cho trang rồi tải lại trang; quảng cáo trước phim có nút bỏ qua sau 1 giây.
- **Truyền hình — AVPlayer iOS 5 / 6 chỉ phát HLS (TS) và tệp MP4**: luồng HTTP-FLV (phần lớn kênh thể thao) lõi đọc liên tục
  rồi đổi vỏ sang HLS trực tiếp (`flv_hls.rs`, bản vá 0004 — chỉ đổi vỏ H.264 / AAC, không giải mã; iPad 1 phát 853×480 không
  rớt khung); luồng TS liền / MKV / DASH vẫn chưa phát được (báo rõ, sang nguồn khác). Máy chủ thể thao đòi đúng User-Agent /
  Referer mà danh sách ghi — lõi gửi theo từng phiên. Danh sách thể thao để link giả «no-signal» (ảnh 10 s + ENDLIST) cho trận
  chưa có link: AVPlayer phát hết rồi app mở lại mãi → nhận ra (địa chỉ / danh sách phát ngắn có hồi kết) và coi như chưa có nguồn.
- **Delegate của UIScrollView / UITableView trên iOS 5 / 6 là `assign`**: màn chủ đã giải phóng mà lưới còn vẽ lại thì gọi vào
  vùng nhớ đã trả (văng khi bấm «home» lúc đang ở màn Truyền hình) → `CBCollectionView` giữ thêm tham chiếu yếu và gỡ delegate
  khi chủ đã mất; các màn tự đặt delegate về nil khi giải phóng.
- **Ô lưới «mồ côi»**: ô kênh gọi `layoutIfNeeded` (đo khung logo) khi lưới đang dựng ô → CALayer bố cục ngược lên lưới, dựng ô
  lồng trong lần dựng đang chạy; lần ngoài ghi đè ô của lần trong → ô đó vẫn hiện mà không ai quản, đè ô thật (sau khi đổi danh
  sách kênh vẫn thấy kênh của danh sách cũ) → `CBCollectionView` chặn dựng lồng (dựng lại tối đa thêm một lượt).
- **Cờ bool gửi sang lõi phải là `BOOL` thật**: `@(a && b)`, `@(x > 0)`, `@(!y)` có kiểu `int` → `NSNumber` số → JSON `1`;
  serde của lõi đọc `1` thành «không phải bool» → mặc định false. Đã dính: link kênh không đuôi `.m3u8` (link chuyển tiếp) bị coi
  là tệp MP4 → không phát; Vượt chặn Mức 1 / 2 lưu `"unblock":1` → lõi coi là tắt (app tự sửa khoá cũ lúc mở). Gán vào biến
  `BOOL` trước, hoặc `cond ? @YES : @NO`.
- **UIAlertView iOS 6**: lúc hộp đang hiện, `keyWindow` là cửa sổ của hộp — mở màn mới (trình phát) từ cửa sổ của app
  (`delegate.window`) và trong `didDismissWithButtonIndex`, không thì màn mở ra không hiện.
- **HLS fMP4** (dexter.pw: `#EXT-X-MAP` + đoạn `moof` / `mdat`): AVPlayer iOS 6 chỉ phát HLS dạng MPEG-TS (fMP4 có từ iOS 10) →
  cổng phát nội bộ đổi vỏ từng đoạn thành MPEG-TS (`patches/0003`, không giải mã lại), bỏ bản 4K (A5 / A6 chỉ giải mã H.264 tới
  1080p), bản ~720p lên đầu danh sách chính.
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
  50 ms (`ffi-ios-wakeup.patch`, đã vào repo chính). Nhịp đó cũng là một việc đẩy vào runtime → có lần mở app (máy hai nhân —
  iPhone 5 / iPad mini, ~1/12 lần) chính nó bị lỡ, runtime ngủ hẳn: không lệnh mạng nào chạy, cổng đồng bộ không đóng được
  («Address already in use»). `patches/0005`: nhịp chạy trên luồng riêng (`block_on`). Lấy ngăn xếp của app đang kẹt trên bản
  phát hành: `kill -ABRT <pid>` → báo cáo trong `/var/mobile/Library/Logs/CrashReporter/`.
- **Tốc độ phát:** AVPlayer iOS 6 chỉ đổi rate khi `canPlayFastForward` / `canPlaySlowForward` (tệp video); luồng HLS báo
  không (0 / 0) — đặt rate khác 1 thì bị bỏ qua, đang dừng mà đặt `rate = 1.5` thì không phát lại → luôn hỏi trước, không được
  thì phát 1×.
- **UIActionSheet ở iPhone ngang:** từ ~4 nút trở lên iOS 6 vẽ thành danh sách cuộn, mục cuối bị che → bảng chọn của trình
  phát tự vẽ (`sheet:items:`). Phông iOS 6 thiếu ⏮ / ⏭ (hiện ô vuông) — dùng « / ».
- **Ảnh bìa của trang mới (vd phimmoi.courses):** NSURLConnection iOS 6 lỗi SSL -1200 hoặc treo bắt tay tới hết giờ → `CBImages`
  tải lại qua lõi (rustls) và ghi nhớ trang đó (`CBCoreImageHosts` trong NSUserDefaults) để lần sau tải qua lõi luôn.
- **`killall <app>` không đóng được app đang nằm nền:** iOS treo tiến trình (SIGTERM chờ tới khi app chạy lại) → cài bản mới
  qua SSH phải `killall -9 ConBangTV`, không thì máy vẫn chạy mã cũ (`cbupdate` đã có SIGKILL dự phòng).
- **Cài bản mới:** đừng chạy `uicache` lúc app đang mở (SpringBoard đơ, phải respring); cài xong mở lại app ngay — bản thử giữ màn
  hình sáng, máy khoá lâu thì tắt Wi-Fi, mất SSH.
- **Đổi biểu tượng:** SpringBoard giữ biểu tượng đã dựng trong `/var/mobile/Library/Caches/com.apple.IconsCache/` (tệp
  `vn.conbangtv.legacy_…`) — thay `Icon*.png` rồi respring vẫn hiện bản cũ. `postinst` xoá các mục đó, cập nhật OTA khởi động lại
  SpringBoard nên biểu tượng mới hiện ngay. Biểu tượng có kênh alpha: iOS 6 giữ phần trong suốt, không tự bo góc, không thêm bóng
  (đã thử trên iPhone 5 bằng `tools/cbscreen` 15/11/2026).

## Kết quả trên iPhone 5 (iOS 6.1.4)

| Mục | Kết quả |
| --- | --- |
| App ObjC + AVPlayer phát thẳng KKPhim (HLS, H.264 High 1080p) | giải mã phần cứng 1920×1080, mở 0,9 s, tua 0,3 s, 150 s không khựng, RAM 14 MB |
| Lõi Rust chung (`cbtv_init`, `http.get` HTTP / HTTPS / Let's Encrypt / HTTP/2) | chạy, không thiếu ký hiệu (237 ký hiệu đã tra) |
| Phát qua cổng phát nội bộ của lõi (`media.open`) | phát 1080p, mở 1,4 s, **đã cắt ~35 s quảng cáo chèn giữa phim**, RAM 20 MB |
| Tốc độ tải | Wi-Fi của máy thử yếu lúc đo (mất 10% gói, trễ ~88 ms): NSURLConnection 0,16–0,68 MB/s, lõi Rust 0,06–0,29 MB/s — cần đo lại khi sóng tốt |

## Việc tiếp theo

1. Tìm kiếm phimmois.fun (lõi chung) trả ~60 phim mới nhất cho mọi từ khoá — app tạm bỏ nhóm đó khi không phim nào khớp
   (`CBGridViewController dropJunk`); sửa hẳn ở lõi thì bỏ được.
2. Trang bật chống bot của Cloudflare (hoathinh3d.pw): các bản khác đọc hộ bằng WebView ẩn (`web.fetch`); WebView iOS 6 nhiều
   khả năng không qua được lớp chặn — chưa làm.
3. Đo lại tốc độ tải qua lõi khi Wi-Fi tốt (lần đo đầu Wi-Fi máy thử yếu).
