ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:17.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ArcLaunchHUDKeyboardHost ArcLaunchGuestKeyboardBridge

ArcLaunchHUDKeyboardHost_FILES = HUDKeyboardHost.xm
ArcLaunchHUDKeyboardHost_FRAMEWORKS = Foundation UIKit
ArcLaunchHUDKeyboardHost_CFLAGS = -fobjc-arc

ArcLaunchGuestKeyboardBridge_FILES = GuestKeyboardBridge.xm
ArcLaunchGuestKeyboardBridge_FRAMEWORKS = Foundation UIKit
ArcLaunchGuestKeyboardBridge_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
