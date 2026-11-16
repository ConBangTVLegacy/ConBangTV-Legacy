# Công cụ mở app từ SSH trên máy iOS 6 jailbreak — dựng: `make` → .theos/obj/debug/cblaunch, chép vào /usr/bin của máy.
TARGET := iphone:clang:9.3:5.0
ARCHS = armv7

include $(THEOS)/makefiles/common.mk

TOOL_NAME = cblaunch
cblaunch_FILES = main.m
cblaunch_FRAMEWORKS = CoreFoundation
# SpringBoardServices nạp bằng dlopen / dlsym (xem main.m), không liên kết cứng
# Nhân iOS 6 chỉ hiểu chữ ký SHA-1
cblaunch_CODESIGN_FLAGS = -Sentitlements.plist -Hsha1

include $(THEOS_MAKE_PATH)/tool.mk
