export TARGET := iphone:clang:latest:12.0
export ARCHS = arm64
# rootful on purpose: iOS 12 jailbreaks (checkra1n / Amethyst) are not rootless
export THEOS_PACKAGE_SCHEME =

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LiquidAss12 LiquidAss12KB

TWEAK_NAME = LiquidAss12 LiquidAss12KB LiquidAss12UI

# system-wide LiquidGlassKit switches/sliders (runs inside apps + Settings, filter: com.apple.UIKit)
LiquidAss12UI_FILES = UISwitchSlider.x LGSupport.m
LiquidAss12UI_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-function
LiquidAss12UI_FRAMEWORKS = UIKit

# keyboard glass runs inside apps, so it is its own dylib (filter: com.apple.UIKit)
LiquidAss12KB_FILES = Keyboard.x LGSupport.m LGGlass.m
LiquidAss12KB_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-function
LiquidAss12KB_FRAMEWORKS = UIKit QuartzCore CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += liquidass12prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
