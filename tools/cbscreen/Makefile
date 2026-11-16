# Chụp toàn màn hình máy iOS 6 từ SSH (xem main.m) — dựng: make → .theos/obj/debug/cbscreen
TARGET := iphone:clang:9.3:5.0
ARCHS = armv7
include $(THEOS)/makefiles/common.mk
TOOL_NAME = cbscreen
cbscreen_FILES = main.m
cbscreen_FRAMEWORKS = CoreFoundation CoreGraphics ImageIO
cbscreen_CODESIGN_FLAGS = -S -Hsha1
include $(THEOS_MAKE_PATH)/tool.mk
