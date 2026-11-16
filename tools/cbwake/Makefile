# Thư viện nạp vào SpringBoard (MobileSubstrate) để mở khoá / bật sáng màn hình máy THỬ từ SSH — iOS 5 không có hàm mở khoá
# trong SpringBoardServices như iOS 6 (cblaunch dùng). Chỉ cài trên máy thử không đặt mật khẩu:
#   make → .theos/obj/debug/CBWake.dylib → /Library/MobileSubstrate/DynamicLibraries/ (kèm CBWake.plist), khởi động lại SpringBoard
#   cblaunch unlock            (gửi thông báo Darwin vn.conbangtv.legacy.unlock)
TARGET := iphone:clang:9.3:5.0
ARCHS = armv7
include $(THEOS)/makefiles/common.mk
LIBRARY_NAME = CBWake
CBWake_FILES = main.m
CBWake_FRAMEWORKS = Foundation CoreFoundation
CBWake_CFLAGS = -fobjc-arc
CBWake_CODESIGN_FLAGS = -S -Hsha1
include $(THEOS_MAKE_PATH)/library.mk
