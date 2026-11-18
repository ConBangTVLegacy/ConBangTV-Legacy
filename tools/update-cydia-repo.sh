#!/usr/bin/env bash
# Tạo / cập nhật nguồn Cydia (APT phẳng) trong thư mục repo/ của trang giới thiệu (conbangtvlegacy.github.io):
#   bash tools/update-cydia-repo.sh <đường dẫn tới …/conbangtvlegacy.github.io/repo> <tệp .deb mới>…
# Chép .deb vào repo/debs (giữ 3 bản mới nhất mỗi gói), tạo Packages(.gz/.bz2) bằng dpkg-scanpackages và Release (MD5 + SHA256).
# Nguồn trong Cydia: https://conbangtvlegacy.github.io/repo/  (dòng APT: deb https://conbangtvlegacy.github.io/repo/ ./)
# Cần dpkg-dev (dpkg-scanpackages), gzip, bzip2 — chạy trên máy Linux dựng.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="${1:?thư mục repo/}"
shift
mkdir -p "$REPO/debs"
for d in "$@"; do
    cp "$d" "$REPO/debs/"
done
cd "$REPO"
# Giữ 3 bản mới nhất của từng gói (theo số bản trong tên tệp; gói = phần trước dấu _ đầu tiên — app, «Hình nổi»…)
for pkg in $(ls debs/*.deb | sed 's#^debs/##; s#_.*##' | sort -u); do
    ls debs/"${pkg}"_*.deb | sort -V | head -n -3 | xargs -r rm -f
done
dpkg-scanpackages -m debs /dev/null > Packages 2>/dev/null
# Cydia 1.1.30 (iOS 5 / 6) hiện chữ có dấu trong Description thành «?»; gói cũ (≤ 0.5.5) mang mô tả có dấu → mọi bản dùng mô tả
# không dấu hiện tại của app/control
# — tương tự gói «Hình nổi» lấy mô tả ở tweak/CBFloat/control (bản 0.1.0 đã dựng còn ngoặc «», cũng hiện thành «?»)
DESC="$(sed -n 's/^Description: *//p' "$ROOT/app/control")"
FDESC="$(sed -n 's/^Description: *//p' "$ROOT/tweak/CBFloat/control")"
awk -v d="$DESC" -v f="$FDESC" '/^Package: /{p = $2}
    /^Description: / && p == "vn.conbangtv.legacy" {$0 = "Description: " d}
    /^Description: / && p == "vn.conbangtv.float" {$0 = "Description: " f}
    {print}' Packages > Packages.tmp && mv Packages.tmp Packages
gzip -9nc Packages > Packages.gz
bzip2 -9c Packages > Packages.bz2
{
    cat <<'EOF'
Origin: Côn Bằng TV Legacy
Label: Côn Bằng TV Legacy
Suite: stable
Version: 1.0
Codename: ios6
Architectures: iphoneos-arm
Components: main
Description: Côn Bằng TV cho iPhone / iPad iOS 5 / iOS 6 đã jailbreak — https://conbangtvlegacy.github.io
EOF
    echo "MD5Sum:"
    for f in Packages Packages.gz Packages.bz2; do echo " $(md5sum "$f" | cut -d' ' -f1) $(stat -c %s "$f") $f"; done
    echo "SHA256:"
    for f in Packages Packages.gz Packages.bz2; do echo " $(sha256sum "$f" | cut -d' ' -f1) $(stat -c %s "$f") $f"; done
} > Release
echo "Nguồn Cydia: $(grep -c '^Package:' Packages) gói"
grep -E '^(Package|Version|Filename|Size):' Packages
