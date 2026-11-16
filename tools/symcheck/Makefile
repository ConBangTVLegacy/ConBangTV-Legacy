# Công cụ tra ký hiệu trên máy iOS 6 — dựng: `make` → .theos/obj/debug/cbsymcheck. Danh sách đầu vào: tools/symlist.py.
TARGET := iphone:clang:9.3:5.0
ARCHS = armv7

include $(THEOS)/makefiles/common.mk

TOOL_NAME = cbsymcheck
cbsymcheck_FILES = main.c
cbsymcheck_CODESIGN_FLAGS = -S -Hsha1

include $(THEOS_MAKE_PATH)/tool.mk
