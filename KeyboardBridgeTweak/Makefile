ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:17.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ArcLaunchGuestKeyboardBridge

ArcLaunchGuestKeyboardBridge_FILES = GuestKeyboardBridge.xm
ArcLaunchGuestKeyboardBridge_FRAMEWORKS = Foundation UIKit
ArcLaunchGuestKeyboardBridge_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
