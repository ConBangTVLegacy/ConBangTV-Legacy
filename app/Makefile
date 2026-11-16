# Côn Bằng TV cho iOS 5 / 6 (iPhone / iPad đã jailbreak) — Theos trên Linux, SDK 9.3, armv7 (chạy được A4 trở lên: iPad 1, iPhone 4).
#   make package                    bản thử (có công cụ gỡ lỗi Debug/, -DDEBUG)
#   make package FINALPACKAGE=1     bản phát hành
# Cần lõi Rust đã dựng: tools/build-core.sh → CORE_LIB_DIR/libconbang_core.a
TARGET := iphone:clang:9.3:5.0
ARCHS = armv7
INSTALL_TARGET_PROCESSES = ConBangTV

# dpkg của iOS 5 / 6 chỉ đọc .deb nén gzip; nhân iOS 5 / 6 chỉ hiểu chữ ký SHA-1
THEOS_PLATFORM_DEB_COMPRESSION_TYPE = gzip
TARGET_CODESIGN_FLAGS = -S -Hsha1

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = ConBangTV
ConBangTV_FILES = main.m $(wildcard Core/*.m) Core/CBShims.c $(wildcard UI/*.m)
ifneq ($(FINALPACKAGE),1)
ConBangTV_FILES += $(wildcard Debug/*.m)
endif
ConBangTV_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore AVFoundation CoreMedia MediaPlayer ImageIO Security
# zlib: giải nén lịch phát sóng XMLTV .xml.gz (Core/CBIPTV.m)
ConBangTV_LIBRARIES = z
ConBangTV_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -ICore -IUI -IDebug

# Giải mã ảnh WebP (iOS 6 không có; ảnh bìa KKPhim / yanhh3d… là WebP): libwebp — tools/vendor-libwebp.sh → vendor/libwebp.
# Chỉ dựng phần giải mã, danh sách lấy từ makefile.unix của libwebp (DEC_OBJS + DSP_DEC_OBJS + UTILS_DEC_OBJS).
WEBP = vendor/libwebp
WEBP_FILES := $(shell sed -n -e '/^DEC_OBJS/,/^$$/p' -e '/^DSP_DEC_OBJS/,/^$$/p' -e '/^UTILS_DEC_OBJS/,/^$$/p' \
	$(WEBP)/makefile.unix 2>/dev/null | grep -o 'src/[a-z0-9_/]*\.o' | sed 's/\.o$$/.c/')
ifeq ($(WEBP_FILES),)
$(error Chưa có libwebp — chạy bash ../tools/vendor-libwebp.sh)
endif
ConBangTV_FILES += $(addprefix $(WEBP)/,$(WEBP_FILES))
ConBangTV_CFLAGS += -I$(WEBP)/src -I$(WEBP)
# Lõi do tools/build-core.sh dựng ở <thư mục chứa repo>/target-core (cạnh repo)
CORE_LIB_DIR ?= $(abspath $(CURDIR)/../../target-core/armv7-apple-ios6/release)
ConBangTV_LDFLAGS = -L$(CORE_LIB_DIR) -lconbang_core

include $(THEOS_MAKE_PATH)/application.mk

# Công cụ cài bản cập nhật OTA (Helper/cbupdate.c): quyền root nhờ setuid — layout/DEBIAN/postinst đặt chown root + chmod 4755.
# Quyền com.apple.springboard.launchapplications để mở lại app sau khi cài (như tools/cblaunch).
TOOL_NAME = cbupdate
cbupdate_FILES = Helper/cbupdate.c
cbupdate_FRAMEWORKS = CoreFoundation
cbupdate_INSTALL_PATH = /usr/libexec/conbangtv
cbupdate_CODESIGN_FLAGS = -SHelper/entitlements.plist -Hsha1
include $(THEOS_MAKE_PATH)/tool.mk

# postinst cần quyền chạy (tệp chép từ Windows không giữ bit x)
before-package::
	chmod 0755 $(THEOS_STAGING_DIR)/DEBIAN/postinst

after-install::
	install.exec "su mobile -c uicache; killall -9 ConBangTV 2>/dev/null || true"
