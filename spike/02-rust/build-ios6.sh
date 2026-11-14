#!/usr/bin/env bash
# Dựng thư viện Rust của bước 2 cho iOS 6 → target/armv7-apple-ios6/release/libcbrspike.a
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
bash "$HERE/../../tools/rust/cargo-ios6.sh" build --release
