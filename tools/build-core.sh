#!/usr/bin/env bash
# Dựng lõi Rust chung của Côn Bằng TV (repo ChimToTV: linux/core + linux/ffi) cho iOS 6 (armv7)
#   → <thư mục làm việc>/target-core/armv7-apple-ios6/release/libconbang_core.a  (Makefile của app: CORE_LIB_DIR)
# Bản clone ChimToTV ở <thư mục làm việc>/upstream (chỉ để dựng, không sửa tay): mỗi lần dựng đặt lại rồi áp patches/*.patch.
#   bash tools/build-core.sh            # dựng bản đang có
#   bash tools/build-core.sh --pull     # lấy bản mới nhất của main rồi dựng
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK:-$(cd "$ROOT/.." && pwd)}"
UP="$WORK/upstream"
if [[ ! -d "$UP/.git" ]]; then
    git clone --quiet --depth 1 https://github.com/Circling5714/ChimToTV.git "$UP"
fi
cd "$UP"
git checkout -q -- .
if [[ "${1:-}" == "--pull" ]]; then
    git pull -q --ff-only
fi
echo "ChimToTV $(git log -1 --format='%h %ad' --date=short)"
for p in "$ROOT"/patches/*.patch; do
    git apply "$p"
    echo "áp $(basename "$p")"
done
cd linux
CARGO_TARGET_DIR="$WORK/target-core" bash "$ROOT/tools/rust/cargo-ios6.sh" rustc --release -p conbang-ffi --crate-type staticlib
ls -la "$WORK/target-core/armv7-apple-ios6/release/libconbang_core.a"
