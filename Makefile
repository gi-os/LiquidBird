TARGET := iphone:clang:latest:15.0
ARCHS := arm64
INSTALL_TARGET_PROCESSES = Twitter

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LiquidBird
LiquidBird_FILES = Tweak.x Tiling.x Debug.x
LiquidBird_CFLAGS = -fobjc-arc
LiquidBird_FRAMEWORKS = UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
