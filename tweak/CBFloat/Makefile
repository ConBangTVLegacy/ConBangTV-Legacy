# CBFloat — «Hình nổi» của Côn Bằng TV Legacy: thư viện nạp vào SpringBoard (MobileSubstrate) cho iOS 8, hiện khung video nổi trên
# mọi màn (màn hình chính, app khác). Không móc hàm nào của SpringBoard — chỉ nghe thông báo Darwin của app (xem main.m).
#   make package → packages/vn.conbangtv.float_<bản>_iphoneos-arm.deb (cài xong khởi động lại SpringBoard)
TARGET := iphone:clang:9.3:8.0
ARCHS = armv7

# dpkg / nhân iOS cũ: gói nén gzip, chữ ký SHA-1 (như app)
THEOS_PLATFORM_DEB_COMPRESSION_TYPE = gzip
TARGET_CODESIGN_FLAGS = -S -Hsha1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CBFloat
CBFloat_FILES = main.m
CBFloat_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore AVFoundation CoreMedia
CBFloat_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
