#!/usr/bin/env bash
# Tạo / cập nhật nguồn Cydia (APT phẳng) trong thư mục repo/ của trang giới thiệu (conbangtvlegacy.github.io):
#   bash tools/update-cydia-repo.sh <đường dẫn tới …/conbangtvlegacy.github.io/repo> <tệp .deb mới>…
# Chép .deb vào repo/debs (giữ 3 bản mới nhất), tạo Packages(.gz/.bz2) bằng dpkg-scanpackages và Release (MD5 + SHA256).
# Nguồn trong Cydia: https://conbangtvlegacy.github.io/repo/  (dòng APT: deb https://conbangtvlegacy.github.io/repo/ ./)
# Cần dpkg-dev (dpkg-scanpackages), gzip, bzip2 — chạy trên máy Linux dựng.
set -euo pipefail
REPO="${1:?thư mục repo/}"
shift
mkdir -p "$REPO/debs"
for d in "$@"; do
    cp "$d" "$REPO/debs/"
done
cd "$REPO"
# Giữ 3 bản mới nhất (theo số bản trong tên tệp)
ls debs/*.deb | sort -V | head -n -3 | xargs -r rm -f
dpkg-scanpackages -m debs /dev/null > Packages 2>/dev/null
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
