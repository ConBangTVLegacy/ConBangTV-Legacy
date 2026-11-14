#!/usr/bin/env bash
# Dựng bản phát hành của Côn Bằng TV Legacy (không có công cụ gỡ lỗi Debug/, không giữ màn hình sáng):
#   bash tools/build-release.sh           # dùng lõi đã dựng (target-core)
#   bash tools/build-release.sh --core    # dựng lại lõi trước (tools/build-core.sh)
# → app/packages/vn.conbangtv.legacy_<bản>_iphoneos-arm.deb (bản lấy từ app/control; nhớ đổi cả CFBundleShortVersionString
#   trong app/Resources/Info.plist). Trước khi cài: tra ký hiệu trên máy iOS 6 bằng cbsymcheck (tools/symlist.py).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export THEOS="${THEOS:-$HOME/theos}"
if [[ "${1:-}" == "--core" ]]; then
    bash "$ROOT/tools/build-core.sh"
fi
VERSION="$(sed -n 's/^Version: *//p' "$ROOT/app/control")"
PLIST_VERSION="$(grep -A1 CFBundleShortVersionString "$ROOT/app/Resources/Info.plist" | sed -n 's/.*<string>\(.*\)<\/string>.*/\1/p')"
if [[ "$VERSION" != "$PLIST_VERSION" ]]; then
    echo "Bản trong app/control ($VERSION) khác Info.plist ($PLIST_VERSION)" >&2
    exit 1
fi
cd "$ROOT/app"
make clean >/dev/null 2>&1 || true
make package FINALPACKAGE=1
BIN=.theos/_/Applications/ConBangTV.app/ConBangTV
if strings "$BIN" | grep -q "ConBangTV-cmd.txt"; then
    echo "LỖI: bản phát hành còn mã gỡ lỗi (Debug/)" >&2
    exit 1
fi
python3 "$ROOT/tools/symlist.py" "$BIN" > packages/symlist-$VERSION.txt
DEB="packages/vn.conbangtv.legacy_${VERSION}_iphoneos-arm.deb"
ls -la "$DEB"
sha256sum "$DEB"
echo "Ký hiệu cần tra trên máy: app/packages/symlist-$VERSION.txt (… | ssh root@<máy> cbsymcheck)"
