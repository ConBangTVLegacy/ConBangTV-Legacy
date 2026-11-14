# Côn Bằng TV cho iOS 6 (iPhone / iPad đã jailbreak) — Theos trên Linux, SDK 9.3, armv7 (chạy được A5 trở lên).
#   make package                    bản thử (có công cụ gỡ lỗi Debug/, -DDEBUG)
#   make package FINALPACKAGE=1     bản phát hành
# Cần lõi Rust đã dựng: tools/build-core.sh → CORE_LIB_DIR/libconbang_core.a
TARGET := iphone:clang:9.3:6.0
ARCHS = armv7
INSTALL_TARGET_PROCESSES = ConBangTV

# dpkg của iOS 6 chỉ đọc .deb nén gzip; nhân iOS 6 chỉ hiểu chữ ký SHA-1
THEOS_PLATFORM_DEB_COMPRESSION_TYPE = gzip
TARGET_CODESIGN_FLAGS = -S -Hsha1

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = ConBangTV
ConBangTV_FILES = main.m $(wildcard Core/*.m) Core/CBShims.c $(wildcard UI/*.m)
ifneq ($(FINALPACKAGE),1)
ConBangTV_FILES += $(wildcard Debug/*.m)
endif
ConBangTV_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore AVFoundation CoreMedia MediaPlayer ImageIO Security
ConBangTV_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -ICore -IUI -IDebug
CORE_LIB_DIR ?= $(HOME)/work/target-core/armv7-apple-ios6/release
ConBangTV_LDFLAGS = -L$(CORE_LIB_DIR) -lconbang_core

include $(THEOS_MAKE_PATH)/application.mk

after-install::
	install.exec "su mobile -c uicache; killall -9 ConBangTV 2>/dev/null || true"
