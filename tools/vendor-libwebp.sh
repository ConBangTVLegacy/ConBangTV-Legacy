#!/usr/bin/env bash
# Lấy libwebp (Google, giấy phép BSD) — chỉ dùng phần giải mã: iOS 6 không đọc được ảnh WebP (iOS 14 mới có), mà ảnh bìa của
# KKPhim (phimimg.com/uploads/movies/*.webp), yanhh3d… đều là WebP. Makefile của app dựng thẳng các tệp .c giải mã.
#   bash tools/vendor-libwebp.sh   → app/vendor/libwebp (Makefile của app đọc danh sách tệp giải mã trong makefile.unix)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="v1.4.0"
DST="$ROOT/app/vendor/libwebp"
if [[ -f "$DST/.cbtv-tag" && "$(cat "$DST/.cbtv-tag")" == "$TAG" ]]; then
    exit 0
fi
rm -rf "$DST"
mkdir -p "$ROOT/app/vendor"
git clone --quiet --depth 1 --branch "$TAG" https://github.com/webmproject/libwebp.git "$DST"
rm -rf "$DST/.git"
echo "$TAG" > "$DST/.cbtv-tag"
echo "libwebp $TAG → $DST"
