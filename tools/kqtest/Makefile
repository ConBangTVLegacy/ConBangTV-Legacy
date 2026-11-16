# Kiểm kqueue EVFILT_USER trên máy iOS 6 (bộ đánh thức của mio / tokio) — dựng: make → .theos/obj/debug/kqtest
TARGET := iphone:clang:9.3:5.0
ARCHS = armv7
include $(THEOS)/makefiles/common.mk
TOOL_NAME = kqtest
kqtest_FILES = main.c
kqtest_CODESIGN_FLAGS = -S -Hsha1
include $(THEOS_MAKE_PATH)/tool.mk
