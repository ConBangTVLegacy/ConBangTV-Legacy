# Thử mạng bằng NSURLConnection của iOS (xem main.m) — dựng: make → .theos/obj/debug/nettest
TARGET := iphone:clang:9.3:6.0
ARCHS = armv7
include $(THEOS)/makefiles/common.mk
TOOL_NAME = nettest
nettest_FILES = main.m
nettest_FRAMEWORKS = Foundation
nettest_CODESIGN_FLAGS = -S -Hsha1
include $(THEOS_MAKE_PATH)/tool.mk
