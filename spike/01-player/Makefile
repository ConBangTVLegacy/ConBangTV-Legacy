# Bước 1 — app thử bộ dựng / trình phát / TLS trên iOS 6 (iPad mini 1, iPhone 5 đã jailbreak).
# Dựng bằng Theos trên Linux: `make package` → packages/*.deb; `make package install THEOS_DEVICE_IP=<ip>` cài qua SSH.
# SDK 9.3 là bản mới nhất còn thư viện armv7; một bản armv7 chạy được cả A5 (iPad mini 1) lẫn A6 (iPhone 5).
TARGET := iphone:clang:9.3:6.0
ARCHS = armv7
INSTALL_TARGET_PROCESSES = ConBangLegacy

# dpkg của iOS 6 chỉ đọc .deb nén gzip (dpkg-deb của Ubuntu mặc định zstd / xz)
THEOS_PLATFORM_DEB_COMPRESSION_TYPE = gzip
# Nhân iOS 6 chỉ hiểu CodeDirectory băm SHA-1 — ldid mặc định ký SHA-256
TARGET_CODESIGN_FLAGS = -S -Hsha1

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = ConBangLegacy
ConBangLegacy_FILES = main.m AppDelegate.m TestsViewController.m PlayerViewController.m CBFetch.m CBLog.m CBCore.m shims_ios6.c
ConBangLegacy_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore AVFoundation CoreMedia CoreVideo Security
ConBangLegacy_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
# Lõi Rust chung (repo chính: linux/core + linux/ffi) dựng cho iOS 6 — tools/build-core.sh → libconbang_core.a
# Lõi do tools/build-core.sh dựng ở <thư mục chứa repo>/target-core (cạnh repo)
CORE_LIB_DIR ?= $(abspath $(CURDIR)/../../../target-core/armv7-apple-ios6/release)
ConBangLegacy_LDFLAGS = -L$(CORE_LIB_DIR) -lconbang_core

include $(THEOS_MAKE_PATH)/application.mk

after-install::
	install.exec "uicache; killall -9 ConBangLegacy 2>/dev/null || true"
