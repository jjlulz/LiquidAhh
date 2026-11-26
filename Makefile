export TARGET := iphone:clang:latest:12.0
export ARCHS = arm64
# rootful on purpose: iOS 12 jailbreaks (checkra1n / Amethyst) are not rootless
export THEOS_PACKAGE_SCHEME =

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LiquidAss12 LiquidAss12UI

LiquidAss12_FILES = Tweak.x LGSupport.m LGGlass.m
LiquidAss12_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-function
LiquidAss12_FRAMEWORKS = UIKit QuartzCore CoreGraphics

LiquidAss12UI_FILES = UIControls.x liquidass12prefs/LGKBridge.m
LiquidAss12UI_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-function
LiquidAss12UI_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += liquidass12prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
