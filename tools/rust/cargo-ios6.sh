#!/usr/bin/env bash
# cargo cho iOS 5 / 6 (armv7, target tự định nghĩa armv7-apple-ios6.json — cortex-a8 để chạy cả A4: iPad 1, iPhone 4) trên máy Ubuntu có Theos + Rust nightly (rust-src).
#   bash tools/rust/cargo-ios6.sh build --release [-p <gói>] …   (chạy trong thư mục crate / workspace)
# Tự thêm: -Z build-std (thư viện chuẩn dựng lại cho target), --target, ring đã vá (vendor/, tạo bằng vendor-ring.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
THEOS="${THEOS:-$HOME/theos}"
TC="$THEOS/toolchain/linux/iphone/bin"
SDKROOT="$THEOS/sdks/iPhoneOS9.3.sdk"
RING="$ROOT/vendor/ring-0.17.14"
[[ -d "$RING" ]] || bash "$ROOT/tools/rust/vendor-ring.sh" >/dev/null
export SDKROOT
export IPHONEOS_DEPLOYMENT_TARGET=5.0
# Mã C trong các crate (ring…) dựng bằng clang của Theos cho armv7 iOS 5 (Cortex-A8 trở lên)
export CC_armv7_apple_ios6="$TC/clang"
export CFLAGS_armv7_apple_ios6="-target armv7-apple-ios5.0 -isysroot $SDKROOT -mcpu=cortex-a8"
export AR_armv7_apple_ios6="$TC/llvm-ar"
. "$HOME/.cargo/env"
cmd="$1"
shift
exec cargo +nightly "$cmd" \
    -Z build-std=std,panic_abort \
    -Z json-target-spec \
    --target "$ROOT/tools/rust/armv7-apple-ios6.json" \
    --config "patch.crates-io.ring.path=\"$RING\"" \
    "$@"
